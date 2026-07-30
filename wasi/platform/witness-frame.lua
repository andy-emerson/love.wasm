-- Build-order step 6.6b witness boot wrapper — THE MILESTONE. This runs LÖVE's
-- REAL boot: require("love.boot") returns LÖVE 12's main-loop function (the
-- coroutine-shaped root of all calls in boot.lua), and calling it runs
-- love.boot -> love.init (reads conf.lua via the real love.filesystem, opens the
-- canvas with love.window.setMode at the conf dimensions, loads main.lua) ->
-- love.run (calls love.load, then yields once per frame running
-- event.pump / timer.step / update / clear / draw / present).
--
-- Under the pump this file IS the resident coroutine: pump_boot runs it through
-- love.boot/init/run + love.load to the first per-frame yield; each pump_frame
-- resumes it for one real game frame. The JS frame driver (run-browser-frame.mjs)
-- pumps several frames, then asserts the love.load MARKER reached the host tap
-- and the presented backbuffer is RED — proving conf -> canvas -> load -> draw ->
-- present ran end to end.
--
-- `arg` is a global love.boot reads (love.rawGameArguments = arg). The pump's
-- fresh Lua state has none, so seed the minimal one desktop love.cpp would pass;
-- getLow picks index 0 ("love") as arg0, which love.filesystem.init anchors on
-- (getExecutablePath is "" on wasi, so boot falls back to arg0).
arg = { [0] = "love" }

-- require("love") first: pump-ext only PRELOADS luaopen_love as "love"; running
-- it (this require) is what registers the love.* submodules — including love.boot
-- — into package.preload. Only then can love.boot be required.
require("love")

-- LÖVE enables all twenty modules by default (boot.lua's `c.modules` table) and
-- loads each enabled one with a bare `require("love." .. v)` that hard-errors if
-- it is missing. Desktop always satisfies that default because desktop links
-- everything; a build shipping a subset does not, so an unmodified game dies in
-- boot before main.lua. That is this build's gap, not the game's: `t.modules.*`
-- has never been required of any LÖVE game, and omitting it is idiomatic.
--
-- So satisfy `require` for every module this build did not link. The preload
-- entry deliberately does NOT set `love.<name>`, which leaves the engine in
-- exactly the shape desktop has when a game sets `t.modules.<name> = false`:
-- feature tests like callbacks.lua's `if love.joystick then` see nil and take
-- the absent path, rather than a truthy stub they would then call into.
--
-- Linked-ness is read, not listed: love.cpp registers a `package.preload` entry
-- per compiled-in module, so an entry that is already there is a real module and
-- is left alone. Linking a module for real therefore retires its stub with no
-- edit here.
--
-- The bargain: this is correct for a module a game ENABLES BUT NEVER CALLS,
-- which is the common case. A game that really uses one gets a nil index and
-- fails loudly, as it should — "boots" and "works" stay separate claims.
for _, name in ipairs {
	"audio", "data", "event", "filesystem", "font", "graphics", "image",
	"joystick", "keyboard", "math", "mouse", "physics", "sensor", "sound",
	"system", "thread", "timer", "touch", "video", "window",
} do
	local key = "love." .. name
	if package.preload[key] == nil then
		package.preload[key] = function()
			print(("[love.wasm preview] love.%s is not in this build; " ..
				"the game enables it, so love.%s is nil as it would be on " ..
				"desktop with t.modules.%s = false"):format(name, name, name))
			return setmetatable({}, { __index = function() return function() end end })
		end
	end
end

local main = require("love.boot")
return main()
