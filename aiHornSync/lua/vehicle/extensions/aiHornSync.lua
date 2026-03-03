-- aiHornSync Vehicle Extension  v1.3
-- Place at: mods/unpacked/aiHornSync/lua/vehicle/extensions/aiHornSync.lua

local M = {}

local logTag             = "aiHornSync"
local myVehId            = nil
local wasHornActive      = false
local wasAIRecording     = false
local wasAIPlaying       = false
local hornStartSimTime   = nil   -- set on press, cleared on release / recording-stop
local honkTimer          = 0
local playbackStartDelay = 0
local PLAYBACK_DELAY     = 0.05

-- Vehicle-side reset debounce: don't spam GE with reset notifications
local lastResetNotify = -999
local RESET_DEBOUNCE  = 1.0

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

-- Flush an in-progress horn press as a completed honk event.
-- Called on horn release OR when recording stops with the horn held down.
local function flushHonk(releaseSimTime)
    if not hornStartSimTime then return end
    local duration = releaseSimTime - hornStartSimTime
    local speedMph = (electrics.values.wheelspeed or 0) * 2.23694
    obj:queueGameEngineLua(string.format(
        "extensions.aiHornSync_main.onVehicleHonk(%d, %f, %f, %f)",
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
    -- Tick horn release timer (playback side)
    if honkTimer > 0 then
        honkTimer = honkTimer - dt
        if honkTimer <= 0 then
            honkTimer = 0
            electrics.horn(false)
        end
    end

    local scriptStatus = getScriptStatus()
    local aiRecording  = scriptStatus == "recording"
    local aiPlaying    = scriptStatus == "following"

    -- Recording: rising edge
    if aiRecording and not wasAIRecording then
        local simTime = obj:getSimTime()
        obj:queueGameEngineLua(string.format(
            "extensions.aiHornSync_main.onVehicleScriptAIStartRecording(%d, %f)",
            getMyVehId(), simTime
        ))
    end

    -- Recording: falling edge
    -- Must flush before submitting so GE receives the final honk first.
    if not aiRecording and wasAIRecording then
    local simTime      = obj:getSimTime()
    local pendingStart = hornStartSimTime
    local pendingDur   = nil
    local pendingSpeed = nil
    if pendingStart then
        pendingDur        = simTime - pendingStart
        pendingSpeed      = (electrics.values.wheelspeed or 0) * 2.23694
        hornStartSimTime  = nil
    end
    obj:queueGameEngineLua(string.format(
        "extensions.aiHornSync_main.onVehicleStopRecording(%d, %s, %s, %s)",
        getMyVehId(),
        pendingStart and tostring(pendingStart) or "nil",
        pendingSpeed and tostring(pendingSpeed) or "nil",
        pendingDur   and tostring(pendingDur)   or "nil"
    ))
end

    wasAIRecording = aiRecording

    -- Playback: rising / falling edges
    if aiPlaying and not wasAIPlaying then
        playbackStartDelay = PLAYBACK_DELAY
    elseif not aiPlaying and wasAIPlaying then
        playbackStartDelay = 0
        obj:queueGameEngineLua(string.format(
            "extensions.aiHornSync_main.onScriptAIPlaybackStop(%d)",
            getMyVehId()
        ))
    end
    wasAIPlaying = aiPlaying

    if playbackStartDelay > 0 then
        playbackStartDelay = playbackStartDelay - dt
        if playbackStartDelay <= 0 then
            playbackStartDelay = 0
            obj:queueGameEngineLua(string.format(
                "extensions.aiHornSync_main.onScriptAIExecuteStart(%d)",
                getMyVehId()
            ))
        end
    end

    -- Horn recording (only during recording)
    local hornActive = (electrics.values.horn or 0) > 0.5

    if aiRecording then
        -- Rising edge: remember when the press started
        if hornActive and not wasHornActive then
            hornStartSimTime = obj:getSimTime()
        end

        -- Falling edge: now we know the full duration, flush to GE
        if not hornActive and wasHornActive then
            flushHonk(obj:getSimTime())
        end
    else
        -- Not recording: discard any stale press state
        hornStartSimTime = nil
    end

    wasHornActive = hornActive
end

-- ============================================================
-- Called by GE to trigger a honk during playback.
-- GE owns the duration logic (via hornOffAt); vehicle ext just
-- turns the horn on. triggerHonkOff() turns it back off.
-- ============================================================

function M.triggerHonk()
    electrics.horn(true)
    honkTimer = 0  -- GE drives release timing, not a local timer
end

function M.triggerHonkOff()
    electrics.horn(false)
    honkTimer = 0
end

-- ============================================================
-- Reset - debounced so Script AI physics resets don't spam GE
-- ============================================================

function M.onReset()
    wasHornActive      = false
    wasAIPlaying       = false
    wasAIRecording     = false
    hornStartSimTime   = nil
    honkTimer          = 0
    playbackStartDelay = 0
    electrics.horn(false)

    local now = obj:getSimTime()
    if (now - lastResetNotify) >= RESET_DEBOUNCE then
        lastResetNotify = now
        obj:queueGameEngineLua(string.format(
            "extensions.aiHornSync_main.onVehicleReset(%d)",
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
    obj:queueGameEngineLua("extensions.load('aiHornSync_main')")
end

function M.onExtensionUnloaded()
    electrics.horn(false)
end

return M