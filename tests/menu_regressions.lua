return function(check,case)
local Menu=require('menu')
local function fixture()
    local f={input={},current=true,draws=0,locks=0,unlocks=0,requests={},logs={}}
    local api={log=function(m)f.logs[#f.logs+1]=m end}
    function api.context()return f.unavailable and nil or {}end
    function api.current()return f.current end
    function api.hud()if not f.noHUD then return {},1280,690 end end
    function api.capture()return{}end
    function api.lock()f.locks=f.locks+1;if f.failLock then error('partial input lock')end end
    function api.unlock()f.unlocks=f.unlocks+1 end
    function api.input()return f.input end
    function api.rect()if f.failDraw then error('renderer unavailable')end;f.draws=f.draws+1 end
    function api.text()end
    f.menu=Menu.new(api,function()return {flying=true,god=false,protected=true,speed=600,model="Abel's car",driving=false}end,
        function(action)f.requests[#f.requests+1]={action=action,menuOpen=f.menu.open,unlocked=f.unlocks>0}end)
    function f.frame(input)f.input=input or {};f.menu:frame({})end
    return f
end
case('menu opens only with a playable context and a working local HUD',function()
    local f=fixture();f.menu:toggle();check(f.menu.open and f.locks==0,'opening defers input locks until a HUD actually draws')
    f.noHUD=true;for i=1,181 do f.menu:tick()end
    check(not f.menu.open and f.locks==0,'missing draw event times out without ever locking player input')
    f.noHUD=false;f.menu:toggle();f.frame();check(f.locks==1 and f.menu.open,'first verified HUD frame captures input exactly once')
    f.frame();check(f.locks==1,'later frames never stack additional ignore-input locks')
    f.current=false;f.menu:tick();check(not f.menu.open and f.unlocks==1,'pawn/map transition releases the menu input lock')
end)
case('menu mouse and keyboard edges dispatch one action and release locks first',function()
    local f=fixture();f.menu:toggle();f.frame({accept=true});check(#f.requests==0,'Enter held before opening cannot activate a feature')
    f.frame({});f.frame({accept=true})
    check(#f.requests==1 and f.requests[1].action=='toggle' and not f.requests[1].menuOpen and f.requests[1].unlocked,'noclip activation runs only after menu input is restored')
    f.menu:toggle();f.frame({});f.frame({down=true});f.frame({});f.frame({down=true});f.frame({});f.frame({right=true});f.frame({right=true})
    check(#f.requests==2 and f.requests[2].action=='faster' and f.menu.open,'speed changes remain in the menu and held keys do not repeat')
    local mouse=fixture();mouse.menu:toggle();mouse.frame({});mouse.frame({x=450,y=28+100+4*39+10,click=true})
    check(#mouse.requests==1 and mouse.requests[1].action=='cycleVehicle' and mouse.menu.open,'vehicle model right half cycles without closing')
    mouse.frame({x=450,y=28+100+4*39+10,click=true})
    check(#mouse.requests==1,'holding mouse button cannot flood spawn/selection requests')
    mouse.frame({});mouse.frame({back=true});check(not mouse.menu.open and mouse.unlocks==1,'Backspace closes and releases input')
end)
case('menu errors restore input and messages remain read-only notifications',function()
    local f=fixture();f.menu:toggle();f.failDraw=true;f.frame()
    check(not f.menu.open and f.unlocks==1,'drawing exception restores controls immediately')
    local partial=fixture();partial.failLock=true;partial.menu:toggle();partial.frame()
    check(not partial.menu.open and partial.unlocks==1,'partial input lock failure also rolls back')
    local toast=fixture();toast.menu:notice('Vehicle spawn failed: test');toast.frame()
    check(toast.draws>0 and toast.locks==0 and #toast.requests==0,'closed-menu error notification draws without touching player input')
    local rows=toast.menu:rows()
    check(rows[1].value=='ON' and rows[2].value=='LANDING GUARD' and rows[3].value:find('6 m/s',1,true),'menu displays current flight, landing protection and selected speed')
end)
case('native menu adapter uses named output parameters and balances input locks',function()
    local oldAdapter,oldEngine=package.loaded.adapter,package.loaded.menu_engine
    local oldName,oldEnum,oldFind,oldRegister=FName,EFindName,FindAllOf,RegisterCustomEvent
    local pc={bShowMouseCursor=false,move=2,look=3,keys={}}
    function pc:IsValid()return true end;function pc:GetAddress()return 1 end;function pc:GetFullName()return'PlayerController /World.PC'end
    function pc:SetIgnoreMoveInput(ignore)self.move=self.move+(ignore and 1 or -1)end
    function pc:SetIgnoreLookInput(ignore)self.look=self.look+(ignore and 1 or -1)end
    function pc:GetMousePosition(x,y)x.LocationX=123;y.LocationY=456;return true end
    function pc:IsInputKeyDown(key)return self.keys[key.KeyName:ToString()] or false end
    package.loaded.adapter={log=function()end};package.loaded.menu_engine=nil
    FName=function(n)return{ToString=function()return n end}end;EFindName={FNAME_Find=0}
    local ok,err=pcall(function()
        local engine=require('menu_engine');local state=engine.capture({pc=pc,pcId='1:PlayerController /World.PC'})
        engine.lock(state);check(pc.move==3 and pc.look==4 and pc.bShowMouseCursor and package.loaded.adapter.menuOpen,'menu adds exactly one move/look input lock')
        pc.keys.LeftMouseButton=true;local input=engine.input({pc=pc})
        check(input.x==123 and input.y==456 and input.click,'mouse positions use UE4SS LocationX/LocationY output tables')
        engine.unlock(state);check(pc.move==2 and pc.look==3 and not pc.bShowMouseCursor and not package.loaded.adapter.menuOpen,'closing preserves preexisting game input lock counts and original cursor')
        engine.unlock(state);check(pc.move==2 and pc.look==3,'repeated cleanup does not subtract another input lock')
        pc.move=0;pc.look=0
        function pc:IsMoveInputIgnored()return self.move>0 end
        function pc:IsLookInputIgnored()return self.look>0 end
        local pawn={};function pawn:IsValid()return true end;function pawn:GetAddress()return 2 end;function pawn:GetFullName()return'Pawn'end
        package.loaded.adapter.playerContext=function()return {controller=pc,pawn=pawn}end
        package.loaded.adapter.gameplay=function()return {IsGamePaused=function()return false end}end
        local hud={PlayerOwner=pc,Canvas={SizeX=1280,SizeY=720,IsValid=function()return true end}}
        function hud:IsValid()return true end
        function hud:GetClass()return {GetFullName=function()return'BlueprintGeneratedClass /Game/UI/ALS_HUD.ALS_HUD_C'end}end
        FindAllOf=function(kind)assert(kind=='HUD');return {hud}end
        local registered={}
        RegisterCustomEvent=function(name,callback)registered[#registered+1]=name end
        engine.register(function()end);local ctx=engine.context();engine.context()
        check(#registered==2 and registered[1]=='ReceiveDrawHUD' and registered[2]=='ExecuteUbergraph_ALS_HUD','loaded HUD fast-call fallback registers only once per class')
        local actual,width,height=engine.hud({get=function()return hud end},ctx)
        check(actual==hud and width==1280 and height==720,'drawing requires the local owner and an active HUD canvas')
        hud.Canvas=nil;check(engine.hud({get=function()return hud end},ctx)==nil,'non-render HUD graph calls without a canvas do not draw or lock controls')

    end)
    package.loaded.adapter,package.loaded.menu_engine=oldAdapter,oldEngine;FName,EFindName,FindAllOf,RegisterCustomEvent=oldName,oldEnum,oldFind,oldRegister
    if not ok then error(err)end
end)
end
