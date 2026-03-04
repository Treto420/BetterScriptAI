registerCoreModule("betterScriptAI/main")
registerCoreModule("betterScriptAI/core")

local function forceLoad()
  extensions.load("betterScriptAI_main")
  extensions.load("betterScriptAI_core")
  local count = be:getObjectCount()
  for i = 0, count - 1 do
    local v = be:getObject(i)
    if v then v:queueLuaCommand("extensions.load('betterScriptAI')") end
  end
end

if onClientStartMission == nil then
  onClientStartMission = forceLoad
end