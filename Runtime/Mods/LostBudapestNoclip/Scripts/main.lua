local config = require("config")
local adapter = require("adapter")
local Controller = require("controller")
local controller = Controller.new(config, adapter)
local protection = require("protection").new(adapter)
local vehicleEngine=require("vehicle_engine")
local vehicles=require("vehicles").new(vehicleEngine)
local actions, queued = {}, false
local heldKeys={}
local usedKeys={}
local lastActionTimes={}
local actionDelays={spawnVehicle=.75,cycleVehicle=.18,previousVehicle=.18}

local function request(action,key)
    -- Input callbacks and the async loop never access Unreal objects.
    for _,item in ipairs(actions)do
        if (type(item)=="table" and item.name or item)==action then return end
    end
    if #actions < 16 then actions[#actions + 1] = key and {name=action,key=key} or action end
end

local function actionReady(action,key)
    local delay=key and actionDelays[action]
    if not delay then return true end
    local ok,now=pcall(function()local ctx=adapter.playerContext();return ctx and adapter.time(ctx)end)
    if not ok or type(now)~="number" or now~=now then return true end
    local previous=lastActionTimes[action]
    if previous and now>=previous and now-previous<delay then return false end
    lastActionTimes[action]=now
    return true
end

local function bind(name,action,fallback)
    if name==false then return end
    local function available(value)
        if type(value)~="string" then return end
        value=value:upper()
        if value=="INSERT" then value="INS" end
        local key=Key[value]
        if key and not usedKeys[key] then return key,value end
    end
    local key,label=available(name)
    if not key then key,label=available(fallback) end
    if not key then adapter.log("Shortcut unavailable for "..action.."; it remains available in the menu.");return end
    usedKeys[key]=action
    local unrealName=({INS="Insert",HOME="Home"})[label] or label
    RegisterKeyBind(key,function()request(action,unrealName)end)
end

-- Reserve these first, including with preserved pre-0.4.1 configurations.
bind("F2","menu")
bind("F3","cycleVehicle")
local extraMenu=config.MenuKey
if type(extraMenu)=="string" and extraMenu:upper()~="F2" and extraMenu:upper()~="INS" and extraMenu:upper()~="INSERT" then
    bind(extraMenu,"menu")
end
local flightKeys=config.Keys or {}
for _,item in ipairs({{"Toggle","toggle","F6"},{"Slower","slower","F7"},{"Faster","faster","F8"},{"Return","return","F10"}})do
    local name=flightKeys[item[1]]
    if name==nil then name=item[3] end
    bind(name,item[2],item[3])
end
local vehicleKeys=config.VehicleKeys or {}
for _,item in ipairs({{"Repair","repair","F1"},{"God","godmode","F4"},{"Drive","drive","F5"},{"Spawn","spawnVehicle","F9"},{"Diagnose","diagnose","HOME"}})do
    local name=vehicleKeys[item[1]]
    if name==nil then name=item[3] end
    bind(name,item[2],item[3])
end
local extraCycle=vehicleKeys.Next
if type(extraCycle)=="string" and extraCycle:upper()~="F2" and extraCycle:upper()~="F3" then bind(extraCycle,"cycleVehicle")end

local menu=require("menu").new(require("menu_engine"),function()
    return {flying=controller:isEnabled(),god=protection.manual,protected=protection.landing or protection.flight,
        speed=config.Speeds[controller.speedIndex],model=vehicles.catalog[vehicles.selected].name,driving=vehicles.driver~=nil,spawned=vehicles:count(),boost=vehicles.boostSpeeds[vehicles.boostIndex],steering=vehicleEngine.invertSteering}
end,request)
adapter.onLog=function(message)menu:notice(message)end

LoopAsync(16, function()
    if not queued and (#actions > 0 or controller:hasWork() or protection:hasWork() or vehicles:hasWork() or menu:hasWork() or vehicleEngine.hasConvertedWork() or next(heldKeys)~=nil) then
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
                    if (not key or not heldKeys[key]) and actionReady(action,key) then
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
                    elseif action == "steering" then vehicleEngine.toggleSteering()
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
                vehicleEngine.tickConverted()
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
    -- Do not hook engine-wide visibility, collision or steering setters. Those
    -- run during level loading and may execute beyond this mod's owned actors.
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
        vehicleEngine.resetSteering()
        heldKeys={}
        lastActionTimes={}
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

adapter.log("Ready. F2 menu; F3 next vehicle; Home diagnostics; F1 repair/recover; F4 god; F5 enter/exit; F6 noclip; F7/F8 speed; F9 spawn; F10 return.")
