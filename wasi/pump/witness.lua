-- Pump witness script: a LÖVE-shaped resident frame loop.
-- Boot runs to the first yield ("BOOTED"); every resume after that is one
-- frame, receiving the host's payload and yielding this frame's output.
-- "quit" returns (a finished game); "explode" raises a runtime error
-- (a crashed game) — the pump must report both without losing the VM.
local frame = 0
local payload = coroutine.yield("BOOTED")
while true do
  frame = frame + 1
  if payload == "quit" then
    return ("DONE at frame %d"):format(frame)
  elseif payload == "explode" then
    error(("witness explosion at frame %d"):format(frame))
  end
  payload = coroutine.yield(("frame %d ack %s"):format(frame, payload))
end
