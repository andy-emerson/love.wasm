-- Step-4 (4.16) buffer witness: love.graphics.newBuffer — an explicit, user-owned
-- GPU buffer (GraphicsBuffer) as a Mesh vertex source. 4.9's Mesh created its
-- vertex buffer implicitly; this bridge creates the Buffer directly with
-- newBuffer, attaches it to a Mesh through BufferAttributes (the buffer-backed
-- Mesh constructor), and draws. Reading the triangle colour inside and the clear
-- outside proves an explicit GraphicsBuffer drives a real WebGL2 draw. The draw
-- path binds the buffer as a vertex source (no buffer mapping, which WebGL2
-- forbids — the map-based readbackBuffer is a #36 divergence, not tested here).
-- Chromium only.
local failures = 0
local function check(name, cond, got)
  if cond then coroutine.yield("ok   " .. name)
  else failures = failures + 1; coroutine.yield("FAIL " .. name .. "   got: " .. tostring(got)) end
end

local love = require("love")
check("require 'love'", type(love) == "table", love)
local gok = pcall(require, "love.graphics")
check("require 'love.graphics' (opengl backend links + registers)",
  gok and type(love.graphics) == "table", love.graphics)

local function near(x, e) return x ~= nil and math.abs(x - e) <= 2 end
local function rgba(r, g, b, a) return ("(%s,%s,%s,%s)"):format(tostring(r),tostring(g),tostring(b),tostring(a)) end

local ok, ri,gi,bi,ai, ro,go,bo,ao = pcall(__wasi_gfx_draw_buffer)
check("newBuffer + buffer-backed Mesh + draw + readback executes", ok, ok and "" or ri)
if ok then
  coroutine.yield(("triangle=%s  background=%s"):format(rgba(ri,gi,bi,ai), rgba(ro,go,bo,ao)))
  check("triangle from the explicit GraphicsBuffer recovered its colour (51,102,153)",
    near(ri,51) and near(gi,102) and near(bi,153) and near(ai,255), rgba(ri,gi,bi,ai))
  check("background outside the triangle is the clear colour (153,102,51)",
    near(ro,153) and near(go,102) and near(bo,51) and near(ao,255), rgba(ro,go,bo,ao))
end

coroutine.yield(("checks done, %d failures"):format(failures))
return failures == 0 and "STEP4-BUFFER-WITNESS: PASS" or "STEP4-BUFFER-WITNESS: FAIL"
