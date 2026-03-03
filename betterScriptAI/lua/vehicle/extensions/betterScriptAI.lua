-- betterScriptAI Vehicle Extension v2.0
-- Place at: mods/unpacked/betterScriptAI/lua/vehicle/extensions/betterScriptAI.lua

local M = {}

local logTag = "betterScriptAI"

local myVehId = nil
local wasHornActive = false
local wasAIRecording = false
local wasAIPlaying = false
local hornStartSimTime = nil -- set on press, cleared on release / recording-stop
local honkTimer = 0
local playbackStartDelay = 0
local PLAYBACK_DELAY = 0.05

-- Vehicle-side reset debounce: don't spam GE with reset notifications
local lastResetNotify = -999
local RESET_DEBOUNCE = 1.0

local function getMyVehId()
  if not myVehId then
    myVehId = obj:getId()
  end
  return myVehId
end

local function getScriptStatus()
  if ai and ai.scriptState then
    local ss = ai.scriptState()
    if ss then return ss.status end
  end
  return nil
end

-- ============================================================
-- Internal helpers
-- ============================================================

local function flushHonk(releaseSimTime)
  if not hornStartSimTime then return end
  local duration = releaseSimTime - hornStartSimTime
  local speedMph = (electrics.values.wheelspeed or 0) * 2.23694
  obj:queueGameEngineLua(string.format(
    "extensions.betterScriptAI_main.onVehicleHonk(%d, %f, %f, %f)",
    getMyVehId(), hornStartSimTime, speedMph, duration
  ))
  log("I", logTag, string.format(
    "Honk flushed: veh %d startSimTime=%.3f dur=%.3fs speed=%.1f mph",
    getMyVehId(), hornStartSimTime, duration, speedMph
  ))
  hornStartSimTime = nil
end

-- ============================================================
-- Per-frame update
-- ============================================================

function M.updateGFX(dt)
  if honkTimer > 0 then
    honkTimer = honkTimer - dt
    if honkTimer <= 0 then
      honkTimer = 0
      electrics.horn(false)
    end
  end

  local scriptStatus = getScriptStatus()
  local aiRecording = scriptStatus == "recording"
  local aiPlaying = scriptStatus == "following"

  if aiRecording and not wasAIRecording then
    local simTime = obj:getSimTime()
    obj:queueGameEngineLua(string.format(
      "extensions.betterScriptAI_main.onVehicleScriptAIStartRecording(%d, %f)",
      getMyVehId(), simTime
    ))
  end

  if not aiRecording and wasAIRecording then
    local simTime = obj:getSimTime()
    local pendingStart = hornStartSimTime
    local pendingDur = nil
    local pendingSpeed = nil

    if pendingStart then
      pendingDur = simTime - pendingStart
      pendingSpeed = (electrics.values.wheelspeed or 0) * 2.23694
      hornStartSimTime = nil
    end

    obj:queueGameEngineLua(string.format(
      "extensions.betterScriptAI_main.onVehicleStopRecording(%d, %s, %s, %s)",
      getMyVehId(),
      pendingStart and tostring(pendingStart) or "nil",
      pendingSpeed and tostring(pendingSpeed) or "nil",
      pendingDur and tostring(pendingDur) or "nil"
    ))
  end

  wasAIRecording = aiRecording

  if aiPlaying and not wasAIPlaying then
    playbackStartDelay = PLAYBACK_DELAY
  elseif not aiPlaying and wasAIPlaying then
    playbackStartDelay = 0
    obj:queueGameEngineLua(string.format(
      "extensions.betterScriptAI_main.onScriptAIPlaybackStop(%d)",
      getMyVehId()
    ))
  end

  wasAIPlaying = aiPlaying

  if playbackStartDelay > 0 then
    playbackStartDelay = playbackStartDelay - dt
    if playbackStartDelay <= 0 then
      playbackStartDelay = 0
      obj:queueGameEngineLua(string.format(
        "extensions.betterScriptAI_main.onScriptAIExecuteStart(%d)",
        getMyVehId()
      ))
    end
  end

  local hornActive = (electrics.values.horn or 0) > 0.5
  if aiRecording then
    if hornActive and not wasHornActive then
      hornStartSimTime = obj:getSimTime()
    end
    if not hornActive and wasHornActive then
      flushHonk(obj:getSimTime())
    end
  else
    hornStartSimTime = nil
  end

  wasHornActive = hornActive
end

-- ============================================================
-- Playback triggers (called by GE)
-- ============================================================

function M.triggerHonk()
  electrics.horn(true)
  honkTimer = 0
end

function M.triggerHonkOff()
  electrics.horn(false)
  honkTimer = 0
end

-- ============================================================
-- Reset
-- ============================================================

function M.onReset()
  wasHornActive = false
  wasAIPlaying = false
  wasAIRecording = false
  hornStartSimTime = nil
  honkTimer = 0
  playbackStartDelay = 0
  electrics.horn(false)

  local now = obj:getSimTime()
  if (now - lastResetNotify) >= RESET_DEBOUNCE then
    lastResetNotify = now
    obj:queueGameEngineLua(string.format(
      "extensions.betterScriptAI_main.onVehicleReset(%d)",
      getMyVehId()
    ))
    log("I", logTag, "Vehicle extension reset (notified GE) veh " .. tostring(getMyVehId()))
  end
end

-- ============================================================
-- Lifecycle
-- ============================================================

function M.onExtensionLoaded()
  myVehId = obj:getId()
  log("I", logTag, "Vehicle extension loaded on veh " .. tostring(myVehId))
  obj:queueGameEngineLua("extensions.load('betterScriptAI_main')")
end

function M.onExtensionUnloaded()
  electrics.horn(false)
end

return M