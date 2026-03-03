-- betterScriptAI GE Extension v2.0
-- Place at: mods/unpacked/betterScriptAI/lua/ge/extensions/betterScriptAI/main.lua

local M = {}

local logTag = "betterScriptAI"

-- honkData[vehId] = { honks = { {time=..., duration=..., speed=...}, ... }, recording=bool, recordingStartSimTime=... }
-- playbackState[vehId] = { honks=..., index=1, elapsed=0, active=bool, hornOffAt=nil }

local honkData = {}
local playbackState = {}

-- Debounce: prevent duplicate events firing within this window (seconds)
local DEBOUNCE_WINDOW = 0.5
local lastPlaybackStart = {}
local lastReset = {}

local function debounce(tbl, vehId)
  local now = os.clock()
  if tbl[vehId] and (now - tbl[vehId]) < DEBOUNCE_WINDOW then
    return true
  end
  tbl[vehId] = now
  return false
end

-- ============================================================
-- Lifecycle
-- ============================================================

function M.onExtensionLoaded()
  log("I", logTag, "GE extension loaded.")
end

function M.onExtensionsLoaded()
  log("I", logTag, "GE extension ready.")
end

-- Bootstrap vehicle extensions and wipe any stale per-session state
function M.onClientStartMission(levelPath)
  log("I", logTag, "onClientStartMission fired – wiping stale state and bootstrapping vehicles.")

  function M.onClientEndMission()
    log("I", logTag, "onClientEndMission - clearing honkdata folder.")
    local honkDir = "mods/unpacked/betterScriptAI/honkdata"
    local files = FS:findFiles(honkDir, "*.json", 0, true, false)
    if files then
        for _, fpath in ipairs(files) do
            FS:removeFile(fpath)
            log("I", logTag, "Deleted: " .. fpath)
        end
    end
    honkData      = {}
    playbackState = {}
end

  -- Wipe all state from any previous session
  honkData = {}
  playbackState = {}
  lastPlaybackStart = {}
  lastReset = {}

  -- Wipe honkdata folder
  local honkDir = "mods/unpacked/betterScriptAI/honkdata"
  FS:directoryCreate(honkDir)
  local files = FS:findFiles(honkDir, "*.json", 0, true, false)
  if files then
    for _, fpath in ipairs(files) do
      FS:removeFile(fpath)
      log("I", logTag, "Wiped stale honkdata file: " .. fpath)
    end
  end

  local count = be:getObjectCount()
  log("I", logTag, string.format("Found %d vehicle(s) to bootstrap.", count))
  for i = 0, count - 1 do
    local veh = be:getObject(i)
    if veh then
      veh:queueLuaCommand("extensions.load('betterScriptAI')")
    end
  end
end

-- Bootstrap any vehicle spawned mid-session
function M.onVehicleSpawned(vehId)
  local veh = be:getObjectByID(vehId)
  if veh then
    veh:queueLuaCommand("extensions.load('betterScriptAI')")
    log("I", logTag, "Loaded vehicle extension on spawned veh " .. tostring(vehId))
  end
end

function M.onVehicleDestroyed(vehId)
  honkData[vehId] = nil
  playbackState[vehId] = nil
end

-- ============================================================
-- Recording
-- ============================================================

-- Called by vehicle extension on rising edge of Script AI recording
function M.onVehicleScriptAIStartRecording(vehId, startSimTime)
  vehId = tonumber(vehId)
  log("I", logTag, string.format("Recording started: veh %d at simTime=%.3f", vehId, startSimTime))

  -- Cancel any active playback
  playbackState[vehId] = nil

  honkData[vehId] = {
    honks = {},
    recording = true,
    recordingStartSimTime = startSimTime,
  }
end

-- Called by vehicle extension on the FALLING edge of the horn during recording.
-- duration = actual measured hold time (seconds) from vehicle side.
function M.onVehicleHonk(vehId, simTime, speed, duration)
  vehId = tonumber(vehId)
  duration = tonumber(duration) or 0.2

  local d = honkData[vehId]
  if not d or not d.recording then return end

  if not d.recordingStartSimTime then
    log("W", logTag, "onVehicleHonk: missing recordingStartSimTime for veh " .. tostring(vehId))
    return
  end

  -- Clamp degenerate durations (< 1 frame is probably a mis-fire; cap at 30 s)
  duration = math.max(0.05, math.min(duration, 30.0))

  local t = simTime - d.recordingStartSimTime
  table.insert(d.honks, { time = t, duration = duration, speed = speed })

  log("I", logTag, string.format(
    "Honk recorded: veh %d t=%.3fs dur=%.3fs speed=%.1f mph",
    vehId, t, duration, speed
  ))
end

-- Called by vehicle extension when Script AI recording stops.
-- The vehicle ext guarantees any in-progress honk is closed before calling this.
function M.onVehicleStopRecording(vehId, finalHonkStart, finalHonkSpeed, finalHonkDur)
  vehId = tonumber(vehId)
  local d = honkData[vehId]
  if not d or not d.recording then return end

  if finalHonkStart and finalHonkDur then
    finalHonkStart = tonumber(finalHonkStart)
    finalHonkSpeed = tonumber(finalHonkSpeed) or 0
    finalHonkDur = math.max(0.05, math.min(tonumber(finalHonkDur), 30.0))
    local t = finalHonkStart - d.recordingStartSimTime
    table.insert(d.honks, { time = t, duration = finalHonkDur, speed = finalHonkSpeed })
    log("I", logTag, string.format("Final honk inserted at stop: veh %d t=%.3fs dur=%.3fs", vehId, t, finalHonkDur))
  end

  d.recording = false
  log("I", logTag, string.format("Recording stopped: veh %d, %d honk(s) captured", vehId, #d.honks))

  if #d.honks > 0 then saveHonkData(vehId)
  else log("W", logTag, "Recording had 0 honks - skipping save.") end
end

-- ============================================================
-- Save / Load
-- ============================================================

local function getHonkPath(vehId)
  return "mods/unpacked/betterScriptAI/honkdata/veh_" .. tostring(vehId) .. ".json"
end

function saveHonkData(vehId)
  local d = honkData[vehId]
  if not d then return end

  local path = getHonkPath(vehId)
  FS:directoryCreate(path:match("(.+)/"))

  local f = io.open(path, "w")
  if f then
    f:write(jsonEncode(d.honks))
    f:close()
    log("I", logTag, "Saved honk data: " .. path)
  else
    log("E", logTag, "Failed to save honk data: " .. path)
  end
end

function loadHonkData(vehId)
  local path = getHonkPath(vehId)
  local f = io.open(path, "r")
  if f then
    local content = f:read("*all")
    f:close()
    local honks = jsonDecode(content)
    if honks and #honks > 0 then
      -- Back-compat: older saves have no duration field; default to 0.2 s
      for _, h in ipairs(honks) do
        if not h.duration then h.duration = 0.2 end
      end
      honkData[vehId] = { honks = honks, recording = false }
      log("I", logTag, string.format("Loaded %d honk(s) for veh %d", #honks, vehId))
      return true
    end
  end
  log("W", logTag, "No honk data found for veh " .. tostring(vehId))
  return false
end

-- ============================================================
-- Playback
-- ============================================================

function startPlayback(vehId)
  playbackState[vehId] = nil
  local d = honkData[vehId]
  if not d or #d.honks == 0 then
    log("W", logTag, "startPlayback: no honks for veh " .. tostring(vehId))
    return
  end
  playbackState[vehId] = {
    honks = d.honks,
    index = 1,
    elapsed = 0,
    active = true,
    hornOffAt = nil,
  }
  log("I", logTag, string.format("Playback started: veh %d (%d honks)", vehId, #d.honks))
end

function stopPlayback(vehId)
  if not playbackState[vehId] then return end
  local veh = be:getObjectByID(vehId)
  if veh then
    veh:queueLuaCommand("extensions.betterScriptAI.triggerHonkOff()")
  end
  playbackState[vehId] = nil
  log("I", logTag, "Playback stopped: veh " .. tostring(vehId))
end

-- ============================================================
-- Script AI hooks
-- ============================================================

function M.onScriptAIExecuteStart(vehId)
  vehId = tonumber(vehId)
  if debounce(lastPlaybackStart, vehId) then return end
  log("I", logTag, "onScriptAIExecuteStart: veh " .. tostring(vehId))
  loadHonkData(vehId)
  startPlayback(vehId)
end

function M.onVehicleScriptAIPlaybackStart(vehId)
  vehId = tonumber(vehId)
  if debounce(lastPlaybackStart, vehId) then return end
  log("I", logTag, "onVehicleScriptAIPlaybackStart: veh " .. tostring(vehId))
  loadHonkData(vehId)
  startPlayback(vehId)
end

function M.onScriptAIPlaybackStop(vehId)
  stopPlayback(tonumber(vehId))
end

-- ============================================================
-- Vehicle reset
-- ============================================================

function M.onVehicleReset(vehId)
  vehId = tonumber(vehId)
  if debounce(lastReset, vehId) then return end
  log("I", logTag, "onVehicleReset: veh " .. tostring(vehId))

  -- Wipe partial recording
  if honkData[vehId] and honkData[vehId].recording then
    log("W", logTag, "onVehicleReset: wiping partial recording for veh " .. tostring(vehId))
    honkData[vehId] = nil
  end

  -- Restart playback from t=0
  if playbackState[vehId] then
    local honks = playbackState[vehId].honks
    playbackState[vehId] = {
      honks = honks,
      index = 1,
      elapsed = 0,
      active = true,
      hornOffAt = nil,
    }
    log("I", logTag, "onVehicleReset: restarted playback from t=0 for veh " .. tostring(vehId))
  end
end

-- ============================================================
-- Per-frame update: fire honks at the right sim-time offsets
-- ============================================================

function M.onUpdate(dt)
  for vehId, ps in pairs(playbackState) do
    if ps.active then
      ps.elapsed = ps.elapsed + dt

      -- Fire every honk whose onset time has been reached
      while ps.index <= #ps.honks do
        local nextHonk = ps.honks[ps.index]
        if ps.elapsed >= nextHonk.time then
          local veh = be:getObjectByID(vehId)
          if veh then
            veh:queueLuaCommand("extensions.betterScriptAI.triggerHonk()")
            log("I", logTag, string.format(
              "Playback honk: veh %d elapsed=%.3fs dur=%.3fs",
              vehId, ps.elapsed, nextHonk.duration
            ))
          end

          -- Extend the release time instead of cutting a prior honk short.
          local offAt = ps.elapsed + nextHonk.duration
          if ps.hornOffAt then
            offAt = math.max(ps.hornOffAt, offAt)
          end
          ps.hornOffAt = offAt
          ps.index = ps.index + 1
        else
          break
        end
      end

      -- Release horn once all active durations have expired
      if ps.hornOffAt and ps.elapsed >= ps.hornOffAt then
        local veh = be:getObjectByID(vehId)
        if veh then
          veh:queueLuaCommand("extensions.betterScriptAI.triggerHonkOff()")
        end
        ps.hornOffAt = nil
      end

      -- All honks played and horn released – done
      if ps.index > #ps.honks and not ps.hornOffAt then
        log("I", logTag, "Playback complete: veh " .. tostring(vehId))
        playbackState[vehId] = nil
      end
    end
  end
end

-- ============================================================
-- Debug helpers (accessible via Lua console)
-- ============================================================

M.saveHonkData = saveHonkData
M.loadHonkData = loadHonkData
M.startPlayback = startPlayback
M.stopPlayback = stopPlayback

return M