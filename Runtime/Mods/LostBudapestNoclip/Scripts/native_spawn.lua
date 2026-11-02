-- Stable UE4SS 3.0.1's nested StructProperty writer loses stack arguments for
-- FTransform. Summon builds the transform inside Unreal instead. No console,
-- arbitrary commands, DLL patching or persistent cheat-manager change is needed.
local Spawn={}
local function valid(v)return v~=nil and v:IsValid() end
local function id(v)return tostring(v:GetAddress())..':'..v:GetFullName() end
local function finite(v)return type(v)=='number' and v==v and v~=math.huge and v~=-math.huge end
local function vector(v)return v and finite(v.X) and finite(v.Y) and finite(v.Z)end
local function footprint(actor)
    local position=actor:K2_GetActorLocation()
    assert(vector(position),'Vehicle location is unavailable')
    local function bounds(colliding)
        local origin,extent={},{}
        -- UE4 versions expose either three or four reflected inputs. Wrong
        -- arity is rejected before Unreal is called; output structs are flat.
        local ok=pcall(function()actor:GetActorBounds(colliding,origin,extent,false)end)
        if not ok then origin,extent={},{};ok=pcall(function()actor:GetActorBounds(colliding,origin,extent)end)end
        if ok and vector(origin) and vector(extent) and extent.X>10 and extent.Y>10 then return origin,extent end
    end
    local origin,extent=bounds(true)
    -- Spawning from an occupied car temporarily disables that pawn's collision.
    -- Keep its actual body-sized footprint instead of shrinking it to a point.
    if not origin then origin,extent=bounds(false)end
    if origin then
        return {x=origin.X,y=origin.Y,ex=extent.X,ey=extent.Y,ox=origin.X-position.X,oy=origin.Y-position.Y}
    end
    -- Keep a separated space even if a model exposes no usable collision bounds.
    -- This is a car/truck footprint, not a point or a vertical collision check.
    local yaw=0
    local readable,rot=pcall(function()return actor:K2_GetActorRotation()end)
    if readable and rot and finite(rot.Yaw) then yaw=math.rad(rot.Yaw)end
    local c,s=math.abs(math.cos(yaw)),math.abs(math.sin(yaw))
    return {x=position.X,y=position.Y,ex=300*c+150*s,ey=300*s+150*c,ox=0,oy=0}
end
local function clearFootprint(shape,position,obstacles)
    local x,y=position.X+shape.ox,position.Y+shape.oy
    for _,other in ipairs(obstacles)do
        -- Ignore height deliberately: FindTeleportSpot can move the new car
        -- onto another car's roof, then gravity turns that into a vehicle pile.
        if math.abs(x-other.x)<shape.ex+other.ex+40 and math.abs(y-other.y)<shape.ey+other.ey+40 then return false end
    end
    return true
end
local function acceptable(actual,target,origin,adjustment)
    if not vector(actual) then return false end
    local dx,dy,dz=actual.X-target.X,actual.Y-target.Y,actual.Z-target.Z
    if dx*dx+dy*dy>adjustment*adjustment or math.abs(dz)>math.min(adjustment,250) then return false end
    if vector(origin) then
        local x,y=actual.X-origin.X,actual.Y-origin.Y
        if x*x+y*y<300*300 then return false end
    end
    return true
end
function Spawn.actor(ctx,class,transform,kind,profile)
    local path=class:GetFullName():match('^[^ ]+ (.+)$')
    assert(path and (path=='/Script/Engine.CameraActor' or path:match('^/Game/Autok/Abel_Car%.Abel_Car_C$') or
        path:match('^/Game/Traffic_AI_System/Cars/[%w_]+/BP_[%w_]+%.BP_[%w_]+_C$')),'Unsupported spawn class')
    local before={}
    for _,actor in ipairs(FindAllOf(kind) or {}) do if valid(actor) then before[id(actor)]=true end end
    local pc,pawn=ctx.controller,ctx.pawn
    local originalCheats=pc.CheatManager
    local cdo=class:GetCDO()
    assert(valid(cdo),'Class defaults are unavailable')
    local saved={collision=cdo.SpawnCollisionHandlingMethod,pawnCollision=pawn:GetActorEnableCollision()}
    if kind=='WheeledVehicle' then
        saved.ai,saved.player=cdo.AutoPossessAI,cdo.AutoPossessPlayer
        assert(type(saved.ai)=='number' and type(saved.player)=='number','Cannot capture vehicle auto-possession defaults')
    end
    assert(type(saved.collision)=='number','Cannot capture spawn collision defaults')
    local touched={};local actor;local stage='prepare spawn helper'
    local function restore()
        local errors={}
        local function attempt(flag,fn)
            if touched[flag] then local ok,err=pcall(fn);if ok then touched[flag]=nil else errors[#errors+1]=tostring(err)end end
        end
        attempt('profile',function()profile:restore()end)
        attempt('cheats',function()pc.CheatManager=originalCheats end)
        attempt('collision',function()cdo.SpawnCollisionHandlingMethod=saved.collision end)
        attempt('ai',function()cdo.AutoPossessAI=saved.ai end)
        attempt('player',function()cdo.AutoPossessPlayer=saved.player end)
        attempt('pawn',function()if valid(pawn) then pawn:SetActorEnableCollision(saved.pawnCollision)end end)
        return #errors==0,table.concat(errors,'; ')
    end
    local ok,err=xpcall(function()
        local cheatClass=StaticFindObject('/Script/Engine.CheatManager')
        assert(valid(cheatClass),'Native spawn command is unavailable in this build')
        local cheats=StaticConstructObject(cheatClass,pc)
        assert(valid(cheats),'Could not construct temporary spawn helper')
        -- No game tick interleaves this synchronous call. Restore every default
        -- and the exact original CheatManager on success and failure.
        touched.cheats=true;pc.CheatManager=cheats
        touched.collision=true;cdo.SpawnCollisionHandlingMethod=3 -- adjust or reject
        if kind=='WheeledVehicle' then
            touched.ai=true;cdo.AutoPossessAI=0
            touched.player=true;cdo.AutoPossessPlayer=0
        end
        touched.pawn=true;pawn:SetActorEnableCollision(false)
        if profile then stage='apply selected body/wheel template';touched.profile=true;profile:apply()end
        stage='native actor construction'
        cheats:Summon(path)
        stage='identify new actor'
        local matches={};local existing={}
        for _,candidate in ipairs(FindAllOf(kind) or {}) do
            if valid(candidate) and not before[id(candidate)] and candidate:GetClass():GetFullName()==class:GetFullName() then
                matches[#matches+1]=candidate
            end
            if kind=='WheeledVehicle' and valid(candidate) and before[id(candidate)] and not candidate:GetFullName():find('Default__',1,true) then existing[#existing+1]=candidate end
        end
        assert(#matches==1,'The engine did not create one clear vehicle/camera spawn; try an open area')
        actor=matches[1]
        if profile then stage='validate selected body/wheel template';profile:validate(actor)end
        stage='set vehicle orientation'
        local q=transform.Rotation
        local yaw=math.deg(2*math.atan(q.Z,q.W))
        actor:K2_SetActorRotation({Pitch=0,Yaw=yaw,Roll=0},true)
        -- Profile scale was installed before physics creation; do not reset it afterward.
        if not profile then actor:SetActorScale3D({X=1,Y=1,Z=1})end
        local placed=false;local attempts=0;local overlapRejects=0
        local shape,obstacles
        if kind=='WheeledVehicle' then
            stage='measure vehicle footprints'
            shape=footprint(actor);obstacles={}
            for _,other in ipairs(existing)do obstacles[#obstacles+1]=footprint(other)end
        end
        local teleport
        if kind=='WheeledVehicle' then
            -- Destination collision checks avoid sweeping the whole route from
            -- Summon's near-player starting point through curbs/parked cars.
            local readable,method=pcall(function()return actor.K2_TeleportTo end)
            if readable and method~=nil then teleport=method end
        end
        stage='find collision-safe destination'
        for _,target in ipairs(transform.Candidates or {transform.Translation}) do
            assert(vector(target),'Invalid spawn destination')
            attempts=attempts+1
            if not shape or clearFootprint(shape,target,obstacles) then
                local moved
                if teleport then moved=actor:K2_TeleportTo(target,{Pitch=0,Yaw=yaw,Roll=0})
                else moved=actor:K2_SetActorLocation(target,true,{},true)end
                local actual=actor:K2_GetActorLocation()
                local adjustment=kind=='WheeledVehicle' and 350 or 30
                local free=not shape or (vector(actual) and clearFootprint(shape,actual,obstacles))
                if not free then overlapRejects=overlapRejects+1 end
                if free and (not teleport or moved==true) and acceptable(actual,target,transform.Origin,adjustment) then placed=true;break end
            else overlapRejects=overlapRejects+1 end
        end
        assert(placed,"No collision-safe destination among "..attempts.." positions ("..overlapRejects.." vehicle-footprint rejections); no vehicle was counted")
    end,function(e)return debug.traceback('Spawn step '..stage..': '..tostring(e),2)end)
    local restored,restoreError=restore()
    if not restored then restored,restoreError=restore() end
    if not ok or not restored then
        if valid(actor) then pcall(function()actor:K2_DestroyActor()end)end
        error(not ok and err or ('Spawn defaults could not be restored: '..restoreError),0)
    end
    if not valid(pc.Pawn) or id(pc.Pawn)~=id(pawn) then
        if valid(actor) then pcall(function()actor:K2_DestroyActor()end)end
        error('The game changed the controlled pawn during spawning',0)
    end
    return actor
end
return Spawn
