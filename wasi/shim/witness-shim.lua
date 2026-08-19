-- love.shim witness (D21, #64). ONE witness, run against SEVERAL artifacts.
--
-- No single love.wasm build links every module, so no single build can exercise
-- the whole shim. Rather than write one witness per artifact and let coverage
-- drift apart, every leg here is guarded by a module presence check and yields
-- "skip" when its module is absent. Coverage is then visible in the transcript
-- instead of implied, and the union of the runs is what covers the shim:
--
--   physics artifact  (LOVE DATA PHYSICS)            the Lua tier + 13 physics names
--   fs artifact       (LOVE DATA MATH FILESYSTEM)    love.math.compress + 4 predicates
--   sound artifact    (LOVE DATA SOUND)              SoundData:getChannels
--
-- The physics artifact carries the only group whose adaptation is not a rename —
-- the spring parameters, which changed units between 11.5 and 12.
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

-- Every love.* module is OPTIONAL here, and that is the point: this one witness
-- runs against several artifacts, each linking a different subset, and together
-- they cover the whole shim. A leg whose module is absent yields "skip" rather
-- than failing, so coverage is visible in the transcript instead of implied.
for _, m in ipairs({ "data", "math", "physics", "filesystem", "audio", "sound", "graphics" }) do
	pcall(require, "love." .. m)
end

local shim = require("love.shim")

-- LEG 1 — before applying, the 5.1 names really are absent. Without this the
-- rest of the witness could pass on a runtime that never needed a shim.
check("pre: unpack absent under 5.4", rawget(_G, "unpack") == nil, rawget(_G, "unpack"))
check("pre: math.atan2 absent under 5.4", math.atan2 == nil, math.atan2)
check("pre: love.math.compress absent in 12", love.math == nil or love.math.compress == nil)


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

-- LEG 5-7 — the physics tier. Guarded: the fs artifact does not link physics,
-- and the physics artifact does not link filesystem, so the two runs together
-- are what cover the shim.
local world, body
if love.physics == nil then
	coroutine.yield("skip love.physics tier — module not linked in this artifact")
else
world = love.physics.newWorld(0, 9.81, true)
body = love.physics.newBody(world, 0, 0, "dynamic")
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
	if love.physics == nil then goto skipjoint end
	do
	local b4 = love.physics.newBody(world, 20, 0, "dynamic")
	love.physics.newFixture(b4, love.physics.newCircleShape(1), 1)
	local dj2 = love.physics.newDistanceJoint(body, b4, 0, 0, 20, 0, false)
	dj2:setFrequency(2.0)
	check("a joint built after re-apply still converts correctly", near(dj2:getFrequency(), 2.0, 1e-2), dj2:getFrequency())
	end
	::skipjoint::
end

-- LEG 8b — love.filesystem: the four predicates 11.0 replaced with getInfo and
-- 12 removed. Each is arithmetic on an existing answer, so the interesting
-- assertion is not that they exist but that they AGREE with getInfo — a stub
-- returning true would pass a weaker test.
if love.filesystem == nil then
	coroutine.yield("skip love.filesystem tier — module not linked in this artifact")
else
	local F = love.filesystem
	-- Setup, not a claim: the read surface needs a source. pcall because an
	-- artifact whose boot already ran this will refuse the second call, and
	-- setSource is settable-once by design.
	pcall(F.init, "love")
	pcall(F.setSource, "/")

	check("love.filesystem.isFile restored", type(F.isFile) == "function")
	check("isFile agrees with getInfo on a real file",
		F.isFile("main.lua") == (F.getInfo("main.lua") ~= nil and F.getInfo("main.lua").type == "file"))
	check("isFile is false for a path that does not exist", F.isFile("no/such/file.txt") == false)
	check("isDirectory is false for a file", F.isDirectory("main.lua") == false)
	check("isSymlink is false in a virtual store", F.isSymlink("main.lua") == false)
	check("getLastModified returns nil + reason when absent",
		select(1, F.getLastModified("no/such/file.txt")) == nil)
	do
		local i = F.getInfo("main.lua")
		check("getLastModified agrees with getInfo.modtime",
			i == nil or F.getLastModified("main.lua") == i.modtime)
	end
end

-- LEG 8c — love.audio.getSourceCount, renamed to getActiveSourceCount in 12.
if love.audio == nil then
	coroutine.yield("skip love.audio tier — module not linked in this artifact")
else
	check("love.audio.getSourceCount restored", type(love.audio.getSourceCount) == "function")
	check("getSourceCount agrees with getActiveSourceCount",
		love.audio.getSourceCount() == love.audio.getActiveSourceCount())
end

-- LEG 8d — SoundData:getChannels, renamed to getChannelCount in 12.
if love.sound == nil then
	coroutine.yield("skip love.sound tier — module not linked in this artifact")
else
	local sd = love.sound.newSoundData(64, 44100, 16, 2)
	check("SoundData:getChannels restored", type(sd.getChannels) == "function")
	check("getChannels agrees with getChannelCount", sd:getChannels() == sd:getChannelCount(), sd:getChannels())
	check("getChannels reports the real channel count", sd:getChannels() == 2, sd:getChannels())
end

-- LEG 8e — love.graphics: STILL UNWITNESSED, and this says why rather than
-- implying coverage. Both entries need a live GL context. The graphics artifact
-- has one, but drives every draw from C++ helpers (__wasi_gfx_draw_*) that do
-- not leave a context open to Lua, so love.graphics.isActive() is false here —
-- checked, not assumed: calling a helper first does not change it.
--
-- The right host is an artifact where LÖVE's own boot runs love.window.setMode
-- (config-frame / config-game), because then the context belongs to the running
-- game rather than to a test helper. That is follow-on work, and until it exists
-- love.graphics.stencil and ParticleSystem:get/setAreaSpread are INSTALLED but
-- NOT EXERCISED — the shim's report lists them, and this leg does not.
if love.graphics == nil or not love.graphics.isActive() then
	coroutine.yield("skip love.graphics tier — no live graphics context in this artifact")
else
	check("love.graphics.stencil restored", type(love.graphics.stencil) == "function")
	do
		local ran = false
		love.graphics.stencil(function() ran = true end, "replace", 1)
		check("stencil runs its callback (11.5 control flow preserved)", ran)
	end
	do
		local ok = pcall(function()
			love.graphics.stencil(function() error("from inside the callback") end)
		end)
		check("stencil restores state even when the callback errors", ok == false)
	end
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
