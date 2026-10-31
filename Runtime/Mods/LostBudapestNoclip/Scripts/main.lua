local config = require("config")
local adapter = require("adapter")
local Controller = require("controller")
local controller = Controller.new(config, adapter)
local protection = require("protection").new(adapter)
local vehicles=require("vehicles").new(require("vehicle_engine"),config)
local actions, queued = {}, false
local heldKeys={}
local usedKeys={}

local function request(action,key)
    -- Input callbacks and the async loop never access Unreal objects.
    if #actions < 16 then actions[#actions + 1] = key and {name=action,key=key} or action end
end

for name, action in pairs({Toggle = "toggle", Slower = "slower", Faster = "faster", Return = "return"}) do
    local key = assert(Key[config.Keys[name]], "Unknown trainer key: " .. tostring(config.Keys[name]))
    usedKeys[key]=true
    RegisterKeyBind(key, function() request(action,config.Keys[name]) end)
end

local vehicleKeys=config.VehicleKeys or {Repair="F1",Next="F2",Diagnose="F3",God="F4",Drive="F5",Spawn="F9"}
for name,action in pairs({Repair="repair",Next="cycleVehicle",Diagnose="diagnose",God="godmode",Drive="drive",Spawn="spawnVehicle"}) do
    local key=Key[vehicleKeys[name] or ""]
    if key and not usedKeys[key] then
        usedKeys[key]=true
        RegisterKeyBind(key,function() request(action,vehicleKeys[name]) end)
    else adapter.log("Vehicle key unavailable/already assigned: "..name.."; edit config.VehicleKeys to remap.") end
end

local menu=require("menu").new(require("menu_engine"),function()
    return {flying=controller:isEnabled(),god=protection.manual,protected=protection.landing or protection.flight,
        speed=config.Speeds[controller.speedIndex],model=vehicles.catalog[vehicles.selected].name,driving=vehicles.driver~=nil,spawned=vehicles:count(),maximum=vehicles.maximum,boost=vehicles.boostSpeeds[vehicles.boostIndex]}
end,request)
adapter.onLog=function(message)menu:notice(message)end
local menuName=config.MenuKey or "INS"
if menuName=="INSERT" then menuName="INS" end -- compatibility with 0.3.0 configurations
local menuKey=Key[menuName]
if menuKey and not usedKeys[menuKey] then
    usedKeys[menuKey]=true
    RegisterKeyBind(menuKey,function()request("menu",menuName=="INS" and "Insert" or menuName)end)
else adapter.log("Menu key unavailable/already assigned; edit config.MenuKey.") end
local hookOk,hookError=pcall(require("menu_engine").register,function(hud)menu:frame(hud)end)
if not hookOk then adapter.log("HUD menu callback unavailable; hotkeys remain active: "..tostring(hookError))end

LoopAsync(16, function()
    if not queued and (#actions > 0 or controller:hasWork() or protection:hasWork() or vehicles:hasWork() or menu:hasWork() or next(heldKeys)~=nil) then
        queued = true
        local ok, err = pcall(ExecuteInGameThread, function()
            -- Drop the pending flag even if a callback fails. Only one queued
            -- game-thread update is allowed; loading cannot build a backlog.
            local callbackOk, callbackError = pcall(function()
                local pending = actions
                actions = {}
                for key in pairs(heldKeys) do
                    if not adapter.keyDown(key) then heldKeys[key]=nil end
                end
                for _, item in ipairs(pending) do
                    local action=type(item)=="table" and item.name or item
                    local key=type(item)=="table" and item.key or nil
                    if not key or not heldKeys[key] then
                    if key then heldKeys[key]=true end
                    if action=="toggle" or action=="return" or action=="drive" or action=="repair" or action=="spawnVehicle" or action=="diagnose" then menu:close() end
                    if action=="menu" then menu:toggle()
                    elseif action == "diagnose" then
                        local diagnosticOk,diagnosticError=xpcall(function() adapter.diagnose();require("vehicle_engine").diagnose() end,function(e)return debug.traceback(tostring(e),2)end)
                        if not diagnosticOk then adapter.log("Vehicle diagnostic incomplete: "..tostring(diagnosticError)) end
                    elseif action == "drive" then
                        if controller:isEnabled() then adapter.log("Turn noclip off before entering trainer driving.") else vehicles:drive() end
                    elseif action == "repair" then vehicles:repair()
                    elseif action == "cycleVehicle" then vehicles:cycle()
                    elseif action == "previousVehicle" then vehicles:cycle(-1)
                    elseif action == "boostFaster" then vehicles:boost(1)
                    elseif action == "boostSlower" then vehicles:boost(-1)
                    elseif action == "spawnVehicle" then vehicles:spawn()
                    elseif action == "godmode" then protection:toggle()
                    elseif action == "return" then controller:disable(true)
                    else controller[action](controller) end
                    end
                end
                menu:tick()
                controller:tick()
                protection:tick(controller:isEnabled())
                vehicles:tick()
            end)
            queued = false
            if not callbackOk then
                menu:close()
                controller:disable(false)
                adapter.log("Trainer callback stopped: " .. tostring(callbackError))
            end
        end)
        if not ok then
            queued = false
            adapter.log("Could not queue a game-thread update: " .. tostring(err))
        end
    end
    return false
end)

if type(RegisterHook) == "function" then
    for _,path in ipairs({"/Script/Engine.GameplayStatics:ApplyDamage","/Script/Engine.GameplayStatics:ApplyPointDamage"}) do
        local damageOk,damageError=pcall(RegisterHook,path,function(_,target,amount)
            if protection.manual or controller:isEnabled() or protection.landing then
                local ok,blocked=pcall(adapter.blockIncomingDamage,target,amount)
                if ok and blocked then protection.blockedCount=(protection.blockedCount or 0)+1 end
            end
            -- No return override: only this protected player's damage amount changes.
        end)
        if not damageOk then adapter.log("Pre-damage guard unavailable for "..path..": "..tostring(damageError))end
    end
    -- Use the stable loader's own sample-supported player restart hook. Its
    -- optional LoadMapPre callback has an upstream argument-count defect.
    local ok, err = pcall(RegisterHook, "/Script/Engine.PlayerController:ClientRestart", function()
        actions = {}
        heldKeys={}
        menu:close()
        controller:disable(false)
        local keepGod=protection.manual
        protection:reset()
        if keepGod then protection:toggle() end
        adapter.reset()
        -- No return override: Unreal retains its normal player restart behavior.
    end)
    if not ok then adapter.log("Player restart hook unavailable; pawn-change cleanup remains active: " .. tostring(err)) end
end

adapter.log("Ready. INSERT menu; F1 repair/recover; F2 next vehicle; F3 diagnostics; F4 god; F5 enter/exit; F6 noclip; F7/F8 speed; F9 spawn; F10 return.")
