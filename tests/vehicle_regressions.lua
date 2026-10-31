return function(check,case)
local Vehicles=require('vehicles')
case('vehicle spawning uses real catalog classes, rejects blocked spawns and cleans failures',function()
    local a={};local made,deleted,ctx=0,0,{}
    a.log=function()end;a.valid=function(v)return type(v)=='table' and v.alive end
    a.player=function()return ctx end;a.class=function(path)return path end
    a.spawnTransform=function(c)assert(c==ctx);return{}end
    a.begin=function(c,cl,t)made=made+1;return{alive=true,cls=cl}end
    a.prepare=function(v)v.ready=true end;a.finish=function(v,t)assert(v.ready);return v end
    a.destroy=function(v)deleted=deleted+1;v.alive=false end
    local v=Vehicles.new(a,{MaxVehicles=5})
    check(Vehicles.new(a).maximum==10,'default spawn cap raised to ten; old configurations need no edits')
    check(v.catalog[1].path=='/Game/Autok/Abel_Car.Abel_Car_C','default spawn is actual player car blueprint')
    check(v:spawn() and #v.spawned==1,'completed vehicle tracked')
    for i=1,4 do check(v:spawn(),'spawn within cap '..i)end
    check(not v:spawn() and made==5,'five-vehicle cap prevents new native spawn')
    v.spawned[1].alive=false;check(v:spawn(),'destroyed car releases cap slot')
    local other=Vehicles.new(a);a.class=function()return nil end
    check(not other:spawn() and made==6,'unloaded class never calls spawn')
    a.class=function(p)return p end;a.finish=function()return nil end
    check(not other:spawn() and deleted==1 and #other.spawned==0,'failed construction deletes only newly created car')
    a.begin=function()return nil end
    check(not other:spawn() and deleted==1,'blocked collision does not call destroy on nonexistent actor')
    local selected=v.selected;for i=1,#v.catalog do v:cycle() end
    check(v.selected==selected,'vehicle selection wraps through seven options')
end)
case('vehicle boost starts off, supports normal driving and returns to off cleanly',function()
    local calls,last=0,nil
    local api={log=function()end,boostControlled=function(speed)calls=calls+1;last=speed end}
    local v=Vehicles.new(api)
    check(v.boostSpeeds[v.boostIndex]==0 and not v:hasWork(),'vehicle boost is off by default')
    v:boost(1);v:tick();check(v:hasWork() and last==60 and calls==1,'selected boost also polls a normally entered game vehicle')
    for i=1,20 do v:boost(1)end
    v:tick();check(last==300,'boost selection stops at its highest supported target')
    for i=1,20 do v:boost(-1)end
    local before=calls;v:tick();check(not v:hasWork() and calls==before,'off stops the boost pump without altering driving')
    v:boost(1);api.boostControlled=function()error('mesh replaced')end;v:tick()
    check(v.boostIndex==1 and not v:hasWork(),'boost failure returns to off rather than writing into a changed vehicle')
end)
case('trainer driving validates entry, rolls back failure and restores on exit',function()
    local exited,ticked=0,0
    local a={log=function()end,player=function()return{}end,repairTarget=function()return{}end}
    a.captureDriver=function(c,t)return{target=t}end;a.enterDriver=function(s)s.entered=true end
    a.exitDriver=function(s)exited=exited+1;return true end;a.driveTick=function(s)ticked=ticked+1 end
    local v=Vehicles.new(a)
    check(v:drive() and v:hasWork(),'driver state stays active after entry')
    v:tick();check(ticked==1,'active driver updates native controls')
    check(v:drive() and not v:hasWork() and exited==1,'F5 exits and clears state')
    a.enterDriver=function()error('possession refused')end
    check(not v:drive() and exited==2 and not v:hasWork(),'partial entry failure restores prior state')
    a.enterDriver=function()end;v:drive();a.driveTick=function()error('vehicle destroyed')end
    v:tick();check(not v:hasWork() and exited==3,'lost vehicle restores original character')
    a.driveTick=function()error('lost control')end;a.exitDriver=function()return false end
    v:drive();v:tick();check(v.driver~=nil and not v:hasWork(),'failed cleanup stops automatic retries instead of spinning every frame')
    a.exitDriver=function()return true end;check(v:drive() and v.driver==nil,'F5 can retry paused driver cleanup')
    a.repairTarget=function()return nil end
    check(not v:repair(),'repair never touches an unowned distant vehicle')
end)
case('native vehicle adapter uses native spawn helper, health guard and reversible possession',function()
    local previousAdapter,previousEngine=package.loaded.adapter,package.loaded.vehicle_engine
    local previousSpawn=package.loaded.native_spawn
    local previousFind,previousStatic,previousName,previousEnum=FindAllOf,StaticFindObject,FName,EFindName
    local objects,vehicle,player,pc,context,statics={},nil,nil,nil,nil,{}
    local function fname(n)return{ToString=function()return n end}end
    local function object(name,address)
        local v={alive=true,name=name,address=address}
        function v:IsValid()return self.alive end
        function v:GetFullName()return self.name end
        function v:GetAddress()return self.address end
        return v
    end
    local repairCalls=0
    local function klass(path,parameters)
        local c=object('BlueprintGeneratedClass '..path,99)
        function c:ForEachFunction(cb)
            local f=object('Function RepairVehicle',100)
            function f:GetFName()return fname('RepairVehicle')end
            function f:ForEachProperty(cb2)
                for i=1,parameters do cb2({GetFName=function()return fname('Input'..i)end})end
            end
            cb(f)
        end
        function c:GetSuperStruct()return nil end
        return c
    end
    local class=klass('/Game/Autok/Abel_Car.Abel_Car_C',1)
    player=object('Abel_C /World.Player',1);player.bHidden=false;player.collision=true;player.tick=true
    function player:IsActorTickEnabled()return self.tick end
    function player:SetActorTickEnabled(v)self.tick=v end
    player.CharacterMovement=object('CharacterMovement',77)
    player.CharacterMovement.MovementMode=1;player.CharacterMovement.CustomMovementMode=0
    function player.CharacterMovement:StopMovementImmediately()end
    function player.CharacterMovement:SetMovementMode(mode,custom)self.MovementMode=mode;self.CustomMovementMode=custom end
    local playerPos={X=0,Y=0,Z=90}
    function player:GetClass()return {GetFullName=function()return 'BlueprintGeneratedClass /Game/Characters/Blueprints/Abel/Abel.Abel_C'end}end
    function player:GetActorEnableCollision()return self.collision end
    function player:SetActorEnableCollision(value)self.collision=value end
    function player:SetActorHiddenInGame(value)self.bHidden=value end
    function player:K2_GetActorLocation()return playerPos end
    function player:K2_SetActorLocation(pos,sweep,hit,teleport)assert(sweep and teleport and type(hit)=='table');playerPos=pos;return true end
    vehicle=object('Abel_Car_C /World.Car',2);vehicle.tick=true;vehicle.BaseEyeHeight=30
    vehicle.Health=20;vehicle.MaxHealth=100
    function vehicle:GetClass()return class end
    function vehicle:K2_GetActorLocation()return{X=500,Y=0,Z=0}end
    function vehicle:K2_GetActorRotation()return{Pitch=90,Yaw=90,Roll=30}end
    function vehicle:K2_SetActorRotation(rot,teleport)assert(rot.Pitch==0 and rot.Roll==0 and teleport);self.upright=true;return true end
    function vehicle:K2_SetActorLocation(pos,sweep,hit,teleport)assert(sweep and teleport);return true end
    function vehicle:IsActorTickEnabled()return self.tick end
    function vehicle:SetActorTickEnabled(value)self.tick=value end
    function vehicle:EnableInput(controller)assert(controller==pc);self.nativeInput=true end
    function vehicle:RepairVehicle()repairCalls=repairCalls+1 end
    local mesh=object('Mesh',3)
    function mesh:SetPhysicsLinearVelocity(vel,add,bone)assert(vel.X==0 and vel.Y==0 and vel.Z==0 and add==false and bone:ToString()=='None');self.stopped=true end
    function mesh:SetPhysicsAngularVelocityInDegrees(vel,add,bone)assert(vel.Z==0 and add==false and bone:ToString()=='None')end
    mesh.velocity={X=0,Y=0,Z=0};mesh.forceCalls=0
    function mesh:GetPhysicsLinearVelocity(bone)assert(bone:ToString()=='None');return self.velocity end
    function mesh:AddForce(force,bone,acceleration)
        assert(bone:ToString()=='None' and acceleration==true and force.Z==0)
        self.forceCalls=self.forceCalls+1;self.force=force
    end
    vehicle.Mesh=mesh
    local movement=object('Movement',4);movement.gear=0
    function movement:GetCurrentGear()return self.gear end
    function movement:SetTargetGear(gear,immediate)assert(immediate==true);self.gear=gear end
    function movement:SetThrottleInput(v)assert(v>=0 and v<=1);self.throttle=v end
    function movement:SetSteeringInput(v)assert(v>=-1 and v<=1);self.steer=v end
    function movement:SetBrakeInput(v)self.brake=v end
    function movement:SetHandbrakeInput(v)self.handbrake=v end
    vehicle.VehicleMovement=movement
    pc=object('Controller',5);pc.Pawn=player;pc.keys={}
    function pc:IsMoveInputIgnored()return false end
    function pc:IsLookInputIgnored()return false end
    function statics:IsGamePaused()return false end
    function pc:GetControlRotation()return{Yaw=self.badRotation and 0/0 or 90}end
    function pc:Possess(pawn)self.Pawn=pawn end
    function pc:SetControlRotation(rotation)assert(type(rotation.Yaw)=='number')end
    function pc:IsInputKeyDown(key)assert(key.KeyName);return self.keys[key.KeyName:ToString()] or false end
    context={controller=pc,pawn=player}
    local cameraClass=object('CameraClass',101)
    local camera=object('TrainerCamera',102)
    function camera:K2_DestroyActor()self.alive=false end
    function camera:K2_AttachToActor(parent,socket,locationRule,rotationRule,scaleRule,weld)
        assert(parent==vehicle and socket:ToString()=='None' and locationRule==0 and rotationRule==0 and scaleRule==0 and weld==false)
        self.attached=parent;return true
    end
    function camera:K2_SetActorRelativeLocationAndRotation(location,rot,sweep,hit,teleport)
        assert(location.X==-500 and location.Z==220 and rot.Pitch==-12 and rot.Yaw==0 and not sweep and teleport)
        self.updated=true
    end
    function camera:K2_SetActorLocationAndRotation(location,rot,sweep,hit,teleport)
        assert(type(location.X)=='number' and rot.Pitch==-12 and rot.Roll==0 and sweep==false and type(hit)=='table' and teleport==true)
        self.updated=true
    end
    pc.viewTarget=player
    function pc:GetViewTarget()return self.viewTarget end
    function pc:SetViewTargetWithBlend(target,time,blend,exp,lock)
        assert(time==0 and blend==0 and exp==0 and lock==false);self.viewTarget=target
    end
    package.loaded.native_spawn={actor=function(ctx,cl,transform,kind)
        if cl==cameraClass then assert(ctx.controller==pc and ctx.pawn==vehicle and kind=='CameraActor');camera.alive=true;camera.updated=false;return camera end
        assert(ctx.pawn==player and ctx.controller==pc and cl==class and kind=='WheeledVehicle')
        check(math.abs(transform.Translation.Y-700)<0.001 and transform.Scale3D.X==1,'spawn placement is forward from player with unit scale')
        check(math.abs(transform.Rotation.Z^2+transform.Rotation.W^2-1)<0.001,'spawn rotation is normalized')
        return vehicle
    end}
    package.loaded.adapter={log=function()end,playerContext=function()return context end,gameplay=function()return statics end}
    package.loaded.vehicle_engine=nil
    FindAllOf=function(name)assert(name=='WheeledVehicle');return objects end
    StaticFindObject=function(path)if path=='/Script/Engine.CameraActor' then return cameraClass end;return path=='/Game/Autok/Abel_Car.Abel_Car_C' and class or nil end
    FName=function(name,mode)assert(mode==0);return fname(name)end;EFindName={FNAME_Find=0}
    local ok,err=pcall(function()
        local e=require('vehicle_engine');objects={vehicle}
        check(e.repairTarget(context,{})==vehicle,'map player car can be recovered without trainer ownership')
        class=klass('/Game/Unknown.Traffic_C',1)
        check(e.repairTarget(context,{})==nil,'unrelated traffic car is not repaired')
        check(e.repairTarget(context,{vehicle})==vehicle,'trainer ownership permits repair')
        class=klass('/Game/Autok/Abel_Car.Abel_Car_C',1)
        pc.badRotation=true;check(not pcall(e.spawnTransform,context),'invalid player rotation never reaches a native spawn')
        pc.badRotation=false
        local transform=e.spawnTransform(context);check(e.begin(context,class,transform)==vehicle,'native helper returns spawned actor')
        e.prepare(vehicle);check(vehicle.AutoPossessAI==0 and vehicle.AutoPossessPlayer==0,'spawn neither creates route-less traffic AI nor steals player possession')
        check(e.finish(vehicle,transform)==vehicle,'construction finishes exactly that actor')
        class=klass('/Game/Traffic_AI_System/Cars/Hatch/BP_Hatch.BP_Hatch_C',1);vehicle.tick=true
        check(e.finish(vehicle,transform)==vehicle and not vehicle.tick,'route-less traffic Blueprint tick stays parked after spawning')
        class=klass('/Game/Autok/Abel_Car.Abel_Car_C',1);vehicle.tick=true
        local result=e.repair(vehicle)
        check(vehicle.Health==100 and vehicle.upright and mesh.stopped,'repair restores exposed health, orientation and velocity')
        check(repairCalls==0,'parameterized repair event never called with invented arguments')
        class=klass('/Game/Autok/Abel_Car.Abel_Car_C',0);e.repair(vehicle)
        check(repairCalls==1,'verified zero-argument repair event is called once')
        vehicle.Health=nil;vehicle.MaxHealth=nil;class=klass('/Game/Autok/Abel_Car.Abel_Car_C',1)
        check(e.repair(vehicle):find('damage was not changed',1,true)~=nil,'missing health repair is reported rather than claimed')
        -- Traffic uses the fallback path; Abel's own car is tested separately.
        class=klass('/Game/Traffic_AI_System/Cars/Hatch/BP_Hatch.BP_Hatch_C',1)
        local state=e.captureDriver(context,vehicle);e.enterDriver(state)
        check(pc.Pawn==vehicle and player.bHidden and not player.collision,'entry possesses vehicle and hides original character')
        check(not vehicle.tick and vehicle.BaseEyeHeight==120,'traffic steering suspended while driving')
        check(pc.viewTarget==camera and camera.alive,'dedicated CameraActor bypasses character-only camera logic')
        check(player.CharacterMovement.MovementMode==0 and not player.tick,'hidden original character cannot fall through the world while driving')
        pc.keys.W=true;pc.keys.D=true;e.driveTick(state)
        check(movement.gear==1 and movement.throttle==1 and movement.steer==1,'forward and steering inputs reach native movement')
        check(camera.updated and camera.attached==vehicle,'fallback camera is attached to the car rather than teleported by an asynchronous timer')
        pc.keys.W=false;pc.keys.S=true;e.driveTick(state)
        check(movement.gear==-1 and movement.throttle==1,'reverse selects a reverse gear')
        pc.keys.SpaceBar=true;e.driveTick(state)
        check(movement.throttle==0 and movement.brake==1 and movement.handbrake,'brake suppresses throttle')
        e.exitDriver(state)
        check(pc.Pawn==player and not player.bHidden and player.collision,'exit restores original character possession and visibility')
        check(pc.viewTarget==player and not camera.alive,'exit restores view target and destroys only the trainer camera')
        check(vehicle.tick and vehicle.BaseEyeHeight==30,'exit restores original actor ticking and eye height')
        check(player.tick and player.CharacterMovement.MovementMode==1,'exit restores original character tick and movement mode')
        check(movement.throttle==0 and movement.handbrake,'unoccupied car is left parked')
        pc.Pawn=vehicle;context.pawn=vehicle
        check(not pcall(e.captureDriver,context,vehicle),'nested driving cannot capture the vehicle as original character')
        context.pawn=player;pc.Pawn=player
        local possess=pc.Possess
        local before=playerPos
        local failed=e.captureDriver(context,vehicle)
        pc.Possess=function()end
        check(not pcall(e.enterDriver,failed),'native possession refusal is detected before hiding the player')
        check(e.exitDriver(failed) and playerPos==before and pc.Pawn==player,'entry rollback never teleports an unentered character')
        pc.Possess=possess
        local retry=e.captureDriver(context,vehicle);e.enterDriver(retry)
        pc.Possess=function()end
        check(e.exitDriver(retry)==false and player.bHidden and player.CharacterMovement.MovementMode==0 and not vehicle.tick,'refused exit retains frozen hidden pawn and manual car control')
        pc.Possess=possess;check(e.exitDriver(retry) and pc.Pawn==player,'later exit retry restores control')
        local transition=e.captureDriver(context,vehicle);e.enterDriver(transition)
        local foreign=object('GameChosenPawn',70);pc.Pawn=foreign
        check(e.exitDriver(transition) and pc.Pawn==foreign,'game-selected new pawn is never overridden during cleanup')
        pc.Pawn=player
        class=klass('/Game/Autok/Abel_Car.Abel_Car_C',1);vehicle.tick=true;pc.viewTarget=player
        local native=e.captureDriver(context,vehicle);e.enterDriver(native)
        check(native.native and vehicle.nativeInput and vehicle.tick and pc.viewTarget==vehicle and not native.camera,'Abel car preserves Blueprint ticking, input and native camera without a fallback camera')
        check(movement.brake==0 and movement.handbrake==false,'native entry releases the parking brake left by the previous exit')
        local throttle,steer=movement.throttle,movement.steer
        pc.keys.W=true;pc.keys.S=false;pc.keys.D=true;e.driveTick(native)
        check(movement.throttle==throttle and movement.steer==steer,'native car input is never overwritten by manual trainer steering/throttle')
        package.loaded.adapter.menuOpen=true;e.driveTick(native)
        check(movement.handbrake and movement.brake==1,'open menu safely brakes the native car')
        package.loaded.adapter.menuOpen=false;e.driveTick(native)
        check(not movement.handbrake and movement.brake==0,'closing the menu releases its native-car parking brake')
        pc.keys.LeftShift=true;pc.keys.W=true;pc.keys.SpaceBar=false;movement.gear=1
        e.driveTick(native,150)
        check(mesh.forceCalls==1 and mesh.force.Y>0 and math.abs(mesh.force.X)<.001,'Shift and W apply bounded forward physical acceleration without changing steering or vertical velocity')
        pc.keys.LeftShift=false;e.driveTick(native,150);check(mesh.forceCalls==1,'releasing Shift immediately stops boost force')
        pc.keys.LeftShift=true;mesh.velocity={X=0,Y=5000,Z=0};e.driveTick(native,150)
        check(mesh.forceCalls==1,'boost adds no force once the selected target speed is exceeded')
        mesh.velocity={X=0,Y=0,Z=0};pc.keys.SpaceBar=true;e.driveTick(native,150)
        check(mesh.forceCalls==1,'braking suppresses boost')
        pc.keys.SpaceBar=false;context.pawn=player;e.boostControlled(150)
        check(mesh.forceCalls==1,'boost ignores the walking pawn without probing car-only properties')
        context.pawn=vehicle;e.boostControlled(150);check(mesh.forceCalls==2,'boost works in a normally possessed native vehicle too')
        context.pawn=player;pc.keys.LeftShift=false
        check(e.exitDriver(native) and pc.Pawn==player and pc.viewTarget==player,'native exit restores the original character and view')
        class=klass('/Game/Traffic_AI_System/Cars/Hatch/BP_Hatch.BP_Hatch_C',1)
        local destroyed=e.captureDriver(context,vehicle);e.enterDriver(destroyed);vehicle.alive=false;pc.Pawn=nil
        check(e.exitDriver(destroyed) and pc.Pawn==player,'destroyed car with no pawn recovers original character')

    end)
    package.loaded.adapter,package.loaded.vehicle_engine=previousAdapter,previousEngine
    package.loaded.native_spawn=previousSpawn
    FindAllOf,StaticFindObject,FName,EFindName=previousFind,previousStatic,previousName,previousEnum
    if not ok then error(err)end
end)
end
