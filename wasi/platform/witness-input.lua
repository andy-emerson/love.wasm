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
--   mousereleased left · wheelmoved(0,1,standard) · resize(800,600) · quit
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

-- Drain the host queue into the event queue + update input state.
local pok, perr = pcall(love.event.pump)
check("love.event.pump() does not throw", pok, perr)

-- Collect the whole translated message sequence.
local msgs = {}
for name, a, b, c, d, e in love.event.poll() do
  msgs[#msgs + 1] = { name, a, b, c, d, e }
end
check("pump produced 11 messages", #msgs == 11, #msgs)

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
-- quit
check("msg11 quit", m(11)[1] == "quit", m(11)[1])

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
