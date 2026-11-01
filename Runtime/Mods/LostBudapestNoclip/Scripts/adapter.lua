-- UE4SS v3.0.1 / Unreal 4.27 adapter. Call only on the game thread.
local Adapter = {menuOpen=false}
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
    print("[Lost Budapest Trainer 0.4.1] " .. message .. "\n")
    if Adapter.onLog then pcall(Adapter.onLog,message) end
end

function Adapter.reset()
    cachedController, gameplay = nil, nil
end

function Adapter.playerContext()
    if not isLocal(cachedController) then
        cachedController = nil
        for _, controller in ipairs(FindAllOf("PlayerController") or {}) do
            if isLocal(controller) then cachedController = controller; break end
        end
    end
    if not cachedController then return nil end
    local pawn = cachedController.Pawn
    if not valid(pawn) then return nil end
    return {controller=cachedController,pawn=pawn}
end

function Adapter.gameplay() return statics() end
function Adapter.keyDown(name)
    local ok,value=pcall(function()
        local ctx=Adapter.playerContext()
        return ctx and down(ctx.controller,name) or false
    end)
    return ok and value or false
end

function Adapter.resolve()
    local player=Adapter.playerContext()
    if not player then return nil end
    local pawn=player.pawn
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
function Adapter.paused(ctx) return Adapter.menuOpen or statics():IsGamePaused(ctx.pawn) end
function Adapter.blocked(ctx)
    return ctx.controller:IsMoveInputIgnored() or ctx.controller:IsLookInputIgnored()
end
function Adapter.input(ctx)
    local pc = ctx.controller
    return {forward = down(pc, "W"), back = down(pc, "S"), left = down(pc, "A"), right = down(pc, "D"),
        up = down(pc, "E") or down(pc, "SpaceBar"), down = down(pc, "Q") or down(pc, "LeftControl"),
        boost = down(pc, "LeftShift") or down(pc, "RightShift")}
end

function Adapter.damageContext()
    local ctx=Adapter.playerContext()
    if not ctx then return nil end
    ctx.identity=identity(ctx.pawn)
    local ok,movement=pcall(function() return ctx.pawn.CharacterMovement end)
    if ok and valid(movement) then ctx.movement=movement end
    return ctx
end
function Adapter.captureDamage(ctx)
    local ok, value = pcall(function() return ctx.pawn.bCanBeDamaged end)
    if not ok or type(value) ~= "boolean" then return nil end
    local saved={ctx=ctx,identity=ctx.identity,pawnIdentity=identity(ctx.pawn),damage=value}
    pcall(function()
        -- The supplied runtime log establishes Abel.Health and his custom Damage function.
        if ctx.pawn:GetClass():GetFullName()=="BlueprintGeneratedClass /Game/Characters/Blueprints/Abel/Abel.Abel_C" then
            local health=ctx.pawn.Health
            if type(health)=="number" and health==health and health>0 and health<1000000 then saved.health=health end
        end
    end)
    return saved
end
function Adapter.disableDamage(ctx) ctx.pawn.bCanBeDamaged=false end
function Adapter.guardHealthAndFall(ctx,saved)
    if ctx.identity~=saved.identity then return end
    if saved.health then
        local health=ctx.pawn.Health
        -- Preserve a living player's health; never pretend to resurrect a scripted death.
        if type(health)=="number" and health>0 and health<saved.health then ctx.pawn.Health=saved.health end
    end
    if valid(ctx.movement) and ctx.movement.MovementMode==3 then
        local v=ctx.movement.Velocity
        if v and type(v.Z)=="number" and v.Z < -300 then
            ctx.movement.Velocity={X=v.X,Y=v.Y,Z=-300}
        end
    end
end
function Adapter.blockIncomingDamage(targetParam,amountParam)
    local target=targetParam:get()
    local ctx=Adapter.damageContext()
    if not ctx or not valid(target) or identity(target)~=ctx.identity then return false end
    local amount=amountParam:get()
    if type(amount)~="number" or amount<=0 then return false end
    amountParam:set(0) -- Native pre-hook: ApplyDamage exits before calling TakeDamage.
    return true
end
function Adapter.restoreDamage(saved)
    local pawn=saved.ctx.pawn
    if valid(pawn) and identity(pawn)==saved.pawnIdentity and pawn.bCanBeDamaged==false then
        pawn.bCanBeDamaged=saved.damage
    end
end
function Adapter.grounded(ctx)
    if not valid(ctx.movement) then return true end
    local mode=ctx.movement.MovementMode
    return mode==1 or mode==2 or mode==4
end

function Adapter.diagnose()
    Adapter.log("VEHICLE DIAGNOSTIC BEGIN (read-only)")
    local ctx = Adapter.resolve()
    local origin = ctx and Adapter.location(ctx) or nil
    local seen, count = {}, 0
    for _, kind in ipairs({"WheeledVehicle", "WheeledVehicleMovementComponent", "Pawn", "PlayerController"}) do
        local objects = FindAllOf(kind) or {}
        Adapter.log(kind .. " loaded=" .. #objects)
        for _, object in ipairs(objects) do
            if count >= 100 then break end
            local ok, err = pcall(function()
                if not valid(object) then return end
                local name = object:GetFullName()
                if seen[name] then return end
                local locationOk, location = pcall(function() return object:K2_GetActorLocation() end)
                if origin and locationOk then
                    local dx,dy,dz=location.X-origin.X,location.Y-origin.Y,location.Z-origin.Z
                    if dx*dx+dy*dy+dz*dz > 10000*10000 then return end
                end
                seen[name], count = true, count + 1
                Adapter.log("OBJECT " .. name .. " CLASS " .. object:GetClass():GetFullName())
                for _, field in ipairs({"Health", "MaxHealth", "VehicleHealth", "Damage", "bIsDead", "bDestroyed", "Controller", "Pawn", "VehicleMovement", "Mesh"}) do
                    local readOk, value = pcall(function() return object[field] end)
                    if readOk and value ~= nil then
                        local textOk, text = pcall(function()
                            if type(value)=="userdata" then return value:GetFullName() end
                            return tostring(value)
                        end)
                        if textOk and text ~= nil then Adapter.log("  " .. field .. "=" .. text) end
                    end
                end
            end)
            if not ok then Adapter.log("Skipped unavailable object: " .. tostring(err)) end
        end
    end
    if ctx then
        Adapter.log("PLAYER "..ctx.pawn:GetFullName())
        for _,field in ipairs({"Health","bCanBeDamaged"}) do
            local ok,value=pcall(function()return ctx.pawn[field]end)
            if ok and (type(value)=="number" or type(value)=="boolean") then Adapter.log("PLAYER "..field.."="..tostring(value))end
        end
    end
    for _,hud in ipairs(FindAllOf("HUD") or {}) do
        if valid(hud) then Adapter.log("HUD "..hud:GetFullName().." CLASS "..hud:GetClass():GetFullName()) end
    end
    Adapter.log("VEHICLE DIAGNOSTIC END; stand beside a working car and send UE4SS.log")
end

return Adapter
