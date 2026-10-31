-- UE4SS v3.0.1 / Unreal 4.27 adapter. Call only on the game thread.
local Adapter = {}
local cachedController, gameplay, keys = nil, nil, {}

local function valid(object)
    return object ~= nil and object:IsValid()
end

local function identity(object)
    assert(valid(object), "The player object is no longer valid")
    return tostring(object:GetAddress()) .. ":" .. object:GetFullName()
end

local function position(v)
    return {X = v.X, Y = v.Y, Z = v.Z}
end

local function isLocal(controller)
    local ok, result = pcall(function() return valid(controller) and controller:IsLocalController() end)
    return ok and result
end

local function statics()
    if not valid(gameplay) then gameplay = StaticFindObject("/Script/Engine.Default__GameplayStatics") end
    assert(valid(gameplay), "GameplayStatics is not available yet")
    return gameplay
end

local function down(controller, name)
    if not keys[name] then
        local key = FName(name, EFindName.FNAME_Find)
        assert(key:ToString() ~= "None", "Unreal input key is unavailable: " .. name)
        keys[name] = {KeyName = key}
    end
    return controller:IsInputKeyDown(keys[name])
end

function Adapter.log(message)
    print("[Lost Budapest Noclip 0.1.0] " .. message .. "\n")
end

function Adapter.reset()
    cachedController, gameplay = nil, nil
end

function Adapter.resolve()
    if not isLocal(cachedController) then
        cachedController = nil
        for _, controller in ipairs(FindAllOf("PlayerController") or {}) do
            if isLocal(controller) then cachedController = controller; break end
        end
    end
    if not cachedController then return nil end
    local pawn = cachedController.Pawn
    if not valid(pawn) then return nil end
    -- A vehicle/spectator/menu pawn must not be treated as a walking character.
    local ok, movement = pcall(function() return pawn.CharacterMovement end)
    if not ok or not valid(movement) then return nil end
    return {controller = cachedController, pawn = pawn, movement = movement,
        identity = identity(pawn) .. "|" .. identity(movement)}
end

function Adapter.same(ctx, snapshot)
    return ctx.identity == snapshot.identity
end

function Adapter.capture(ctx)
    return {ctx = ctx, identity = ctx.identity, pawnIdentity = identity(ctx.pawn), position = position(ctx.pawn:K2_GetActorLocation()),
        collision = ctx.pawn:GetActorEnableCollision(), mode = ctx.movement.MovementMode,
        custom = ctx.movement.CustomMovementMode}
end

function Adapter.apply(ctx)
    ctx.movement:StopMovementImmediately()
    ctx.movement:SetMovementMode(0, 0) -- MOVE_None; movement is driven by the trainer.
    ctx.pawn:SetActorEnableCollision(false)
    assert(ctx.movement.MovementMode == 0 and not ctx.pawn:GetActorEnableCollision(),
        "The game did not accept movement/collision changes")
    return true
end

function Adapter.owned(ctx)
    return ctx.movement.MovementMode == 0 and not ctx.pawn:GetActorEnableCollision()
end

function Adapter.restore(snapshot)
    local ctx = snapshot.ctx
    if not valid(ctx.pawn) then return true end -- The old pawn has been destroyed.
    if identity(ctx.pawn) ~= snapshot.pawnIdentity then return true end
    if not valid(ctx.movement) then
        -- Collision can still be restored when the component was replaced.
        if not ctx.pawn:GetActorEnableCollision() then ctx.pawn:SetActorEnableCollision(snapshot.collision) end
        return true
    end
    if identity(ctx.pawn) .. "|" .. identity(ctx.movement) ~= snapshot.identity then return true end
    local errors = {}
    local ok, err = pcall(function()
        -- Leave a later movement mode selected by the game intact.
        if ctx.movement.MovementMode == 0 then
            ctx.movement:StopMovementImmediately()
            ctx.movement:SetMovementMode(snapshot.mode, snapshot.custom)
        end
    end)
    if not ok then errors[#errors + 1] = tostring(err) end
    ok, err = pcall(function()
        if not ctx.pawn:GetActorEnableCollision() then ctx.pawn:SetActorEnableCollision(snapshot.collision) end
    end)
    if not ok then errors[#errors + 1] = tostring(err) end
    if #errors > 0 then error(table.concat(errors, "; ")) end
    return true
end

function Adapter.teleport(ctx, target)
    local moved = ctx.pawn:K2_SetActorLocation(target, false, {}, true)
    if moved == false then
        -- Unreal can report no movement when the actor is already at its target.
        local actual = ctx.pawn:K2_GetActorLocation()
        if math.abs(actual.X-target.X) <= 0.01 and math.abs(actual.Y-target.Y) <= 0.01
            and math.abs(actual.Z-target.Z) <= 0.01 then return true end
    end
    return moved
end

function Adapter.location(ctx) return position(ctx.pawn:K2_GetActorLocation()) end
function Adapter.rotation(ctx)
    local rotation = ctx.controller:GetControlRotation()
    return {Pitch = rotation.Pitch, Yaw = rotation.Yaw}
end
function Adapter.time(ctx) return statics():GetTimeSeconds(ctx.pawn) end
function Adapter.paused(ctx) return statics():IsGamePaused(ctx.pawn) end
function Adapter.blocked(ctx)
    return ctx.controller:IsMoveInputIgnored() or ctx.controller:IsLookInputIgnored()
end
function Adapter.input(ctx)
    local pc = ctx.controller
    return {forward = down(pc, "W"), back = down(pc, "S"), left = down(pc, "A"), right = down(pc, "D"),
        up = down(pc, "E") or down(pc, "SpaceBar"), down = down(pc, "Q") or down(pc, "LeftControl"),
        boost = down(pc, "LeftShift") or down(pc, "RightShift")}
end

return Adapter
