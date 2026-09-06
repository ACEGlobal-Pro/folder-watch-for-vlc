--[[
Folder Watch for VLC — settings panel (VLC 3 Lua extension, View menu).
https://github.com/ACEGlobal-Pro/folder-watch-for-vlc · MIT licence

Chooses the folders the "Folder Watch" sidebar tree shows (with the system
folder dialog where one exists), sets the rescan interval, asks the watcher
for an immediate rebuild, and shows what the watcher last did. The watcher is
lua/intf/folderwatch.lua; the tree is lua/sd/folderwatch.lua. This panel only
reads and writes the files they share.
]]

local VERSION = "1.0.0"
local DEFAULT_INTERVAL = 15
local PROJECT_URL = "https://github.com/ACEGlobal-Pro/folder-watch-for-vlc"

local DIR, CONF, TRIGGER, STATUS
local dlg, ui = nil, {}
local roots = {}
local interval = DEFAULT_INTERVAL

function descriptor()
  return {
    title = "Folder Watch for VLC",
    version = VERSION,
    author = "ACE Global Pro",
    url = PROJECT_URL,
    shortdesc = "Folder Watch for VLC",
    description = "Shows your media folders as a tree in VLC's sidebar and keeps it fresh: delete, add or replace files and the tree follows within seconds.",
    capabilities = {},
  }
end

------------------------------------------------------------------ platform

local function is_windows() return package.config:sub(1, 1) == "\\" end

local function is_mac()
  if is_windows() then return false end
  local f = io.open("/System/Library/CoreServices/SystemVersion.plist", "r")
  if f then f:close() return true end
  return false
end

local function state_dir()
  local d = os.getenv("FOLDERWATCH_DIR")
  if d and d ~= "" then return d end
  return vlc.config.userdatadir()
end

local function sep() return is_windows() and "\\" or "/" end

-- Shell command that prints one chosen folder path, or nothing when cancelled.
local function picker_command()
  local override = os.getenv("FOLDERWATCH_PICKER_CMD")
  if override and override ~= "" then return override end
  if is_mac() then
    return [[osascript -e 'tell application (path to frontmost application as text) to POSIX path of (choose folder with prompt "Choose a folder for Folder Watch")' 2>/dev/null]]
  elseif is_windows() then
    return [[powershell -NoProfile -STA -Command "Add-Type -AssemblyName System.Windows.Forms; $d = New-Object System.Windows.Forms.FolderBrowserDialog; $d.Description = 'Choose a folder for Folder Watch'; if ($d.ShowDialog() -eq 'OK') { Write-Output $d.SelectedPath }"]]
  else
    return [[(zenity --file-selection --directory --title="Choose a folder for Folder Watch" 2>/dev/null) || (kdialog --getexistingdirectory "$HOME" 2>/dev/null)]]
  end
end

local function pick_folder()
  local ok, out = pcall(function()
    local p = io.popen(picker_command(), "r")
    if not p then return nil end
    local s = p:read("*a") or ""
    p:close()
    return s
  end)
  if not ok or not out then return nil end
  out = out:gsub("^%s+", ""):gsub("%s+$", "")
  if out == "" then return nil end
  return out
end

------------------------------------------------------------------ files

local function read_lines(path)
  local ok0, st = pcall(vlc.net.stat, path)
  if not ok0 or type(st) ~= "table" then return nil end
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
  if not ok or not f then return false end
  f:write(text)
  f:close()
  return true
end

local function load_config()
  roots, interval = {}, DEFAULT_INTERVAL
  for _, line in ipairs(read_lines(CONF) or {}) do
    local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if k == "root" and v ~= "" then roots[#roots + 1] = v
    elseif k == "interval" then interval = tonumber(v) or DEFAULT_INTERVAL end
  end
end

local function save_config()
  local out = { "# Folder Watch for VLC — folders shown in the sidebar. One root= line per folder.", "interval=" .. interval }
  for _, r in ipairs(roots) do out[#out + 1] = "root=" .. r end
  return write_file(CONF, table.concat(out, "\n") .. "\n")
end

local function status_text()
  local lines = read_lines(STATUS)
  if not lines or #lines == 0 then
    return "Watcher: not running yet. Quit VLC, run ./install.sh --configure (or enable the Lua interface in Preferences), and start VLC again."
  end
  local t = {}
  for _, line in ipairs(lines) do
    local k, v = line:match("^([%w_]+)=(.*)$")
    if k == "last_scan" then t[#t + 1] = "Last scan: " .. v
    elseif k == "files" then t[#t + 1] = "Files: " .. v
    elseif k == "folders" then t[#t + 1] = "Folders: " .. v
    elseif k == "unavailable" and v ~= "" then t[#t + 1] = "Unreadable folders: " .. v
    elseif k == "pending_rebuild" and v:sub(1, 3) == "yes" then t[#t + 1] = "Rebuild pending: " .. v
    elseif k == "last_action" then t[#t + 1] = "Last action: " .. v end
  end
  return table.concat(t, "<br/>")
end

------------------------------------------------------------------ actions

local function refresh_list()
  ui.list:clear()
  for i, r in ipairs(roots) do ui.list:add_value(r, i) end
end

local function set_message(text)
  ui.message:set_text(text)
  dlg:update()
end

local function normalise(path)
  path = (path or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if is_windows() then
    path = path:gsub("[\\/]+$", "")
  else
    path = path:gsub("/+$", "")
    if path == "" then path = "/" end
  end
  return path
end

local function add_root(path, then_save)
  path = normalise(path)
  if path == "" then set_message("Type or choose a folder first.") return false end
  local ok, st = pcall(vlc.net.stat, path)
  if not ok or type(st) ~= "table" or st.type ~= "dir" then set_message("Not a readable folder: " .. path) return false end
  for _, r in ipairs(roots) do if r == path then set_message("Already in the list.") return false end end
  roots[#roots + 1] = path
  refresh_list()
  if then_save then
    if save_config() then set_message("Added and saved: " .. path .. " — the sidebar tree updates within " .. interval .. " seconds.")
    else set_message("Added, but could not write " .. CONF) end
  else
    set_message("Added. Click Save to apply.")
  end
  return true
end

local function on_choose()
  local picked = pick_folder()
  if not picked then set_message("No folder chosen.") return end
  add_root(picked, true)
end

local function on_add()
  if add_root(ui.path:get_text(), false) then ui.path:set_text("") end
end

local function on_remove()
  local sel = ui.list:get_selection()
  local keep = {}
  for i, r in ipairs(roots) do if not sel[i] then keep[#keep + 1] = r end end
  if #keep == #roots then set_message("Select a folder in the list first.") return end
  roots = keep
  refresh_list()
  set_message("Removed. Click Save to apply.")
end

local function on_save()
  local n = tonumber(ui.interval:get_text())
  if not n or n < 2 then set_message("Interval must be a number of seconds, 2 or more.") return end
  interval = math.floor(n)
  if save_config() then
    set_message("Saved. The sidebar tree rebuilds within " .. interval .. " seconds (after playback leaves the watched folders).")
  else
    set_message("Could not write " .. CONF)
  end
end

local function on_rescan()
  if write_file(TRIGGER, tostring(os.time()) .. "\n") then
    set_message("Rescan requested. The tree rebuilds on the watcher's next pass.")
  else
    set_message("Could not write " .. TRIGGER)
  end
end

local function on_refresh()
  ui.status:set_text(status_text())
  dlg:update()
end

------------------------------------------------------------------ dialog

local function build_dialog()
  dlg = vlc.dialog("Folder Watch for VLC")
  dlg:add_label("<b>Folders shown in the sidebar under “Folder Watch”</b>", 1, 1, 4, 1)
  ui.list = dlg:add_list(1, 2, 4, 1)
  dlg:add_button("Choose folder…", on_choose, 1, 3, 1, 1)
  ui.path = dlg:add_text_input("", 2, 3, 2, 1)
  dlg:add_button("Add path", on_add, 4, 3, 1, 1)
  dlg:add_button("Remove selected", on_remove, 1, 4, 1, 1)
  dlg:add_label("Rescan every (seconds):", 2, 4, 1, 1)
  ui.interval = dlg:add_text_input(tostring(interval), 3, 4, 1, 1)
  dlg:add_button("Save", on_save, 4, 4, 1, 1)
  dlg:add_button("Rescan now", on_rescan, 1, 5, 1, 1)
  dlg:add_button("Refresh status", on_refresh, 2, 5, 1, 1)
  ui.message = dlg:add_label("", 1, 6, 4, 1)
  ui.status = dlg:add_label(status_text(), 1, 7, 4, 1)
  dlg:add_label("Folder Watch for VLC " .. VERSION .. " · free, MIT · created by ACE Global Pro · " .. PROJECT_URL, 1, 8, 4, 1)
  refresh_list()
end

function activate()
  DIR = state_dir()
  CONF = DIR .. sep() .. "folderwatch.conf"
  TRIGGER = DIR .. sep() .. "folderwatch.rescan"
  STATUS = DIR .. sep() .. "folderwatch.status"
  load_config()
  build_dialog()
  if #roots == 0 then
    set_message("No folders yet. Choose the folder that holds your videos or music.")
    on_choose()
  end
end

function deactivate()
  if dlg then dlg:delete(); dlg = nil end
end

function close()
  vlc.deactivate()
end
