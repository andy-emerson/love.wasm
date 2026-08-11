-- The hotswap witness's game (#56). Same shape as the shell fixture: a real,
-- desktop-compatible LÖVE 12 project setting no t.modules.
function love.conf(t)
  t.identity = "hotswap-witness"
  t.window.width, t.window.height = 96, 64
  t.window.title = "love.wasm hotswap witness"
end
