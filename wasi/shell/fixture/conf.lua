-- The shell witness's game. A real, desktop-compatible LÖVE 12 project: this
-- same folder runs on desktop LÖVE unchanged.
--
-- It sets NO t.modules, exactly like a real game. LÖVE enables all twenty
-- modules by default and boot.lua hard-errors on a missing one, so leaving them
-- alone is what exercises the boot wrapper's handling of the three this build
-- does not link (touch, video, thread) — the path every third-party game takes.
function love.conf(t)
  t.identity = "shell-witness"
  t.window.width, t.window.height = 96, 64
  t.window.title = "love.wasm shell witness"
end
