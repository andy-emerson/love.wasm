-- Step-4 (4.5b) witness: creating a shader must not disturb what is bound.
--
-- 4.5 proves a user shader compiles, binds and executes. It cannot prove this,
-- because it draws WITH its shader: setShader() re-binds a program immediately
-- after newShader(), so anything newShader() broke is repaired before the draw.
-- The uncovered case is the one every real game hits — love.load creates shaders
-- to use later, and the frame keeps drawing with the DEFAULT shader.
--
-- That case drew nothing at all. Shader::loadVolatile saves GL_CURRENT_PROGRAM,
-- binds its new program to inspect uniforms, and restores what it saved; the
-- WebGL host reported that query as 0 — "nothing bound" — so the restore
-- unbound the default shader while LÖVE's `current` cache still believed it was
-- attached, and every later draw failed with GL_INVALID_OPERATION. The clear
-- colour still reached the screen, so the game looked like it was running.
--
-- The bridge draws the left half with the default shader, creates a shader it
-- NEVER attaches, then draws the right half the same way. The RIGHT half is the
-- assertion; the left half is the control proving the draw path worked before
-- the shader existed. Chromium only.
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

local gok = pcall(require, "love.graphics")
check("require 'love.graphics' (opengl backend links + registers)",
  gok and type(love.graphics) == "table", love.graphics)

local function near(x, e) return x ~= nil and math.abs(x - e) <= 2 end
local function rgba(r, g, b, a) return ("(%s,%s,%s,%s)"):format(tostring(r),tostring(g),tostring(b),tostring(a)) end

local ok, Rl, Gl, Bl, Al, Rr, Gr, Br, Ar = pcall(__wasi_gfx_draw_shader_unused)
check("draw + newShader (never attached) + draw executes", ok, ok and "" or Rl)
if ok then
  coroutine.yield(("before shader = %s   after shader = %s"):format(rgba(Rl,Gl,Bl,Al), rgba(Rr,Gr,Br,Ar)))
  check("control: the draw BEFORE newShader lands (204,153,102)",
    near(Rl,204) and near(Gl,153) and near(Bl,102) and near(Al,255), rgba(Rl,Gl,Bl,Al))
  -- The regression: this reads back as the clear colour (76,76,76) when creating
  -- a shader has unbound the program, because the draw is silently dropped.
  check("the draw AFTER newShader still lands (204,153,102) — an unused shader did not unbind the program",
    near(Rr,204) and near(Gr,153) and near(Br,102) and near(Ar,255), rgba(Rr,Gr,Br,Ar))
end

coroutine.yield(("checks done, %d failures"):format(failures))
return failures == 0 and "SHADER-UNUSED-WITNESS: PASS" or "SHADER-UNUSED-WITNESS: FAIL"
