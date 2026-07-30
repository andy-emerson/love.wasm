-- Filesystem directory-enumeration witness — pre-step-7 "unblock a real game".
-- love.filesystem.getDirectoryItems over the new fs_list seam. The host merges
-- the read-only project and the writable save namespace and de-dupes, so a
-- written file shadows a project file of the same name exactly once — the same
-- merged listing physfs gave across a mounted search path. Runs as the pump's
-- resident coroutine (love preloaded by pump-ext); node:wasi AND real Chromium.
--
-- (Archive / .love-zip mounting stays a declared deferral — a loud return false;
-- enumeration is the piece real games actually need.)
local failures = 0
local function check(name, cond, got)
  if cond then
    coroutine.yield("ok   " .. name)
  else
    failures = failures + 1
    coroutine.yield("FAIL " .. name .. "   got: " .. tostring(got))
  end
end
local function has(t, v)
  for _, x in ipairs(t) do if x == v then return true end end
  return false
end
local function count(t, v)
  local c = 0
  for _, x in ipairs(t) do if x == v then c = c + 1 end end
  return c
end

local love = require("love")
check("require 'love'", type(love) == "table", love)
local fok = pcall(require, "love.filesystem")
check("require 'love.filesystem'", fok and type(love.filesystem) == "table", fok)
local fs = love.filesystem
pcall(fs.init, "love")
pcall(fs.setSource, "/project")
check("setIdentity('fslistgame')", (pcall(fs.setIdentity, "fslistgame")))

-- Build a save-namespace subtree: a directory with two files.
pcall(fs.createDirectory, "sub")
pcall(fs.write, "sub/a.txt", "A")
pcall(fs.write, "sub/b.txt", "B")

-- Enumerate the subdirectory: exactly its two files, immediate children only.
local items = fs.getDirectoryItems("sub")
check("getDirectoryItems('sub') returns a table", type(items) == "table", items)
check("'sub' lists a.txt", has(items, "a.txt"), items and table.concat(items, ","))
check("'sub' lists b.txt", has(items, "b.txt"), items and table.concat(items, ","))
check("'sub' has exactly 2 entries", #items == 2, #items)

-- Enumerate the root: the read-only project files AND the created directory,
-- merged into one listing.
local root = fs.getDirectoryItems("")
check("root lists project main.lua", has(root, "main.lua"), root and table.concat(root, ","))
check("root lists project conf.lua", has(root, "conf.lua"), root and table.concat(root, ","))
check("root lists project lib.lua", has(root, "lib.lua"), root and table.concat(root, ","))
check("root lists the created 'sub' directory", has(root, "sub"), root and table.concat(root, ","))

-- De-dup: shadow a project file in the save namespace; it still appears ONCE.
pcall(fs.write, "greeting.txt", "SAVE OVERRIDE")
local root2 = fs.getDirectoryItems("")
check("shadowed greeting.txt appears exactly once (save + project de-duped)",
  count(root2, "greeting.txt") == 1, count(root2, "greeting.txt"))

-- Honesty: a file is not a directory -> the backend returns false -> an empty
-- listing (never a faked entry, never a crash).
local notdir = fs.getDirectoryItems("main.lua")
check("getDirectoryItems('main.lua') is empty (a file is not a directory)",
  type(notdir) == "table" and #notdir == 0, notdir and #notdir)

-- An absent path enumerates to empty, not an error.
local absent = fs.getDirectoryItems("does-not-exist")
check("getDirectoryItems('does-not-exist') is empty",
  type(absent) == "table" and #absent == 0, absent and #absent)

coroutine.yield(("checks done, %d failures"):format(failures))
return failures == 0 and "STEP-FSLIST-WITNESS: PASS" or "STEP-FSLIST-WITNESS: FAIL"
