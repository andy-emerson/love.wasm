-- Reports what a PREVIOUS run's save left behind, then writes this run's.
-- run-durability.mjs drives two page loads over this game: the first prints
-- DUR-READ nil and writes the payload; after page.reload() the second must
-- print the payload back — which only a save store that survives the reload
-- can do, and the OPFS-disabled leg is required to print nil again.
--
-- The payload comes from a project file the witness rewrites per run, so a
-- stale store from an earlier run can never fake a round-trip.
function love.load()
  print("DUR-READ " .. tostring(love.filesystem.read("dur.txt")))
  local payload = love.filesystem.read("payload.txt")
  love.filesystem.write("dur.txt", payload)
  print("DUR-WROTE " .. tostring(payload))
end

function love.draw()
  love.graphics.clear(0, 0, 0, 1)
end
