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
    local rows=f.menu:rows();check(rows[8].value:find('0 spawned',1,true) and rows[12].value=='F2 / Backspace','spawn count and close shortcut stay visible')
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
case('native HUD queue uses flat reflected parameters and owns only its text entry',function()
    local oldAdapter,oldEngine=package.loaded.adapter,package.loaded.menu_engine
    local oldName,oldEnum=FName,EFindName
    local pc={bShowMouseCursor=false,move=2,look=3,keys={}}
    function pc:IsValid()return true end;function pc:GetAddress()return 1 end;function pc:GetFullName()return'LocalPC'end
    function pc:SetIgnoreMoveInput(v)self.move=self.move+(v and 1 or -1)end
    function pc:SetIgnoreLookInput(v)self.look=self.look+(v and 1 or -1)end
    function pc:IsInputKeyDown(key)return self.keys[key.KeyName:ToString()] or false end
    function pc:GetViewportSize(x,y)x.SizeX=1280;y.SizeY=720 end
    function pc:DeprojectScreenPositionToWorld(x,y,origin,direction)
        assert(x==32 and y==40);origin.X=10;origin.Y=20;origin.Z=30;direction.X=1;direction.Y=0;direction.Z=0;return true
    end
    local hud={PlayerOwner=pc,calls=0}
    function hud:IsValid()return true end;function hud:GetAddress()return 2 end;function hud:GetFullName()return'LocalHUD'end
    function pc:GetHUD()return hud end
    function hud:AddDebugText(text,source,duration,offset,desired,color,skip,absolute,attached,font,scale,shadow)
        assert(source==self and duration==.5 and offset.X==1010 and offset.Y==20 and desired.Z==30)
        assert(color.R==225 and color.A==255 and skip==false and absolute==true and attached==false and font==nil and scale==1 and shadow==true)
        self.calls=self.calls+1;self.text=text
    end
    function hud:RemoveDebugText(source,leaveDuration)assert(source==self and leaveDuration==false);self.removed=true end
    package.loaded.adapter={log=function()end};package.loaded.menu_engine=nil
    FName=function(n)return{ToString=function()return n end}end;EFindName={FNAME_Find=0}
    local ok,err=pcall(function()
        local e=require('menu_engine');local saved={pc=pc,pcId='1:LocalPC'}
        e.present(saved,'Menu',.5);check(hud.calls==1 and hud.text=='Menu','native queue accepts a screen-positioned menu without Canvas/ReceiveDrawHUD')
        local state=e.capture(saved);e.lock(state)
        check(pc.move==3 and pc.look==4 and not pc.bShowMouseCursor and package.loaded.adapter.menuOpen,'keyboard UI adds one move/look lock and leaves cursor ownership alone')
        pc.keys.Enter=true;check(e.input(saved).accept,'keyboard polling still works with movement ignored')
        e.unlock(state);e.unlock(state)
        check(pc.move==2 and pc.look==3 and not package.loaded.adapter.menuOpen,'cleanup preserves preexisting lock counts and is repeatable')
        e.clear(saved);check(hud.removed,'only the HUD-keyed trainer text is removed')
        hud.PlayerOwner=nil;check(not pcall(e.present,saved,'Other player',.5),'foreign/unowned HUDs cannot receive the menu')
    end)
    package.loaded.adapter,package.loaded.menu_engine=oldAdapter,oldEngine;FName,EFindName=oldName,oldEnum
    if not ok then error(err)end
end)
end
