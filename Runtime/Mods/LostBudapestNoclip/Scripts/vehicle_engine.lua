-- All calls are made by main.lua on the game thread. No guessed memory offsets.
local adapter=require("adapter")
local config=require("config")
local Engine={log=adapter.log,invertSteering=config.InvertVehicleSteering~=false}
local function number(v)return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge end
local function vector(v)return v and number(v.X) and number(v.Y) and number(v.Z) end
local function rotation(v)return v and number(v.Pitch) and number(v.Yaw) and number(v.Roll) end
function Engine.valid(actor) return actor~=nil and actor:IsValid() end
function Engine.player()
    local ctx=adapter.playerContext()
    -- Avoid probing nonexistent CharacterMovement/VehicleMovement fields. On the
    -- stable UE4SS loader a missing-property native error can hide its own text.
    if ctx and ctx.controller.bShowMouseCursor==true then return nil end
    if ctx and not ctx.controller:IsMoveInputIgnored() and not ctx.controller:IsLookInputIgnored()
        and not adapter.gameplay():IsGamePaused(ctx.pawn) then return ctx end
end
function Engine.class(path)
    local class=StaticFindObject(path)
    if Engine.valid(class) then return class end
end
function Engine.toggleSteering()
    Engine.invertSteering=not Engine.invertSteering
    Engine.steeringHeld=nil
    Engine.log(Engine.invertSteering and "Steering correction on." or "Steering correction off; original game steering restored.")
end
function Engine.hasConvertedWork()
    -- Pure Lua check: the asynchronous scheduler must not inspect Unreal objects.
    return not Engine.maintenanceFailed and require("player_vehicle").hasWork()
end
function Engine.spawnTransform(ctx)
    local position=ctx.pawn:K2_GetActorLocation()
    local yaw=ctx.controller:GetControlRotation().Yaw
    assert(vector(position) and number(yaw),"Invalid player transform")
    yaw=yaw%360
    local rad=math.rad(yaw)
    local candidates={}
    for _,distance in ipairs({700,1100,1500,2000}) do
        for _,offset in ipairs({0,30,-30,60,-60,90,-90,135,-135,180}) do
            local angle=rad+math.rad(offset)
            candidates[#candidates+1]={X=position.X+math.cos(angle)*distance,Y=position.Y+math.sin(angle)*distance,Z=position.Z+80}
        end
    end
    return {Origin={X=position.X,Y=position.Y,Z=position.Z},Candidates=candidates,Translation={X=position.X+math.cos(rad)*700,Y=position.Y+math.sin(rad)*700,Z=position.Z+80},
        Rotation={X=0,Y=0,Z=math.sin(rad/2),W=math.cos(rad/2)},Scale3D={X=1,Y=1,Z=1}}
end
function Engine.begin(ctx,class,transform)
    -- Build compatible selected models on the real player Blueprint, not the AI Blueprint.
    if config.PlayerVehicleSetup~=false and class:GetFullName():find("/Game/Traffic_AI_System/Cars/",1,true) then
        local player=assert(Engine.class("/Game/Autok/Abel_Car.Abel_Car_C"),"Abel player vehicle must be loaded for this model")
        local profile=require("player_vehicle").new(class,player)
        local actor=require("native_spawn").actor(ctx,player,transform,"WheeledVehicle",profile)
        if profile.doorWarning then Engine.log("Selected car spawned; extra-door hiding unavailable: "..profile.doorWarning)end
        Engine.maintenanceFailed=false
        return actor
    end
    return require("native_spawn").actor(ctx,class,transform,"WheeledVehicle")
end
function Engine.prepare(actor)
    -- Traffic blueprints must not auto-possess an AI with no assigned route.
    actor.AutoPossessAI=0
    actor.AutoPossessPlayer=0
end
function Engine.finish(actor,transform)
    local finished=actor
    if Engine.valid(finished) and finished:GetClass():GetFullName():find("/Game/Traffic_AI_System/Cars/",1,true) then
        -- No traffic route was assigned. Leave parked until trainer driving starts.
        finished:SetActorTickEnabled(false)
    end
    return finished
end
function Engine.destroy(actor) actor:K2_DestroyActor() end
local function id(actor) return tostring(actor:GetAddress())..":"..actor:GetFullName() end
function Engine.repairTarget(ctx,spawned)
    local own={}
    for _,actor in ipairs(spawned) do if Engine.valid(actor) then own[id(actor)]=true end end
    local origin=ctx.pawn:K2_GetActorLocation()
    local closest,best=nil,1200*1200
    for _,actor in ipairs(FindAllOf("WheeledVehicle") or {}) do
        if Engine.valid(actor) and not actor:GetFullName():find("Default__",1,true) then
            local class=actor:GetClass():GetFullName()
            local controlled=id(actor)==id(ctx.pawn)
            if controlled then return actor end
            if own[id(actor)] or class=="BlueprintGeneratedClass /Game/Autok/Abel_Car.Abel_Car_C" then
                local p=actor:K2_GetActorLocation()
                local d=(p.X-origin.X)^2+(p.Y-origin.Y)^2+(p.Z-origin.Z)^2
                if d<best then closest,best=actor,d end
            end
        end
    end
    return closest
end
local function repairFunction(actor)
    local class=actor:GetClass()
    local allowed={RepairVehicle=true,RepairCar=true,Repair=true,ResetDamage=true}
    for _=1,8 do
        if not Engine.valid(class) then break end
        local found=nil
        class:ForEachFunction(function(fn)
            local name=fn:GetFName():ToString()
            if allowed[name] then
                local parameters=0
                local ok=pcall(function() fn:ForEachProperty(function(prop)
                    if prop:GetFName():ToString()~="ReturnValue" then parameters=parameters+1 end
                end) end)
                if ok and parameters==0 then found=name;return true end
            end
        end)
        if found then return found end
        class=class:GetSuperStruct()
    end
end
local function finite(value) return type(value)=="number" and value==value and math.abs(value)<1000000000 end
function Engine.repair(actor)
    local health=false
    -- Only invoke verified no-argument repair functions, never guessed params.
    local name
    local inspected,result=pcall(repairFunction,actor)
    if inspected then name=result end
    if name then
        actor[name](actor);health=true
        if not Engine.valid(actor) then return "The game's repair function removed/replaced the vehicle; no further changes applied." end
    end
    for _,pair in ipairs({{"Health","MaxHealth"},{"VehicleHealth","MaxVehicleHealth"},{"CarHealth","MaxCarHealth"}}) do
        local ok=pcall(function()
            local current,maximum=actor[pair[1]],actor[pair[2]]
            if finite(current) and finite(maximum) and maximum>0 then actor[pair[1]]=maximum;health=true end
        end)
    end
    local p=actor:K2_GetActorLocation()
    local rotation=actor:K2_GetActorRotation()
    assert(vector(p) and number(rotation.Yaw),"Vehicle transform is invalid")
    actor:K2_SetActorRotation({Pitch=0,Yaw=rotation.Yaw,Roll=0},true)
    actor:K2_SetActorLocation({X=p.X,Y=p.Y,Z=p.Z+40},true,{},true)
    local mesh=actor.Mesh
    if Engine.valid(mesh) then
        local bone=FName("None",EFindName.FNAME_Find)
        mesh:SetPhysicsLinearVelocity({X=0,Y=0,Z=0},false,bone)
        mesh:SetPhysicsAngularVelocityInDegrees({X=0,Y=0,Z=0},false,bone)
    end
    if health then return "Vehicle recovered upright; exposed health/repair system reset." end
    return "Vehicle recovered upright and motion stopped. This blueprint exposes no verified health repair; damage was not changed."
end
local function key(pc,name) return pc:IsInputKeyDown({KeyName=FName(name,EFindName.FNAME_Find)}) end
function Engine.tickConverted()
    if not Engine.hasConvertedWork() then return end
    local ok,err=pcall(function()
        local profiles=require("player_vehicle")
        profiles.maintainDoors(Engine.log)
        if not Engine.invertSteering or adapter.menuOpen then Engine.steeringHeld=nil;return end
        local ctx=Engine.player()
        if not ctx then Engine.steeringHeld=nil;return end
        local movement=profiles.convertedMovement(ctx.pawn)
        if not Engine.valid(movement) then Engine.steeringHeld=nil;return end
        local left,right=key(ctx.controller,"A"),key(ctx.controller,"D")
        local target=id(ctx.pawn)..":"..id(movement)
        if left or right then
            movement:SetSteeringInput((left and 1 or 0)-(right and 1 or 0))
            Engine.steeringHeld=target
        else
            -- Release only a keyboard correction we applied to this same car.
            -- With no A/D held, leave gamepad and other native inputs alone.
            if Engine.steeringHeld==target then movement:SetSteeringInput(0)end
            Engine.steeringHeld=nil
        end
    end)
    if not ok then
        Engine.maintenanceFailed=true;Engine.steeringHeld=nil
        Engine.log("Converted car maintenance stopped: "..tostring(err))
    end
end
function Engine.captureDriver(ctx,actor)
    assert(id(ctx.pawn)~=id(actor),"Already inside a vehicle; use its normal exit control")
    local movement=actor.VehicleMovement
    assert(Engine.valid(movement),"This actor has no supported wheeled-vehicle movement")
    assert(type(ctx.pawn.bHidden)=="boolean","Cannot capture character visibility")
    local pawnMovement=ctx.pawn.CharacterMovement
    assert(Engine.valid(pawnMovement),"Trainer entry requires your walking character")
    return {pc=ctx.controller,pawn=ctx.pawn,actor=actor,movement=movement,movementId=id(movement),pawnId=id(ctx.pawn),actorId=id(actor),
        hidden=ctx.pawn.bHidden,collision=ctx.pawn:GetActorEnableCollision(),tick=actor:IsActorTickEnabled(),
        pawnMovement=pawnMovement,pawnMovementId=id(pawnMovement),pawnMode=pawnMovement.MovementMode,pawnCustom=pawnMovement.CustomMovementMode,
        pawnTick=ctx.pawn:IsActorTickEnabled(),eye=actor.BaseEyeHeight,viewTarget=ctx.controller:GetViewTarget(),
        native=actor:GetClass():GetFullName()=="BlueprintGeneratedClass /Game/Autok/Abel_Car.Abel_Car_C"}
end
function Engine.enterDriver(state)
    state.pawnMovement:StopMovementImmediately()
    state.pawnMovement:SetMovementMode(0,0)
    state.pawn:SetActorTickEnabled(false)
    if not state.native then state.actor:SetActorTickEnabled(false) end -- Only suspend route-less traffic steering.
    state.pc:Possess(state.actor)
    assert(Engine.valid(state.pc.Pawn) and id(state.pc.Pawn)==state.actorId,"The game refused vehicle possession")
    state.pawnMovement:SetMovementMode(0,0)
    state.pawn:SetActorHiddenInGame(true)
    state.pawn:SetActorEnableCollision(false)
    if state.native then
        state.movement:SetBrakeInput(0);state.movement:SetHandbrakeInput(false)
        state.actor:EnableInput(state.pc)
        state.pc:SetViewTargetWithBlend(state.actor,0,0,0,false)
        return -- Preserve Abel's own Blueprint input, camera and vehicle settings.
    end
    if type(state.eye)=="number" then state.actor.BaseEyeHeight=120 end
    local facing=state.actor:K2_GetActorRotation()
    assert(rotation(facing),"Vehicle camera rotation is invalid")
    state.pc:SetControlRotation(facing)
    local class=assert(Engine.class("/Script/Engine.CameraActor"),"Engine camera class is unavailable")
    local transform={Translation=state.actor:K2_GetActorLocation(),Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
    state.camera=require("native_spawn").actor({controller=state.pc,pawn=state.actor},class,transform,"CameraActor")
    assert(Engine.valid(state.camera),"Could not create driving camera")
    state.cameraId=id(state.camera)
    assert(state.camera:K2_AttachToActor(state.actor,FName("None",EFindName.FNAME_Find),0,0,0,false)~=false,"Could not attach driving camera")
    state.camera:K2_SetActorRelativeLocationAndRotation({X=-500,Y=0,Z=220},{Pitch=-12,Yaw=0,Roll=0},false,{},true)
    -- A real CameraActor bypasses character-only ALS camera-manager logic.
    state.pc:SetViewTargetWithBlend(state.camera,0,0,0,false)
end
local function releaseCamera(state)
    if Engine.valid(state.camera) and id(state.camera)==state.cameraId then
        if Engine.valid(state.pc) then
            local current=state.pc:GetViewTarget()
            if Engine.valid(current) and id(current)==state.cameraId then
                local pawn=state.pc.Pawn
                local target=state.viewTarget
                if Engine.valid(pawn) and id(pawn)~=state.pawnId then target=pawn end
                if not Engine.valid(target) then target=pawn end
                if Engine.valid(target) then state.pc:SetViewTargetWithBlend(target,0,0,0,false) end
            end
        end
        state.camera:K2_DestroyActor()
    end
end
function Engine.exitDriver(state)
    local carValid=Engine.valid(state.actor) and id(state.actor)==state.actorId
    local pawnValid=Engine.valid(state.pawn) and id(state.pawn)==state.pawnId
    local pcValid=Engine.valid(state.pc)
    local current=pcValid and state.pc.Pawn or nil
    local controlsCar=Engine.valid(current) and id(current)==state.actorId
    local recoverLostCar=pcValid and not Engine.valid(current) and not carValid
    if carValid and Engine.valid(state.movement) and id(state.movement)==state.movementId then
        state.movement:SetThrottleInput(0);state.movement:SetSteeringInput(0)
        state.movement:SetBrakeInput(1);state.movement:SetHandbrakeInput(true)
    end
    if (controlsCar or recoverLostCar) and not pawnValid then return false end
    if pawnValid and (controlsCar or recoverLostCar) then
        state.pawn:SetActorEnableCollision(state.collision)
        if carValid then
            local p=state.actor:K2_GetActorLocation()
            local facing=state.actor:K2_GetActorRotation()
            if vector(p) and number(facing.Yaw) then
            local yaw=math.rad(facing.Yaw%360)
            -- Swept placement from the original safe position; a wall can stop the exit short.
            state.pawn:K2_SetActorLocation({X=p.X-math.sin(yaw)*250,Y=p.Y+math.cos(yaw)*250,Z=p.Z+100},true,{},true)
            end
        end
        local ok=pcall(function() state.pc:Possess(state.pawn) end)
        if not ok or not Engine.valid(state.pc.Pawn) or id(state.pc.Pawn)~=state.pawnId then
            -- Retain a stationary hidden original pawn while the player retries.
            state.pawn:SetActorEnableCollision(false)
            state.pawn:SetActorHiddenInGame(true)
            state.pawn:SetActorTickEnabled(false)
            if Engine.valid(state.pawnMovement) and id(state.pawnMovement)==state.pawnMovementId then state.pawnMovement:SetMovementMode(0,0) end
            return false
        end
    end
    if carValid then
        state.actor:SetActorTickEnabled(state.tick)
        if type(state.eye)=="number" then state.actor.BaseEyeHeight=state.eye end
    end
    if pawnValid then
        if Engine.valid(state.pawnMovement) and id(state.pawnMovement)==state.pawnMovementId and state.pawnMovement.MovementMode==0 then
            state.pawnMovement:StopMovementImmediately()
            state.pawnMovement:SetMovementMode(state.pawnMode,state.pawnCustom)
        end
        state.pawn:SetActorTickEnabled(state.pawnTick)
        state.pawn:SetActorHiddenInGame(state.hidden)
        state.pawn:SetActorEnableCollision(state.collision)
    end
    releaseCamera(state)
    if state.native and pcValid and Engine.valid(state.viewTarget) and controlsCar then
        state.pc:SetViewTargetWithBlend(state.viewTarget,0,0,0,false)
    end
    -- A different valid pawn selected by the game is deliberately left possessed.
    return true
end
local function applyBoost(state,targetKmh)
    if not targetKmh or targetKmh<=0 or adapter.menuOpen then return end
    if not key(state.pc,"W") or not (key(state.pc,"LeftShift") or key(state.pc,"RightShift")) or key(state.pc,"SpaceBar") then return end
    if state.movement:GetCurrentGear()<0 then return end
    local mesh=state.actor.Mesh
    assert(Engine.valid(mesh),"Vehicle physics mesh is unavailable")
    local bone=FName("None",EFindName.FNAME_Find)
    local velocity=mesh:GetPhysicsLinearVelocity(bone)
    local facing=state.actor:K2_GetActorRotation()
    assert(vector(velocity) and rotation(facing),"Vehicle boost physics data is invalid")
    local yaw=math.rad(facing.Yaw%360)
    local x,y=math.cos(yaw),math.sin(yaw)
    local speed=velocity.X*x+velocity.Y*y
    if speed < -100 then return end
    local acceleration=math.min(1200,math.max(0,(targetKmh/0.036-speed)*2))
    if acceleration>0 then mesh:AddForce({X=x*acceleration,Y=y*acceleration,Z=0},bone,true) end
end
function Engine.boostControlled(targetKmh)
    if adapter.menuOpen then return end
    local ctx=Engine.player()
    if not ctx then return end
    local class=ctx.pawn:GetClass():GetFullName()
    if class~="BlueprintGeneratedClass /Game/Autok/Abel_Car.Abel_Car_C" and not class:find("/Game/Traffic_AI_System/Cars/",1,true) then return end
    local movement=ctx.pawn.VehicleMovement
    if Engine.valid(movement) then applyBoost({pc=ctx.controller,actor=ctx.pawn,movement=movement},targetKmh)end
end
function Engine.driveTick(state,targetKmh)
    assert(Engine.valid(state.pc) and Engine.valid(state.actor) and Engine.valid(state.movement),"The driving context changed")
    assert(id(state.movement)==state.movementId,"The vehicle movement component was replaced")
    assert(id(state.actor)==state.actorId and Engine.valid(state.pc.Pawn) and id(state.pc.Pawn)==state.actorId,"Vehicle control changed")
    if adapter.menuOpen then
        state.movement:SetThrottleInput(0);state.movement:SetSteeringInput(0)
        state.movement:SetBrakeInput(1);state.movement:SetHandbrakeInput(true);state.menuBraked=true
        return
    end
    if state.menuBraked then
        state.movement:SetBrakeInput(0);state.movement:SetHandbrakeInput(false);state.menuBraked=false
    end
    if adapter.gameplay():IsGamePaused(state.actor) then return end
    if state.native then applyBoost(state,targetKmh);return end -- Preserve normal input and camera.
    local facing=state.actor:K2_GetActorRotation()
    assert(rotation(facing),"Vehicle camera rotation is invalid")
    local w,s=key(state.pc,"W"),key(state.pc,"S")
    local brake=key(state.pc,"SpaceBar")
    if w~=s then
        local gear=state.movement:GetCurrentGear()
        if w and gear<=0 then state.movement:SetTargetGear(1,true) end
        if s and gear>=0 then state.movement:SetTargetGear(-1,true) end
    end
    state.movement:SetThrottleInput(w~=s and not brake and 1 or 0)
    state.movement:SetSteeringInput((key(state.pc,"D") and 1 or 0)-(key(state.pc,"A") and 1 or 0))
    state.movement:SetBrakeInput(brake and 1 or 0)
    state.movement:SetHandbrakeInput(brake)
    applyBoost(state,targetKmh)
    -- A fixed forward view also works on traffic pawns without camera input bindings.
    state.pc:SetControlRotation(facing)
    assert(Engine.valid(state.camera) and id(state.camera)==state.cameraId,"Driving camera changed")
    -- Camera follows its attachment every engine frame, not the 16 ms input pump.

end
function Engine.diagnose()
    local ctx=Engine.player()
    if not ctx then Engine.log("No controlled pawn for vehicle diagnostics.");return end
    local origin=ctx.pawn:K2_GetActorLocation()
    local items={}
    for _,actor in ipairs(FindAllOf("WheeledVehicle") or {}) do
        if Engine.valid(actor) then
            local p=actor:K2_GetActorLocation()
            local distance=(p.X-origin.X)^2+(p.Y-origin.Y)^2+(p.Z-origin.Z)^2
            if distance<3000*3000 then items[#items+1]={actor=actor,distance=distance} end
        end
    end
    table.sort(items,function(a,b)return a.distance<b.distance end)
    for index=1,math.min(3,#items) do
        local actor=items[index].actor
        Engine.log("NEARBY VEHICLE "..actor:GetFullName())
        local bodyOk,body=pcall(function()return actor.Mesh.SkeletalMesh end)
        if bodyOk and Engine.valid(body) then Engine.log("BODY "..body:GetFullName())end
        local class=actor:GetClass()
        for _=1,6 do
            if not Engine.valid(class) then break end
            local count=0
            class:ForEachFunction(function(fn)
                local name=fn:GetFName():ToString()
                if name:lower():find("repair") or name:lower():find("damage") or name:lower():find("enter") or name:lower():find("exit") or name:lower():find("radio") or name:lower():find("camera") or name:lower():find("input") then
                    Engine.log("FUNCTION "..fn:GetFullName().." (stable loader exposes no parameter enumeration)")
                end
            end)
            class:ForEachProperty(function(prop)
                local name=prop:GetFName():ToString()
                if count<50 then
                    local lower=name:lower()
                    if lower:find("health") or lower:find("damage") or lower:find("repair") or lower:find("driver") or lower:find("enter") or lower:find("radio") or lower:find("camera") or lower:find("player") then
                        count=count+1
                        local ok,value=pcall(function() return actor[name] end)
                        local kind=type(value)
                        Engine.log("PROPERTY "..name.."="..(ok and (kind=="number" or kind=="string" or kind=="boolean") and tostring(value) or "object/unavailable"))
                    end
                end
            end)
            class=class:GetSuperStruct()
        end
    end
end
return Engine
