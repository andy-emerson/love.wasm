-- Build-order step 6.5 witness: love.joystick + love.gamepad on the love_gamepad
-- host seam (the browser Gamepad API). Runs as the pump's resident coroutine
-- (love preloaded by pump-ext), yielding one line per check; the final return
-- value is the verdict.
--
-- The seam is POLL-based (unlike 6.4's push queue): each love.event.pump() calls
-- the gamepad poll once (via the weak hook in the event backend), which calls the
-- host's gamepad_count() once — ADVANCING the host's scripted frame — then DIFFS
-- the new gamepad state against the previous poll to synthesize the joystick/
-- gamepad Messages SDL would push. So three pumps observe three scripted frames:
--   frame0: 1 standard gamepad "Test Controller", A(0) pressed, leftx = +0.5
--   frame1: A(0) released, B(1) pressed, leftx = -1.0
--   frame2: no gamepads (disconnected)
-- We drain love.event.poll() after each pump and assert the synthesized events,
-- then query love.joystick and assert it reflects exactly what the poll saw.
--
-- getGamepadAxis returns a float through the f32 seam + clampval, so axis value
-- checks use a tolerance rather than exact equality.
local failures = 0
local function check(name, cond, got)
  if cond then
    coroutine.yield("ok   " .. name)
  else
    failures = failures + 1
    coroutine.yield("FAIL " .. name .. "   got: " .. tostring(got))
  end
end

local lok, love = pcall(require, "love")
check("require 'love'", lok and type(love) == "table", love)

local eok = pcall(require, "love.event")
check("require 'love.event' SUCCEEDS", eok and type(love.event) == "table", eok)
local jok = pcall(require, "love.joystick")
check("require 'love.joystick' SUCCEEDS", jok and type(love.joystick) == "table", jok)

-- Drain the event queue into a flat list. For joystick/gamepad messages arg1 is
-- the Joystick object; arg2/arg3 are the button/axis and value.
local function drain()
  local list = {}
  for name, a, b, c in love.event.poll() do
    list[#list + 1] = { name = name, stick = a, b = b, c = c }
  end
  return list
end

-- Does the list contain a message with this name (and optional 2nd/3rd args)?
-- tol, if given, matches the 3rd arg within a numeric tolerance.
local function has(list, name, arg2, arg3, tol)
  for _, m in ipairs(list) do
    if m.name == name then
      local ok = true
      if arg2 ~= nil then ok = ok and (m.b == arg2) end
      if arg3 ~= nil then
        if tol then
          ok = ok and (type(m.c) == "number" and math.abs(m.c - arg3) < tol)
        else
          ok = ok and (m.c == arg3)
        end
      end
      if ok then return true end
    end
  end
  return false
end

-- ── pump1: frame0 — connect + A pressed + leftx 0.5 ──────────────────────────
local pok = pcall(love.event.pump)
check("pump1 love.event.pump() does not throw", pok, pok)
local l1 = drain()
check("pump1 joystickadded", has(l1, "joystickadded"))
check("pump1 raw joystickpressed(1)", has(l1, "joystickpressed", 1))
check("pump1 gamepadpressed 'a'", has(l1, "gamepadpressed", "a"))
check("pump1 raw joystickaxis(1, ~0.5)", has(l1, "joystickaxis", 1, 0.5, 0.01))
check("pump1 gamepadaxis 'leftx' ~0.5", has(l1, "gamepadaxis", "leftx", 0.5, 0.01))

check("getJoystickCount() == 1", love.joystick.getJoystickCount() == 1, love.joystick.getJoystickCount())
local js = love.joystick.getJoysticks()[1]
check("getJoysticks()[1] is a Joystick", js ~= nil, js)
check("js:isGamepad() == true", js:isGamepad() == true, js:isGamepad())
check("js:isGamepadDown('a') == true", js:isGamepadDown("a") == true, js:isGamepadDown("a"))
check("js:getGamepadAxis('leftx') ~= 0.5", math.abs(js:getGamepadAxis("leftx") - 0.5) < 0.01, js:getGamepadAxis("leftx"))
check("js:getName() == 'Test Controller'", js:getName() == "Test Controller", js:getName())
check("js:getAxisCount() == 4", js:getAxisCount() == 4, js:getAxisCount())
check("js:getHatCount() == 0", js:getHatCount() == 0, js:getHatCount())

-- ── pump2: frame1 — A released, B pressed, leftx -1.0 ────────────────────────
check("pump2 love.event.pump() does not throw", pcall(love.event.pump), true)
local l2 = drain()
check("pump2 gamepadreleased 'a'", has(l2, "gamepadreleased", "a"))
check("pump2 gamepadpressed 'b'", has(l2, "gamepadpressed", "b"))
check("pump2 gamepadaxis 'leftx' ~-1.0", has(l2, "gamepadaxis", "leftx", -1.0, 0.01))
check("pump2 raw joystickpressed(2)", has(l2, "joystickpressed", 2))
check("js:isGamepadDown('b') == true", js:isGamepadDown("b") == true, js:isGamepadDown("b"))
check("js:isGamepadDown('a') == false", js:isGamepadDown("a") == false, js:isGamepadDown("a"))
check("js:getGamepadAxis('leftx') ~= -1.0", math.abs(js:getGamepadAxis("leftx") - (-1.0)) < 0.01, js:getGamepadAxis("leftx"))

-- ── pump3: frame2 — disconnected ─────────────────────────────────────────────
check("pump3 love.event.pump() does not throw", pcall(love.event.pump), true)
local l3 = drain()
check("pump3 joystickremoved", has(l3, "joystickremoved"))
check("getJoystickCount() == 0 (removed)", love.joystick.getJoystickCount() == 0, love.joystick.getJoystickCount())

coroutine.yield(("checks done, %d failures"):format(failures))
return failures == 0 and "STEP65-JOYSTICK-WITNESS: PASS" or "STEP65-JOYSTICK-WITNESS: FAIL"
