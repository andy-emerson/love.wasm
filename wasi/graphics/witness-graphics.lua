-- Step-4 (4.1c) graphics witness: the real LÖVE core booting under the pump WITH
-- love.graphics linked on the opengl backend, reseamed to the host's WebGL2
-- context via static imports. It requires love.graphics (which creates the real
-- opengl::Graphics instance), then drives the backend through the graphics-ext
-- bridge: setMode against the current WebGL2 context, clear to a known color,
-- present, and read pixel (0,0) back. The recovered pixel is the witness — the
-- graphics analog of the audio tone recovery — proving the real backend clears a
-- real framebuffer through the WebGL2 seam (not a mock). Backend fidelity is the
-- claim; the Lua love.graphics.clear wrap lands with the window seam in step 6.
local failures = 0
local function check(name, cond, got)
  if cond then
    coroutine.yield("ok   " .. name)
  else
    failures = failures + 1
    coroutine.yield("FAIL " .. name .. "   got: " .. tostring(got))
  end
end

local love = require("love")
check("require 'love'", type(love) == "table", love)

-- Creating the graphics module builds the real opengl::Graphics (createInstance).
local gok = pcall(require, "love.graphics")
check("require 'love.graphics' (opengl backend links + registers)",
  gok and type(love.graphics) == "table", love.graphics)

-- Bring the backend up against the host WebGL2 context and clear to a known
-- color: 0.2,0.4,0.6 -> exact 8-bit (51,102,153), alpha 1.0 -> 255.
local okc, R, G, B, A = pcall(__wasi_gfx_clear_read, 0.2, 0.4, 0.6)
check("setMode + clear + present + readback executes", okc, R)
if okc then
  coroutine.yield(("readback rgba = (%s,%s,%s,%s)"):format(tostring(R), tostring(G), tostring(B), tostring(A)))
  local function near(x, e) return x ~= nil and math.abs(x - e) <= 2 end
  check("cleared pixel recovered (51,102,153,255)",
    near(R, 51) and near(G, 102) and near(B, 153) and near(A, 255),
    ("(%s,%s,%s,%s)"):format(tostring(R), tostring(G), tostring(B), tostring(A)))
end

coroutine.yield(("checks done, %d failures"):format(failures))
return failures == 0 and "STEP4-GRAPHICS-WITNESS: PASS" or "STEP4-GRAPHICS-WITNESS: FAIL"
