-- Drives lua/extensions/folderwatch.lua headlessly with a stub dialog (run as a Lua interface script).
local function log(s) vlc.msg.info("[exttest] " .. tostring(s)) end
local buttons, widgets = {}, {}
local function widget(kind, init)
  local w = { kind = kind, text = init or "", values = {}, selection = {} }
  function w:set_text(t) self.text = t end
  function w:get_text() return self.text end
  function w:clear() self.values = {} end
  function w:add_value(text, id) self.values[#self.values + 1] = { text = text, id = id } end
  function w:get_selection() return self.selection end
  return w
end
local stub = {}
function stub:add_label(text, ...) local w = widget("label", text); widgets[#widgets + 1] = w; return w end
function stub:add_list(...) local w = widget("list"); widgets.list = w; return w end
function stub:add_text_input(init, ...) local w = widget("text", init); widgets[#widgets + 1] = w; return w end
function stub:add_button(label, cb, ...) buttons[label] = cb; return widget("button", label) end
function stub:update() end
function stub:delete() end
vlc.dialog = function() return stub end
vlc.deactivate = function() end

local path = os.getenv("EXT_SCRIPT")
local chunk, err = loadfile(path)
if not chunk then log("SYNTAX ERROR " .. tostring(err)) vlc.misc.quit() return end
chunk()
local d = descriptor()
log("descriptor title=" .. tostring(d.title))
activate()
log("list has " .. #widgets.list.values .. " root(s) after activate")
local origroot = widgets.list.values[1].text
local newroot = os.getenv("EXT_NEWROOT")
-- creation order: heading(1), path input(2), "Rescan every" label(3), interval input(4), message(5), status(6), footer(7)
local path_input, interval_input, message, status = widgets[2], widgets[4], widgets[5], widgets[6]
path_input:set_text(newroot); buttons["Add path"]()
log("after add: " .. #widgets.list.values .. " root(s); message=" .. message.text)
path_input:set_text(newroot); buttons["Add path"]()
log("duplicate add: message=" .. message.text)
path_input:set_text("/nonexistent/folder"); buttons["Add path"]()
log("bad add: message=" .. message.text)
interval_input:set_text("1"); buttons["Save"]()
log("bad interval: message=" .. message.text)
interval_input:set_text("7"); buttons["Save"]()
log("save: message=" .. message.text)
-- native picker: FOLDERWATCH_PICKER_CMD prints the folder in pick.txt; an empty file means cancel
widgets.list.selection = { [2] = widgets.list.values[2].text }; buttons["Remove selected"](); buttons["Save"]()
buttons["Choose folder…"]()
log("picker add: " .. #widgets.list.values .. " root(s); message=" .. message.text)
local pickfile = os.getenv("FOLDERWATCH_DIR") .. "/pick.txt"
local pf = io.open(pickfile, "w"); pf:write(""); pf:close()
buttons["Choose folder…"]()
log("picker cancel: message=" .. message.text)
-- first run: empty config must open the picker on activate
deactivate()
local cf = io.open(os.getenv("FOLDERWATCH_DIR") .. "/folderwatch.conf", "w"); cf:write("interval=15\n"); cf:close()
local opened = false
local realpopen = io.popen
io.popen = function(cmd, mode) opened = true; return realpopen(cmd, mode) end
activate()
io.popen = realpopen
log("first run: picker opened=" .. tostring(opened) .. "; roots=" .. #widgets.list.values)
local cf2 = io.open(os.getenv("FOLDERWATCH_DIR") .. "/folderwatch.conf", "w"); cf2:write("interval=7\nroot=" .. origroot .. "\nroot=" .. newroot .. "\n"); cf2:close()
deactivate(); activate()
widgets.list.selection = { [1] = widgets.list.values[1].text }; buttons["Remove selected"]()
log("after remove: " .. #widgets.list.values .. " root(s); message=" .. message.text)
buttons["Save"]()
buttons["Rescan now"]()
log("rescan: message=" .. message.text)
buttons["Refresh status"]()
log("status: " .. status.text)
deactivate()
log("done")
vlc.misc.quit()
