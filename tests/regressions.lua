package.path = TRAINER_SCRIPTS .. '/?.lua;' .. package.path

local Controller = require('controller')
local Config = require('config')
TEST_ASSERTIONS, TEST_FAILURES = 0, 0

local function check(value, label)
    TEST_ASSERTIONS = TEST_ASSERTIONS + 1
    if not value then
        TEST_FAILURES = TEST_FAILURES + 1
        TEST_PRINT('FAIL: ' .. label)
    end
end

local function close(a, b, epsilon)
    return math.abs(a - b) <= (epsilon or 0.000001)
end

local function copy(v) return {X=v.X, Y=v.Y, Z=v.Z} end
local function length(v) return math.sqrt(v.X*v.X + v.Y*v.Y + v.Z*v.Z) end
local function delta(a,b) return {X=a.X-b.X,Y=a.Y-b.Y,Z=a.Z-b.Z} end
local function samePosition(a,b) return close(a.X,b.X) and close(a.Y,b.Y) and close(a.Z,b.Z) end

local function case(label, fn)
    local before = TEST_FAILURES
    local ok, failure = pcall(fn)
    if not ok then
        TEST_FAILURES = TEST_FAILURES + 1
        TEST_PRINT('ERROR: ' .. label .. ': ' .. tostring(failure))
    end
    TEST_PRINT((before == TEST_FAILURES and 'PASS: ' or 'FAILED: ') .. label)
end

local function fixture()
    local f = {clock=100,events={},logs={},keys={},rotation={Pitch=0,Yaw=0,Roll=0}}
    local ctx = {identity='pawn-A',position={X=10,Y=20,Z=30},mode=1,custom=0,collision=true,valid=true}
    f.original, f.current = ctx, ctx
    local function event(name, target)
        table.insert(f.events,{name=name,target=target and target.identity,collision=target and target.collision,mode=target and target.mode})
    end
    local api = {}
    function api.resolve() event('resolve');return f.current end
    function api.capture(target)
        event('capture',target)
        if f.missingComponent then error('No supported CharacterMovement component') end
        return {ctx=target,identity=target.identity,position=copy(target.position),mode=target.mode,custom=target.custom,collision=target.collision}
    end
    function api.apply(target)
        event('apply',target);target.collision=false
        if f.failApply then error('injected half-applied movement error') end
        target.mode,target.custom=0,0
    end
    function api.restore(saved)
        event('restore',saved.ctx)
        if f.failRestore then return false end
        if not saved.ctx.valid then return true end
        saved.ctx.mode,saved.ctx.custom,saved.ctx.collision=saved.mode,saved.custom,saved.collision
        return true
    end
    function api.same(target,saved) return target~=nil and target.valid and target.identity==saved.identity end
    function api.teleport(target,position)
        event('teleport',target)
        if f.failTeleport then error('injected Unreal teleport exception') end
        if f.rejectTeleport then return false end
        target.position=copy(position);return true
    end
    function api.location(target) return copy(target.position) end
    function api.rotation() return f.rotation end
    function api.time() return f.clock end
    function api.paused() return f.paused or false end
    function api.blocked() return f.blocked or false end
    function api.input() return f.keys end
    function api.log(message) table.insert(f.logs,tostring(message)) end
    f.api=api
    f.core=Controller.new(Config,api)
    function f.tick(seconds) f.clock=f.clock+seconds;f.core:tick() end
    function f.enable() f.core:toggle();f.tick(0) end
    function f.travel(seconds,keys)
        f.keys=keys or {forward=true}
        local before=copy(f.original.position);f.tick(seconds)
        return delta(f.original.position,before)
    end
    return f
end

case('inactive state and unsupported contexts never alter physics',function()
    local f=fixture();f.core:tick()
    check(not f.core:isEnabled(),'new trainer starts disabled')
    check(f.original.collision and f.original.mode==1,'disabled tick leaves collision and movement intact')
    f.current=nil;f.core:toggle()
    check(not f.core:isEnabled(),'menu without pawn cannot enable noclip')
    check(f.original.collision and f.original.mode==1,'menu toggle never changes previous pawn')
    local missing=fixture();missing.missingComponent=true;pcall(function()missing.core:toggle()end)
    check(not missing.core:isEnabled(),'missing component does not leave active state')
    check(missing.original.collision and missing.original.mode==1,'capture failure happens before any modification')
end)

case('activation and exact restoration preserve original state',function()
    local f=fixture();f.enable()
    check(f.core:isEnabled(),'valid character enables noclip')
    check(not f.original.collision and f.original.mode==0,'active noclip disables collision and native movement')
    f.core:toggle()
    check(not f.core:isEnabled(),'second toggle disables noclip')
    check(f.original.collision and f.original.mode==1 and f.original.custom==0,'normal walking state restored exactly')
    local custom=fixture();custom.original.collision=false;custom.original.mode=6;custom.original.custom=17;custom.enable();custom.core:disable(false)
    check(not custom.original.collision,'previously disabled collision remains disabled')
    check(custom.original.mode==6 and custom.original.custom==17,'original custom movement mode is restored')
    local calls=#custom.events;custom.core:disable(false)
    check(#custom.events==calls,'disabling an already disabled trainer does not restore twice')
end)

case('activation rollback and movement failures restore owned state',function()
    local half=fixture();half.failApply=true;pcall(function()half.core:toggle()end)
    check(half.original.collision and half.original.mode==1,'half-applied activation rolls collision back')
    check(not half.core:isEnabled(),'failed activation is not advertised as active')
    local bad=fixture();bad.enable();bad.failTeleport=true;bad.keys={forward=true};pcall(function()bad.tick(0.02)end)
    check(not bad.core:isEnabled(),'movement exception stops noclip')
    check(bad.original.collision and bad.original.mode==1,'movement exception restores movement and collision')
    local rejected=fixture();rejected.enable();rejected.rejectTeleport=true;rejected.keys={forward=true};pcall(function()rejected.tick(0.02)end)
    check(not rejected.core:isEnabled(),'false teleport result stops noclip')
    check(rejected.original.collision and rejected.original.mode==1,'false teleport result restores owned state')
end)

case('camera-space movement, opposite keys and diagonal speed',function()
    local axis=fixture();axis.enable();local along=axis.travel(0.01,{forward=true})
    check(along.X>0 and close(along.Y,0) and close(along.Z,0),'forward follows zero-yaw zero-pitch view')
    local diag=fixture();diag.enable();local diagonal=diag.travel(0.01,{forward=true,right=true,up=true})
    check(close(length(along),length(diagonal)),'diagonal with vertical movement has the same total speed')
    check(diagonal.X>0 and diagonal.Y>0 and diagonal.Z>0,'diagonal axes have expected directions')
    local cancel=fixture();cancel.enable();local unmoved=cancel.travel(0.02,{forward=true,back=true,left=true,right=true,up=true,down=true})
    check(close(length(unmoved),0),'opposing keys cancel without drifting')
    local pitched=fixture();pitched.rotation={Pitch=45,Yaw=90,Roll=0};pitched.enable();local rise=pitched.travel(0.01,{forward=true})
    check(close(rise.X,0) and rise.Y>0 and rise.Z>0 and close(rise.Y,rise.Z),'forward includes control pitch and yaw')
    local reverse=fixture();reverse.enable();local back=reverse.travel(0.01,{back=true})
    check(back.X<0 and close(length(back),length(along)),'backward uses the same speed in reverse')
end)

case('pause, blocked input, negative clock and frame stalls cannot teleport',function()
    local f=fixture();f.enable();local baseline=length(f.travel(0.01,{forward=true}));local before=copy(f.original.position)
    f.paused=true;f.tick(5)
    check(samePosition(before,f.original.position),'pause blocks movement despite pressed keys')
    f.paused=false;local resumed=copy(f.original.position);f.tick(0.01)
    check(samePosition(resumed,f.original.position),'first resumed tick establishes a fresh clock instead of spending paused time')
    local resume=length(f.travel(0.01,{forward=true}))
    check(close(resume,baseline),'normal movement resumes after fresh clock observation')
    f.blocked=true;before=copy(f.original.position);f.tick(5)
    check(samePosition(before,f.original.position),'menu or ignored player input blocks movement')
    check(not f.core:isEnabled() and f.original.collision and f.original.mode==1,'lost player control safely disables and restores noclip')
    f.blocked=false;f.enable();local unblocked=length(f.travel(0.01,{forward=true}))
    check(close(unblocked,baseline),'explicit re-enable starts a fresh clock after blocked input')
    before=copy(f.original.position);f.tick(-1)
    check(samePosition(before,f.original.position),'backward game clock cannot move character')
    local stalled=fixture();stalled.enable();local slow=length(stalled.travel(10,{forward=true}))
    check(slow>0 and slow<=baseline*10.001,'a long callback stall is capped instead of causing a huge teleport')
end)

case('speed adjustment bounds and temporary boost',function()
    local f=fixture();f.enable();local base=length(f.travel(0.01,{forward=true}));f.core:faster();local fast=length(f.travel(0.01,{forward=true}))
    check(fast>base,'faster changes active movement speed')
    f.core:slower();local normal=length(f.travel(0.01,{forward=true}))
    check(close(base,normal),'slower reverses one faster adjustment')
    local boosted=length(f.travel(0.01,{forward=true,boost=true}))
    check(boosted>normal,'held boost increases speed')
    local released=length(f.travel(0.01,{forward=true}))
    check(close(released,normal),'released boost does not alter selected normal speed')
    for i=1,100 do f.core:slower() end
    local minimum=length(f.travel(0.01,{forward=true}));f.core:slower();local stillMinimum=length(f.travel(0.01,{forward=true}))
    check(minimum>0 and close(minimum,stillMinimum),'speed has a positive stable lower bound')
    for i=1,100 do f.core:faster() end
    local maximum=length(f.travel(0.01,{forward=true}));f.core:faster();local stillMaximum=length(f.travel(0.01,{forward=true}))
    check(maximum>minimum and close(maximum,stillMaximum),'speed has a stable upper bound')
end)

case('possession and map-context changes restore only the old pawn',function()
    local f=fixture();f.enable()
    local new={identity='pawn-B',position={X=50,Y=60,Z=70},mode=3,custom=0,collision=true,valid=true};f.current=new;f.tick(0.02)
    check(not f.core:isEnabled(),'possession change turns noclip off')
    check(f.original.collision and f.original.mode==1,'still-valid old pawn is restored after possession change')
    check(new.collision and new.mode==3 and samePosition(new.position,{X=50,Y=60,Z=70}),'new pawn never receives old snapshot or movement')
    local gone=fixture();gone.enable();gone.current=nil;gone.tick(0.02)
    check(not gone.core:isEnabled(),'lost player context turns noclip off')
    check(gone.original.collision and gone.original.mode==1,'lost context restores the valid owned pawn')
end)

case('emergency return teleports before restoring collision',function()
    local f=fixture();local start=copy(f.original.position);f.enable();f.travel(0.02,{forward=true,up=true});f.events={};f.core:disable(true)
    check(samePosition(f.original.position,start),'panic return moves to the activation position')
    check(not f.core:isEnabled() and f.original.collision and f.original.mode==1,'panic return also restores and disables noclip')
    local teleport,restore
    for index,e in ipairs(f.events)do if e.name=='teleport' then teleport=index;check(e.collision==false and e.mode==0,'panic teleport happens while collision and native movement are disabled')elseif e.name=='restore' then restore=index end end
    check(teleport~=nil and restore~=nil and teleport<restore,'panic return precedes restoring collision')
end)

case('failed emergency return keeps noclip active until a successful retry',function()
    for _,kind in ipairs({'exception','false result'})do
        local f=fixture();local start=copy(f.original.position);f.enable();f.travel(0.02,{forward=true});f.events={}
        f.failTeleport=kind=='exception';f.rejectTeleport=kind=='false result'
        local result=f.core:disable(true)
        check(result==false and f.core:isEnabled(),'failed F10 keeps the active flight session: '..kind)
        check(not f.original.collision and f.original.mode==0,'failed F10 does not enable collision inside geometry: '..kind)
        check(not samePosition(f.original.position,start),'failed return does not pretend to reach its entry point: '..kind)
        local restored=false
        for _,e in ipairs(f.events)do if e.name=='restore'then restored=true end end
        check(not restored,'failed F10 never restores physics prematurely: '..kind)
        f.failTeleport=false;f.rejectTeleport=false
        check(f.core:disable(true)==true,'retry can complete the retained emergency return: '..kind)
        check(not f.core:isEnabled() and f.original.collision and f.original.mode==1 and samePosition(f.original.position,start),
            'successful retry returns and restores the original state: '..kind)
    end
end)

case('failed restoration stays recoverable and cannot stack a second activation',function()
    local f=fixture();f.enable();f.failRestore=true;f.core:disable(false)
    check(not f.core:isEnabled() and f.core:hasWork(),'failed restoration stops flight but retains cleanup work')
    f.core:tick();f.core:tick();f.core:tick()
    check(not f.core:hasWork(),'automatic restore retries are bounded')
    local writes=0
    for _,e in ipairs(f.events)do if e.name=='apply'then writes=writes+1 end end
    f.failRestore=false;f.core:toggle()
    check(not f.core:isEnabled() and f.original.collision and f.original.mode==1,'toggle retries pending restoration without stacking another flight')
    local after=0
    for _,e in ipairs(f.events)do if e.name=='apply'then after=after+1 end end
    check(after==writes,'cleanup retry never performs an extra activation')
end)

case('external engine ownership changes stop flight',function()
    local f=fixture();f.api.owned=function()return f.ownership~=false end;f.enable();f.ownership=false;f.keys={forward=true};local before=copy(f.original.position);f.tick(0.02)
    check(not f.core:isEnabled(),'external movement or collision change stops noclip')
    check(samePosition(before,f.original.position),'trainer does not overwrite later engine movement with a flight teleport')
end)

local function engine()
    local f={inGame=false,events={},logs={},queue={},pressed={},clock=100,position={X=10,Y=20,Z=30},collision=true,
        rotation={Pitch=0,Yaw=0,Roll=0},registry={}}
    local function guard(name)
        assert(f.inGame,'Unreal access outside game thread: '..name)
        table.insert(f.events,name)
    end
    local function valid(self)guard('IsValid');return self.valid~=false end
    f.pc={valid=true,localController=true,bShowMouseCursor=false}
    f.pawn={valid=true}
    f.movement={valid=true,MovementMode=1,CustomMovementMode=0}
    f.pawn.CharacterMovement=f.movement;f.pc.Pawn=f.pawn
    f.pc.IsValid=valid;f.pawn.IsValid=valid;f.movement.IsValid=valid
    function f.pc:GetAddress()guard('GetAddress');return 0x5000 end
    function f.pc:GetFullName()guard('GetFullName');return 'PlayerController /World.PC'end
    function f.pc:IsLocalController()guard('IsLocalController');return self.localController end
    function f.pc:IsMoveInputIgnored()guard('IsMoveInputIgnored');return f.ignored or (f.moveLocks or 0)>0 end
    function f.pc:IsLookInputIgnored()guard('IsLookInputIgnored');return (f.lookLocks or 0)>0 end
    function f.pc:SetIgnoreMoveInput(value)guard('SetIgnoreMoveInput');f.moveLocks=(f.moveLocks or 0)+(value and 1 or -1)end
    function f.pc:SetIgnoreLookInput(value)guard('SetIgnoreLookInput');f.lookLocks=(f.lookLocks or 0)+(value and 1 or -1)end
    function f.pc:GetMousePosition()guard('GetMousePosition');return false end
    function f.pc:GetControlRotation()guard('GetControlRotation');return f.rotation end
    function f.pc:IsInputKeyDown(key)
        guard('IsInputKeyDown')
        assert(type(key)=='table' and type(key.KeyName)=='table','FKey must be a struct containing KeyName')
        assert(type(key.KeyName.ToString)=='function','FKey.KeyName must be an FName, not a raw string')
        return f.pressed[key.KeyName:ToString()] or false
    end
    function f.pawn:GetAddress()guard('GetAddress');return f.pawnAddress or 0x1000 end
    function f.pawn:GetFullName()guard('GetFullName');return f.pawnName or 'Character /Game/Test.PersistentLevel.Player' end
    function f.movement:GetAddress()guard('GetAddress');return 0x2000 end
    function f.movement:GetFullName()guard('GetFullName');return 'CharacterMovementComponent /Game/Test.Player.CharacterMovement' end
    function f.pawn:K2_GetActorLocation()guard('K2_GetActorLocation');return copy(f.position) end
    function f.pawn:GetActorEnableCollision()guard('GetActorEnableCollision');return f.collision end
    function f.pawn:SetActorEnableCollision(value)
        guard('SetActorEnableCollision');assert(type(value)=='boolean','collision requires boolean');f.collision=value
    end
    function f.movement:StopMovementImmediately()guard('StopMovementImmediately')end
    function f.movement:SetMovementMode(mode,custom)
        guard('SetMovementMode')
        assert(type(mode)=='number' and mode%1==0 and mode>=0 and mode<=6,'movement mode must be uint8 enum')
        assert(type(custom)=='number' and custom%1==0 and custom>=0 and custom<=255,'custom movement mode argument is required')
        self.MovementMode,self.CustomMovementMode=mode,custom
    end
    function f.pawn:K2_SetActorLocation(location,sweep,hit,teleport,...)
        guard('K2_SetActorLocation')
        assert(type(location)=='table' and type(location.X)=='number' and type(location.Y)=='number' and type(location.Z)=='number','location requires FVector table')
        assert(sweep==false and type(hit)=='table' and teleport==true and select('#',...)==0,'location requires no-sweep, output-hit-table, teleport arguments')
        if f.rejectLocation or (f.falseWhenUnmoved and samePosition(location,f.position))then return false end
        f.position=copy(location);return true
    end
    f.statics={IsValid=valid}
    function f.statics:GetTimeSeconds(context)guard('GetTimeSeconds');assert(context==f.pawn,'world context must be pawn');return f.clock end
    function f.statics:IsGamePaused(context)guard('IsGamePaused');assert(context==f.pawn,'pause requires world context');return f.paused or false end
    function f.load()
        package.loaded.adapter=nil;package.loaded.vehicle_engine=nil;package.loaded.menu_engine=nil
        Key={HOME=36,INS=45,F1=112,F2=113,F3=114,F4=115,F5=116,F6=117,F7=118,F8=119,F9=120,F10=121};EFindName={FNAME_Find=0}
        FindAllOf=function(name)guard('FindAllOf');if name=='HUD' then return f.huds or {}end;assert(name=='PlayerController');return f.controllers or {f.pc} end
        StaticFindObject=function(path)guard('StaticFindObject');assert(path=='/Script/Engine.Default__GameplayStatics');return f.statics end
        FName=function(name,mode)
            guard('FName');assert(type(name)=='string' and mode==EFindName.FNAME_Find,'input names must use find-only FName lookup')
            return {ToString=function()return f.missingKey==name and 'None' or name end}
        end
        RegisterKeyBind=function(key,callback)assert(not f.registry[key],'duplicate key registration');f.registry[key]=callback end
        f.hudCallbacks={}
        RegisterCustomEvent=function(name,callback)f.hudCallbacks[name]=callback end
        ExecuteInGameThread=function(callback)
            if f.failQueue then error('simulated loader scheduling failure') end
            table.insert(f.queue,callback)
        end
        LoopAsync=function(delay,callback)assert(delay>0 and delay<=100);f.loop=callback end
        RegisterLoadMapPreHook=function()f.forbiddenMapCalls=(f.forbiddenMapCalls or 0)+1;error('Do not register the upstream-broken LoadMapPre callback')end
        RegisterHook=function(path,callback)
            if path=='/Script/Engine.PlayerController:ClientRestart' then f.restart=callback
            else
                local allowed={
                    ['/Script/Engine.GameplayStatics:ApplyDamage']=true,
                    ['/Script/Engine.GameplayStatics:ApplyPointDamage']=true,
                    ['/Script/PhysXVehicles.WheeledVehicleMovementComponent:SetSteeringInput']=true,
                    ['/Script/Engine.SceneComponent:SetVisibility']=true,
                    ['/Script/Engine.SceneComponent:SetHiddenInGame']=true,
                    ['/Script/Engine.PrimitiveComponent:SetCollisionEnabled']=true,
                }
                assert(allowed[path],'only documented native input/visibility/damage setters are hooked')
                f.damageHooks=f.damageHooks or {};f.damageHooks[path]=callback
            end
            return 1,2
        end
        f.originalPrint=print;print=function(text)table.insert(f.logs,tostring(text))end
        dofile(TRAINER_SCRIPTS..'/main.lua')
    end
    function f.flush()
        local tasks=f.queue;f.queue={};f.inGame=true
        local ok,err=pcall(function()for _,task in ipairs(tasks)do task()end end)
        f.inGame=false;if not ok then error(err)end
    end
    function f.press(key)f.registry[Key[key]]()end
    function f.step(seconds)f.clock=f.clock+seconds;f.loop();f.flush()end
    function f.finish()print=f.originalPrint end
    return f
end

case('new vehicle keys are queued and failed diagnostics cannot drop active flight',function()
    local f=engine();f.load()
    check(f.registry[Key.F1] and f.registry[Key.F2] and f.registry[Key.F5] and f.registry[Key.F9],'repair, select, driving and spawn keys registered')
    check(f.registry[Key.HOME] and f.registry[Key.F4],'Home diagnostic and god-mode keys registered')
    check(f.registry[Key.F2] and f.registry[Key.F3] and not f.registry[Key.INS],'F2 menu and F3 selection replace the old Insert binding')
    f.press('F6');f.step(0)
    f.press('F5');f.step(0.01);check(not f.pawn.collision,'driving request cannot capture an active noclip pawn')
    f.press('HOME');f.step(0.01);check(not f.pawn.collision,'diagnostic read failure leaves flight active')
    f.press('F3');f.step(0.01);check(not f.pawn.collision,'vehicle selection does not mutate player physics')
    f.pawn.bCanBeDamaged=true;f.press('F4');f.step(0.01);check(f.pawn.bCanBeDamaged==false,'god mode key disables the actual player damage property')
    f.inGame=true;f.restart();f.inGame=false;f.step(0.01);check(f.pawn.bCanBeDamaged==false,'manual god mode remains requested across player restarts and vehicle possession')
    f.finish()
end)

case('native pre-damage guard suppresses protected-player damage before health processing',function()
    local f=engine();f.load();f.pawn.bCanBeDamaged=true;f.pawn.Health=100
    local amount={value=150,get=function(self)return self.value end,set=function(self,v)self.value=v end}
    local target={get=function()return f.pawn end}
    local hook=f.damageHooks['/Script/Engine.GameplayStatics:ApplyDamage']
    local point=f.damageHooks['/Script/Engine.GameplayStatics:ApplyPointDamage']
    check(type(hook)=='function' and type(point)=='function','both native damage entry points registered')
    f.inGame=true;hook(nil,target,amount);check(amount.value==150,'unprotected game damage remains unchanged');f.inGame=false
    f.press('F4');f.step(0);f.inGame=true;hook(nil,target,amount)
    check(amount.value==0 and f.pawn.Health==100,'protected lethal native damage becomes zero before any health loss')
    local other={IsValid=function()return true end,GetAddress=function()return 44 end,GetFullName=function()return'OtherPawn'end}
    amount.value=50;point(nil,{get=function()return other end},amount)
    check(amount.value==50,'damage to other actors is never suppressed')
    amount.value=25;point(nil,target,amount);check(amount.value==0,'point damage obeys the same protected-player filter')
    f.inGame=false;f.finish()
end)

case('F2 reaches the real HUD renderer and closes without leaving input locked',function()
    local f=engine();f.load()
    local hud={PlayerOwner=f.pc,Canvas={SizeX=1280,SizeY=768,IsValid=function()return true end}}
    function hud:IsValid()return true end
    function hud:GetClass()return {GetFullName=function()return 'BlueprintGeneratedClass /Game/UI/HUD_Shooter.HUD_Shooter_C'end}end
    function hud:DrawRect()assert(f.inGame);f.menuRects=(f.menuRects or 0)+1 end
    function hud:DrawText(text)assert(f.inGame);if text=='LOST BUDAPEST' then f.menuTitle=true end end
    f.huds={hud};f.press('F2');f.step(0)
    check(type(f.hudCallbacks.ExecuteUbergraph_HUD_Shooter)=='function' and not f.pc.bShowMouseCursor,'F2 schedules the menu and registers the loaded HUD without premature input capture')
    f.inGame=true;f.hudCallbacks.ReceiveDrawHUD({get=function()return hud end});f.inGame=false
    check(f.menuTitle and f.menuRects>0 and f.pc.bShowMouseCursor and f.moveLocks==1 and f.lookLocks==1,'the real adapter draws through the local HUD and captures controls once')
    f.press('F2');f.step(.02)
    check(not f.pc.bShowMouseCursor and f.moveLocks==0 and f.lookLocks==0,'F2 closes the rendered menu and restores both input counters')
    local drawn=false;for _,message in ipairs(f.logs)do if message:find('Trainer menu drawn successfully.',1,true)then drawn=true end end
    check(drawn,'log distinguishes an actually drawn frame from a menu request')
    f.finish()
end)

case('held hotkeys cannot repeatedly toggle god mode',function()
    local f=engine();f.load();f.pawn.bCanBeDamaged=true
    f.pressed.F4=true;f.press('F4');f.step(0)
    f.press('F4');f.step(.02);f.press('F4');f.step(.02)
    local on,off=0,0
    for _,message in ipairs(f.logs)do
        if message:find('God mode on',1,true)then on=on+1 end
        if message:find('God mode off',1,true)then off=off+1 end
    end
    check(on==1 and off==0,'repeated down callbacks during one hold cannot turn god mode back off')
    f.pressed.F4=false;f.step(.02);f.pressed.F4=true;f.press('F4');f.step(.02)
    local released=false;for _,message in ipairs(f.logs)do if message:find('God mode off',1,true)then released=true end end
    check(released,'releasing and pressing the key again permits the next toggle')
    f.finish()
end)

case('preserved old shortcuts migrate to the reserved F2 menu and F3 selection',function()
    local previous,oldKeys=Config.MenuKey,Config.VehicleKeys
    Config.MenuKey='INSERT';Config.VehicleKeys={Next='F2',Diagnose='F3'}
    local f=engine();f.load()
    check(type(f.registry[Key.F2])=='function' and type(f.registry[Key.F3])=='function' and type(f.registry[Key.HOME])=='function' and not f.registry[Key.INS],'preserved old bindings cannot steal F2/F3 and diagnostics fall back to Home')
    f.press('F3');f.step(0)
    local selected=false;for _,m in ipairs(f.logs)do if m:find('Selected vehicle:',1,true) then selected=true end end
    check(selected,'F3 reaches car selection with the old config')
    f.press('F2');f.step(.02)
    local wrong=false;for _,m in ipairs(f.logs)do if m:find('Selected vehicle: Hatchback',1,true) then wrong=true end end
    check(not wrong,'F2 cannot cycle another model after migration')
    f.finish();Config.MenuKey,Config.VehicleKeys=previous,oldKeys
end)

case('player custom health and lethal falling speed are guarded without resurrecting dead pawns',function()
    local f=engine();f.load();local a=require('adapter');f.inGame=true
    f.pawn.Health=100
    function f.pawn:GetClass()return {GetFullName=function()return 'BlueprintGeneratedClass /Game/Characters/Blueprints/Abel/Abel.Abel_C'end}end
    f.pawn.bCanBeDamaged=true
    local ctx=a.damageContext();local saved=a.captureDamage(ctx)
    f.pawn.Health=40;f.movement.MovementMode=3;f.movement.Velocity={X=25,Y=-10,Z=-2500}
    a.guardHealthAndFall(ctx,saved)
    check(f.pawn.Health==100,'living Abel custom Health restored to the captured positive baseline')
    check(f.movement.Velocity.Z==-300 and f.movement.Velocity.X==25 and f.movement.Velocity.Y==-10,'lethal vertical fall speed capped while retaining horizontal movement')
    f.pawn.Health=0;a.guardHealthAndFall(ctx,saved);check(f.pawn.Health==0,'scripted death is not falsely revived by writing positive health to a dead pawn')
    f.movement.MovementMode=1;f.movement.Velocity.Z=-900;a.guardHealthAndFall(ctx,saved)
    check(f.movement.Velocity.Z==-900,'walking movement is not altered by the fall guard')
    f.inGame=false;f.finish()
end)

case('shipped UE4SS adapter and bindings use typed game-thread calls',function()
    local f=engine();f.load()
    check(#f.events==0,'startup registers bindings without reading any Unreal objects')
    check((f.forbiddenMapCalls or 0)==0,'startup never registers the upstream-broken LoadMapPre hook')
    check(type(f.restart)=='function','startup registers the supported ClientRestart cleanup hook')
    check(f.registry[Key.F6] and f.registry[Key.F7] and f.registry[Key.F8] and f.registry[Key.F10],'all four documented hotkeys are registered')
    f.press('F6')
    check(#f.events==0 and #f.queue==0,'key callback only records an action')
    for i=1,20 do f.loop()end
    check(#f.queue==1,'async polling coalesces to one pending game-thread update')
    check(#f.events==0,'async loop performs no direct Unreal reads')
    f.flush()
    check(not f.collision and f.movement.MovementMode==0,'queued toggle enables actual adapter state only on the game thread')
    f.pressed.W=true;f.step(0.02)
    check(f.position.X>10 and close(f.position.Y,20) and close(f.position.Z,30),'actual adapter uses FKey structs and complete Unreal movement signatures')
    f.press('F10');f.step(0.01)
    check(samePosition(f.position,{X=10,Y=20,Z=30}),'documented F10 binding returns to entry point')
    check(f.collision and f.movement.MovementMode==1,'F10 restores collision and original movement')
    f.finish()
end)

case('main scheduler recovers from queue failure and player restarts',function()
    local f=engine();f.load();f.press('F6');f.failQueue=true;f.loop()
    check(#f.events==0 and #f.queue==0,'game-thread scheduling failure cannot leak engine calls')
    f.failQueue=false;f.loop();f.flush()
    check(not f.collision and f.movement.MovementMode==0,'queued action remains available after a scheduling retry')
    f.loop();check(#f.queue==1,'active trainer has a pending update before player restart')
    f.inGame=true;local result=f.restart();f.inGame=false
    check(result==nil,'player restart observation does not override engine return values')
    check(f.collision and f.movement.MovementMode==1,'player restart hook restores current player physics')
    f.flush();f.loop()
    check(#f.queue==0 and f.collision and f.movement.MovementMode==1,'pre-restart queued update cannot reactivate or move the player')
    f.finish()
end)

case('adapter rejects unknown input names and preserves later engine movement',function()
    local f=engine();f.load();f.press('F6');f.step(0);f.missingKey='W';f.pressed.W=true;f.step(0.02)
    check(f.collision and f.movement.MovementMode==1,'missing native key stops and restores instead of silently using an invalid FKey')
    f.finish()
    local changed=engine();changed.load();changed.press('F6');changed.step(0);changed.movement.MovementMode=3;changed.step(0.02)
    check(changed.movement.MovementMode==3,'cleanup preserves a movement mode later selected by the game')
    check(changed.collision,'cleanup still restores trainer-owned disabled collision')
    changed.finish()
end)

case('adapter selects a local character and rejects unavailable actors',function()
    local remote=engine();remote.pc.localController=false;remote.load();remote.press('F6');remote.step(0)
    check(remote.collision and remote.movement.MovementMode==1,'remote controller is never modified')
    remote.finish()
    local missing=engine();missing.movement.valid=false;missing.load();missing.press('F6');missing.step(0)
    check(missing.collision and missing.movement.MovementMode==1,'invalid native movement component cannot enable noclip')
    missing.finish()
    local invalid=engine();invalid.pawn.valid=false;invalid.load();invalid.press('F6');invalid.step(0)
    check(invalid.collision and invalid.movement.MovementMode==1,'invalid native pawn cannot enable noclip')
    invalid.finish()
end)

case('native no-motion return and refused return are distinguished',function()
    local still=engine();still.load();still.press('F6');still.step(0);still.falseWhenUnmoved=true;still.press('F10');still.step(0.01)
    check(still.collision and still.movement.MovementMode==1,'F10 at the entry point succeeds even when Unreal reports no movement')
    check(samePosition(still.position,{X=10,Y=20,Z=30}),'already-at-entry return does not change position')
    still.finish()
    local refused=engine();refused.load();refused.press('F6');refused.step(0);refused.pressed.W=true;refused.step(0.02);refused.pressed.W=false
    local away=copy(refused.position);refused.rejectLocation=true;refused.press('F10');refused.step(0.01)
    check(not refused.collision and refused.movement.MovementMode==0 and samePosition(away,refused.position),'real refused native return retains collision-free flight')
    refused.rejectLocation=false;refused.press('F10');refused.step(0.01)
    check(refused.collision and refused.movement.MovementMode==1 and samePosition(refused.position,{X=10,Y=20,Z=30}),'native return retry reaches entry before restoring physics')
    refused.finish()
end)

case('destroyed movement cleanup verifies the original pawn identity first',function()
    local f=engine();f.load();local adapter=require('adapter');f.inGame=true
    local ctx=assert(adapter.resolve());local snapshot=adapter.capture(ctx);adapter.apply(ctx)
    check(type(snapshot.pawnIdentity)=='string' and #snapshot.pawnIdentity>0,'snapshot independently records original pawn identity')
    f.movement.valid=false;f.events={};check(adapter.restore(snapshot)==true,'same pawn with removed movement component can finish cleanup')
    check(f.collision,'same pawn collision is restored even after movement component destruction')
    f.inGame=false;f.finish()
    local reused=engine();reused.load();adapter=require('adapter');reused.inGame=true
    ctx=assert(adapter.resolve());snapshot=adapter.capture(ctx);adapter.apply(ctx)
    reused.movement.valid=false;reused.pawnName='Character /Game/NewMap.PersistentLevel.NewPawn';reused.collision=false;reused.events={}
    check(adapter.restore(snapshot)==true,'reused object identity is acknowledged without restoring an obsolete snapshot')
    check(not reused.collision,'a reused pawn does not receive the old pawn collision state')
    local wrote=false
    for _,e in ipairs(reused.events)do if e=='SetActorEnableCollision' or e=='SetMovementMode'then wrote=true end end
    check(not wrote,'pawn identity is checked before the invalid-component collision restoration branch')
    reused.inGame=false;reused.finish()
end)

case('non-finite engine data stops before unsafe movement',function()
    local capture=fixture();capture.original.position.X=0/0;pcall(function()capture.core:toggle()end)
    check(not capture.core:isEnabled() and capture.original.collision and capture.original.mode==1,'non-finite initial position is refused before writes')
    local clock=fixture();clock.enable();clock.clock=math.huge;clock.core:tick()
    check(not clock.core:isEnabled() and clock.original.collision and clock.original.mode==1,'non-finite time restores rather than generating an infinite teleport')
    local view=fixture();view.enable();view.rotation.Pitch=0/0;view.keys={forward=true};view.tick(0.02)
    check(not view.core:isEnabled() and view.original.collision and view.original.mode==1,'non-finite aim rotation stops and restores noclip')
end)

case('packaged startup settings disable unsafe script hot reload',function()
    local handle=assert(io.open(TRAINER_ROOT..'/Runtime/UE4SS-settings.ini','rb'))
    local text=handle:read('*a');handle:close()
    check(text:match('EnableHotReloadSystem%s*=%s*0')~=nil,'stable UE4SS hot reload is disabled to avoid orphaned movement state')
    check(text:match('GuiConsoleEnabled%s*=%s*0')~=nil and text:match('GuiConsoleVisible%s*=%s*0')~=nil,'normal trainer startup does not open a debug GUI')
end)

case('god mode and post-flight landing guard preserve original damage permission',function()
    local P=require('protection')
    local ctx={identity='A',damage=true};local current=ctx;local clock=0;local grounded=true
    local a={resolve=function()return current end,same=function(c,v)return c.identity==v.identity end,
      captureDamage=function(c)return{ctx=c,identity=c.identity,damage=c.damage}end,
      disableDamage=function(c)c.damage=false end,restoreDamage=function(v)v.ctx.damage=v.damage end,
      grounded=function()return grounded end,time=function()return clock end,log=function()end}
    local p=P.new(a)
    p:tick(false);check(ctx.damage,'initial state unchanged')
    p:toggle();p:tick(false);check(not ctx.damage,'manual god mode blocks damage')
    p:toggle();p:tick(false);check(not ctx.damage,'off retains landing grace')
    clock=0.8;p:tick(false);check(ctx.damage,'off restores original damage')
    p:tick(true);check(not ctx.damage,'flight automatically protects')
    p:tick(false);check(not ctx.damage,'first walking frame does not remove flight protection')
    grounded=false;clock=1;p:tick(false);check(not ctx.damage,'fall retains protection')
    grounded=true;clock=10;p:tick(false);check(not ctx.damage,'landing starts grace after impact')
    clock=10.8;p:tick(false);check(ctx.damage,'settled landing restores damage')
    ctx.damage=false;p:toggle();p:tick(false);p:reset();check(not ctx.damage,'preexisting invulnerability preserved')
    ctx.damage=true;p:toggle();p:tick(false);current={identity='B',damage=true};p:tick(false)
    check(ctx.damage,'old pawn restored when possession changes')
    check(not current.damage,'manual god applies to new controlled character')
    p:reset();check(current.damage and not p:hasWork(),'restart restores original permission and disables god mode')
end)

dofile(TRAINER_ROOT..'/tests/vehicle_regressions.lua')(check,case)
dofile(TRAINER_ROOT..'/tests/menu_regressions.lua')(check,case)
dofile(TRAINER_ROOT..'/tests/spawn_regressions.lua')(check,case)
dofile(TRAINER_ROOT..'/tests/player_vehicle_regressions.lua')(check,case)

TEST_PRINT(string.format('RESULT: %d assertions; %d failures.',TEST_ASSERTIONS,TEST_FAILURES))
