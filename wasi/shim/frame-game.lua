-- The game the frame leg runs, as a REAL LÖVE game read through love.filesystem.
--
-- This exists because ParticleSystem:get/setAreaSpread needs a live GL context,
-- and the only place love.wasm has one that Lua can reach is inside a running
-- game: LÖVE's own boot calls love.window.setMode, and love.draw runs with the
-- context current. The graphics artifact's C++ helpers open and close their own
-- context and leave nothing behind, which is why the other legs could only skip.
--
-- Results go to stdout with a fixed prefix; the runner asserts on them. That is
-- the same channel the frame witness already uses for its love.load marker, and
-- it works because print() flushes per call (lauxlib.h:265, D6).

-- This game does NOT require or apply the shim. That is the assertion: the boot
-- wrapper switched it on before any game code ran, which is what "the engine
-- applies it for you" has to mean. A game that shimmed itself would prove
-- nothing about a real 11.5 game, which of course does no such thing.
local shim = require("love.shim") -- read the REPORT only; never apply

local failures, checks = 0, 0
local function check(name, cond, got)
	checks = checks + 1
	if cond then
		print("SHIMFRAME ok   " .. name)
	else
		failures = failures + 1
		print("SHIMFRAME FAIL " .. name .. "   got: " .. tostring(got))
	end
end

function love.load()
	print("SHIMFRAME-BEGIN")

	-- Switched on by the boot wrapper, before this file was loaded.
	check("the boot wrapper applied the Lua tier before game code", unpack ~= nil, unpack)
	check("unpack works without this game asking for it",
		unpack ~= nil and select("#", unpack({ 1, 2, 3 })) == 3)
	check("math.atan2 restored before game code", math.atan2 ~= nil)

	-- ParticleSystem needs a texture, so this also proves the shim's lazily
	-- patched constructor survives a real boot rather than only a bare require.
	local id = love.image.newImageData(4, 4)
	local img = love.graphics.newImage(id)
	local ps = love.graphics.newParticleSystem(img, 16)

	check("ParticleSystem:setAreaSpread restored", type(ps.setAreaSpread) == "function")
	check("ParticleSystem:getAreaSpread restored", type(ps.getAreaSpread) == "function")

	ps:setAreaSpread("uniform", 10, 20)
	local dist, dx, dy = ps:getAreaSpread()
	check("setAreaSpread reached 12's emission area", dist == "uniform", dist)
	check("area spread x round-trips", dx == 10, dx)
	check("area spread y round-trips", dy == 20, dy)

	-- 11.5 returned exactly three values here (wrap_ParticleSystem.cpp:743) and
	-- 12's getEmissionArea returns five. A game forwarding the result must not
	-- receive two it never expected.
	check("getAreaSpread returns 11.5's THREE values, not 12's five",
		select("#", ps:getAreaSpread()) == 3, select("#", ps:getAreaSpread()))

	-- Agreement with the 12 spelling, so this is a view of the same state rather
	-- than a parallel one the shim invented.
	local edist, edx, edy = ps:getEmissionArea()
	check("getAreaSpread agrees with getEmissionArea",
		dist == edist and dx == edx and dy == edy)

	-- The stencil trio is UPSTREAM'S, not ours, and this asserts that rather than
	-- assuming it. LÖVE 12 ships src/modules/graphics/wrap_Graphics.lua defining
	-- love.graphics.stencil / get/setStencilTest with markDeprecated. An earlier
	-- revision of the shim implemented stencil() on a diff that missed those
	-- Lua-defined APIs; this check is what stops that mistake coming back.
	check("love.graphics.stencil exists", type(love.graphics.stencil) == "function")
	check("setStencilTest exists (upstream's Lua layer)", type(love.graphics.setStencilTest) == "function")
	do
		local applied = shim.report()
		local ours = false
		for _, a in ipairs(applied) do if a == "love.graphics.stencil" then ours = true end end
		check("the shim does NOT install stencil — upstream already has it", ours == false)
	end

	if failures == 0 then
		print(("SHIMFRAME-PASS %d checks"):format(checks))
	else
		print(("SHIMFRAME-FAIL %d of %d"):format(failures, checks))
	end
end

function love.draw()
	-- Red, exactly as the canned frame game draws it, so this leg stays a valid
	-- frame witness too: if the context were not genuinely live, love.draw could
	-- not have painted, and the runner's centre-pixel check would say so.
	love.graphics.clear(0, 0, 0, 1)
	love.graphics.setColor(1, 0, 0, 1)
	love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
end
