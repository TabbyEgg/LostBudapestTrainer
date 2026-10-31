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
        helper.Summon=function(self,path)summon(self,path);created.K2_SetActorLocation=function(self)self.position={X=0,Y=0,Z=0};return false end end
        check(not pcall(spawn.actor,ctx,class,spread,'WheeledVehicle') and not created.alive,'all blocked placements remove the failed spawn and never consume a visible-car slot')
        helper.Summon=summon
        fail=true;check(not pcall(spawn.actor,ctx,class,transform,'WheeledVehicle'),'native engine spawn failure is reported')
        check(pc.CheatManager==previousCheats and pawn.collision and cdo.AutoPossessAI==2 and cdo.AutoPossessPlayer==1 and cdo.SpawnCollisionHandlingMethod==0,'engine exception restores the exact original manager, collision and class defaults')
        fail=false;local move=helper.Summon
        helper.Summon=function()error(function()end)end
        local succeeded,message=pcall(spawn.actor,ctx,class,transform,'WheeledVehicle')
        check(not succeeded and type(message)=='string' and message:find('stack traceback',1,true),'opaque native function errors become useful traced text')
        check(pc.CheatManager==previousCheats and pawn.collision,'opaque native errors still release every temporary player change')
        helper.Summon=move

        helper.Summon=function(self,path)move(self,path);created.K2_SetActorLocation=function()error('placement refused')end end
        check(not pcall(spawn.actor,ctx,class,transform,'WheeledVehicle') and not created.alive and first.alive,'placement exception destroys only the newly created actor')
        check(pc.CheatManager==previousCheats and pawn.collision,'placement failure still restores temporary state')
        local unknown=object('BlueprintGeneratedClass /Game/Unknown.Unknown_C',30)
        check(not pcall(spawn.actor,ctx,unknown,transform,'WheeledVehicle'),'unknown class is rejected before any native spawn')
    end)
    FindAllOf,StaticFindObject,StaticConstructObject=oldFind,oldStatic,oldConstruct;package.loaded.native_spawn=oldSpawn
    if not ok then error(err)end
end)
end
