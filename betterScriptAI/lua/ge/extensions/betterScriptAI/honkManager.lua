-- betterScriptAI: honkManager.lua
-- GE-level bridge between honkRecorder (vehicle) and the HonkManager UI panel.
-- Owns all cross-vehicle state, pushes updates via guihooks, receives commands via bngApi.engineLua().

local M = {}

-- ─────────────────────────────────────────────
-- State
-- ─────────────────────────────────────────────

local vehicles = {}       -- [vehId] = { id, name, state, honkCount, speedMin, speedMax }
local logBuffer = {}      -- ring buffer of log entries
local LOG_MAX = 500

local syncSession = {
  active = false,
  participants = {},      -- list of vehIds
  countdown = 0,
  timer = nil,
}

-- ─────────────────────────────────────────────
-- Internal helpers
-- ─────────────────────────────────────────────

local function getVehName(vehId)
  local veh = be:getObjectByID(vehId)
  if veh then
    local model = veh:getField("JBeam", 0) or ("Vehicle " .. vehId)
    return model
  end
  return "Vehicle " .. vehId
end

local function pushVehicleUpdate(vehId)
  local v = vehicles[vehId]
  if not v then return end
  guihooks.trigger("honkMgr_vehicleUpdate", v)
end

local function pushAllVehicles()
  local list = {}
  for _, v in pairs(vehicles) do
    table.insert(list, v)
  end
  guihooks.trigger("honkMgr_allVehicles", list)
end

local function addLog(vehId, evtType, message)
  local entry = {
    timestamp = os.date("%H:%M:%S"),
    vehicleId = vehId,
    type      = evtType,   -- "honk" | "record" | "playback" | "sync" | "error"
    message   = message,
  }
  table.insert(logBuffer, entry)
  if #logBuffer > LOG_MAX then
    table.remove(logBuffer, 1)
  end
  guihooks.trigger("honkMgr_logEntry", entry)
end

local function ensureVehicle(vehId)
  if not vehicles[vehId] then
    vehicles[vehId] = {
      id       = vehId,
      name     = getVehName(vehId),
      state    = "idle",    -- "idle" | "recording" | "hasData" | "playing"
      honkCount = 0,
      speedMin  = nil,
      speedMax  = nil,
    }
  end
  return vehicles[vehId]
end

-- ─────────────────────────────────────────────
-- Public API — called by UI via bngApi.engineLua()
-- ─────────────────────────────────────────────

function M.startRecording(vehId)
  vehId = tonumber(vehId)
  local v = ensureVehicle(vehId)
  v.state     = "recording"
  v.honkCount = 0
  v.speedMin  = nil
  v.speedMax  = nil

  local veh = be:getObjectByID(vehId)
  if veh then
    veh:queueLuaCommand("betterScriptAI.startRecording()")
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
    veh:queueLuaCommand("betterScriptAI.stopRecording()")
  end

  addLog(vehId, "record", "Recording stopped on " .. v.name .. " — " .. v.honkCount .. " honk(s) captured")
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

  local veh = be:getObjectByID(vehId)
  if veh then
    veh:queueLuaCommand("betterScriptAI.playback()")
  end

  addLog(vehId, "playback", "Playback started on " .. v.name)
  pushVehicleUpdate(vehId)
end

function M.stopPlayback(vehId)
  vehId = tonumber(vehId)
  local v = vehicles[vehId]
  if not v then return end
  v.state = "hasData"

  local veh = be:getObjectByID(vehId)
  if veh then
    veh:queueLuaCommand("betterScriptAI.stopPlayback()")
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

  local veh = be:getObjectByID(vehId)
  if veh then
    veh:queueLuaCommand("betterScriptAI.clearHonkData()")
  end

  addLog(vehId, "record", "Data cleared on " .. v.name)
  pushVehicleUpdate(vehId)
end

-- Sync: fire playback on multiple vehicles simultaneously
-- ids is a JSON array string e.g. "[1,2,3]"
function M.syncPlayback(idsJson)
  local ids = jsonDecode(idsJson)
  if not ids or #ids == 0 then return end

  syncSession.active       = true
  syncSession.participants = ids

  addLog(0, "sync", "Sync playback triggered for " .. #ids .. " vehicle(s)")
  guihooks.trigger("honkMgr_syncStatus", {
    phase        = "playing",
    participants = ids,
  })

  for _, vehId in ipairs(ids) do
    M.playback(vehId)
  end
end

-- Request a full state dump to the UI (called on panel open)
function M.requestFullState()
  pushAllVehicles()
  guihooks.trigger("honkMgr_logBuffer", logBuffer)
  guihooks.trigger("honkMgr_syncStatus", {
    phase        = syncSession.active and "playing" or "idle",
    participants = syncSession.participants,
  })
end

-- ─────────────────────────────────────────────
-- Callbacks — called by honkRecorder.lua on the vehicle
-- to push live state back up to the GE layer
-- ─────────────────────────────────────────────

-- Called by vehicle script when a honk is captured
function M.onHonkRecorded(vehId, speed)
  vehId = tonumber(vehId)
  speed = tonumber(speed)
  local v = ensureVehicle(vehId)

  v.honkCount = v.honkCount + 1
  if not v.speedMin or speed < v.speedMin then v.speedMin = speed end
  if not v.speedMax or speed > v.speedMax then v.speedMax = speed end

  addLog(vehId, "honk", string.format(
    "%s honk #%d at %.1f mph", v.name, v.honkCount, speed
  ))
  pushVehicleUpdate(vehId)
end

-- Called by vehicle script when playback finishes naturally
function M.onPlaybackComplete(vehId)
  vehId = tonumber(vehId)
  local v = vehicles[vehId]
  if not v then return end
  v.state = "hasData"

  addLog(vehId, "playback", "Playback complete on " .. v.name)
  pushVehicleUpdate(vehId)

  -- Check if all sync participants are done
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
      guihooks.trigger("honkMgr_syncStatus", { phase = "idle", participants = {} })
      addLog(0, "sync", "Sync session complete")
    end
  end
end

-- ─────────────────────────────────────────────
-- Vehicle lifecycle
-- ─────────────────────────────────────────────

function M.onVehicleSpawned(vehId)
  ensureVehicle(vehId)
  addLog(vehId, "record", vehicles[vehId].name .. " spawned and registered")
  pushAllVehicles()
end

function M.onVehicleDestroyed(vehId)
  if vehicles[vehId] then
    addLog(vehId, "record", vehicles[vehId].name .. " removed")
    vehicles[vehId] = nil
  end
  pushAllVehicles()
end

-- ─────────────────────────────────────────────
-- Extension lifecycle
-- ─────────────────────────────────────────────

function M.onExtensionLoaded()
  log("I", "honkManager", "HonkManager bridge loaded")
end

function M.onExtensionUnloaded()
  vehicles    = {}
  logBuffer   = {}
  syncSession = { active = false, participants = {}, countdown = 0 }
end

return M