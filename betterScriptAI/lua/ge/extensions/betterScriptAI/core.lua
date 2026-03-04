-- betterScriptAI: core.lua
-- GE bridge between betterScriptAI vehicle extension and the UI panel.

local M = {}

-- ============================================================
-- State
-- ============================================================

local vehicles  = {}
local logBuffer = {}
local LOG_MAX   = 500

local syncSession = {
  active       = false,
  participants = {},
  countdown    = 0,
}

-- ============================================================
-- Internal helpers
-- ============================================================

local function getVehName(vehId)
  local veh = be:getObjectByID(vehId)
  if veh then
    return veh:getField("JBeam", 0) or ("Vehicle " .. vehId)
  end
  return "Vehicle " .. vehId
end

local function pushVehicleUpdate(vehId)
  local v = vehicles[vehId]
  if not v then return end
  guihooks.trigger("bsai_vehicleUpdate", v)
end

local function pushAllVehicles()
  local list = {}
  for _, v in pairs(vehicles) do table.insert(list, v) end
  guihooks.trigger("bsai_allVehicles", list)
end

local function addLog(vehId, evtType, message)
  local entry = {
    timestamp = os.date("%H:%M:%S"),
    vehicleId = vehId,
    type      = evtType,
    message   = message,
  }
  table.insert(logBuffer, entry)
  if #logBuffer > LOG_MAX then table.remove(logBuffer, 1) end
  guihooks.trigger("bsai_logEntry", entry)
end

local function isIgnoredVehicle(vehId)
  local veh = be:getObjectByID(vehId)
  if veh then
    local jbeam = veh:getField("JBeam", 0) or ""
    if jbeam:lower():find("unicycle") then return true end
  end
  return false
end

local function ensureVehicle(vehId)
  if isIgnoredVehicle(vehId) then return nil end
  if not vehicles[vehId] then
    vehicles[vehId] = {
      id        = vehId,
      name      = getVehName(vehId),
      state     = "idle",
      honkCount = 0,
      speedMin  = nil,
      speedMax  = nil,
    }
  end
  return vehicles[vehId]
end

-- ============================================================
-- Public API - called by UI via bngApi.engineLua()
-- ============================================================

function M.startRecording(vehId)
  vehId = tonumber(vehId)
  local v = ensureVehicle(vehId)
  if not v then return end
  v.state     = "recording"
  v.honkCount = 0
  v.speedMin  = nil
  v.speedMax  = nil

  local veh = be:getObjectByID(vehId)
  if veh then
    veh:queueLuaCommand("ai.startRecording()")
  end

  addLog(vehId, "record", "Recording started on " .. v.name)
  pushVehicleUpdate(vehId)
end

function M.stopRecording(vehId)
  vehId = tonumber(vehId)
  local v = vehicles[vehId]
  if not v then return end
  v.state = "hasData"

  local veh = be:getObjectByID(vehId)
  if veh then
    veh:queueLuaCommand("ai.stopRecording()")
  end

  addLog(vehId, "record", "Recording stopped on " .. v.name .. " - " .. v.honkCount .. " honk(s) captured")
  pushVehicleUpdate(vehId)
end

function M.playback(vehId)
  vehId = tonumber(vehId)
  local v = vehicles[vehId]
  if not v or v.state ~= "hasData" then
    addLog(vehId, "error", "Playback requested but no data for vehicle " .. vehId)
    return
  end
  v.state = "playing"

  -- Trigger Script AI to start following the recorded path.
  -- betterScriptAI.lua vehicle extension will detect the "following" state change
  -- and fire onScriptAIExecuteStart, which causes main.lua to handle honk playback.
  local veh = be:getObjectByID(vehId)
  if veh then
    veh:queueLuaCommand("ai.startFollowing()")
  end

  addLog(vehId, "playback", "Playback started on " .. v.name)
  pushVehicleUpdate(vehId)
end

function M.stopPlayback(vehId)
  vehId = tonumber(vehId)
  local v = vehicles[vehId]
  if not v then return end
  v.state = "hasData"

  extensions.betterScriptAI_main.stopPlayback(vehId)

  local veh = be:getObjectByID(vehId)
  if veh then
    veh:queueLuaCommand("ai.setMode('disabled')")
  end

  addLog(vehId, "playback", "Playback stopped on " .. v.name)
  pushVehicleUpdate(vehId)
end

function M.clearData(vehId)
  vehId = tonumber(vehId)
  local v = vehicles[vehId]
  if not v then return end
  v.state     = "idle"
  v.honkCount = 0
  v.speedMin  = nil
  v.speedMax  = nil

  extensions.betterScriptAI_main.stopPlayback(vehId)
  local veh = be:getObjectByID(vehId)
  if veh then
    veh:queueLuaCommand("ai.setMode('disabled')")
  end

  addLog(vehId, "record", "Data cleared on " .. v.name)
  pushVehicleUpdate(vehId)
end

function M.syncPlayback(idsJson)
  local ids = jsonDecode(idsJson)
  if not ids or #ids == 0 then return end

  syncSession.active       = true
  syncSession.participants = ids

  addLog(0, "sync", "Sync playback triggered for " .. #ids .. " vehicle(s)")
  guihooks.trigger("bsai_syncStatus", { phase = "playing", participants = ids })

  for _, vehId in ipairs(ids) do
    M.playback(vehId)
  end
end

function M.requestFullState()
  pushAllVehicles()
  guihooks.trigger("bsai_logBuffer", logBuffer)
  guihooks.trigger("bsai_syncStatus", {
    phase        = syncSession.active and "playing" or "idle",
    participants = syncSession.participants,
  })
end

-- ============================================================
-- Callbacks from vehicle extension
-- ============================================================

function M.onHonkRecorded(vehId, speed)
  vehId = tonumber(vehId)
  speed = tonumber(speed)
  local v = ensureVehicle(vehId)
  if not v then return end

  v.honkCount = v.honkCount + 1
  if not v.speedMin or speed < v.speedMin then v.speedMin = speed end
  if not v.speedMax or speed > v.speedMax then v.speedMax = speed end

  addLog(vehId, "honk", string.format("%s honk #%d at %.1f mph", v.name, v.honkCount, speed))
  pushVehicleUpdate(vehId)
end

function M.onPlaybackComplete(vehId)
  vehId = tonumber(vehId)
  local v = vehicles[vehId]
  if not v then return end
  v.state = "hasData"

  addLog(vehId, "playback", "Playback complete on " .. v.name)
  pushVehicleUpdate(vehId)

  if syncSession.active then
    local allDone = true
    for _, id in ipairs(syncSession.participants) do
      if vehicles[id] and vehicles[id].state == "playing" then
        allDone = false
        break
      end
    end
    if allDone then
      syncSession.active = false
      guihooks.trigger("bsai_syncStatus", { phase = "idle", participants = {} })
      addLog(0, "sync", "Sync session complete")
    end
  end
end

-- ============================================================
-- Vehicle lifecycle
-- ============================================================

function M.onVehicleSpawned(vehId)
  if isIgnoredVehicle(vehId) then return end
  local v = ensureVehicle(vehId)
  if not v then return end
  addLog(vehId, "record", v.name .. " spawned and registered")
  pushAllVehicles()
end

function M.onVehicleDestroyed(vehId)
  if vehicles[vehId] then
    addLog(vehId, "record", vehicles[vehId].name .. " removed")
    vehicles[vehId] = nil
  end
  pushAllVehicles()
end

-- ============================================================
-- Extension lifecycle
-- ============================================================

function M.onExtensionLoaded()
  log("I", "betterScriptAI", "BetterScriptAI core bridge loaded")
end

function M.onExtensionUnloaded()
  vehicles    = {}
  logBuffer   = {}
  syncSession = { active = false, participants = {}, countdown = 0 }
end

return M