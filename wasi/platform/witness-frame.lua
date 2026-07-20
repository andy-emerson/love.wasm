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

local main = require("love.boot")
return main()
