-- Step-6.7 witness: the EMBEDDING CONTRACT. The real love.filesystem WRITE path
-- (save namespace, separate from the read-only project) and the host-callable
-- live-edit RELOAD primitive (write -> invalidate -> re-require = live edit),
-- driven as the pump's resident coroutine (love preloaded by pump-ext), yielding
-- one line per check so the host transcript shows each fact as it lands. The
-- final return value is the verdict.
--
-- 6.2 proved the READ path (host bytes recovered byte-exact through the real
-- module). 6.7 proves what makes the runtime CONSUMABLE by a live-edit host:
--   * write/append/remove/createDirectory land in the save namespace, never the
--     read-only project (proven by overwriting a project file, then removing the
--     save copy to reveal the pristine project value beneath);
--   * getSaveDirectory reflects t.identity; getInfo sees written files/dirs;
--   * writes are NUL-safe (a payload with an embedded NUL survives byte-exact);
--   * the reload invariant: require a module (v==1); host-edit its source via
--     the write path (v==2); pump_invalidate clears the game module cache;
--     re-require re-reads and re-evaluates -> v==2 (love's own modules survive).
local failures = 0
local function check(name, cond, got)
  if cond then
    coroutine.yield("ok   " .. name)
  else
    failures = failures + 1
    coroutine.yield("FAIL " .. name .. "   got: " .. tostring(got))
  end
end

-- The LÖVE core + real love.filesystem load (as in 6.2), with the boot read
-- surface exercised so the `loader` searcher is installed for require().
local love = require("love")
check("require 'love'", type(love) == "table", love)
local fok = pcall(require, "love.filesystem")
check("require 'love.filesystem'", fok and type(love.filesystem) == "table", fok)
local fs = love.filesystem
pcall(fs.init, "love")
pcall(fs.setSource, "/project")

-- setIdentity + the save directory string derived from it.
check("setIdentity('step67game')", (pcall(fs.setIdentity, "step67game")))
local save = fs.getSaveDirectory()
check("getSaveDirectory() is a non-empty string", type(save) == "string" and #save > 0, save)

-- write + read-back, NUL-safe. Payload carries an embedded NUL and high bytes.
local payload = "AB\0CD\255\0EF"
local wok = pcall(fs.write, "save.dat", payload)
check("write('save.dat', <bytes incl NUL>) succeeds", wok)
local back, blen = fs.read("save.dat")
check("read('save.dat') returns the EXACT bytes (NUL-safe)", back == payload, back and #back)
local info = fs.getInfo("save.dat")
check("getInfo('save.dat').type == 'file'", info and info.type == "file", info and info.type)
check("getInfo('save.dat').size matches (" .. #payload .. ")", info and info.size == #payload, info and info.size)

-- The write did NOT touch the read-only project: an untouched project file still
-- reads its project bytes.
check("project read still works after write (conf.lua has love.conf)",
  (fs.read("conf.lua") or ""):find("love%.conf") ~= nil)

-- Namespace separation, proven by transcript alone (no host-map inspection):
-- overwrite a project file in the save namespace, see the shadow, then remove
-- the save copy and see the PRISTINE project value reappear — the project file
-- was never mutated.
check("greeting.txt reads the project value first", fs.read("greeting.txt") == "project data", fs.read("greeting.txt"))
pcall(fs.write, "greeting.txt", "SAVE OVERRIDE")
check("save shadows project on read", fs.read("greeting.txt") == "SAVE OVERRIDE", fs.read("greeting.txt"))
pcall(fs.remove, "greeting.txt")
check("removing the save copy reveals the pristine project file (project untouched)",
  fs.read("greeting.txt") == "project data", fs.read("greeting.txt"))

-- Writing 'main.lua' goes to the save namespace, not the project; removing it
-- reveals the pristine project main.lua underneath.
pcall(fs.write, "main.lua", "return 'saved-main'\n")
check("write('main.lua') shadows via the save namespace",
  (fs.read("main.lua") or ""):find("saved%-main") ~= nil, fs.read("main.lua"))
pcall(fs.remove, "main.lua")
check("project main.lua intact underneath (love.draw present)",
  (fs.read("main.lua") or ""):find("love%.draw") ~= nil)

-- append extends an existing save file.
pcall(fs.write, "app.dat", "one")
pcall(fs.append, "app.dat", "two")
check("append extends the file to 'onetwo'", fs.read("app.dat") == "onetwo", fs.read("app.dat"))

-- remove: getInfo is nil afterward.
pcall(fs.write, "gone.dat", "x")
check("getInfo before remove is a file", fs.getInfo("gone.dat") ~= nil)
pcall(fs.remove, "gone.dat")
check("getInfo('gone.dat') is nil after remove", fs.getInfo("gone.dat") == nil, fs.getInfo("gone.dat"))

-- createDirectory: getInfo reports a directory.
pcall(fs.createDirectory, "mydir")
local dinfo = fs.getInfo("mydir")
check("createDirectory then getInfo('mydir').type == 'directory'", dinfo and dinfo.type == "directory", dinfo and dinfo.type)

-- File:open('w')/write/flush/close round-trips through the same save namespace.
local wf = fs.openFile("file.dat", "w")
check("openFile('file.dat','w') returns a File", type(wf) == "userdata", type(wf))
if wf then
  wf:write("hello")
  wf:flush()
  wf:close()
end
check("File:write/flush persisted 'hello'", fs.read("file.dat") == "hello", fs.read("file.dat"))

-- RELOAD / INVALIDATE (D5=A: whole-chunk re-eval at module granularity).
-- reload(edit)@S ≡ a fresh run reaching S: the edit changes the FUTURE (the next
-- require), not the past. This proves write-path + invalidate + re-eval compose.
local m1 = require("mod")
check("require('mod').v == 1 (initial project module)", type(m1) == "table" and m1.v == 1, m1 and m1.v)
-- Host-edit the module: write a NEW version through the write path just proven.
-- It lands in the save namespace and shadows the project mod.lua.
pcall(fs.write, "mod.lua", "return {v=2}\n")
check("without invalidate, require('mod') is still the cached v==1", require("mod").v == 1, require("mod").v)
-- Drive the reload primitive (the Lua twin of the pump_invalidate host export).
local cleared = __pump_invalidate()
check("__pump_invalidate() cleared >= 1 game module", type(cleared) == "number" and cleared >= 1, cleared)
local m2 = require("mod")
check("require('mod').v == 2 after write + invalidate (LIVE EDIT)", type(m2) == "table" and m2.v == 2, m2 and m2.v)
-- love's own C++ modules survive invalidate (only game modules were dropped).
check("love survives invalidate (still a table)", type(require("love")) == "table")
check("love.filesystem survives invalidate (still a table)", type(require("love.filesystem")) == "table")

coroutine.yield(("checks done, %d failures"):format(failures))
return failures == 0 and "STEP67-EMBED-WITNESS: PASS" or "STEP67-EMBED-WITNESS: FAIL"
