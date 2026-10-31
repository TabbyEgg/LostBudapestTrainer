return function(check,case)
local Profile=require('player_vehicle')
local function fixture()
    local f={ids=100,actors={},summons=0,logs={}}
    local function object(name)
        f.ids=f.ids+1
        local value={alive=true,name=name,address=f.ids}
        function value:IsValid()return self.alive end
        function value:GetFullName()return self.name end
        function value:GetAddress()return self.address end
        return value
    end
    local function fname(name)return{ToString=function()return name end}end
    local function material(name,dynamic,parent)
        local v=object(name);v.Parent=parent
        function v:GetClass()return{GetFullName=function()return 'Class /Script/Engine.MaterialInstance'..(dynamic and 'Dynamic' or 'Constant')end}end
        return v
    end
    local function body(name,bonePrefix)
        local b=object(name);b.bones={}
        for i=1,4 do b.bones[bonePrefix..i]=i end
        return b
    end
    local function mesh(name,bodyAsset,animation,physics,materials)
        local v=object(name)
        local data={SkeletalMesh=bodyAsset,AnimClass=animation,PhysicsAssetOverride=physics,AnimationMode=0,
            RelativeScale3D={X=1,Y=1,Z=1},materials=materials or {}}
        setmetatable(v,{__index=data,__newindex=function(self,key,value)
            if key==self.failField then rawset(self,'failField',nil);error('injected template write failure')end
            data[key]=value
        end})
        function v:GetAnimInstance()return self.instance end
        function v:GetBoneIndex(bone)return self.SkeletalMesh and self.SkeletalMesh.bones[bone:ToString()] or -1 end
        function v:GetNumMaterials()return self.materialCount or #self.materials end
        function v:GetMaterial(index)return self.materials[index+1]end
        function v:SetMaterial(index,mat)self.materials[index+1]=mat end
        return v
    end
    local function wheelArray(prefix,count,wheelClass)
        local entries={}
        for i=1,count do entries[i]={WheelClass=wheelClass,BoneName=fname(prefix..i),AdditionalOffset={X=i,Y=i+1,Z=i+2},bDisableSteering=false}end
        return setmetatable({GetArrayNum=function()return #entries end},{__index=function(_,i)return entries[i]end,
            __newindex=function()error('wheel arrays must never be resized/reassigned')end}),entries
    end
    f.nativeBody=body('SkeletalMesh /Game/Abel.Body','AbelWheel')
    f.selectedBody=body('SkeletalMesh /Game/Hatch.Body','HatchWheel')
    f.nativeAnimation=object('AnimBlueprintGeneratedClass /Game/Abel.Anim_C')
    f.selectedAnimation=object('AnimBlueprintGeneratedClass /Game/Hatch.Anim_C')
    f.nativePhysics=object('PhysicsAsset /Game/Abel.Physics')
    f.selectedPhysics=object('PhysicsAsset /Game/Hatch.Physics')
    f.nativeWheel=object('Class /Game/Abel.Wheel_C');f.selectedWheel=object('Class /Game/Hatch.Wheel_C')
    f.nativeMaterial=material('MaterialInstanceConstant /Game/Abel.Paint')
    f.selectedMaterial=material('MaterialInstanceConstant /Game/Hatch.Paint')
    f.source=object('SourceDefaults');f.player=object('PlayerDefaults')
    f.source.Mesh=mesh('SourceMesh',f.selectedBody,f.selectedAnimation,f.selectedPhysics,{f.selectedMaterial})
    f.player.Mesh=mesh('PlayerMesh',f.nativeBody,f.nativeAnimation,f.nativePhysics,{f.nativeMaterial,f.nativeMaterial})
    local sourceArray;sourceArray,f.sourceWheels=wheelArray('HatchWheel',4,f.selectedWheel)
    local playerArray;playerArray,f.playerWheels=wheelArray('AbelWheel',4,f.nativeWheel)
    for i,w in ipairs(f.sourceWheels)do w.AdditionalOffset={X=40+i,Y=41+i,Z=42+i};w.bDisableSteering=i>2 end
    f.source.VehicleMovement=object('SourceMovement');f.source.VehicleMovement.WheelSetups=sourceArray
    f.player.VehicleMovement=object('NativeMovement');f.player.VehicleMovement.WheelSetups=playerArray
    f.player.AutoPossessAI=2;f.player.AutoPossessPlayer=1;f.player.SpawnCollisionHandlingMethod=0
    f.sourceClass=object('BlueprintGeneratedClass /Game/Traffic_AI_System/Cars/Hatch/BP_Hatch.BP_Hatch_C')
    function f.sourceClass:GetCDO()return f.source end
    f.playerClass=object('BlueprintGeneratedClass /Game/Autok/Abel_Car.Abel_Car_C')
    function f.playerClass:GetCDO()return f.player end
    f.pawn=object('WalkingPlayer');f.pawn.collision=true
    function f.pawn:GetActorEnableCollision()return self.collision end
    function f.pawn:SetActorEnableCollision(v)self.collision=v end
    f.pc=object('LocalController');f.pc.Pawn=f.pawn
    f.originalCheats=object('OriginalCheats');f.pc.CheatManager=f.originalCheats
    f.cheatClass=object('Class /Script/Engine.CheatManager');f.cheats=object('SpawnHelper')
    function f.clone()
        local a=object('NewPlayerCar');a.Mesh=mesh('NewPlayerMesh',f.player.Mesh.SkeletalMesh,f.player.Mesh.AnimClass,
            f.player.Mesh.PhysicsAssetOverride,{f.nativeMaterial,f.nativeMaterial})
        a.Mesh.AnimationMode=f.player.Mesh.AnimationMode
        a.VehicleMovement=object('NewPlayerMovement')
        local entries={}
        for i=1,4 do
            local w=f.playerWheels[i]
            entries[i]={WheelClass=w.WheelClass,BoneName=w.BoneName,AdditionalOffset={X=w.AdditionalOffset.X,Y=w.AdditionalOffset.Y,Z=w.AdditionalOffset.Z},bDisableSteering=w.bDisableSteering}
        end
        a.VehicleMovement.WheelSetups=setmetatable({GetArrayNum=function()return #entries end},{__index=entries})
        function a:GetClass()return f.playerClass end
        function a:K2_SetActorRotation()end;function a:SetActorScale3D()end
        function a:K2_SetActorLocation(v)self.position=v;return true end
        function a:K2_GetActorLocation()return self.position end
        function a:K2_DestroyActor()self.alive=false end
        return a
    end
    function f.cheats:Summon(path)
        assert(path=='/Game/Autok/Abel_Car.Abel_Car_C')
        f.summons=f.summons+1
        f.profileSeenBeforeConstruction=f.player.Mesh.SkeletalMesh==f.selectedBody and f.playerWheels[1].BoneName:ToString()=='HatchWheel1'
        if f.failSummon then error('engine spawn failed')end
        local a=f.clone()
        if f.overwriteBody then a.Mesh.SkeletalMesh=f.nativeBody end
        if f.overwriteAnimationInstance then a.Mesh.instance={IsValid=function()return true end,GetClass=function()return f.nativeAnimation end}end
        if f.overwriteRuntimeWheels then
            a.VehicleMovement.Wheels={GetArrayNum=function()return 4 end}
            for i=1,4 do a.VehicleMovement.Wheels[i]={IsValid=function()return true end,GetClass=function()return f.nativeWheel end}end
        end
        if f.overwritePhysics then a.Mesh.PhysicsAssetOverride=f.nativePhysics end
        if f.overwriteWheels then a.VehicleMovement.WheelSetups[1].BoneName=fname('AbelWheel1')end
        f.actors[#f.actors+1]=a;f.created=a
    end
    f.oldFind,f.oldStatic,f.oldConstruct=FindAllOf,StaticFindObject,StaticConstructObject
    FindAllOf=function(kind)assert(kind=='WheeledVehicle');return f.actors end
    StaticFindObject=function(path)assert(path=='/Script/Engine.CheatManager');return f.cheatClass end
    StaticConstructObject=function(class,outer)assert(class==f.cheatClass and outer==f.pc);return f.cheats end
    function f.spawn(profile)
        return require('native_spawn').actor({controller=f.pc,pawn=f.pawn},f.playerClass,
            {Translation={X=700,Y=0,Z=100},Rotation={Z=0,W=1}},'WheeledVehicle',profile)
    end
    function f.finish()FindAllOf,StaticFindObject,StaticConstructObject=f.oldFind,f.oldStatic,f.oldConstruct end
    function f.defaultsRestored()
        return f.player.Mesh.SkeletalMesh==f.nativeBody and f.player.Mesh.AnimClass==f.nativeAnimation and f.player.Mesh.PhysicsAssetOverride==f.nativePhysics
            and f.playerWheels[1].BoneName:ToString()=='AbelWheel1' and f.playerWheels[1].WheelClass==f.nativeWheel and f.playerWheels[1].AdditionalOffset.X==1 and f.playerWheels[3].bDisableSteering==false
    end
    return f
end
local function runFixture(fn)
    local f=fixture();local ok,err=pcall(fn,f);f.finish();if not ok then error(err)end
end
case('selected bodies are constructed on Abel player Blueprint with matching animation and wheel rig',function()
    runFixture(function(f)
        local profile=Profile.new(f.sourceClass,f.playerClass)
        check(f.defaultsRestored(),'planning is read-only')
        local actor=f.spawn(profile)
        check(f.profileSeenBeforeConstruction,'body and wheel setup installed before actor/physics creation')
        check(actor:GetClass()==f.playerClass and actor.Mesh.SkeletalMesh==f.selectedBody,'selected visual model uses native Abel logic rather than the traffic class')
        check(actor.Mesh.AnimClass==f.selectedAnimation and actor.Mesh.PhysicsAssetOverride==f.selectedPhysics,'source animation and physics stay matched to its body')
        local w=actor.VehicleMovement.WheelSetups[1]
        check(w.WheelClass==f.selectedWheel and w.BoneName:ToString()=='HatchWheel1' and w.AdditionalOffset.Y==42,'native car has the selected body wheel classes, bones and offsets')
        check(actor.VehicleMovement.WheelSetups[3].bDisableSteering==true,'per-wheel steering disable flags follow the selected rig')
        check(f.defaultsRestored(),'all Abel defaults restored immediately after a successful spawn')
        check(actor.Mesh.SkeletalMesh==f.selectedBody and w.BoneName:ToString()=='HatchWheel1','restoring the template does not change the spawned instance')
        check(actor.Mesh:GetMaterial(0)==f.selectedMaterial and actor.Mesh:GetMaterial(1)==nil,'selected materials replace and clear the stock body overrides')
        check(f.source.Mesh.SkeletalMesh==f.selectedBody and f.sourceWheels[1].BoneName:ToString()=='HatchWheel1','source traffic defaults are never modified')
        check(f.pc.CheatManager==f.originalCheats and f.pawn.collision and f.player.AutoPossessPlayer==1,'existing spawn cleanup still restores controller, collision and auto possession')
    end)
end)
case('incompatible source rigs are refused before template edits or native spawning',function()
    runFixture(function(f)
        f.sourceWheels[2].BoneName={ToString=function()return 'MissingWheel'end}
        check(not pcall(Profile.new,f.sourceClass,f.playerClass),'missing source wheel bone refuses conversion')
        check(f.defaultsRestored() and f.summons==0,'incompatible planning leaves defaults and game state unchanged')
    end)
    runFixture(function(f)
        f.source.Mesh.AnimationMode=1
        check(not pcall(Profile.new,f.sourceClass,f.playerClass),'unsupported animation mode never reuses the stock incompatible animation')
        check(f.defaultsRestored(),'animation refusal preserves the player defaults')
    end)
    runFixture(function(f)
        f.source.Mesh.RelativeScale3D={X=2,Y=2,Z=2}
        check(not pcall(Profile.new,f.sourceClass,f.playerClass),'unsupported body scale is rejected rather than stretching stock wheels')
    end)
    runFixture(function(f)
        f.player.VehicleMovement.WheelSetups.GetArrayNum=function()return 3 end
        check(not pcall(Profile.new,f.sourceClass,f.playerClass),'different wheel counts never resize native arrays')
    end)
end)
case('partial template changes and failed construction always restore the native setup',function()
    runFixture(function(f)
        local profile=Profile.new(f.sourceClass,f.playerClass);rawset(f.player.Mesh,'failField','AnimClass')
        check(not pcall(f.spawn,profile),'a partial template write failure cancels spawning')
        check(f.defaultsRestored() and f.summons==0,'partially modified body restored before any actor exists')
        check(f.pc.CheatManager==f.originalCheats and f.pawn.collision,'partial profile failure still restores the outer spawn state')
    end)
    runFixture(function(f)
        f.failSummon=true
        check(not pcall(f.spawn,Profile.new(f.sourceClass,f.playerClass)),'engine construction failure reaches cleanup')
        check(f.defaultsRestored() and f.pc.CheatManager==f.originalCheats and f.pawn.collision,'engine failure restores every temporary template and controller field')
    end)
    runFixture(function(f)
        f.overwriteBody=true
        check(not pcall(f.spawn,Profile.new(f.sourceClass,f.playerClass)) and not f.created.alive,'construction that replaces the selected body is rejected and its new actor removed')
        check(f.defaultsRestored(),'body validation failure also restores the original native setup')
    end)
    runFixture(function(f)
        f.overwriteAnimationInstance=true
        check(not pcall(f.spawn,Profile.new(f.sourceClass,f.playerClass)) and not f.created.alive,'a stale stock animation instance is rejected even if the class property looks correct')
        check(f.defaultsRestored(),'animation instance rejection restores the template')
    end)
    runFixture(function(f)
        f.overwriteRuntimeWheels=true
        check(not pcall(f.spawn,Profile.new(f.sourceClass,f.playerClass)) and not f.created.alive,'instantiated physics wheels must match the selected wheel classes')
        check(f.defaultsRestored(),'runtime physics wheel rejection restores native defaults')
    end)
    runFixture(function(f)
        f.overwritePhysics=true
        check(not pcall(f.spawn,Profile.new(f.sourceClass,f.playerClass)) and not f.created.alive,'construction that restores stock physics under a different body is rejected')
        check(f.defaultsRestored(),'physics validation failure restores the player template')
    end)
    runFixture(function(f)
        f.overwriteWheels=true
        check(not pcall(f.spawn,Profile.new(f.sourceClass,f.playerClass)) and not f.created.alive,'construction that changes wheel bones is rejected instead of shipping a mismatched rig')
        check(f.defaultsRestored(),'wheel validation failure restores original wheel data')
    end)
end)
case('runtime source rigs can supply construction-only assets without sharing mutable paint',function()
    runFixture(function(f)
        local live=f.clone();live.Mesh.SkeletalMesh=f.selectedBody;live.Mesh.AnimClass=f.selectedAnimation;live.Mesh.PhysicsAssetOverride=f.selectedPhysics
        live.VehicleMovement.WheelSetups=f.source.VehicleMovement.WheelSetups
        function live:GetClass()return f.sourceClass end
        local dynamic={Parent=f.selectedMaterial,IsValid=function()return true end,GetClass=function()return{GetFullName=function()return 'Class /Script/Engine.MaterialInstanceDynamic'end}end}
        dynamic.Parent={Parent=f.selectedMaterial,IsValid=function()return true end,GetFullName=function()return'InnerTrafficPaint'end,GetClass=dynamic.GetClass}
        function dynamic:GetFullName()return'OuterTrafficPaint'end
        live.Mesh.materials={dynamic};f.actors={live};f.source.Mesh.AnimClass=nil
        local profile=Profile.new(f.sourceClass,f.playerClass)
        check(profile.body==f.selectedBody and profile.animation==f.selectedAnimation,'matching live source supplies assets assigned only by construction')
        local actor=f.spawn(profile)
        check(actor.Mesh:GetMaterial(0)==f.selectedMaterial and live.Mesh:GetMaterial(0)==dynamic,'new player car gets immutable paint parent without changing the traffic instance')
        check(f.defaultsRestored() and live.alive,'live-source conversion keeps existing traffic and native defaults intact')
    end)
end)
case('vehicle model routing chooses the native player template and preserves explicit legacy mode',function()
    local names={'adapter','vehicle_engine','native_spawn','player_vehicle'}
    local old={};for _,name in ipairs(names)do old[name]=package.loaded[name]end
    local oldFind=StaticFindObject
    local config=require('config');local previous=config.PlayerVehicleSetup
    local function class(name)return{IsValid=function()return true end,GetFullName=function()return name end}end
    local source=class('BlueprintGeneratedClass /Game/Traffic_AI_System/Cars/Hatch/BP_Hatch.BP_Hatch_C')
    local native=class('BlueprintGeneratedClass /Game/Autok/Abel_Car.Abel_Car_C')
    local profile={};local recorded
    package.loaded.adapter={log=function()end}
    package.loaded.player_vehicle={new=function(selected,player)assert(selected==source and player==native);return profile end}
    package.loaded.native_spawn={actor=function(ctx,cl,transform,kind,plan)recorded={class=cl,plan=plan};return recorded end}
    package.loaded.vehicle_engine=nil
    StaticFindObject=function(path)assert(path=='/Game/Autok/Abel_Car.Abel_Car_C');return native end
    local ok,err=pcall(function()
        local engine=require('vehicle_engine')
        config.PlayerVehicleSetup=nil;engine.begin({},source,{})
        check(recorded.class==native and recorded.plan==profile,'older configs default to native player logic for other models')
        config.PlayerVehicleSetup=false;engine.begin({},source,{})
        check(recorded.class==source and recorded.plan==nil,'explicit legacy setting retains the original traffic fallback')
        config.PlayerVehicleSetup=true;engine.begin({},native,{})
        check(recorded.class==native and recorded.plan==nil,'original Abel car stays unchanged without applying a model profile')
        StaticFindObject=function()return nil end
        check(not pcall(engine.begin,{},source,{}),'missing native player class cancels model spawning instead of silently substituting AI logic')
    end)
    StaticFindObject=oldFind;config.PlayerVehicleSetup=previous
    for _,name in ipairs(names)do package.loaded[name]=old[name]end
    if not ok then error(err)end
end)

end
