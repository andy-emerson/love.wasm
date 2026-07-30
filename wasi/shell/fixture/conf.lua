-- The shell witness's game. A real, desktop-compatible LÖVE 12 project: this
-- same folder runs on desktop LÖVE unchanged.
--
-- boot.lua requires every ENABLED module, so anything the union artifact does not
-- link must be turned off here. That constraint is what "inside the linked
-- envelope" means for a third-party game (Beta step 2), stated once, concretely.
function love.conf(t)
  t.identity = "shell-witness"
  t.window.width, t.window.height = 96, 64
  t.window.title = "love.wasm shell witness"
  t.modules.joystick = false
  t.modules.touch = false
  t.modules.sensor = false
  t.modules.video = false
  t.modules.thread = false
end
