-- The draw-call sweep: the instrument for D9 (browser graphics backend).
--
-- WHAT IT IS FOR. WebGPU's headline advantage over WebGL2 is not fill rate, it
-- is the cost of *submitting* work: every WebGL2 entry point is validated on the
-- way through, and that cost is paid per call. Whether that matters to LÖVE is a
-- question about LÖVE's own batching, not about the browser in the abstract:
-- love.graphics coalesces consecutive draws that share state into one buffered
-- draw (Graphics.cpp:2035 flushes when the texture, shader, format or primitive
-- mode changes), so a game that draws ten thousand sprites from one atlas issues
-- almost no calls, and a game that draws a hundred sprites from a hundred images
-- issues a hundred. The sweep measures both ends deliberately:
--
--   batched   — N sprites, one texture. LÖVE coalesces; call count stays flat.
--               This is the vertex/fill curve, where WebGPU has little to offer.
--   unbatched — N sprites, alternating between two textures, forcing a flush per
--               sprite. Call count IS N. This is the curve WebGPU would lift.
--
-- The gap between the two curves is the answer. If unbatched falls off the
-- desktop pace at a few hundred sprites, WebGL2's overhead binds on real games.
-- If it holds to tens of thousands, it does not, and the case for WebGPU rests
-- on the feature ceiling (#36) alone rather than on speed.
--
-- WHAT IT REPORTS. The headline is CPU milliseconds spent inside love.draw with
-- the batch flushed before the clock stops, so the submission cost of the last
-- batch is inside the sample rather than trailing into present. Wall-clock frame
-- time is recorded alongside it but is the weaker number: the browser leg is
-- paced by requestAnimationFrame and floors at the refresh interval, so it only
-- becomes meaningful once a cell exceeds the frame budget.
--
-- SAME FILE, BOTH LEGS. This project runs unmodified under desktop LÖVE
-- (`love wasi/bench/project`) and under love.wasm (`wasi/bench/run.sh`). Run
-- both on one machine and the useful figure is the ratio; absolute numbers from
-- different hardware compare nothing.

local W, H = 1280, 720

-- Warmup exists because the first frames at a new cell pay for buffer growth and
-- shader/pipeline setup that a steady-state game does not pay every frame.
local WARMUP, MEASURE = 20, 60

local COUNTS = { 100, 250, 500, 1000, 2000, 4000, 8000, 16000, 32000 }

-- Once a cell costs this much CPU per frame, the rest of that mode's ladder is
-- abandoned: it is already far past any playable budget, and on a software
-- rasteriser the top of the ladder can take minutes. Abandoned cells are
-- reported as such rather than omitted, so a short table is never mistaken for a
-- fast one.
local ABORT_MS = 400

local SPRITE = 32       -- source texture edge, in pixels
local SCALE = 0.25      -- drawn at 8x8, keeping fill cost small so the sample is
                        -- dominated by submission rather than by shading

local imgs = {}
local xs, ys = {}, {}
local MAXN = COUNTS[#COUNTS]

-- A fixed LCG rather than love.math.random, so the desktop and browser legs draw
-- byte-identical geometry and the ratio compares like with like.
local function lcg(seed)
	return function()
		seed = (1103515245 * seed + 12345) % 2147483648
		return seed / 2147483648
	end
end

local function median(t)
	table.sort(t)
	local n = #t
	if n == 0 then return 0 end
	if n % 2 == 1 then return t[(n + 1) / 2] end
	return (t[n / 2] + t[n / 2 + 1]) / 2
end

-- Enough JSON for a flat array of flat records. Vendoring a real encoder for
-- this would be more code than the sweep.
local function jsonvalue(v)
	if type(v) == "string" then return '"' .. v:gsub('[\\"]', '\\%0') .. '"' end
	if type(v) == "boolean" then return tostring(v) end
	if type(v) == "number" then return string.format("%.6g", v) end
	return "null"
end

local cells = {}
for _, mode in ipairs({ "batched", "unbatched" }) do
	for _, n in ipairs(COUNTS) do
		cells[#cells + 1] = { mode = mode, n = n }
	end
end

local ci = 1
local frame = 0
local cpu, wall = {}, {}
local results = {}
local abandoned = {}   -- mode -> the count at which that ladder was abandoned

function love.load()
	local rnd = lcg(20260815)
	for i = 1, MAXN do
		xs[i] = rnd() * (W - SPRITE * SCALE)
		ys[i] = rnd() * (H - SPRITE * SCALE)
	end

	-- Two visibly different textures. The pair is what forces the per-sprite
	-- flush in unbatched mode; their content is irrelevant beyond being opaque.
	for k = 1, 2 do
		local d = love.image.newImageData(SPRITE, SPRITE)
		d:mapPixel(function(x, y)
			if k == 1 then return 1, y / SPRITE, x / SPRITE, 1 end
			return x / SPRITE, 1, y / SPRITE, 1
		end)
		imgs[k] = love.graphics.newImage(d)
	end
end

function love.update(dt)
	if cells[ci] and frame >= WARMUP then wall[#wall + 1] = dt * 1000 end
end

function love.draw()
	local cell = cells[ci]
	if not cell then return end

	local n = cell.n
	local t0 = love.timer.getTime()
	if cell.mode == "batched" then
		local img = imgs[1]
		for i = 1, n do
			love.graphics.draw(img, xs[i], ys[i], 0, SCALE, SCALE)
		end
	else
		local a, b = imgs[1], imgs[2]
		for i = 1, n do
			love.graphics.draw(i % 2 == 0 and a or b, xs[i], ys[i], 0, SCALE, SCALE)
		end
	end
	-- Without this the buffered batch is submitted during present, outside the
	-- clock, and batched mode would report a cost it has not finished paying.
	love.graphics.flushBatch()
	local t1 = love.timer.getTime()

	frame = frame + 1
	if frame > WARMUP then cpu[#cpu + 1] = (t1 - t0) * 1000 end
	if frame < WARMUP + MEASURE then return end

	local mcpu, mwall = median(cpu), median(wall)
	results[#results + 1] = {
		mode = cell.mode, n = n, cpu_ms = mcpu, wall_ms = mwall,
		-- In unbatched mode the flush is per sprite, so N is the draw-call
		-- count; in batched mode LÖVE coalesces and the figure is not a call
		-- count, which is why it is reported only for the mode where it means
		-- something.
		us_per_draw = cell.mode == "unbatched" and (mcpu * 1000 / n) or nil,
	}
	cpu, wall, frame = {}, {}, 0

	-- Abandon the rest of this mode's ladder once a cell is hopeless.
	if mcpu >= ABORT_MS and not abandoned[cell.mode] then
		abandoned[cell.mode] = n
		while cells[ci + 1] and cells[ci + 1].mode == cell.mode do ci = ci + 1 end
	end

	ci = ci + 1
	if cells[ci] then return end

	local parts = {}
	for _, r in ipairs(results) do
		local fields = {}
		for _, k in ipairs({ "mode", "n", "cpu_ms", "wall_ms", "us_per_draw" }) do
			fields[#fields + 1] = jsonvalue(k) .. ":" .. jsonvalue(r[k])
		end
		parts[#parts + 1] = "{" .. table.concat(fields, ",") .. "}"
	end
	local meta = {
		'"renderer":' .. jsonvalue(select(1, love.graphics.getRendererInfo())),
		'"warmup":' .. WARMUP, '"measure":' .. MEASURE,
		'"abort_ms":' .. ABORT_MS,
		'"abandoned_batched":' .. jsonvalue(abandoned.batched),
		'"abandoned_unbatched":' .. jsonvalue(abandoned.unbatched),
	}
	love.filesystem.write("bench.json",
		"{" .. table.concat(meta, ",") .. ',"results":[' .. table.concat(parts, ",") .. "]}")

	-- The desktop leg has no driver reading the save namespace, so it prints.
	print("bench.json written to " .. love.filesystem.getSaveDirectory())
	for _, r in ipairs(results) do
		print(string.format("%-9s n=%-6d cpu %8.3f ms  wall %8.3f ms%s",
			r.mode, r.n, r.cpu_ms, r.wall_ms,
			r.us_per_draw and string.format("  %6.3f us/draw", r.us_per_draw) or ""))
	end

	love.event.quit(0)
end
