-- Headless acceptance check for the red-square boot ROM, run through
-- MesenCE's --testrunner mode. Exit codes (via emu.stop):
--   0 pass, 2 script error, 3 wrong colours, 4 frame counter did not advance,
--   5 frame counter address unresolved.
-- No file or OS access is used: MesenCE's Lua sandbox blocks it by default.

local FRAME_COUNTER_ADDRESS = __FRAME_COUNTER_ADDRESS__
local SAMPLE_FRAME = 30
local COUNTER_FRAME = 60

local frames = 0
local counterAtSample = nil

local function channels(px)
  return (px >> 16) & 0xFF, (px >> 8) & 0xFF, px & 0xFF
end

local function isRed(px)
  local r, g, b = channels(px)
  return r > 200 and g < 40 and b < 40
end

local function isBlack(px)
  local r, g, b = channels(px)
  return r < 24 and g < 24 and b < 24
end

local function readCounter()
  return emu.readWord(FRAME_COUNTER_ADDRESS, emu.memType.snesWorkRam)
end

-- Scans count pixels starting at 0, calling getPixel(i) for i = 0..count-1,
-- and returns the index of the first red pixel, the index of the last red
-- pixel, and how many red pixels were found in total (nil, nil, 0 if none).
local function scanForRedRun(getPixel, count)
  local first, last, redCount = nil, nil, 0
  for i = 0, count - 1 do
    if isRed(getPixel(i)) then
      if first == nil then first = i end
      last = i
      redCount = redCount + 1
    end
  end
  return first, last, redCount
end

local function checkPicture()
  local size = emu.getScreenSize()
  local w, h = size.width, size.height
  local buf = emu.getScreenBuffer()
  local function at(x, y) return buf[y * w + x + 1] end
  local cx, cy = math.floor(w / 2), math.floor(h / 2)
  if not isRed(at(cx, cy)) then return false end
  local inset = 4
  local corners = { at(inset, inset), at(w - 1 - inset, inset), at(inset, h - 1 - inset), at(w - 1 - inset, h - 1 - inset) }
  for _, px in ipairs(corners) do
    if not isBlack(px) then return false end
  end

  -- Measure the square instead of probing fixed coordinates: pin its size
  -- and horizontal position exactly, and tolerate only a small
  -- emulator-specific vertical origin offset.
  local rowFirst, rowLast, rowCount = scanForRedRun(function(x) return at(x, cy) end, w)
  if rowFirst == nil or rowFirst ~= 96 or rowLast ~= 159 then return false end
  if rowCount ~= (rowLast - rowFirst + 1) then return false end -- contiguous, no stray red

  local colFirst, colLast, colCount = scanForRedRun(function(y) return at(cx, y) end, h)
  if colFirst == nil then return false end
  local colHeight = colLast - colFirst + 1
  if colHeight ~= 64 then return false end
  -- MesenCE's screen buffer places PPU line 1 a few rows below buffer row 0
  -- (observed +6 in 2.2.1), so the vertical origin is tolerated within 8
  -- rows; size and horizontal position are exact.
  if colFirst < 80 - 8 or colFirst > 80 + 8 then return false end
  if colCount ~= colHeight then return false end -- contiguous, no stray red

  return true
end

local function onFrame()
  frames = frames + 1
  local ok, code = pcall(function()
    if frames == SAMPLE_FRAME then
      if not checkPicture() then return 3 end
      if FRAME_COUNTER_ADDRESS == 0 then return 5 end
      counterAtSample = readCounter()
      return nil
    end
    if frames == COUNTER_FRAME then
      if readCounter() == counterAtSample then return 4 end
      return 0
    end
    return nil
  end)
  if not ok then
    emu.stop(2)
  elseif code ~= nil then
    emu.stop(code)
  end
end

emu.addEventCallback(onFrame, emu.eventType.endFrame)
