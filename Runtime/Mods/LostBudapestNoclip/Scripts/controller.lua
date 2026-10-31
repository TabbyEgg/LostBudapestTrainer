-- Pure Lua state machine. The adapter is the only code that accesses Unreal.
local Controller = {}
Controller.__index = Controller

local function finite(n)
    return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function vector(v)
    assert(v and finite(v.X) and finite(v.Y) and finite(v.Z), "Invalid player position")
    return {X = v.X, Y = v.Y, Z = v.Z}
end

local function axis(positive, negative)
    return (positive and 1 or 0) - (negative and 1 or 0)
end

function Controller.new(config, api)
    assert(type(config.Speeds) == "table" and #config.Speeds > 0, "No flight speeds configured")
    local previous = 0
    for _, speed in ipairs(config.Speeds) do
        assert(finite(speed) and speed > previous and speed <= 50000, "Invalid flight speed")
        previous = speed
    end
    assert(type(config.DefaultSpeedIndex) == "number" and config.DefaultSpeedIndex % 1 == 0
        and config.Speeds[config.DefaultSpeedIndex], "Invalid default speed index")
    assert(finite(config.BoostMultiplier) and config.BoostMultiplier >= 1 and config.BoostMultiplier <= 10,
        "Invalid boost multiplier")
    assert(finite(config.MaxDeltaSeconds) and config.MaxDeltaSeconds > 0 and config.MaxDeltaSeconds <= 0.1,
        "Invalid maximum movement interval")
    return setmetatable({config = config, api = api, enabled = false, snapshot = nil,
        speedIndex = config.DefaultSpeedIndex, lastTime = nil, restoreAttempts = 0}, Controller)
end

function Controller:isEnabled()
    return self.enabled
end

function Controller:hasWork()
    return self.enabled or (self.snapshot ~= nil and self.restoreAttempts < 4)
end

function Controller:_log(message)
    self.api.log(message)
end

function Controller:_restore()
    if not self.snapshot then return true end
    self.restoreAttempts = self.restoreAttempts + 1
    local ok, result = pcall(self.api.restore, self.snapshot)
    if ok and result ~= false then
        self.snapshot, self.lastTime, self.restoreAttempts = nil, nil, 0
        return true
    end
    if self.restoreAttempts == 1 or self.restoreAttempts == 4 then
        self:_log("State restoration pending: " .. tostring(ok and "Unreal refused restoration" or result)
            .. ". Press the toggle again to retry; restart the game if movement remains locked.")
    end
    return false
end

function Controller:disable(returnToStart)
    local wasEnabled = self.enabled
    local snapshot = self.snapshot
    if snapshot and returnToStart then
        local samePawn = false
        local ok, err = pcall(function()
            local ctx = self.api.resolve()
            assert(ctx and self.api.same(ctx, snapshot), "The original player pawn is no longer controlled")
            samePawn = true
            assert(self.api.teleport(ctx, vector(snapshot.position)) ~= false, "Return teleport was refused")
        end)
        if not ok then
            self:_log("Could not return to the entry point: " .. tostring(err))
            if samePawn and wasEnabled then
                -- Keep collision disabled if the emergency return itself failed.
                self.lastTime = nil
                self:_log("Noclip remains on. Retry F10, or fly to an open position before toggling off.")
                return false
            end
        end
    end
    self.enabled, self.lastTime, self.restoreAttempts = false, nil, 0
    local restored = self:_restore()
    self:_log(restored and (returnToStart and "Noclip off; entry-point return requested." or "Noclip off.")
        or "Noclip stopped; previous state still needs restoration.")
    return restored
end

function Controller:toggle()
    if self.enabled then return self:disable(false) end
    if self.snapshot then
        self:disable(false)
        return false -- Never enable a second session over a pending restoration.
    end
    local ok, err = pcall(function()
        local ctx = assert(self.api.resolve(), "Enter the game on foot before enabling noclip")
        assert(not self.api.paused(ctx), "Close the pause menu before enabling noclip")
        assert(not self.api.blocked(ctx), "Player controls are currently unavailable")
        local snapshot = self.api.capture(ctx)
        assert(snapshot and snapshot.ctx and snapshot.identity, "Unable to capture player state")
        snapshot.position = vector(snapshot.position)
        assert(type(snapshot.collision) == "boolean", "Unable to read collision state")
        assert(finite(snapshot.mode) and snapshot.mode % 1 == 0 and snapshot.mode >= 0 and snapshot.mode <= 6,
            "Unable to read movement mode")
        assert(finite(snapshot.custom) and snapshot.custom % 1 == 0 and snapshot.custom >= 0 and snapshot.custom <= 255,
            "Unable to read custom movement mode")
        self.snapshot = snapshot -- Set before the first engine write, allowing rollback.
        assert(self.api.apply(ctx) ~= false, "The game refused noclip")
        self.enabled, self.lastTime = true, nil
    end)
    if not ok then
        self.enabled, self.lastTime = false, nil
        self:_restore()
        self:_log("Could not enable noclip: " .. tostring(err))
        return false
    end
    self:_log("Noclip on; " .. self.config.Speeds[self.speedIndex] .. " cm/s. F10 returns to the entry point.")
    return true
end

function Controller:slower()
    self.speedIndex = math.max(1, self.speedIndex - 1)
    self:_log("Flight speed: " .. self.config.Speeds[self.speedIndex] .. " cm/s.")
end

function Controller:faster()
    self.speedIndex = math.min(#self.config.Speeds, self.speedIndex + 1)
    self:_log("Flight speed: " .. self.config.Speeds[self.speedIndex] .. " cm/s.")
end

function Controller:_tick()
    if not self.enabled then self:_restore(); return end
    local ctx = self.api.resolve()
    if not ctx or not self.api.same(ctx, self.snapshot) then
        self:disable(false)
        self:_log("Player pawn changed; noclip remains off for the new pawn.")
        return
    end
    local now = self.api.time(ctx)
    assert(finite(now), "The game clock is unavailable")
    if self.api.paused(ctx) then self.lastTime = nil; return end
    if self.api.blocked(ctx) or (self.api.owned and not self.api.owned(ctx)) then
        self:disable(false)
        self:_log("The game changed player control; noclip stopped.")
        return
    end
    local previous = self.lastTime
    self.lastTime = now
    if not previous then return end
    local dt = now - previous
    if dt <= 0 then return end
    dt = math.min(dt, self.config.MaxDeltaSeconds)
    local input = self.api.input(ctx)
    local forward, right, up = axis(input.forward, input.back), axis(input.right, input.left), axis(input.up, input.down)
    if forward == 0 and right == 0 and up == 0 then return end
    local rotation = self.api.rotation(ctx)
    assert(rotation and finite(rotation.Pitch) and finite(rotation.Yaw), "Camera rotation is unavailable")
    local pitch, yaw = math.rad(rotation.Pitch), math.rad(rotation.Yaw)
    local x = forward * math.cos(pitch) * math.cos(yaw) - right * math.sin(yaw)
    local y = forward * math.cos(pitch) * math.sin(yaw) + right * math.cos(yaw)
    local z = forward * math.sin(pitch) + up
    local magnitude = math.sqrt(x*x + y*y + z*z)
    if magnitude < 0.000001 then return end
    local distance = self.config.Speeds[self.speedIndex] * dt * (input.boost and self.config.BoostMultiplier or 1)
    local position = vector(self.api.location(ctx))
    local target = {X = position.X + x/magnitude*distance, Y = position.Y + y/magnitude*distance,
        Z = position.Z + z/magnitude*distance}
    assert(self.api.teleport(ctx, target) ~= false, "The game refused flight movement")
end

function Controller:tick()
    local ok, err = pcall(function() self:_tick() end)
    if not ok then
        self.enabled, self.lastTime = false, nil
        self:_restore()
        self:_log("Noclip stopped after an engine error: " .. tostring(err))
    end
end

return Controller
