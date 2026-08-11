-- The hotswap witness's game (#56, D4=B). counter and x are FILE-SCOPE LOCALS
-- shared by love.update AND love.draw — exactly the state a whole-chunk re-eval
-- would wipe and the function-body hotswap must preserve. The witness rewrites
-- this file on disk while the game runs (v2 reverses the movement, v3 restores
-- it after a deliberately broken save) and reads the HOT-STATE lines: counter
-- must never reset, and draw must keep seeing what update mutates.
local counter = 0
local x = 8

function love.load()
  -- Printed once per SESSION: leg 4 asserts hotswap never re-runs it.
  print("HOT-LOAD once")
end

function love.update(dt)
  counter = counter + 1
  x = x + 120 * dt   -- v1 moves right
  if x > 88 then x = 88 end
  if x < 0 then x = 0 end
end

function love.draw()
  love.graphics.clear(0, 0, 0, 1)
  love.graphics.setColor(0, 1, 0, 1)
  love.graphics.rectangle("fill", x, 24, 8, 8)
  -- draw reports the state update mutates: the shared-alias evidence. Every
  -- 20th frame, so the log stays readable at frame rate.
  if counter % 20 == 0 then
    print(("HOT-STATE v=1 counter=%d x=%.1f"):format(counter, x))
  end
end
