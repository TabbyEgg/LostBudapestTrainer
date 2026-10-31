local config = require("config")
local adapter = require("adapter")
local Controller = require("controller")
local controller = Controller.new(config, adapter)
local protection = require("protection").new(adapter)
local actions, queued = {}, false

local function request(action)
    -- Input callbacks and the async loop never access Unreal objects.
    if #actions < 16 then actions[#actions + 1] = action end
end

for name, action in pairs({Toggle = "toggle", Slower = "slower", Faster = "faster", Return = "return"}) do
    local key = assert(Key[config.Keys[name]], "Unknown trainer key: " .. tostring(config.Keys[name]))
    RegisterKeyBind(key, function() request(action) end)
end

if Key.F3 then RegisterKeyBind(Key.F3, function() request("diagnose") end) end
if Key.F4 then RegisterKeyBind(Key.F4, function() request("godmode") end) end

LoopAsync(16, function()
    if not queued and (#actions > 0 or controller:hasWork() or protection:hasWork()) then
        queued = true
        local ok, err = pcall(ExecuteInGameThread, function()
            -- Drop the pending flag even if a callback fails. Only one queued
            -- game-thread update is allowed; loading cannot build a backlog.
            local callbackOk, callbackError = pcall(function()
                local pending = actions
                actions = {}
                for _, action in ipairs(pending) do
                    if action == "diagnose" then adapter.diagnose()
                    elseif action == "godmode" then protection:toggle()
                    elseif action == "return" then controller:disable(true)
                    else controller[action](controller) end
                end
                controller:tick()
                protection:tick(controller:isEnabled())
            end)
            queued = false
            if not callbackOk then
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
    -- Use the stable loader's own sample-supported player restart hook. Its
    -- optional LoadMapPre callback has an upstream argument-count defect.
    local ok, err = pcall(RegisterHook, "/Script/Engine.PlayerController:ClientRestart", function()
        actions = {}
        controller:disable(false)
        protection:reset()
        adapter.reset()
        -- No return override: Unreal retains its normal player restart behavior.
    end)
    if not ok then adapter.log("Player restart hook unavailable; pawn-change cleanup remains active: " .. tostring(err)) end
end

adapter.log("Ready. F6 toggle; WASD fly; E/Space up; Q/Ctrl down; Shift boost; F7/F8 speed; F10 return and disable.")
