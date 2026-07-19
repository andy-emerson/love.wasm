-- Step-6.3 witness: the REAL love.window backend, on the love_win host seam,
-- driving the REAL love.graphics through a real present() — and, riding that,
-- the close of build-order step 4's last item (captureScreenshot reading the
-- presented backbuffer). Runs as the pump's resident coroutine (love is
-- preloaded by pump-ext), yielding one line per check so the host transcript
-- shows each fact as it lands. The final return value is the verdict.
--
-- What this proves that the windowless step-4 graphics witnesses could not:
--   * love.window.setMode creates a real canvas + WebGL2 context HOST-side and
--     hands it to graphics->setMode — the context handoff the SDL backend does
--     on desktop, now done over the love_win seam.
--   * With an open window registered as M_WINDOW, Graphics::isActive() is true,
--     so love.graphics.present() runs for real (flush + resolve + swapBuffers)
--     instead of early-returning windowless.
--   * captureScreenshot + present reads the PRESENTED system backbuffer (FBO 0)
--     back into an ImageData, and the drawn geometry is recovered from it —
--     end to end through the real window/present path.
local failures = 0
local function check(name, cond, got)
  if cond then
    coroutine.yield("ok   " .. name)
  else
    failures = failures + 1
    coroutine.yield("FAIL " .. name .. "   got: " .. tostring(got))
  end
end

local W, H = 64, 48

-- The LÖVE core links and registers.
local lok, love = pcall(require, "love")
check("require 'love'", lok and type(love) == "table", love)

-- love.window now loads (its backend is no longer a step-6 stop-line): the real
-- module registers on the wasm/love_win backend.
local wok, werr = pcall(require, "love.window")
check("require 'love.window' SUCCEEDS", wok and type(love.window) == "table", werr)

-- love.graphics creates the real opengl::Graphics instance.
local gok, gerr = pcall(require, "love.graphics")
check("require 'love.graphics' (opengl backend links + registers)",
  gok and type(love.graphics) == "table", gerr)

-- love.image registers the ImageData type (its metatable + methods): the
-- screenshot callback below receives an ImageData, and getPixel/getWidth are
-- only bound once love.image has opened.
local iok, ierr = pcall(require, "love.image")
check("require 'love.image' (ImageData type registered)",
  iok and type(love.image) == "table", ierr)

-- THE CRUX: setMode drives the host to create the real canvas + WebGL2 context
-- and binds graphics to it. stencil=true exercises the stencil attachment path.
local smok, smret = pcall(love.window.setMode, W, H, {stencil = true})
check("love.window.setMode(W,H,{stencil=true}) succeeds", smok and smret == true, smret)

check("love.window.isOpen() == true (present()'s isActive gate)",
  love.window.isOpen() == true, love.window.isOpen())

-- Window dimensions report the requested size (DPI scale 1.0 on the canvas).
-- love.window's Lua surface reports size via getMode()/getDesktopDimensions,
-- not getWidth (getWidth/getHeight are love.graphics, checked below).
local mw, mh = love.window.getMode()
check("love.window.getMode() reports (W,H)", mw == W and mh == H, tostring(mw) .. "x" .. tostring(mh))

local dw, dh = love.window.getDesktopDimensions()
check("love.window.getDesktopDimensions() == (W,H)", dw == W and dh == H, tostring(dw) .. "x" .. tostring(dh))

-- graphics reports the backbuffer size, proving it bound to the window's context.
check("love.graphics.getWidth() == W (backbuffer bound to window)",
  love.graphics.getWidth() == W, love.graphics.getWidth())
check("love.graphics.getHeight() == H (backbuffer bound to window)",
  love.graphics.getHeight() == H, love.graphics.getHeight())
check("love.graphics.getPixelWidth() == W",
  love.graphics.getPixelWidth() == W, love.graphics.getPixelWidth())

-- Draw something deterministic: clear to a known colour, then fill the LEFT HALF
-- (full height) with a distinct colour. Exact 8-bit values so readback is
-- unambiguous; the left/right split is purely horizontal, so inside-vs-outside
-- needs no Y reasoning.
local clearC = {0.2, 0.4, 0.6}  -- (51,102,153)
local drawC  = {0.8, 0.2, 0.2}  -- (204,51,51)

-- STEP-4 CLOSE: enqueue a screenshot, then present. The callback fires DURING
-- present() (after flush + resolve), receiving the ImageData read back from the
-- presented system backbuffer. Stash sampled pixels for the assertions below.
local shot = { fired = false }
local function grab(x, y)
  local r, g, b, a = shot.img:getPixel(x, y)
  return { math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), math.floor(a * 255 + 0.5) }
end

local drawOK, drawErr = pcall(function()
  love.graphics.clear(clearC[1], clearC[2], clearC[3], 1.0)
  love.graphics.setColor(drawC[1], drawC[2], drawC[3], 1.0)
  love.graphics.rectangle("fill", 0, 0, W / 2, H)
  love.graphics.setColor(1, 1, 1, 1)

  love.graphics.captureScreenshot(function(imageData)
    shot.fired = true
    shot.img = imageData
    shot.w, shot.h = imageData:getWidth(), imageData:getHeight()
    shot.inside = grab(math.floor(W / 4), math.floor(H / 2))   -- inside the rect
    shot.outside = grab(math.floor(3 * W / 4), math.floor(H / 2)) -- outside the rect
  end)

  love.graphics.present()
end)
check("clear + rectangle + captureScreenshot + present executes", drawOK, drawErr)

check("screenshot callback fired during present() (isActive was true)", shot.fired == true)
check("ImageData dimensions match backbuffer (W,H)",
  shot.w == W and shot.h == H, tostring(shot.w) .. "x" .. tostring(shot.h))

local function near(v, e) return v ~= nil and math.abs(v - e) <= 2 end

if shot.inside then
  coroutine.yield(("inside  rgba = (%d,%d,%d,%d)"):format(shot.inside[1], shot.inside[2], shot.inside[3], shot.inside[4]))
  check("drawn pixel recovered from presented backbuffer (204,51,51,255)",
    near(shot.inside[1], 204) and near(shot.inside[2], 51) and near(shot.inside[3], 51) and near(shot.inside[4], 255),
    ("(%d,%d,%d,%d)"):format(shot.inside[1], shot.inside[2], shot.inside[3], shot.inside[4]))
end

if shot.outside then
  coroutine.yield(("outside rgba = (%d,%d,%d,%d)"):format(shot.outside[1], shot.outside[2], shot.outside[3], shot.outside[4]))
  check("clear pixel recovered from presented backbuffer (51,102,153,255)",
    near(shot.outside[1], 51) and near(shot.outside[2], 102) and near(shot.outside[3], 153) and near(shot.outside[4], 255),
    ("(%d,%d,%d,%d)"):format(shot.outside[1], shot.outside[2], shot.outside[3], shot.outside[4]))
end

coroutine.yield(("checks done, %d failures"):format(failures))
return failures == 0 and "STEP6-WIN-WITNESS: PASS" or "STEP6-WIN-WITNESS: FAIL"
