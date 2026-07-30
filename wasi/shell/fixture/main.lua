-- Moves on arrow keys, so the witness can prove REAL DOM key events reach
-- love.keyboard, and draws in a colour that lives in an editable module, so the
-- witness can prove a live edit reaches the running game.
local x = 8

function love.load()
  -- Reading through a subdirectory proves the project (not the canned fixture in
  -- fs-host.mjs) is what love.filesystem is serving.
  print("SHELL-LOAD " .. tostring(love.filesystem.read("assets/note.txt")))
end

function love.update(dt)
  if love.keyboard.isDown("right") then x = x + 120 * dt end
  if love.keyboard.isDown("left")  then x = x - 120 * dt end
  if x < 0 then x = 0 end
  if x > 80 then x = 80 end
end

function love.draw()
  -- require() inside the frame, not at file scope: pump_invalidate() clears the
  -- module cache, but main.lua is never re-run, so a file-scope local would keep
  -- pointing at the old table. This is EMBEDDING.md §4's supported-edit class.
  local c = require("colour")
  love.graphics.clear(0, 0, 0, 1)
  love.graphics.setColor(c[1], c[2], c[3], 1)
  love.graphics.rectangle("fill", x, 24, 16, 16)
end
