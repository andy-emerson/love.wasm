-- love.shim witness (D21, #64). Runs as the pump's resident coroutine on the
-- LOVE + DATA + PHYSICS artifact, so it can exercise both tiers the shim has:
-- the Lua 5.1 restorations, and the LÖVE 11.5 API names 12 removed.
--
-- The physics artifact is the right host for a first witness because physics is
-- 13 of the 27 absent names, and it carries the only group whose adaptation is
-- not a rename — the spring parameters, which changed units between 11.5 and 12.
--
-- Each leg yields one line so the host transcript shows facts as they land.
local failures = 0
local function check(name, cond, got)
	if cond then
		coroutine.yield("ok   " .. name)
	else
		failures = failures + 1
		coroutine.yield("FAIL " .. name .. "   got: " .. tostring(got))
	end
end

local function near(a, b, tol)
	if type(a) ~= "number" or type(b) ~= "number" then return false end
	return math.abs(a - b) <= (tol or 1e-3) * math.max(1.0, math.abs(b))
end

require("love")
require("love.data")
require("love.physics")

local shim = require("love.shim")

-- LEG 1 — before applying, the 5.1 names really are absent. Without this the
-- rest of the witness could pass on a runtime that never needed a shim.
check("pre: unpack absent under 5.4", rawget(_G, "unpack") == nil, rawget(_G, "unpack"))
check("pre: math.atan2 absent under 5.4", math.atan2 == nil, math.atan2)
check("pre: love.math.compress absent in 12", love.math == nil or love.math.compress == nil)
check("pre: World:getBodyList absent in 12", love.physics ~= nil)

shim.apply(_G, love)

-- LEG 2 — the Lua 5.1 tier.
check("unpack restored", type(unpack) == "function" and select("#", unpack({ 1, 2, 3 })) == 3)
check("unpack returns the values", (select(2, unpack({ 7, 8, 9 }))) == 8)
check("table.getn restored", table.getn({ "a", "b" }) == 2)
check("math.atan2 restored and correct", near(math.atan2(1, 1), math.pi / 4))
check("math.pow restored", math.pow(2, 10) == 1024)
check("math.log10 restored", near(math.log10(1000), 3))
check("math.ldexp restored", math.ldexp(0.75, 4) == 12)
do
	local m, e = math.frexp(12)
	check("math.frexp restored (mantissa in [0.5,1))", m >= 0.5 and m < 1.0, m)
	check("math.frexp round-trips through ldexp", near(math.ldexp(m, e), 12))
end
check("loadstring restored", loadstring("return 41 + 1")() == 42)
check("string.gfind restored", (function()
	local n = 0
	for _ in string.gfind("a b c", "%a") do n = n + 1 end
	return n
end)() == 3)

-- LEG 3 — the declined set is REPORTED, not silently missing. This is the
-- non-goal list being visible rather than stated (D21).
do
	local _, declined = shim.report()
	local sawSetfenv = false
	for _, d in ipairs(declined) do
		if tostring(d):find("setfenv") then sawSetfenv = true end
	end
	check("setfenv is declined and declared, not faked", sawSetfenv and setfenv == nil, setfenv)
end

-- LEG 4 — the shim must survive a PARTIAL BUILD. That is not a hypothetical
-- here: every love.wasm artifact links a subset, and this one carries LOVE +
-- DATA + PHYSICS with no love.math at all. A shim that assumed a whole engine
-- would crash before a single name was restored, so each tier is guarded by a
-- presence check and the absent ones are simply not installed.
check("shim survives a build with no love.math", love.math == nil or type(love.math) == "table")
if love.math == nil then
	coroutine.yield("skip love.math.compress — module not linked in this artifact")
else
	-- Removed in 12; adapted onto love.data. Argument order differs between the
	-- two, so this is adaptation rather than aliasing.
	local payload = string.rep("love.wasm ", 64)
	local cd = love.math.compress(payload, "lz4")
	local back = love.math.decompress(cd)
	check("love.math.compress round-trips through love.data", back == payload,
		type(back) == "string" and #back or back)
end

-- LEG 5 — the physics list renames. 12.0 merged fixtures into shapes, so a
-- body's fixture list IS its shape list.
local world = love.physics.newWorld(0, 9.81, true)
local body = love.physics.newBody(world, 0, 0, "dynamic")
local shape = love.physics.newCircleShape(1)
love.physics.newFixture(body, shape, 1) -- upstream's own deprecated entry point

check("World:getBodyList restored", type(world:getBodyList()) == "table" and #world:getBodyList() >= 1)
check("Body:getFixtureList restored (-> getShapes)", #body:getFixtureList() >= 1)
check("World:getJointList restored", type(world:getJointList()) == "table")
check("World:getContactList restored", type(world:getContactList()) == "table")

-- LEG 6 — the spring family: the one group that is a UNITS change, not a
-- rename. The shim routes through the engine's own exact conversion, so a
-- frequency set in 11.5 units must read back as the same frequency.
do
	local b2 = love.physics.newBody(world, 5, 0, "dynamic")
	love.physics.newFixture(b2, love.physics.newCircleShape(1), 1)
	local dj = love.physics.newDistanceJoint(body, b2, 0, 0, 5, 0, false)

	check("DistanceJoint:setFrequency restored", type(dj.setFrequency) == "function")
	dj:setFrequency(4.0)
	dj:setDampingRatio(0.5)
	check("frequency round-trips through the stiffness conversion", near(dj:getFrequency(), 4.0, 1e-2), dj:getFrequency())
	check("damping ratio round-trips", near(dj:getDampingRatio(), 0.5, 1e-2), dj:getDampingRatio())

	-- And it is a real conversion, not a stored value: 12's own units must have
	-- moved. A stub that just remembered 4.0 would leave stiffness at zero.
	check("the conversion actually reached 12's stiffness", dj:getStiffness() > 0, dj:getStiffness())
end

-- LEG 7 — WheelJoint spells the same four with a "Spring" infix.
do
	local b3 = love.physics.newBody(world, 9, 0, "dynamic")
	love.physics.newFixture(b3, love.physics.newCircleShape(1), 1)
	local wj = love.physics.newWheelJoint(body, b3, 9, 0, 0, 1)
	check("WheelJoint:setSpringFrequency restored", type(wj.setSpringFrequency) == "function")
	wj:setSpringFrequency(3.0)
	check("spring frequency round-trips", near(wj:getSpringFrequency(), 3.0, 1e-2), wj:getSpringFrequency())
end

-- LEG 8 — the shim is safe in both directions, and idempotent on BOTH tiers.
-- The Lua tier is idempotent for free, because install() refuses to overwrite.
-- The LÖVE tier is not free: it patches metatables through wrapped constructors
-- and has to remember what it already did. An earlier revision did not, and
-- reported every physics patch twice on the second apply.
--
-- WHAT THIS LEG ACTUALLY DETECTS, per §4.4, because the mutation runs were more
-- interesting than expected. Two guards defend idempotency — patchOnFirst's
-- `patched` set, and note()'s `seen` set — and removing EITHER ALONE leaves the
-- witness green, because the other still suppresses the duplicate. Only
-- removing BOTH turns it red (it then reports 24 installs instead of 18).
-- So this leg is a detector for the pair, not for either guard: the two are
-- deliberately redundant, and no leg here can tell you which one is carrying
-- the weight. Said plainly rather than left as an unearned claim.
do
	local before = math.atan2
	local beforeCount = #(select(1, shim.report()))
	shim.apply(_G, love)
	check("re-applying does not overwrite a restored Lua name", math.atan2 == before)
	check("re-applying does not re-report the LÖVE tier",
		#(select(1, shim.report())) == beforeCount, #(select(1, shim.report())))

	-- And the double-wrap is gone: a joint built AFTER the second apply must
	-- still get working spring methods exactly once.
	local b4 = love.physics.newBody(world, 20, 0, "dynamic")
	love.physics.newFixture(b4, love.physics.newCircleShape(1), 1)
	local dj2 = love.physics.newDistanceJoint(body, b4, 0, 0, 20, 0, false)
	dj2:setFrequency(2.0)
	check("a joint built after re-apply still converts correctly", near(dj2:getFrequency(), 2.0, 1e-2), dj2:getFrequency())
end

-- LEG 9 — detection, keyed off the t.version LÖVE already reads (boot.lua:378).
check("wantsShim('11.5') is true", shim.wantsShim("11.5") == true)
check("wantsShim('12.0') is false", shim.wantsShim("12.0") == false)
check("wantsShim(nil) assumes old", shim.wantsShim(nil) == true)

-- LEG 10 — declared, never silent (D9): the report names what was installed.
do
	local applied = shim.report()
	check("the shim reports what it installed", #applied >= 12, #applied)
	coroutine.yield(shim.describe())
end

if failures == 0 then
	return "SHIM-WITNESS: PASS"
end
return "SHIM-WITNESS: FAIL (" .. failures .. ")"
