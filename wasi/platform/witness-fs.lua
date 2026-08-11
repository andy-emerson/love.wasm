-- Step-6.1 witness: the love_fs VFS seam carries a file's bytes intact.
-- Runs as the pump's resident coroutine; yields one line per check so the host
-- transcript shows each fact as it lands. The final return value is the verdict.
-- No love core here (6.1 is the raw seam): the bridge globals __wasi_fs_size /
-- __wasi_fs_read talk straight to the host store through the import surface.
local failures = 0
local function check(name, cond, got)
  if cond then
    coroutine.yield("ok   " .. name)
  else
    failures = failures + 1
    coroutine.yield("FAIL " .. name .. "   got: " .. tostring(got))
  end
end

-- A text file comes back with its content intact.
local main = __wasi_fs_read("main.lua")
check("read main.lua returns a string", type(main) == "string", type(main))
check("main.lua carries its source (love.draw present)",
  type(main) == "string" and main:find("love%.draw", 1) ~= nil, main and #main)

-- The host's reported size agrees with the bytes actually delivered.
check("fs_size(main.lua) matches the bytes read",
  type(main) == "string" and __wasi_fs_size("main.lua") == #main,
  __wasi_fs_size("main.lua"))

-- A second file, independently.
local conf = __wasi_fs_read("conf.lua")
check("read conf.lua carries love.conf",
  type(conf) == "string" and conf:find("love%.conf", 1) ~= nil, conf and #conf)

-- THE CRUX: a binary asset with embedded NULs and high bytes survives byte-exact.
-- bin.dat is {0x00,0x01,0x02,0xFF,0x00,0x80,0x7F,0xAA}. A C-string round-trip
-- would truncate at index 1 (the first NUL); a length-accurate, NUL-safe seam
-- recovers all 8 bytes.
local bin = __wasi_fs_read("bin.dat")
check("read bin.dat returns a string", type(bin) == "string", type(bin))
check("bin.dat is the full 8 bytes (not NUL-truncated)", bin and #bin == 8, bin and #bin)
if type(bin) == "string" and #bin == 8 then
  local b = { bin:byte(1, 8) }
  local want = { 0x00, 0x01, 0x02, 0xFF, 0x00, 0x80, 0x7F, 0xAA }
  local ok = true
  for i = 1, 8 do if b[i] ~= want[i] then ok = false end end
  check("bin.dat bytes are exact (NULs + high bytes intact)", ok,
    ("%d %d %d %d %d %d %d %d"):format(b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8]))
end

-- An absent file is reported honestly, not faked.
local miss, err = __wasi_fs_read("nope.lua")
check("absent file returns nil + error", miss == nil and type(err) == "string", err)
check("fs_size of an absent file is -1", __wasi_fs_size("nope.lua") == -1,
  __wasi_fs_size("nope.lua"))

-- Reads are deterministic (same bytes twice).
check("re-reading main.lua yields identical bytes", __wasi_fs_read("main.lua") == main)

coroutine.yield(("checks done, %d failures"):format(failures))
return failures == 0 and "STEP6-FS-WITNESS: PASS" or "STEP6-FS-WITNESS: FAIL"
