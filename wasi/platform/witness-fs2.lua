-- Step-6.2 witness: the REAL love.filesystem module, riding the love_fs VFS
-- seam (6.1). Runs as the pump's resident coroutine (love is preloaded by
-- pump-ext), yielding one line per check so the host transcript shows each fact
-- as it lands. The final return value is the verdict.
--
-- This is the inverse of step-3's terminal check: there, require("love.filesystem")
-- STOPPED at the documented seam ("host-import VFS, build-order step 6"); here it
-- SUCCEEDS, and the real module recovers host-provided files byte-exact — a
-- binary asset with embedded NULs included — through the real Lua API surface
-- (getInfo / read / openFile / load / require), the way the graphics witness
-- drives the real love.graphics.
local failures = 0
local function check(name, cond, got)
  if cond then
    coroutine.yield("ok   " .. name)
  else
    failures = failures + 1
    coroutine.yield("FAIL " .. name .. "   got: " .. tostring(got))
  end
end

-- The LÖVE core links and registers.
local lok, love = pcall(require, "love")
check("require 'love'", lok and type(love) == "table", love)

-- THE INVERSE OF STEP 3: love.filesystem now loads (the stop-line is gone).
local fok, ferr = pcall(require, "love.filesystem")
check("require 'love.filesystem' SUCCEEDS (step-3 stop-line gone)",
  fok and type(love.filesystem) == "table", ferr)

-- init + setSource: the boot read call surface, unguarded on this path.
local iok = pcall(love.filesystem.init, "love")
check("love.filesystem.init(arg0)", iok)
local sok = pcall(love.filesystem.setSource, "/project")
check("love.filesystem.setSource", sok)
check("love.filesystem.getSource round-trips", love.filesystem.getSource() == "/project",
  love.filesystem.getSource())

-- getInfo: type and size, straight from the host fs_stat.
local info = love.filesystem.getInfo("main.lua")
check("getInfo('main.lua') returns a table", type(info) == "table", info)
check("getInfo('main.lua').type == 'file'", info and info.type == "file", info and info.type)

-- read(filename): the whole-file overload. Content arrives intact.
local main, mainlen = love.filesystem.read("main.lua")
check("read('main.lua') returns a string", type(main) == "string", type(main))
check("read('main.lua') carries its source (love.draw present)",
  type(main) == "string" and main:find("love%.draw", 1) ~= nil, main and #main)
check("getInfo('main.lua').size matches the bytes read",
  info and type(main) == "string" and info.size == #main, info and info.size)
check("read returns length as second value", mainlen == #main, mainlen)

-- read(filename, size): the sized overload reads a prefix.
local head = love.filesystem.read("main.lua", 8)
check("read('main.lua', 8) returns 8 bytes", type(head) == "string" and #head == 8, head and #head)
check("the 8-byte prefix matches", head == main:sub(1, 8), head)

-- THE CRUX: a binary asset with embedded NULs and high bytes survives byte-exact
-- through the REAL module now (File -> FileData -> lua_pushlstring), not just the
-- raw 6.1 bridge. bin.dat is {0x00,0x01,0x02,0xFF,0x00,0x80,0x7F,0xAA}.
local bin = love.filesystem.read("bin.dat")
check("read('bin.dat') returns a string", type(bin) == "string", type(bin))
check("bin.dat is the full 8 bytes (not NUL-truncated)", bin and #bin == 8, bin and #bin)
if type(bin) == "string" and #bin == 8 then
  local b = { bin:byte(1, 8) }
  local want = { 0x00, 0x01, 0x02, 0xFF, 0x00, 0x80, 0x7F, 0xAA }
  local ok = true
  for i = 1, 8 do if b[i] ~= want[i] then ok = false end end
  check("bin.dat bytes are exact (NULs + high bytes intact)", ok,
    ("%d %d %d %d %d %d %d %d"):format(b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8]))
end

-- openFile: a File object round-trips, reading its own bytes.
local file = love.filesystem.openFile("conf.lua", "r")
check("openFile('conf.lua','r') returns a File", type(file) == "userdata", type(file))
if file then
  local fdata = file:read()
  check("File:read() carries love.conf",
    type(fdata) == "string" and fdata:find("love%.conf", 1) ~= nil, fdata and #fdata)
  file:close()
end

-- load: the file's chunk compiles to a callable function.
local chunk = love.filesystem.load("main.lua")
check("load('main.lua') returns a function", type(chunk) == "function", type(chunk))

-- require through the real `loader` searcher: lib.lua resolves via requirePath
-- ("?.lua") to the host module's table.
local rok, lib = pcall(require, "lib")
check("require('lib') succeeds via the love loader", rok and type(lib) == "table", lib)
check("require('lib') returns the host module's table",
  rok and type(lib) == "table" and lib.answer == 42 and lib.greet() == "hello from lib",
  rok and (type(lib) == "table" and tostring(lib.answer)) or lib)

-- An absent file is reported honestly, not faked.
check("getInfo('nope') is nil", love.filesystem.getInfo("nope") == nil, love.filesystem.getInfo("nope"))
check("read('nope') fails (nil + error)", (love.filesystem.read("nope")) == nil)

coroutine.yield(("checks done, %d failures"):format(failures))
return failures == 0 and "STEP6-FS2-WITNESS: PASS" or "STEP6-FS2-WITNESS: FAIL"
