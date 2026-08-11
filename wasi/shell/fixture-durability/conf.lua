-- The durability witness's game (#55). The identity is set explicitly because
-- it names the OPFS directory the saves land in — the thing under test.
-- Like the shell fixture it sets NO t.modules, the shape every real game has.
function love.conf(t)
  t.identity = "durability-witness"
  t.window.width, t.window.height = 64, 64
  t.window.title = "love.wasm durability witness"
end
