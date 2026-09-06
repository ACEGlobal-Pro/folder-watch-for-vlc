--[[
Folder Watch for VLC — sidebar half (VLC 3 Lua services-discovery script).
https://github.com/ACEGlobal-Pro/folder-watch-for-vlc · MIT licence

Shows every configured folder as a tree under the sidebar entry
"Folder Watch". The tree is built once each time this script is loaded; the
watcher (lua/intf/folderwatch.lua) reloads it whenever anything on disk changes.

Configuration: <state dir>/folderwatch.conf, where <state dir> is
$FOLDERWATCH_DIR if set, else VLC's user data folder
(macOS ~/Library/Application Support/org.videolan.vlc, Windows %APPDATA%\vlc,
Linux $XDG_DATA_HOME/vlc or ~/.local/share/vlc).
    root=/absolute/folder          (repeat once per folder, order kept)
    interval=15                    (used by the watcher only)
    ignore=srt,sub,txt,...         (extensions never shown; VLC's own default list if absent)
]]

local TITLE = "Folder Watch"
local CONF_NAME = "folderwatch.conf"
local MAX_DEPTH = 12
-- VLC's default --ignore-filetypes list, plus macOS Finder droppings.
local DEFAULT_IGNORE = "m3u,db,nfo,ini,jpg,jpeg,ljpg,gif,png,pgm,pgmyuv,pbm,pam,tga,bmp,pnm,xpm,xcf,pcx,tif,tiff,lbm,sfv,txt,sub,idx,srt,cue,ssa,ds_store,localized"
-- Names with these extensions are files for certain, so they are never opened to find out.
local MEDIA_EXT = "mp4,m4v,mkv,avi,mov,wmv,flv,webm,mpg,mpeg,mpe,ts,m2ts,mts,vob,3gp,ogv,ogm,divx,rm,rmvb,asf,mp3,m4a,m4b,aac,flac,wav,ogg,oga,opus,wma,aiff,aif,alac,ape,ac3,dts"

function descriptor()
  return { title = TITLE }
end

local function log(s) vlc.msg.info("[folderwatch sd] " .. tostring(s)) end

local function to_set(csv)
  local t = {}
  for w in tostring(csv):gmatch("[^,%s]+") do t[w:lower()] = true end
  return t
end

local MEDIA = to_set(MEDIA_EXT)

-- Services-discovery scripts cannot call vlc.config.userdatadir(), so derive it.
local function state_dir()
  local d = os.getenv("FOLDERWATCH_DIR")
  if d and d ~= "" then return d end
  local appdata = os.getenv("APPDATA")
  if appdata and appdata ~= "" then return appdata .. "\\vlc" end
  local home = os.getenv("HOME") or ""
  if package.config:sub(1, 1) == "/" and os.getenv("XDG_DATA_HOME") then return os.getenv("XDG_DATA_HOME") .. "/vlc" end
  local mac = home .. "/Library/Application Support/org.videolan.vlc"
  local probe = io.open(mac .. "/.", "r")
  if probe then probe:close() return mac end
  return home .. "/.local/share/vlc"
end

local function read_config()
  local cfg = { roots = {}, ignore = to_set(DEFAULT_IGNORE) }
  local ok, s = pcall(vlc.stream, vlc.strings.make_uri(state_dir() .. "/" .. CONF_NAME))
  if not ok or not s then return cfg end
  while true do
    local line = s:readline()
    if not line then break end
    local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if k == "root" and v ~= "" then
      cfg.roots[#cfg.roots + 1] = v
    elseif k == "ignore" then
      cfg.ignore = to_set(v)
    end
  end
  return cfg
end

local function basename(path)
  return path:match("([^/]+)/*$") or path
end

local function ext_of(name)
  return (name:match("%.([%w]+)$") or ""):lower()
end

-- Natural order: "ep2" before "ep10", case-insensitive.
local function natkey(name)
  return (name:lower():gsub("%d+", function(d) return ("0"):rep(12 - #d) .. d end))
end

-- Lists a folder through VLC's own file access; nil when the URI is not a listable folder.
local function list(uri)
  local ok, s = pcall(vlc.stream, uri)
  if not ok or not s then return nil end
  local ok2, entries = pcall(function() return s:readdir() end)
  if not ok2 or type(entries) ~= "table" then return nil end
  local out = {}
  for _, e in ipairs(entries) do
    local name = e:name()
    local uri2 = e:uri()
    if name and uri2 then out[#out + 1] = { uri = uri2, name = name } end
  end
  table.sort(out, function(a, b) return natkey(a.name) < natkey(b.name) end)
  return out
end

local function classify(entry, ignore)
  if entry.name:sub(1, 1) == "." then return "skip" end
  local ext = ext_of(entry.name)
  if ignore[ext] then return "skip" end
  if MEDIA[ext] then return "file" end
  local entries = list(entry.uri)
  if entries then return "dir", entries end
  return "file"
end

local counts = { files = 0, dirs = 0 }

local function build(node, entries, ignore, depth)
  for _, entry in ipairs(entries) do
    local kind, children = classify(entry, ignore)
    if kind == "dir" then
      counts.dirs = counts.dirs + 1
      local sub = node:add_subnode({ title = entry.name })
      if depth < MAX_DEPTH then build(sub, children, ignore, depth + 1) end
    elseif kind == "file" then
      counts.files = counts.files + 1
      node:add_subitem({ path = entry.uri, title = entry.name })
    end
  end
end

function main()
  local cfg = read_config()
  if #cfg.roots == 0 then
    vlc.sd.add_node({ title = "No folders yet — open View › Folder Watch for VLC and choose one" })
    log("no roots configured in " .. state_dir() .. "/" .. CONF_NAME)
    return
  end
  for _, root in ipairs(cfg.roots) do
    -- One node per configured root, always, so the watcher can address roots by position.
    local node = vlc.sd.add_node({ title = basename(root) })
    local entries = list(vlc.strings.make_uri(root))
    if entries then
      build(node, entries, cfg.ignore, 1)
    else
      log("root not readable, left empty: " .. root)
    end
  end
  log("tree built: " .. counts.dirs .. " folders, " .. counts.files .. " files from " .. #cfg.roots .. " root(s)")
end
