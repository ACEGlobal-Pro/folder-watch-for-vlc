--[[
Folder Watch for VLC — watcher half (VLC 3 Lua interface script).
https://github.com/ACEGlobal-Pro/folder-watch-for-vlc · MIT licence

Runs for as long as VLC is open (enable with extraintf=luaintf and
lua-intf=folderwatch). It loads the "Folder Watch" sidebar tree
(lua/sd/folderwatch.lua) and rescans the configured folders every
<interval> seconds. Whenever anything changed on disk — a file or folder
deleted, added, renamed or replaced (size/mtime differs) — it rebuilds the
tree by reloading the sidebar entry. The rebuild is deferred while
something from the library is playing or paused, because VLC stops playback
when the row being played is removed. An unreadable root (drive unmounted)
is left exactly as it was, never emptied.

Why a rebuild and not in-place edits: VLC 3.0's Lua API cannot add rows
into a sidebar tree, and vlc.playlist.delete() silently ignores sidebar
rows (verified on 3.0.23), so the sidebar script is the only thing that can
change the tree, and it can only build from scratch.

Files in the state dir ($FOLDERWATCH_DIR, else VLC's user data dir):
  folderwatch.conf    settings (see the sd script header); edited by the extension
  folderwatch.rescan  any content change forces a rebuild (the extension writes it)
  folderwatch.status  what the watcher last did, for the extension to display
]]

local SD_NAME = "lua{sd='folderwatch'}"
local TITLE = "Folder Watch"
local TAG = "[folderwatch] "
local MAX_DEPTH = 12
local DEFAULT_INTERVAL = 15
local DEFAULT_IGNORE = "m3u,db,nfo,ini,jpg,jpeg,ljpg,gif,png,pgm,pgmyuv,pbm,pam,tga,bmp,pnm,xpm,xcf,pcx,tif,tiff,lbm,sfv,txt,sub,idx,srt,cue,ssa,ds_store,localized"

local function log(s) vlc.msg.info(TAG .. tostring(s)) end
local function warn(s) vlc.msg.warn(TAG .. tostring(s)) end
local function dbg(s) vlc.msg.dbg(TAG .. tostring(s)) end

------------------------------------------------------------------ files & config

local function state_dir()
  local d = os.getenv("FOLDERWATCH_DIR")
  if d and d ~= "" then return d end
  return vlc.config.userdatadir()
end

local DIR = state_dir()
local CONF = DIR .. "/folderwatch.conf"
local TRIGGER = DIR .. "/folderwatch.rescan"
local STATUS = DIR .. "/folderwatch.status"

local function to_set(csv)
  local t = {}
  for w in tostring(csv):gmatch("[^,%s]+") do t[w:lower()] = true end
  return t
end

local function stat(path)
  local ok, st = pcall(vlc.net.stat, path)
  if ok and type(st) == "table" then return st end
  return nil
end

local function read_lines(path)
  if not stat(path) then return nil end
  local ok, s = pcall(vlc.stream, vlc.strings.make_uri(path))
  if not ok or not s then return nil end
  local lines = {}
  while true do
    local line = s:readline()
    if not line then break end
    lines[#lines + 1] = line
  end
  return lines
end

local function write_file(path, text)
  local ok, f = pcall(vlc.io.open, path, "w")
  if not ok or not f then warn("cannot write " .. path) return false end
  f:write(text)
  f:close()
  return true
end

local function read_config()
  local cfg = { roots = {}, interval = DEFAULT_INTERVAL, ignore = to_set(DEFAULT_IGNORE) }
  for _, line in ipairs(read_lines(CONF) or {}) do
    local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if k == "root" and v ~= "" then cfg.roots[#cfg.roots + 1] = v
    elseif k == "interval" then cfg.interval = math.max(2, math.floor(tonumber(v) or DEFAULT_INTERVAL))
    elseif k == "ignore" then cfg.ignore = to_set(v) end
  end
  return cfg
end

local function write_default_config()
  local out = { "# Folder Watch for VLC — folders shown in the sidebar. One root= line per folder.", "interval=" .. DEFAULT_INTERVAL }
  write_file(CONF, table.concat(out, "\n") .. "\n")
  log("wrote default configuration to " .. CONF)
end

local function read_trigger()
  local lines = read_lines(TRIGGER)
  return lines and table.concat(lines, "\n") or nil
end

------------------------------------------------------------------ disk scan

local function ext_of(name) return (name:match("%.([%w]+)$") or ""):lower() end

local function scan_dir(abs, rel, snap, ignore, depth)
  local ok, names = pcall(vlc.net.opendir, abs)
  if not ok or type(names) ~= "table" then return end
  for _, name in ipairs(names) do
    if name ~= "." and name ~= ".." and name:sub(1, 1) ~= "." and not ignore[ext_of(name)] then
      local child_abs = abs .. "/" .. name
      local child_rel = (rel == "" and name) or (rel .. "/" .. name)
      local st = stat(child_abs)
      if st and st.type == "dir" then
        snap[child_rel] = "d"
        if depth < MAX_DEPTH then scan_dir(child_abs, child_rel, snap, ignore, depth + 1) end
      elseif st then
        snap[child_rel] = tostring(st.modification_time) .. ":" .. tostring(st.size)
      end
    end
  end
end

-- Returns { [i] = { available = bool, entries = { [rel] = signature } } } per configured root.
local function scan(cfg)
  local result = {}
  for i, root in ipairs(cfg.roots) do
    local st = stat(root)
    local r = { available = (st ~= nil and st.type == "dir"), entries = {} }
    if r.available then scan_dir(root, "", r.entries, cfg.ignore, 1) end
    result[i] = r
  end
  return result
end

local function count(entries)
  local files, dirs = 0, 0
  for _, sig in pairs(entries) do if sig == "d" then dirs = dirs + 1 else files = files + 1 end end
  return files, dirs
end

-- Compares two scans; returns how many entries vanished and how many are new or changed.
-- A root that is unreadable now is skipped; a root that just became readable counts as changed.
local function diff(old, new)
  local removed, changed = 0, 0
  for i, r in ipairs(new) do
    local o = old[i]
    if not r.available then
      -- leave the tree as it is
    elseif not o or not o.available then
      changed = changed + 1
    else
      for rel in pairs(o.entries) do
        if r.entries[rel] == nil then removed = removed + 1; dbg("gone: " .. rel) end
      end
      for rel, sig in pairs(r.entries) do
        if o.entries[rel] ~= sig then changed = changed + 1; dbg("new/changed: " .. rel) end
      end
    end
  end
  return removed, changed
end

------------------------------------------------------------------ playback & sidebar

local function playing_path()
  local ok, st = pcall(vlc.playlist.status)
  if not ok or st == "stopped" then return nil end
  local ok2, item = pcall(vlc.input.item)
  if not ok2 or not item then return nil end
  local uri = item:uri()
  if not uri then return nil end
  local ok3, p = pcall(vlc.strings.make_path, uri)
  if ok3 and p then return p end
  return nil
end

local function library_playing(cfg)
  local p = playing_path()
  if not p then return false end
  for _, r in ipairs(cfg.roots) do
    if p == r or p:sub(1, #r + 1) == r .. "/" then return true end
  end
  return false
end

local function rebuild(reason)
  pcall(vlc.sd.remove, SD_NAME)
  local ok, err = pcall(vlc.sd.add, SD_NAME)
  if ok then log("rebuilt sidebar tree (" .. reason .. ")") else warn("rebuild failed: " .. tostring(err)) end
end

local function ensure_loaded()
  local ok, loaded = pcall(vlc.sd.is_loaded, SD_NAME)
  if ok and loaded then return end
  local ok2, err = pcall(vlc.sd.add, SD_NAME)
  if ok2 then log("sidebar tree loaded") else warn("cannot load sidebar tree: " .. tostring(err)) end
end

-- Debug-level listing of what the sidebar currently holds (visible with -vv only).
local function dump_tree()
  local ok, root = pcall(vlc.playlist.get, "root", false)
  if not ok or type(root) ~= "table" or not root.children then return end
  local sd
  for _, c in ipairs(root.children) do if c.name == TITLE and c.children then sd = c end end
  if not sd then dbg("tree: sidebar node absent") return end
  local files, dirs = 0, 0
  local function walk(n)
    for _, c in ipairs(n.children or {}) do
      if c.children then dirs = dirs + 1; walk(c) else files = files + 1; dbg("tree leaf " .. tostring(c.path)) end
    end
  end
  walk(sd)
  dbg("tree: " .. dirs .. " folders, " .. files .. " files")
end

------------------------------------------------------------------ status & loop

local function now()
  local ok, d = pcall(os.date, "%Y-%m-%d %H:%M:%S")
  return ok and d or tostring(vlc.misc.mdate())
end

local function write_status(cfg, snap, last_action, pending)
  local files, dirs, missing = 0, 0, {}
  for i, r in ipairs(snap) do
    if r.available then
      local f, d = count(r.entries); files = files + f; dirs = dirs + d
    else
      missing[#missing + 1] = cfg.roots[i]
    end
  end
  local out = {
    "last_scan=" .. now(),
    "files=" .. files,
    "folders=" .. dirs,
    "roots=" .. #cfg.roots,
    "unavailable=" .. table.concat(missing, " | "),
    "pending_rebuild=" .. (pending and "yes (waiting for playback to leave the library)" or "no"),
    "last_action=" .. last_action,
    "interval=" .. cfg.interval,
  }
  write_file(STATUS, table.concat(out, "\n") .. "\n")
end

-- VLC 3 has no should_die() for interface scripts: on quit it cancels this
-- thread inside mwait(), so the loop simply never returns on its own.
local function quitting()
  return vlc.misc.should_die ~= nil and vlc.misc.should_die()
end

local function sleep(seconds)
  for _ = 1, seconds do
    if quitting() then return false end
    vlc.misc.mwait(vlc.misc.mdate() + 1000000)
  end
  return not quitting()
end

-- Keeps the last good snapshot of a root that became unreadable, so its
-- files are not treated as deleted when it comes back.
local function carry_unreadable(snap, fresh)
  for i, r in ipairs(fresh) do
    if not r.available and snap[i] and snap[i].available then
      fresh[i] = { available = false, entries = snap[i].entries }
    elseif not r.available and snap[i] then
      fresh[i] = snap[i]
    end
  end
  return fresh
end

local function run()
  if not stat(CONF) then write_default_config() end
  local cfg = read_config()
  local conf_mtime = (stat(CONF) or {}).modification_time
  local trigger = read_trigger()
  log("watching " .. #cfg.roots .. " root(s) every " .. cfg.interval .. "s; state in " .. DIR)

  ensure_loaded()
  local snap = scan(cfg)
  local pending, pending_reason = false, nil
  local last_action = "started " .. now()
  write_status(cfg, snap, last_action, pending)
  for i, r in ipairs(snap) do if not r.available then warn("root not readable: " .. cfg.roots[i]) end end

  while sleep(cfg.interval) do
    local force = nil
    local m = (stat(CONF) or {}).modification_time
    if m ~= conf_mtime then
      conf_mtime = m
      cfg = read_config()
      force = "settings changed"
      log("settings reloaded: " .. #cfg.roots .. " root(s), interval " .. cfg.interval .. "s")
    end
    local t = read_trigger()
    if t ~= trigger then trigger = t; force = force or "manual rescan" end

    local fresh = scan(cfg)
    for i, r in ipairs(fresh) do
      if snap[i] and snap[i].available and not r.available then warn("root became unreadable, leaving its tree as is: " .. cfg.roots[i]) end
    end
    local removed, changed = diff(snap, fresh)

    if force then
      pending, pending_reason = true, force
    elseif removed + changed > 0 then
      pending = true
      pending_reason = removed .. " removed, " .. changed .. " new/changed"
    end

    if pending then
      if library_playing(cfg) then
        dbg("rebuild deferred: playing from the library")
      else
        rebuild(pending_reason)
        pending, pending_reason = false, nil
        last_action = "rebuilt tree " .. now()
        if quitting() then break end
        vlc.misc.mwait(vlc.misc.mdate() + 1000000)
        dump_tree()
      end
    end

    snap = carry_unreadable(snap, fresh)
    write_status(cfg, snap, last_action, pending)
  end
  log("stopping")
end

local ok, err = pcall(run)
if not ok then vlc.msg.err(TAG .. "crashed: " .. tostring(err)) end
