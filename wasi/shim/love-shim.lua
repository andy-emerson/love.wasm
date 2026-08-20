R"luastring"--(
-- DO NOT REMOVE THE ABOVE LINE. It is used to load this file as a C++ string.
-- love.shim — the inbound compatibility tier (D21).
--
-- ONE DIRECTION ONLY: it takes a game written for an older world (Lua 5.1,
-- LÖVE 11.5) and prepares the environment so that game runs here. It is not
-- the outbound polyfill that lets a love.wasm game run on desktop (D18), and
-- it is not a translator (#79/#100). D21 keeps those three tiers apart on
-- purpose, because collapsing them is what let compatibility questions be
-- deferred here without design.
--
-- MECHANISM: environment preparation, never source rewriting. Everything below
-- INSTALLS a missing name; nothing edits the game's Lua. That is deliberate:
--   - the whole gap is missing names, not wrong source (the 11.5->12 diff found
--     24 absent APIs, every one with a target in 12 — see #64);
--   - rewriting source would break hotswap, which re-runs the edited chunk from
--     disk (D4/D5): the running code would stop matching the file on disk;
--   - "declared, never silent" (D9) is cheap for a list of installed names and
--     near-impossible for a source diff.
--
-- NON-GOALS, enforced rather than stated (D21). This tier will never:
--   - paper over VALUE SEMANTICS. Restoring a name fixes something MISSING;
--     changing a value masks something WRONG. love.graphics.newFont(4.5) and
--     the luaL_checkinteger class (#93) are declared divergences, not shims.
--   - supply a MISSING CAPABILITY. No shim conjures video, sockets or threads.
--   - carry PER-GAME LOGIC. The moment it needs to know which game is running
--     it has become a patch set, and D9 reopens.
-- Two 5.1 features are DECLINED below for exactly the first reason, and the
-- decline is reported rather than hidden.
--
-- SAFE IN BOTH DIRECTIONS: every install is `x = x or <definition>`, so on a
-- runtime that already has the name this file changes nothing.

local shim = {}

-- What was installed, what was declined, and why. D9 requires the shim be
-- declared and never silent; this table is that declaration, and the caller
-- decides how to surface it.
local applied, declined = {}, {}
-- Applying twice must not report twice. The Lua tier is naturally idempotent
-- because `install` refuses to overwrite, but the LÖVE tier patches metatables
-- through wrapped constructors and needs to remember what it has already done —
-- a witness caught it double-reporting before this existed.
local seen = {}

local function note(list, key, text)
	if seen[key] then return false end
	seen[key] = true
	list[#list + 1] = text
	return true
end

local function install(owner, name, value, label)
	if owner == nil then return false end
	if owner[name] ~= nil then return false end
	owner[name] = value
	note(applied, "a:" .. (label or name), label or name)
	return true
end

local function decline(what, why)
	note(declined, "d:" .. what, what .. " (" .. why .. ")")
end

--------------------------------------------------------------------------------
-- Tier 1 — Lua 5.1 names that 5.2/5.3/5.4 moved or removed.
--
-- D8 chose Lua 5.4; these are the language-level casualties. Observed on one
-- real 11.5 game (Legend of Lua): three of them covered 41 call sites, 29 of
-- them inside vendored libraries, which is why restoring the name once beats
-- forking four libraries.
--------------------------------------------------------------------------------

function shim.applyLua(env)
	env = env or _G

	-- Removed in 5.2. table.unpack is the same function under a new name.
	install(env, "unpack", table.unpack, "unpack")

	-- Removed in 5.2 along with the whole `n` field convention.
	install(table, "getn", function(t) return #t end, "table.getn")
	install(table, "maxn", function(t)
		local n = 0
		for k in pairs(t) do
			if type(k) == "number" and k > n then n = k end
		end
		return n
	end, "table.maxn")
	install(table, "foreach", function(t, f)
		for k, v in pairs(t) do
			local r = f(k, v)
			if r ~= nil then return r end
		end
	end, "table.foreach")
	install(table, "foreachi", function(t, f)
		for i, v in ipairs(t) do
			local r = f(i, v)
			if r ~= nil then return r end
		end
	end, "table.foreachi")

	-- math.atan2 removed in 5.3: two-argument math.atan does the same job, and
	-- has since 5.3, so this is a pure rename.
	install(math, "atan2", function(y, x) return math.atan(y, x) end, "math.atan2")
	install(math, "pow", function(x, y) return x ^ y end, "math.pow")
	install(math, "log10", function(x) return math.log(x, 10) end, "math.log10")
	install(math, "ldexp", function(m, e) return m * 2.0 ^ e end, "math.ldexp")
	install(math, "frexp", function(x)
		if x == 0 or x ~= x or x == math.huge or x == -math.huge then return x, 0 end
		local e = math.floor(math.log(math.abs(x), 2)) + 1
		local m = x / 2.0 ^ e
		-- log2 rounding can land a hair outside [0.5, 1); normalise exactly.
		while math.abs(m) >= 1.0 do m, e = m / 2.0, e + 1 end
		while math.abs(m) < 0.5 do m, e = m * 2.0, e - 1 end
		return m, e
	end, "math.frexp")

	-- Renamed in 5.2 / 5.3.
	install(env, "loadstring", function(chunk, name)
		if type(chunk) ~= "string" then
			error("loadstring expects a string", 2)
		end
		return load(chunk, name)
	end, "loadstring")
	install(string, "gfind", string.gmatch, "string.gfind")

	-- DECLINED, and reported. setfenv/getfenv and module() cannot be reproduced
	-- under 5.4's _ENV without changing what the game's code means — the failure
	-- would be a wrong result rather than a missing name, which is the exact
	-- class D21 forbids this tier to touch. A game using them fails loudly at
	-- its own call site, which is the honest outcome.
	if env.setfenv == nil then decline("setfenv/getfenv", "5.4 _ENV has no faithful equivalent") end
	if env.module == nil then decline("module()", "5.2 removed it; emulation changes scoping") end

	return shim
end

--------------------------------------------------------------------------------
-- Tier 2 — LÖVE 11.5 names that LÖVE 12 removed outright.
--
-- Scope comes from a measured diff, not a guess: wasi/shim/api-diff.py compares
-- 11.5's Lua-facing surface against 12's and finds **24** names absent, each
-- with a verified target in 12 (#64). Everything 12 merely RENAMED or REPLACED
-- is already carried by upstream's own 30 deprecation entries and needs nothing
-- from us.
--
-- The count was 27 in an earlier revision. That diff scanned only the C++
-- registration tables; LÖVE 12 also ships Lua-level API files, and
-- src/modules/graphics/wrap_Graphics.lua defines stencil, getStencilTest and
-- setStencilTest. Three names that were never absent. The extractor now reads
-- both, which is why it lives in the repo rather than in a session.
--------------------------------------------------------------------------------

-- LÖVE objects use `m.__index = m` (common/runtime.cpp:520) and set no
-- __metatable guard, so an instance's metatable IS its method table and can be
-- extended. Getting one needs an instance, so patch lazily on first
-- construction and then step out of the way.
local patched = {}

local function patchOnFirst(owner, ctorName, methods, label)
	if owner == nil or owner[ctorName] == nil then return false end
	-- Re-applying must not wrap an already-wrapped (or already-applied)
	-- constructor. Without this, a second apply() installs a second wrapper and
	-- reports the same patch again.
	if patched[ctorName] then return false end
	patched[ctorName] = true
	local orig = owner[ctorName]
	owner[ctorName] = function(...)
		local obj = orig(...)
		local mt = getmetatable(obj)
		if type(mt) == "table" then
			for name, fn in pairs(methods) do
				if mt[name] == nil then mt[name] = fn end
			end
			owner[ctorName] = orig -- patched once; unwrap
		end
		return obj
	end
	note(applied, "a:" .. label, label)
	return true
end

-- 11.5's spring joints were tuned in FREQUENCY (Hz) + DAMPING RATIO. Box2D 2.4
-- and LÖVE 12 changed the parameterisation to STIFFNESS + DAMPING, which is a
-- units change rather than a rename — b2LinearStiffness converts using both
-- bodies' MASS (libraries/box2d/dynamics/b2_joint.cpp:40).
--
-- That looked at first like the value-semantics class D21 forbids. It is not,
-- and the difference matters: LÖVE 12 exposes the conversion IN BOTH DIRECTIONS
-- as love.physics.computeLinearStiffness / computeLinearFrequency
-- (wrap_Physics.cpp:909-912). So this shim does not approximate anything — it
-- calls the engine's own exact transform with the joint's own bodies. That is a
-- faithful adaptation, not a paper-over.
--
-- ONE DECLARED DIVERGENCE REMAINS, and no shim can close it: frequency is
-- mass-relative and stiffness is absolute. A game that changes a body's mass
-- AFTER setting a spring keeps its frequency on 11.5 and keeps its stiffness
-- here. Setting the spring again after the mass change restores agreement.
local function springMethods(getK, setK, getD, setD)
	local function bodies(joint)
		local a, b = joint:getBodies()
		return a, b
	end
	return {
		getFrequency = function(joint)
			local f = select(1, love.physics.computeLinearFrequency(joint[getK](joint), joint[getD](joint), bodies(joint)))
			return f
		end,
		setFrequency = function(joint, hz)
			local _, ratio = love.physics.computeLinearFrequency(joint[getK](joint), joint[getD](joint), bodies(joint))
			local k, d = love.physics.computeLinearStiffness(hz, ratio, bodies(joint))
			joint[setK](joint, k)
			joint[setD](joint, d)
		end,
		getDampingRatio = function(joint)
			local _, ratio = love.physics.computeLinearFrequency(joint[getK](joint), joint[getD](joint), bodies(joint))
			return ratio
		end,
		setDampingRatio = function(joint, ratio)
			local freq = select(1, love.physics.computeLinearFrequency(joint[getK](joint), joint[getD](joint), bodies(joint)))
			local k, d = love.physics.computeLinearStiffness(freq, ratio, bodies(joint))
			joint[setK](joint, k)
			joint[setD](joint, d)
		end,
	}
end

local function springAliases(m, prefix)
	-- WheelJoint spells the same four with a "Spring" infix.
	return {
		[prefix .. "Frequency"] = m.getFrequency,
		[prefix .. "DampingRatio"] = m.getDampingRatio,
	}
end

function shim.applyLove(love)
	if type(love) ~= "table" then return shim end

	-- love.math.compress/decompress moved to love.data in 11.0, were deprecated
	-- through 11.x, and are gone in 12. Argument order differs, so this adapts
	-- rather than aliases — same operation, same result.
	if love.math and love.data then
		install(love.math, "compress", function(data, format, level)
			return love.data.compress("data", format or "lz4", data, level or -1)
		end, "love.math.compress")
		install(love.math, "decompress", function(cd, format)
			if type(cd) == "string" then
				return love.data.decompress("string", format, cd)
			end
			return love.data.decompress("string", cd)
		end, "love.math.decompress")
	end

	if love.physics then
		local P = love.physics

		patchOnFirst(P, "newWorld", {
			getBodyList = function(w) return w:getBodies() end,
			getJointList = function(w) return w:getJoints() end,
			getContactList = function(w) return w:getContacts() end,
		}, "World:getBodyList/getJointList/getContactList")

		patchOnFirst(P, "newBody", {
			-- 12.0 merged fixtures into shapes; a body's fixture list is its
			-- shape list, and 11.5 code that only enumerates it works unchanged.
			getFixtureList = function(b) return b:getShapes() end,
		}, "Body:getFixtureList")

		local linear = springMethods("getStiffness", "setStiffness", "getDamping", "setDamping")
		patchOnFirst(P, "newDistanceJoint", linear, "DistanceJoint spring (frequency/dampingRatio)")
		patchOnFirst(P, "newMouseJoint", linear, "MouseJoint spring (frequency/dampingRatio)")
		patchOnFirst(P, "newWeldJoint", linear, "WeldJoint spring (frequency/dampingRatio)")

		local wheel = springMethods("getSpringStiffness", "setSpringStiffness", "getSpringDamping", "setSpringDamping")
		patchOnFirst(P, "newWheelJoint", {
			getSpringFrequency = wheel.getFrequency,
			setSpringFrequency = wheel.setFrequency,
			getSpringDampingRatio = wheel.getDampingRatio,
			setSpringDampingRatio = wheel.setDampingRatio,
		}, "WheelJoint spring (springFrequency/springDampingRatio)")
	end

	-- 11.0 replaced these four with love.filesystem.getInfo; 12 removed them.
	-- Each is derivable, so this is arithmetic on an existing answer, not a
	-- reimplementation of the filesystem.
	if love.filesystem then
		local F = love.filesystem
		install(F, "isFile", function(p)
			local i = F.getInfo(p)
			return i ~= nil and i.type == "file"
		end, "love.filesystem.isFile")
		install(F, "isDirectory", function(p)
			local i = F.getInfo(p)
			return i ~= nil and i.type == "directory"
		end, "love.filesystem.isDirectory")
		install(F, "isSymlink", function(p)
			local i = F.getInfo(p)
			return i ~= nil and i.type == "symlink"
		end, "love.filesystem.isSymlink")
		install(F, "getLastModified", function(p)
			local i = F.getInfo(p)
			if i == nil then return nil, "File does not exist" end
			return i.modtime
		end, "love.filesystem.getLastModified")
	end

	if love.audio then
		install(love.audio, "getSourceCount", function()
			return love.audio.getActiveSourceCount()
		end, "love.audio.getSourceCount")
	end

	-- SoundData:getChannels became getChannelCount in 12. Same count, clearer
	-- name; the 11.5 spelling is the one every existing game wrote.
	if love.sound then
		patchOnFirst(love.sound, "newSoundData", {
			getChannels = function(sd) return sd:getChannelCount() end,
		}, "SoundData:getChannels")
	end

	if love.graphics then
		-- ParticleSystem:get/setAreaSpread became get/setEmissionArea in 11.0.
		-- 12's getEmissionArea returns FIVE values; 11.5's getAreaSpread returned
		-- THREE (wrap_ParticleSystem.cpp:743 in 11.5). Truncating is the faithful
		-- answer: a game written for 11.5 that forwards the results somewhere
		-- would otherwise receive two it never expected.
		patchOnFirst(love.graphics, "newParticleSystem", {
			getAreaSpread = function(ps)
				local dist, dx, dy = ps:getEmissionArea()
				return dist, dx, dy
			end,
			setAreaSpread = function(ps, dist, dx, dy) return ps:setEmissionArea(dist, dx, dy) end,
		}, "ParticleSystem:get/setAreaSpread")

		-- NOT SHIMMED: love.graphics.stencil, getStencilTest, setStencilTest.
		-- An earlier revision implemented stencil() here, on a diff that said 12 had
		-- removed it. That diff was wrong: it scanned only the C++ registration
		-- tables, and LÖVE 12 ships src/modules/graphics/wrap_Graphics.lua — a
		-- Lua-level compatibility layer that defines all three with markDeprecated.
		-- Upstream's version is also better than the one here was: it saves and
		-- restores the previous stencil state AND the colour mask, which a stencil
		-- mask needs and which this file did not do. Re-adding it would shadow a
		-- working implementation with a worse one.
	end

	return shim
end

--------------------------------------------------------------------------------
-- Detection and reporting.
--------------------------------------------------------------------------------

-- LÖVE already asks this question: boot.lua reads t.version from conf.lua and
-- calls love.isVersionCompatible (modules/love/boot.lua:378-384). A game
-- declaring t.version = "11.5" is telling us exactly what it was written for,
-- so there is no need to invent a marker.
function shim.wantsShim(confVersion)
	if confVersion == nil then return true end -- no declaration: assume old
	local major = tostring(confVersion):match("^(%d+)")
	if major == nil then return true end
	return tonumber(major) < 12
end

function shim.report()
	return applied, declined
end

-- One line per fact, for whoever wants to surface it. D9's requirement is that
-- a restored name is visible, not that it is loud.
function shim.describe()
	local out = { ("love.shim: %d installed, %d declined"):format(#applied, #declined) }
	for _, a in ipairs(applied) do out[#out + 1] = "  + " .. a end
	for _, d in ipairs(declined) do out[#out + 1] = "  - " .. d end
	return table.concat(out, "\n")
end

function shim.apply(env, loveTable)
	shim.applyLua(env)
	shim.applyLove(loveTable or (env or _G).love)
	return shim
end

-- THE TWO TIERS APPLY AT DIFFERENT TIMES, which is the thing a boot wrapper has
-- to get right and which is easy to get wrong in a way that fails silently.
--
--   The Lua tier must run BEFORE any game code — and conf.lua is game code, so
--   before love.boot.
--   The LÖVE tier can only run AFTER the love.* modules exist — and love.boot
--   is what loads them, during love.init.
--
-- There is no single moment that satisfies both. Calling apply() before boot
-- installs the Lua names correctly and silently skips every LÖVE-tier patch,
-- because love.graphics and friends are still nil; nothing errors, and the
-- restorations simply are not there. A frame witness caught exactly that.
--
-- arm() resolves it: the Lua tier goes on immediately, and the LÖVE tier is
-- attached to the module loaders, so each love.* module gets its restorations
-- the moment it is required — still well before main.lua runs. applyLove is
-- idempotent, so re-running it per module converges rather than duplicating.
function shim.arm(env)
	env = env or _G
	shim.applyLua(env)

	local preload = package.preload
	for _, name in ipairs({ "data", "math", "physics", "filesystem", "audio", "sound", "graphics" }) do
		local key = "love." .. name
		local orig = preload[key]
		if type(orig) == "function" then
			preload[key] = function(...)
				local m = orig(...)
				shim.applyLove(env.love)
				return m
			end
		end
	end

	return shim
end

return shim
-- DO NOT REMOVE THE NEXT LINE. It is used to load this file as a C++ string.
--)luastring"--"
