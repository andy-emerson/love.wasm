-- The sweep fixture's configuration, written to be identical under desktop LÖVE
-- and under love.wasm, because the whole point of the fixture is a ratio between
-- the two on one machine.
--
-- vsync = 0 matters: with vsync on, desktop frame time floors at the refresh
-- interval and the desktop leg reports 16.7 ms for every cell it can actually
-- draw in one, which would flatten exactly the curve we came to measure. The
-- browser leg is driven by requestAnimationFrame and is paced regardless, which
-- is why the fixture's headline number is CPU time inside love.draw rather than
-- wall-clock frame time.
function love.conf(t)
	t.identity = "love-wasm-bench"
	t.window.title = "love.wasm draw-call sweep"
	t.window.width = 1280
	t.window.height = 720
	t.window.vsync = 0
	t.window.resizable = false

	-- Everything the sweep does not touch is off, so no unrelated module's
	-- per-frame work lands in the samples.
	t.modules.audio = false
	t.modules.joystick = false
	t.modules.physics = false
	t.modules.sound = false
	t.modules.thread = false
	t.modules.video = false
	t.modules.touch = false
	t.modules.sensor = false
end
