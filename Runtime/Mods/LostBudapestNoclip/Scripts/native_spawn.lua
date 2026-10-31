-- Stable UE4SS 3.0.1's nested StructProperty writer loses stack arguments for
-- FTransform. Summon builds the transform inside Unreal instead. No console,
-- arbitrary commands, DLL patching or persistent cheat-manager change is needed.
local Spawn={}
local function valid(v)return v~=nil and v:IsValid() end
local function id(v)return tostring(v:GetAddress())..':'..v:GetFullName() end
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
    local touched={};local actor
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
        if profile then touched.profile=true;profile:apply()end
        cheats:Summon(path)
        local matches={}
        for _,candidate in ipairs(FindAllOf(kind) or {}) do
            if valid(candidate) and not before[id(candidate)] and candidate:GetClass():GetFullName()==class:GetFullName() then
                matches[#matches+1]=candidate
            end
        end
        assert(#matches==1,'The engine did not create one clear vehicle/camera spawn; try an open area')
        actor=matches[1]
        if profile then profile:validate(actor)end
        local q=transform.Rotation
        local yaw=math.deg(2*math.atan(q.Z,q.W))
        actor:K2_SetActorRotation({Pitch=0,Yaw=yaw,Roll=0},true)
        actor:SetActorScale3D({X=1,Y=1,Z=1})
        local placed=false
        for _,target in ipairs(transform.Candidates or {transform.Translation}) do
            actor:K2_SetActorLocation(target,true,{},true)
            local actual=actor:K2_GetActorLocation()
            if (actual.X-target.X)^2+(actual.Y-target.Y)^2+(actual.Z-target.Z)^2 <= 30^2 then placed=true;break end
        end
        assert(placed,"All nearby spawn positions were obstructed; no vehicle was counted")
    end,function(e)return debug.traceback(tostring(e),2)end)
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
