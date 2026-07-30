-- Build-order step 6.4 witness: love.event + love.keyboard + love.mouse on the
-- love_input host seam. Runs as the pump's resident coroutine (love preloaded by
-- pump-ext), yielding one line per check; the final return value is the verdict.
--
-- The host (wasi/host/input-host.mjs) has PRE-SEEDED a fixed script of DOM events
-- into its queue. This witness drives ONE love.event.pump() — the wasm Event
-- backend drains that queue via the input_poll import, translating each DOM event
-- into a love::event::Message (the exact job event/sdl/Event.cpp::convert does for
-- SDL) AND updating the shared input snapshot. We then:
--   (1) drain love.event.poll() and assert the callback name + args of every
--       message, in order — proving the host->guest PUSH path and the DOM<->LÖVE
--       name/button translation; and
--   (2) query love.keyboard / love.mouse and assert they reflect exactly what the
--       pump saw — proving the shared-state reader split (isDown / getPosition).
--
-- The seeded script (see input-host.mjs) is:
--   keydown KeyA · textinput "A" · keyup KeyA · keydown ArrowLeft(left held) ·
--   mousemoved(10,20,+10,+20) · mousepressed left · mousepressed right ·
--   mousereleased left · wheelmoved(0,1,standard) · resize(800,600) ·
--   touchpressed 7 · touchmoved 7 · touchpressed 9 · touchreleased 7 · quit
--
-- The touch tail is two fingers on purpose: love.touch keeps a LIST of live
-- touches, so a single finger would not tell a working list from a single slot.
-- After the pump, finger 9 must be the only one left.
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
local kok = pcall(require, "love.keyboard")
check("require 'love.keyboard' SUCCEEDS", kok and type(love.keyboard) == "table", kok)
local mok = pcall(require, "love.mouse")
check("require 'love.mouse' SUCCEEDS", mok and type(love.mouse) == "table", mok)
local tok = pcall(require, "love.touch")
check("require 'love.touch' SUCCEEDS", tok and type(love.touch) == "table", tok)

-- Drain the host queue into the event queue + update input state.
local pok, perr = pcall(love.event.pump)
check("love.event.pump() does not throw", pok, perr)

-- Collect the whole translated message sequence.
-- Eight slots, because a touch message carries the most: id, x, y, dx, dy,
-- pressure, devicetype, mouse.
local msgs = {}
for name, a, b, c, d, e, f, g, h in love.event.poll() do
  msgs[#msgs + 1] = { name, a, b, c, d, e, f, g, h }
end
check("pump produced 15 messages", #msgs == 15, #msgs)

local function m(i) return msgs[i] or {} end
local function eq(i, name, a, b, c, d)
  local r = m(i)
  local ok = r[1] == name
  if a ~= nil then ok = ok and r[2] == a end
  if b ~= nil then ok = ok and r[3] == b end
  if c ~= nil then ok = ok and r[4] == c end
  if d ~= nil then ok = ok and r[5] == d end
  return ok, string.format("%s(%s,%s,%s,%s)", tostring(r[1]), tostring(r[2]), tostring(r[3]), tostring(r[4]), tostring(r[5]))
end

-- keydown KeyA -> keypressed(key="a", scancode="a", isrepeat=false)
local ok1, g1 = eq(1, "keypressed", "a", "a", false)
check("msg1 keypressed a/a/false", ok1, g1)
-- textinput "A" (the actual typed char rides through faithfully)
local ok2, g2 = eq(2, "textinput", "A")
check("msg2 textinput 'A'", ok2, g2)
-- keyup KeyA -> keyreleased(a, a)
local ok3, g3 = eq(3, "keyreleased", "a", "a")
check("msg3 keyreleased a/a", ok3, g3)
-- keydown ArrowLeft -> keypressed(left, left, false)
local ok4, g4 = eq(4, "keypressed", "left", "left", false)
check("msg4 keypressed left/left/false", ok4, g4)
-- mousemoved(10,20, dx=10, dy=20, istouch=false)
local ok5, g5 = eq(5, "mousemoved", 10, 20, 10, 20)
check("msg5 mousemoved 10,20,10,20", ok5 and m(5)[6] == false, g5)
-- mousepressed left -> button 1 (DOM 0 -> LÖVE 1)
local ok6, g6 = eq(6, "mousepressed", 10, 20, 1)
check("msg6 mousepressed x10 y20 button1(left)", ok6, g6)
-- mousepressed right -> button 2 (DOM 2 -> LÖVE 2)
local ok7, g7 = eq(7, "mousepressed", 10, 20, 2)
check("msg7 mousepressed button2(right)", ok7, g7)
-- mousereleased left -> button 1
local ok8, g8 = eq(8, "mousereleased", 10, 20, 1)
check("msg8 mousereleased button1(left)", ok8, g8)
-- wheelmoved(0,1,"standard")
local ok9, g9 = eq(9, "wheelmoved", 0, 1, "standard")
check("msg9 wheelmoved 0,1,standard", ok9, g9)
-- resize(800,600)
local ok10, g10 = eq(10, "resize", 800, 600)
check("msg10 resize 800,600", ok10, g10)
-- ── love.touch ──────────────────────────────────────────────────────────────
-- The id reaches Lua as lightuserdata (upstream's choice — a double cannot hold
-- every id), so it is compared by identity across messages, never by value.
local t11, t12, t13, t14 = m(11), m(12), m(13), m(14)
check("msg11 touchpressed", t11[1] == "touchpressed", t11[1])
check("msg11 x,y = 30,40", t11[3] == 30 and t11[4] == 40, tostring(t11[3]) .. "," .. tostring(t11[4]))
check("msg11 dx,dy = 0,0 (a press has no delta)", t11[5] == 0 and t11[6] == 0, tostring(t11[5]) .. "," .. tostring(t11[6]))
check("msg11 pressure = 1", t11[7] == 1, t11[7])
check("msg11 devicetype = touchscreen", t11[8] == "touchscreen", t11[8])
check("msg11 mouse = false (a browser never synthesizes touch from the mouse)", t11[9] == false, t11[9])
check("msg11 id is lightuserdata", type(t11[2]) == "userdata", type(t11[2]))

check("msg12 touchmoved, same finger as msg11", t12[1] == "touchmoved" and t12[2] == t11[2], t12[1])
check("msg12 x,y = 35,48", t12[3] == 35 and t12[4] == 48, tostring(t12[3]) .. "," .. tostring(t12[4]))
check("msg12 dx,dy = 5,8 (the move carries its delta)", t12[5] == 5 and t12[6] == 8, tostring(t12[5]) .. "," .. tostring(t12[6]))
check("msg12 pressure = 0.5", t12[7] == 0.5, t12[7])

check("msg13 touchpressed, a DIFFERENT finger", t13[1] == "touchpressed" and t13[2] ~= t11[2], t13[1])
check("msg14 touchreleased, the FIRST finger", t14[1] == "touchreleased" and t14[2] == t11[2], t14[1])

-- The live-touch list: the module's state, updated by the pump as it converts,
-- which is the half love.event.poll() cannot show.
local touches = love.touch.getTouches()
check("getTouches() has exactly the one finger still down", #touches == 1, #touches)
if #touches == 1 then
  check("the survivor is finger 9, not finger 7", touches[1] == t13[2], tostring(touches[1]))
  local tx, ty = love.touch.getPosition(touches[1])
  check("getPosition(9) = 60,70", tx == 60 and ty == 70, tostring(tx) .. "," .. tostring(ty))
  check("getPressure(9) = 0.25", love.touch.getPressure(touches[1]) == 0.25, love.touch.getPressure(touches[1]))
  check("getDeviceType(9) = touchscreen", love.touch.getDeviceType(touches[1]) == "touchscreen", love.touch.getDeviceType(touches[1]))
  -- A released finger must be gone, not merely absent from the list.
  check("getPosition on the RELEASED finger errors", not pcall(love.touch.getPosition, t11[2]), "no error")
end

-- quit
check("msg15 quit", m(15)[1] == "quit", m(15)[1])

-- Now the shared-state readers. After the pump: 'a' was pressed then released,
-- 'left' is still held; left mouse pressed then released, right still held; last
-- cursor position (10,20).
check("keyboard.isScancodeDown('left') == true", love.keyboard.isScancodeDown("left") == true, love.keyboard.isScancodeDown("left"))
check("keyboard.isDown('left') == true", love.keyboard.isDown("left") == true, love.keyboard.isDown("left"))
check("keyboard.isDown('a') == false (released)", love.keyboard.isDown("a") == false, love.keyboard.isDown("a"))
check("keyboard.isScancodeDown('a') == false", love.keyboard.isScancodeDown("a") == false, love.keyboard.isScancodeDown("a"))

local mx, my = love.mouse.getPosition()
check("mouse.getPosition() == 10,20", mx == 10 and my == 20, tostring(mx) .. "," .. tostring(my))
check("mouse.isDown(1) == false (left released)", love.mouse.isDown(1) == false, love.mouse.isDown(1))
check("mouse.isDown(2) == true (right held)", love.mouse.isDown(2) == true, love.mouse.isDown(2))

-- Query-API round trips through the layout-static name maps.
check("getScancodeFromKey('a') == 'a'", love.keyboard.getScancodeFromKey("a") == "a", love.keyboard.getScancodeFromKey("a"))
check("getKeyFromScancode('left') == 'left'", love.keyboard.getKeyFromScancode("left") == "left", love.keyboard.getKeyFromScancode("left"))

-- setKeyRepeat / hasKeyRepeat round-trip.
love.keyboard.setKeyRepeat(true)
check("setKeyRepeat/hasKeyRepeat round-trips", love.keyboard.hasKeyRepeat() == true, love.keyboard.hasKeyRepeat())

coroutine.yield(("checks done, %d failures"):format(failures))
return failures == 0 and "STEP64-INPUT-WITNESS: PASS" or "STEP64-INPUT-WITNESS: FAIL"
