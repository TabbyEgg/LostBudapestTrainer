return function(check,case)
local Menu=require('menu')
local function fixture()
    local f={input={},current=true,presents=0,locks=0,unlocks=0,clears=0,requests={},logs={}}
    local api={log=function(m)f.logs[#f.logs+1]=m end}
    function api.context()if not f.unavailable then return {}end end
    function api.current()return f.current end
    function api.capture()return{}end
    function api.lock()f.locks=f.locks+1;if f.failLock then error('partial input lock')end end
    function api.unlock()f.unlocks=f.unlocks+1 end
    function api.input()return f.input end
    function api.present(ctx,text,duration)
        if f.failPresent then error('HUD unavailable')end
        f.presents=f.presents+1;f.text=text;f.duration=duration
    end
    function api.clear()f.clears=f.clears+1 end
    f.menu=Menu.new(api,function()return {flying=true,god=false,protected=true,speed=600,model="Abel's car",driving=false}end,
        function(action)f.requests[#f.requests+1]={action=action,menuOpen=f.menu.open,unlocked=f.unlocks>0}end)
    function f.tick(input)f.input=input or {};f.menu:tick()end
    return f
end
case('native text menu does not depend on a Blueprint canvas event',function()
    local f=fixture();f.menu:notice('startup');check(not f.menu:hasWork() and f.presents==0,'startup messages never start world polling')
    f.unavailable=true;f.menu:toggle();check(not f.menu.open and f.locks==0,'unplayable context cannot lock controls')
    f.unavailable=false;f.menu:toggle();check(f.menu.open and f.locks==0,'opening waits for successful native text submission')
    f.tick();check(f.presents==1 and f.locks==1 and f.text:find('LOST BUDAPEST TRAINER',1,true),'queued tick submits the menu without any HUD script callback')
    check(f.text:find('> Noclip',1,true) and f.text:find('Vehicle model',1,true) and f.text:find('F3: next car',1,true),'native text includes selection, live features and car shortcut')
    f.tick();check(f.locks==1,'refreshes never stack additional input locks')
    f.current=false;f.tick();check(not f.menu.open and f.unlocks==1 and f.clears==1,'player change clears our text and restores controls')
end)
case('native menu keyboard edges dispatch actions after restoring input',function()
    local f=fixture();f.menu:toggle();f.tick({accept=true});check(#f.requests==0,'Enter held before opening cannot activate a feature')
    f.tick({});f.tick({accept=true})
    check(#f.requests==1 and f.requests[1].action=='toggle' and not f.requests[1].menuOpen and f.requests[1].unlocked,'noclip activation follows menu cleanup')
    f.menu:toggle();f.tick();f.tick({down=true});f.tick();f.tick({down=true});f.tick();f.tick({right=true});f.tick({right=true})
    check(#f.requests==2 and f.requests[2].action=='faster' and f.menu.open,'speed adjustment stays open and held arrows do not repeat')
    f.tick();f.tick({back=true});check(not f.menu.open and f.unlocks==2,'Backspace closes without leaking either input lock')
    local spawn,close,steering
    for _,row in ipairs(f.menu:rows())do
        if row.action=='spawnVehicle' then spawn=row end
        if row.action=='close' then close=row end
        if row.action=='steering' or row.label=='Keyboard steering fix' then steering=row end
    end
    check(spawn and spawn.value:find('0 spawned',1,true) and close and close.value=='F2 / Backspace','spawn count and close shortcut stay visible')
    check(not steering,'automatic keyboard steering correction has no menu option')
end)
case('native text failure and partial input capture never leave controls blocked',function()
    local f=fixture();f.menu:toggle();f.failPresent=true;f.tick()
    check(not f.menu.open and f.locks==0,'failed HUD submission never locks movement or look')
    local partial=fixture();partial.failLock=true;partial.menu:toggle();partial.tick()
    check(not partial.menu.open and partial.unlocks==1,'partial lock failure rolls back its captured state')
    local toast=fixture();toast.menu:notice('Selected vehicle: Estate');check(not toast.menu:hasWork(),'a notice alone does not wake the asynchronous scheduler')
    toast.tick();check(toast.presents==1 and toast.duration==2.5 and toast.locks==0,'an existing game-thread action can display car selection without locking input')
    toast.tick();check(toast.presents==1,'an unchanged notification is not submitted repeatedly')
end)
-- Model the relevant pinned-loader tail: UObject nil is not consumed;
-- FloatProperty then reads nil as zero. This is the actual 3.0.1 source behavior,
-- not a visual/rendering assertion or a replacement for the menu implementation.
local function decodeFontTail(font,scale,shadow)
    local stack={[1]=font,[2]=scale,[3]=shadow};local index=1
    local object=stack[index]
    if object~=nil then index=index+1 end
    local nativeScale=tonumber(stack[index]) or 0;index=index+1
    local nativeShadow=not not stack[index]
    return object,nativeScale,nativeShadow
end
case('nil UObject before trailing parameters reproduces the pinned zero-font-scale bug',function()
    local font,scale,shadow=decodeFontTail(nil,1.25,true)
    check(font==nil and scale==0 and shadow,'nil font leaves the argument on the stack and the native font scale becomes zero')
    local real={};font,scale,shadow=decodeFontTail(real,1.25,true)
    check(font==real and scale==1.25 and shadow,'a supplied font object is consumed and preserves the intended native scale')
end)
case('native HUD queue passes a real font and owns only its text entry',function()
    local oldAdapter,oldEngine=package.loaded.adapter,package.loaded.menu_engine
    local oldName,oldEnum,oldFind,oldFirst,oldStatic,oldLoad=FName,EFindName,FindAllOf,FindFirstOf,StaticFindObject,LoadAsset
    local pc={bShowMouseCursor=false,move=2,look=3,keys={}}
    function pc:IsValid()return true end;function pc:GetAddress()return 1 end;function pc:GetFullName()return'LocalPC'end
    function pc:SetIgnoreMoveInput(v)self.move=self.move+(v and 1 or -1)end
    function pc:SetIgnoreLookInput(v)self.look=self.look+(v and 1 or -1)end
    function pc:IsMoveInputIgnored()return self.move>0 end
    function pc:IsLookInputIgnored()return self.look>0 end
    function pc:IsInputKeyDown(key)return self.keys[key.KeyName:ToString()] or false end
    function pc:GetViewportSize(x,y)assert(x==y);x.SizeX=1280;x.SizeY=720 end
    function pc:DeprojectScreenPositionToWorld(x,y,origin,direction)
        assert(x==32 and y==40);origin.X=10;origin.Y=20;origin.Z=30;direction.X=1;direction.Y=0;direction.Z=0;return true
    end
    local function obj(name,address)
        local value={alive=true}
        function value:IsValid()return self.alive end
        function value:GetAddress()return address end
        function value:GetFullName()return name end
        return value
    end
    local fontClass=obj('Class /Script/Engine.Font',9)
    function fontClass:GetSuperStruct()return nil end
    local function font(name,address)
        local value=obj(name,address)
        function value:GetClass()return fontClass end
        function value:IsA(class)return class==fontClass or class=='/Script/Engine.Font' end
        return value
    end
    local currentFont=font('Font /Engine/EngineFonts/Roboto.Roboto',10)
    local defaultFont=font('Font /Script/Engine.Default__Font',11)
    local engine=obj('GameEngine /Engine/Transient.GameEngine_0',12);engine.SmallFont=currentFont
    local fontQueries,loads,fontsAvailable=0,0,true
    FindAllOf=function(kind)
        fontQueries=fontQueries+1
        if kind=='Engine' or kind=='GameEngine' then return {engine}end
        if kind=='Font' then return fontsAvailable and {defaultFont,currentFont} or {defaultFont}end
        return {}
    end
    FindFirstOf=function(kind)fontQueries=fontQueries+1;if kind=='Engine' or kind=='GameEngine' then return engine end;return fontsAvailable and currentFont or nil end
    StaticFindObject=function(path)
        fontQueries=fontQueries+1
        if path=='/Script/Engine.Font' then return fontClass end
        if fontsAvailable and (path:find('Roboto',1,true) or path:find('SmallFont',1,true)) then return currentFont end
    end
    LoadAsset=function(path)loads=loads+1;return nil,false,false end
    local hud={PlayerOwner=pc,calls=0}
    function hud:IsValid()return true end;function hud:GetAddress()return 2 end;function hud:GetFullName()return'LocalHUD'end
    function pc:GetHUD()return hud end
    function hud:AddDebugText(text,source,duration,offset,desired,color,skip,absolute,attached,suppliedFont,scale,shadow)
        assert(source==self and duration==.5 and offset.X==1010 and offset.Y==20 and desired.Z==30)
        assert(color.R==225 and color.A==255 and skip==false and absolute==true and attached==false and suppliedFont==currentFont and scale==1 and shadow==true)
        local nativeFont,nativeScale=decodeFontTail(suppliedFont,scale,shadow)
        assert(nativeFont==currentFont and nativeScale>0,'native text must not be submitted with a zero font scale')
        self.calls=self.calls+1;self.text=text;self.font=nativeFont;self.scale=nativeScale
    end
    function hud:RemoveDebugText(source,leaveDuration)assert(source==self and leaveDuration==false);self.removed=true end
    local pawn=obj('LocalPawn',3)
    local api={log=function()end,playerContext=function()return{controller=pc,pawn=pawn}end,gameplay=function()return{IsGamePaused=function()return false end}end}
    package.loaded.adapter=api;package.loaded.menu_engine=nil
    FName=function(n)return{ToString=function()return n end}end;EFindName={FNAME_Find=0}
    local ok,err=pcall(function()
        local e=require('menu_engine');local saved={pc=pc,pcId='1:LocalPC'}
        check(fontQueries==0 and loads==0,'requiring the native adapter does not search or load fonts during startup')
        e.present(saved,'Menu',.5)
        check(hud.calls==1 and hud.text=='Menu' and hud.font==currentFont and hud.scale==1,'the actual adapter passes a real font and preserves positive native font scale')
        local priorQueries=fontQueries;e.present(saved,'Refreshed',.5)
        check(fontQueries==priorQueries and loads==0,'a valid cached font is reused without a new object search or asset load')
        local queued={SrcActor=hud,FontScale=1,Font=currentFont}
        hud.DebugTextList={GetArrayNum=function()return 1 end,[1]=queued}
        local accepted=pcall(e.present,saved,'Verified native queue',.5)
        check(accepted and queued.FontScale>0 and queued.Font==currentFont and e.lastDiagnostic:find('native-scale=1',1,true),'a readable owned native queue entry verifies the positive scale and font after submission')
        queued.FontScale=0;e.lastDiagnostic=nil
        local zeroAccepted,zeroError=pcall(e.present,saved,'Rejected zero native scale',.5)
        check(not zeroAccepted and tostring(zeroError):find('native HUD text scale is zero',1,true),'native zero scale rejects submission even when the Lua font and scale arguments were valid')
        hud.DebugTextList=nil;e.lastDiagnostic=nil
        currentFont.alive=false;currentFont=font('Font /Game/UI/Replacement.Replacement',13);engine.SmallFont=currentFont
        e.present(saved,'New font',.5)
        check(hud.font==currentFont and fontQueries>priorQueries,'an invalidated cached font is reacquired before another native call')
        local state=e.capture(saved);e.lock(state)
        check(pc.move==3 and pc.look==4 and not pc.bShowMouseCursor and api.menuOpen,'keyboard UI adds one move/look lock and leaves cursor ownership alone')
        pc.keys.Enter=true;check(e.input(saved).accept,'keyboard polling still works with movement ignored')
        e.unlock(state);e.unlock(state)
        check(pc.move==2 and pc.look==3 and not api.menuOpen,'cleanup preserves preexisting lock counts and is repeatable')
        e.clear(saved);check(hud.removed,'only the HUD-keyed trainer text is removed')
        hud.PlayerOwner=nil;check(not pcall(e.present,saved,'Other player',.5),'foreign/unowned HUDs cannot receive the menu');hud.PlayerOwner=pc
        package.loaded.menu_engine=nil;fontsAvailable=false;engine.SmallFont=nil;currentFont.alive=false;pc.move=0;pc.look=0
        local missing=require('menu_engine');local before=hud.calls
        local menu=Menu.new(missing,function()return{flying=false,god=false,speed=600,model='Estate',driving=false}end,function()end)
        menu:toggle();menu:tick()
        check(not menu.open and pc.move==0 and pc.look==0 and hud.calls==before,'missing real fonts cannot submit invisible text or capture player input')
    end)
    package.loaded.adapter,package.loaded.menu_engine=oldAdapter,oldEngine
    FName,EFindName,FindAllOf,FindFirstOf,StaticFindObject,LoadAsset=oldName,oldEnum,oldFind,oldFirst,oldStatic,oldLoad
    if not ok then error(err)end
end)
end
