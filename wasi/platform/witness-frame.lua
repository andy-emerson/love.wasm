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
-- So satisfy `require` for every module this build did not link, and report the
-- absence when a game USES it — which is the `preview-warn.cpp` contract (#27)
-- every other preview limitation here follows: warn once, at the point of use,
-- naming the feature.
--
-- Reporting at *require* time would be exactly backwards. LÖVE enables all
-- twenty modules for every game, so a require-time notice fires on every boot
-- whether or not the game cares — noise where there is no signal — and stays
-- silent in the one case worth knowing about, a game that actually calls the
-- thing. The question this build has to answer is "did a game need a feature we
-- do not have?", so the notice belongs where that question is answered.
--
-- `love.<name>` is deliberately left NIL rather than set to a stub table. That
-- keeps the engine in exactly the shape desktop has when a game sets
-- `t.modules.<name> = false`, so a feature test — callbacks.lua's
-- `if love.joystick then`, or a game's own `if love.video then` — takes the
-- absent path instead of finding a truthy stub and calling into it. The
-- reporting rides on a metatable on `love` itself, which fires on the same read:
-- the feature test both reports and correctly evaluates false, and a naive
-- `love.video.newVideoStream(...)` prints the notice immediately before the
-- nil-index error, so the failure is attributed instead of anonymous.
--
-- Linked-ness is read, not listed: love.cpp registers a `package.preload` entry
-- per compiled-in module, so an entry that is already there is a real module and
-- is left alone. Linking a module for real therefore retires its stub with no
-- edit here — which is what happened to `joystick` and `sensor`.
local absent = {}
for _, name in ipairs {
	"audio", "data", "event", "filesystem", "font", "graphics", "image",
	"joystick", "keyboard", "math", "mouse", "physics", "sensor", "sound",
	"system", "thread", "timer", "touch", "video", "window",
} do
	local key = "love." .. name
	if package.preload[key] == nil then
		local warned = false
		local function report()
			if warned then return end
			warned = true
			print(("[love.wasm preview] love.%s is not in this build; " ..
				"this game uses it, and that use does nothing"):format(name))
		end
		absent[name] = report
		-- `require("love.<name>")` must succeed or boot.lua dies before main.lua.
		-- A game that keeps the returned table (rather than reading `love.<name>`)
		-- bypasses the metatable below, so the table reports for itself.
		package.preload[key] = function()
			return setmetatable({}, { __index = function() report(); return function() end end })
		end
	end
end

-- `love` has no metatable of its own (love.cpp attaches one only to the
-- `_deprecation` userdata), so this is additive. It fires only for reads that
-- MISS — every module actually linked, and every callback a game assigns, is a
-- present key and never reaches here.
setmetatable(love, {
	__index = function(_, key)
		local report = absent[key]
		if report then report() end
		return nil
	end,
})

local main = require("love.boot")
return main()
