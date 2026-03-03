registerCoreModule("aiHornSync/main")

local function forceLoad()
    extensions.load("aiHornSync_main")
    local count = be:getObjectCount()
    for i = 0, count - 1 do
        local v = be:getObject(i)
        if v then v:queueLuaCommand("extensions.load('aiHornSync')") end
    end
end

if onClientStartMission == nil then
    onClientStartMission = forceLoad
end