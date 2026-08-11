-- love.physics (Box2D) link witness — pre-step-7 "unblock a real game" work.
-- Pure compute: no graphics, no window, no host imports. Runs as the pump's
-- resident coroutine (love preloaded by pump-ext), yielding one line per check;
-- the final return value is the verdict. Runs on node:wasi AND real Chromium.
--
-- What this proves: love.physics requires and a real Box2D world simulates. A
-- dynamic body with a shape attached (12.0 merged fixtures into shapes, so the
-- shape carries density and gives the body mass) FALLS under gravity — its
-- position advances in +y (down in LÖVE) and it gains downward velocity — while
-- staying put horizontally. Box2D is in-tree, single-threaded, and needs no seam;
-- world:update takes dt as a plain argument, so no clock (love.timer) is needed.
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

local pok = pcall(require, "love.physics")
check("require 'love.physics' SUCCEEDS", pok and type(love.physics) == "table", pok)

-- A world with downward gravity (+y is down in LÖVE); allow bodies to sleep.
local world = love.physics.newWorld(0, 9.81, true)
check("newWorld returns a World", type(world) == "userdata", world)

-- A dynamic body at the origin. In 12.0 a shape attaches to a body directly and
-- carries the density that gives the body its mass (no fixtures).
local body = love.physics.newBody(world, 0, 0, "dynamic")
check("newBody('dynamic') returns a Body", type(body) == "userdata", body)

local shape = love.physics.newRectangleShape(body, 0, 0, 10, 10)
check("newRectangleShape attaches to the body", type(shape) == "userdata", shape)
check("shape:getType() == 'polygon'", shape:getType() == "polygon", shape:getType())
check("shape:getBody() links back to the body", shape:getBody() == body, shape:getBody())
check("body has nonzero mass (the shape gave it mass)", body:getMass() > 0, body:getMass())
check("world:getBodyCount() == 1", world:getBodyCount() == 1, world:getBodyCount())

local x0, y0 = body:getPosition()
check("body starts at the origin", math.abs(x0) < 1e-6 and math.abs(y0) < 1e-6,
  tostring(x0) .. "," .. tostring(y0))

-- Simulate ~1 second at a fixed 1/60 dt (dt is a plain argument — no clock).
for _ = 1, 60 do world:update(1 / 60) end

local x1, y1 = body:getPosition()
local vx, vy = body:getLinearVelocity()
check("body FELL under gravity (y advanced in +y)", y1 > y0 + 1.0,
  tostring(y0) .. " -> " .. tostring(y1))
check("body gained downward velocity (vy > 0)", vy > 0, vy)
check("no sideways drift (x unchanged)", math.abs(x1 - x0) < 1e-3, x1)

coroutine.yield(("checks done, %d failures"):format(failures))
return failures == 0 and "STEP-PHYSICS-WITNESS: PASS" or "STEP-PHYSICS-WITNESS: FAIL"
