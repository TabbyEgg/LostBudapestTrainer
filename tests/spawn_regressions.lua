return function(check,case)
case('stable-loader native spawn avoids FTransform marshaling and restores all temporary state',function()
    local oldFind,oldStatic,oldConstruct=FindAllOf,StaticFindObject,StaticConstructObject
    local oldSpawn=package.loaded.native_spawn;package.loaded.native_spawn=nil
    local function object(name,address)
        local o={name=name,address=address,alive=true}
        function o:IsValid()return self.alive end;function o:GetFullName()return self.name end;function o:GetAddress()return self.address end
        return o
    end
    local cdo=object('CDO',10);cdo.AutoPossessAI=2;cdo.AutoPossessPlayer=1;cdo.SpawnCollisionHandlingMethod=0
    local class=object('BlueprintGeneratedClass /Game/Autok/Abel_Car.Abel_Car_C',11);function class:GetCDO()return cdo end
    local pawn=object('WalkingPawn',12);pawn.collision=true
    function pawn:GetActorEnableCollision()return self.collision end;function pawn:SetActorEnableCollision(v)self.collision=v end
    local previousCheats=object('GameCheatManager',13);local pc=object('PC',14);pc.CheatManager=previousCheats;pc.Pawn=pawn
    local cheatClass=object('Class /Script/Engine.CheatManager',15)
    local actors,created,fail,wrongClass={},nil,false,false
    local helper=object('TemporaryCheatManager',16)
    function helper:Summon(path)
        assert(path=='/Game/Autok/Abel_Car.Abel_Car_C' and pc.CheatManager==self)
        assert(cdo.AutoPossessAI==0 and cdo.AutoPossessPlayer==0 and cdo.SpawnCollisionHandlingMethod==3 and not pawn.collision)
        if fail then error('spawn rejected')end
        -- Keep earlier successful cars outside this fixture's placement lane;
        -- the separate footprint cases below exercise occupied destinations.
        for i,old in ipairs(actors)do old.position={X=-5000-i*1000,Y=0,Z=0}end
        created=object('Car '..tostring(#actors),20+#actors)
        function created:GetClass()return class end
        function created:K2_SetActorRotation(rot,teleport)assert(rot.Roll==0 and rot.Pitch==0 and teleport)end
        function created:SetActorScale3D(scale)assert(scale.X==1 and scale.Y==1 and scale.Z==1)end
        function created:K2_SetActorLocation(location,sweep,hit,teleport)assert(location.X==700 and sweep and teleport and type(hit)=='table');self.placed=true;self.position=location;return true end
        function created:K2_GetActorLocation()return self.position or {X=0,Y=0,Z=0}end
        function created:K2_DestroyActor()self.alive=false end
        actors[#actors+1]=created
    end
    FindAllOf=function(kind)assert(kind=='WheeledVehicle');return actors end
    StaticFindObject=function(path)assert(path=='/Script/Engine.CheatManager');return cheatClass end
    StaticConstructObject=function(cl,outer)assert(cl==cheatClass and outer==pc);return helper end
    local ok,err=pcall(function()
        local spawn=require('native_spawn')
        local ctx={controller=pc,pawn=pawn};local transform={Translation={X=700,Y=0,Z=90},Rotation={Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
        local actor=spawn.actor(ctx,class,transform,'WheeledVehicle')
        check(actor==created and actor.placed,'native Summon discovers only its new car and places it through flat reflected arguments')
        check(pc.CheatManager==previousCheats and pawn.collision and pc.Pawn==pawn,'successful spawn retains original cheat manager, pawn collision and possession')
        check(cdo.AutoPossessAI==2 and cdo.AutoPossessPlayer==1 and cdo.SpawnCollisionHandlingMethod==0,'all shared class defaults restored after successful spawn')
        local first=created;spawn.actor(ctx,class,transform,'WheeledVehicle')
        check(created~=first and first.alive,'a later spawn never mistakes an existing car for its result')
        local summon=helper.Summon
        helper.Summon=function(self,path)
            summon(self,path)
            created.K2_SetActorLocation=function(self,location)
                self.position=location.X==700 and {X=50,Y=0,Z=0} or location
                return location.X~=700
            end
        end
        local spread={Translation=transform.Translation,Rotation=transform.Rotation,Candidates={{X=700,Y=0,Z=90},{X=1100,Y=0,Z=90}}}
        local recovered=spawn.actor(ctx,class,spread,'WheeledVehicle')
        check(recovered.position.X==1100,'blocked initial placement tries a clear alternative instead of counting a car stuck near the player')
        helper.Summon=function(self,path)
            summon(self,path)
            created.K2_SetActorLocation=function()error('vehicle placement must not sweep through the path from the player')end
            created.K2_TeleportTo=function(self,location,rotation)
                assert(rotation.Pitch==0 and rotation.Roll==0 and rotation.Yaw==0)
                if location.X==700 then return false end
                self.position={X=location.X-140,Y=180,Z=location.Z+70};return true
            end
        end
        local adjusted=spawn.actor(ctx,class,spread,'WheeledVehicle')
        check(adjusted.position.X==960 and adjusted.position.Y==180,'collision-checked teleport accepts the engine adjusting the destination beyond the former 30cm tolerance')
        helper.Summon=function(self,path)
            summon(self,path)
            created.K2_TeleportTo=function(self,location)self.position=location;return true end
        end
        local separated=spawn.actor(ctx,class,{Translation=spread.Translation,Rotation=spread.Rotation,Candidates=spread.Candidates,Origin={X=500,Y=0,Z=90}},'WheeledVehicle')
        check(separated.position.X==1100,'adjusted placement remains at least three metres from the player')
        helper.Summon=function(self,path)
            summon(self,path)
            created.K2_TeleportTo=function(self,location)self.position=location;return false end
        end
        check(not pcall(spawn.actor,ctx,class,spread,'WheeledVehicle') and not created.alive,'a refused destination is never accepted merely because the actor position looks close')
        helper.Summon=function(self,path)summon(self,path);created.K2_SetActorLocation=function(self)self.position={X=0,Y=0,Z=0};return false end end
        check(not pcall(spawn.actor,ctx,class,spread,'WheeledVehicle') and not created.alive,'all blocked placements remove the failed spawn and never consume a visible-car slot')
        helper.Summon=summon
        fail=true;check(not pcall(spawn.actor,ctx,class,transform,'WheeledVehicle'),'native engine spawn failure is reported')
        check(pc.CheatManager==previousCheats and pawn.collision and cdo.AutoPossessAI==2 and cdo.AutoPossessPlayer==1 and cdo.SpawnCollisionHandlingMethod==0,'engine exception restores the exact original manager, collision and class defaults')
        fail=false;local move=helper.Summon
        helper.Summon=function()error(function()end)end
        local succeeded,message=pcall(spawn.actor,ctx,class,transform,'WheeledVehicle')
        check(not succeeded and type(message)=='string' and message:find('Spawn step native actor construction',1,true) and message:find('stack traceback',1,true),'opaque native function errors identify the failing construction step')
        check(pc.CheatManager==previousCheats and pawn.collision,'opaque native errors still release every temporary player change')
        helper.Summon=move
        local restoredProfile=false
        local badProfile={apply=function()error(function()end)end,restore=function()restoredProfile=true end}
        succeeded,message=pcall(spawn.actor,ctx,class,transform,'WheeledVehicle',badProfile)
        check(not succeeded and message:find('Spawn step apply selected body/wheel template',1,true) and restoredProfile,'opaque model-template failures retain their exact step and restore partial edits')
        badProfile.apply=function()end;badProfile.validate=function()error(function()end)end;restoredProfile=false
        succeeded,message=pcall(spawn.actor,ctx,class,transform,'WheeledVehicle',badProfile)
        check(not succeeded and message:find('Spawn step validate selected body/wheel template',1,true) and restoredProfile and not created.alive,'model validation failures identify their step and delete only the rejected new car')

        helper.Summon=function(self,path)move(self,path);created.K2_SetActorLocation=function()error('placement refused')end end
        check(not pcall(spawn.actor,ctx,class,transform,'WheeledVehicle') and not created.alive and first.alive,'placement exception destroys only the newly created actor')
        check(pc.CheatManager==previousCheats and pawn.collision,'placement failure still restores temporary state')
        local unknown=object('BlueprintGeneratedClass /Game/Unknown.Unknown_C',30)
        check(not pcall(spawn.actor,ctx,unknown,transform,'WheeledVehicle'),'unknown class is rejected before any native spawn')
    end)
    FindAllOf,StaticFindObject,StaticConstructObject=oldFind,oldStatic,oldConstruct;package.loaded.native_spawn=oldSpawn
    if not ok then error(err)end
end)
case('vehicle footprints reject stacking before and after native destination adjustment',function()
    local oldFind,oldStatic,oldConstruct=FindAllOf,StaticFindObject,StaticConstructObject
    local oldSpawn=package.loaded.native_spawn;package.loaded.native_spawn=nil
    local ids=200
    local function object(name)
        ids=ids+1;local o={name=name,address=ids,alive=true}
        function o:IsValid()return self.alive end
        function o:GetFullName()return self.name end
        function o:GetAddress()return self.address end
        return o
    end
    local cdo=object('CDO');cdo.AutoPossessAI=2;cdo.AutoPossessPlayer=1;cdo.SpawnCollisionHandlingMethod=0
    local class=object('BlueprintGeneratedClass /Game/Autok/Abel_Car.Abel_Car_C');function class:GetCDO()return cdo end
    local pawn=object('WalkingPawn');pawn.collision=true
    function pawn:GetActorEnableCollision()return self.collision end
    function pawn:SetActorEnableCollision(v)self.collision=v end
    local pc=object('Controller');pc.Pawn=pawn;pc.CheatManager=object('OriginalCheats');local originalCheats=pc.CheatManager
    local cheatClass=object('Class /Script/Engine.CheatManager');local helper=object('Helper')
    local actors,created,teleports,adjust,arity={},nil,{},nil,4
    local function vehicle(name,position,extent)
        local a=object(name);a.position=position;a.extent=extent or {X=250,Y=110,Z=120}
        function a:GetClass()return class end
        function a:K2_GetActorLocation()return self.position end
        function a:K2_GetActorRotation()return {Pitch=0,Yaw=0,Roll=0}end
        function a:GetActorBounds(...)
            assert(select('#',...)==arity,'fixture rejects the other engine arity')
            local colliding,origin,box=...
            assert(colliding==true)
            origin.X=self.position.X;origin.Y=self.position.Y;origin.Z=self.position.Z
            box.X=self.extent.X;box.Y=self.extent.Y;box.Z=self.extent.Z
        end
        function a:K2_SetActorRotation()end
        function a:SetActorScale3D()end
        function a:K2_TeleportTo(point)
            teleports[#teleports+1]=point.X
            self.position=adjust and adjust(point) or {X=point.X,Y=point.Y,Z=point.Z}
            return true
        end
        function a:K2_DestroyActor()self.alive=false end
        return a
    end
    function helper:Summon()created=vehicle('New car',{X=50,Y=0,Z=90});actors[#actors+1]=created end
    FindAllOf=function(kind)assert(kind=='WheeledVehicle');return actors end
    StaticFindObject=function(path)assert(path=='/Script/Engine.CheatManager');return cheatClass end
    StaticConstructObject=function(cl,outer)assert(cl==cheatClass and outer==pc);return helper end
    local ok,err=pcall(function()
        local spawn=require('native_spawn');local ctx={controller=pc,pawn=pawn}
        local transform={Rotation={Z=0,W=1},Origin={X=0,Y=0,Z=90},Candidates={{X=700,Y=0,Z=90},{X=1400,Y=0,Z=90}}}
        local parked=vehicle('Parked car',{X=700,Y=0,Z=90});actors={parked}
        local car=spawn.actor(ctx,class,transform,'WheeledVehicle')
        check(car.position.X==1400 and #teleports==1 and teleports[1]==1400,'a parked vehicle footprint rejects a candidate before any teleport')
        check(parked.alive and pc.CheatManager==originalCheats and pawn.collision,'occupied-space search preserves existing cars and temporary state')
        car.alive=false;teleports={};arity=3
        transform.Candidates={{X=1300,Y=0,Z=90},{X=2000,Y=0,Z=90}}
        adjust=function(point)if point.X==1300 then return {X=1000,Y=0,Z=290}end;return point end
        car=spawn.actor(ctx,class,transform,'WheeledVehicle')
        check(car.position.X==2000 and #teleports==2,'an engine adjustment onto another car is rejected after teleport, including with three-parameter bounds metadata')
        car.alive=false;teleports={};arity=4;adjust=nil;parked.position.Z=3000
        transform.Candidates={{X=700,Y=0,Z=90},{X=1400,Y=0,Z=90}}
        car=spawn.actor(ctx,class,transform,'WheeledVehicle')
        check(car.position.X==1400 and #teleports==1,'vehicle footprints remain occupied even when the other car is already elevated')
        car.alive=false;teleports={};transform.Candidates={{X=700,Y=0,Z=90}}
        local succeeded,message=pcall(spawn.actor,ctx,class,transform,'WheeledVehicle')
        check(not succeeded and not created.alive and #teleports==0 and message:find('vehicle-footprint rejections',1,true),'fully occupied destinations destroy only the new car and report footprint rejection')
        check(parked.alive and pc.CheatManager==originalCheats and pawn.collision and cdo.AutoPossessAI==2 and cdo.SpawnCollisionHandlingMethod==0,'failed spacing restores class defaults, controller and player collision')
        parked.position={X=700,Y=0,Z=90}
        parked.GetActorBounds=function(self,colliding,origin,box)
            origin.X=self.position.X;origin.Y=self.position.Y;origin.Z=self.position.Z
            box.X=colliding and 0 or 800;box.Y=colliding and 0 or 150;box.Z=150
        end
        transform.Candidates={{X=1700,Y=0,Z=90},{X=2300,Y=0,Z=90}}
        car=spawn.actor(ctx,class,transform,'WheeledVehicle')
        check(car.position.X==2300,'temporarily noncolliding occupied vehicles retain their full visual body footprint')
        car.alive=false
        -- Missing native bounds must still keep a conservative car-sized gap.
        parked.position={X=700,Y=0,Z=90};parked.GetActorBounds=nil
        transform.Candidates={{X=700,Y=0,Z=90},{X=1600,Y=0,Z=90}}
        car=spawn.actor(ctx,class,transform,'WheeledVehicle')
        check(car.position.X==1600,'unavailable bounds fall back to a separated footprint rather than treating a car as a point')
    end)
    FindAllOf,StaticFindObject,StaticConstructObject=oldFind,oldStatic,oldConstruct;package.loaded.native_spawn=oldSpawn
    if not ok then error(err)end
end)
end
