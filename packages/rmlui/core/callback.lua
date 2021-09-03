local console = require "core.sandbox.console"
local createSandbox = require "core.sandbox.create"
local filemanager = require "core.filemanager"
local event = require "core.event"
local createElement = require "core.DOM.element"
local createEvent = require "core.DOM.event"
local environment = require "core.environment"
local fs = require "filesystem"
require "core.DOM.document"
require "core.DOM.window"

local m = {}

local events = {}

local function invoke(f, ...)
	local ok, err = xpcall(f, function(msg)
		return debug.traceback(msg)
	end, ...)
	if not ok then
		console.warn(err)
	end
	return ok, err
end
function m.OnDocumentCreate(document)
	local globals = createSandbox()
	event("OnDocumentCreate", document, globals)
	globals.window.document = globals.document
	environment[document] = globals
end
function m.OnDocumentDestroy(document)
	event("OnDocumentDestroy", document)
	environment[document] = nil
end
function m.OnLoadInlineScript(document, content, source_path, source_line)
    local _ <close> = fs.switch_sync()
	local path = filemanager.vfspath(source_path)
	if not path then
		console.warn(("file '%s' does not exist."):format(source_path))
		return
	end
	local source = "--@"..path..":"..source_line.."\n "..content
	local f, err = load(source, source, "t", environment[document])
	if not f then
		console.warn(err)
		return
	end
	invoke(f)
end
function m.OnLoadExternalScript(document, source_path)
    local _ <close> = fs.switch_sync()
	local path = filemanager.vfspath(source_path)
	if not path then
		console.warn(("file '%s' does not exist."):format(source_path))
		return
	end
	local f, err = loadfile(path, "bt", environment[document])
	if not f then
		console.warn(("file '%s' load failed: %s."):format(source_path, err))
		return
	end
	invoke(f)
end
function m.OnEvent(ev, e)
	local delegate = events[ev]
	if not delegate then
		return
	end
	local f = delegate[1]
	if delegate[2] then
		debug.setupvalue(f, delegate[2], createEvent(e))
	end
	invoke(f)
end
function m.OnEventAttach(ev, document, element, source)
	if source == "" then
		return
	end
	local globals = environment[document]
	local code = ("local event;local this=...;return function()%s;end"):format(source)
	local payload, err = load(code, source, "t", globals)
	if not payload then
		console.warn(err)
		return
	end
	local ok, f = invoke(payload, createElement(element, document))
	if not ok then
		return
	end
	local upvalue = {}
	local i = 1
	while true do
		local name = debug.getupvalue(f, i)
		if not name then
			break
		end
		upvalue[name] = i
		i = i + 1
	end
	events[ev] = {f, upvalue.event}
end
function m.OnEventDetach(ev)
	events[ev] = nil
end

function m.OnOpenFile(path)
    local _ <close> = fs.switch_sync()
	return filemanager.realpath(path)
end

return m
