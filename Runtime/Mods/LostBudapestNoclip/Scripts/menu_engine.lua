-- Queue native HUD text on the game thread; Unreal owns its PostRender drawing.
-- Does not require a Blueprint ReceiveDrawHUD implementation or canvas hooks.
local adapter=require('adapter')
local Engine={log=adapter.log}
local function valid(v)return v~=nil and v:IsValid()end
local function id(v)return tostring(v:GetAddress())..':'..v:GetFullName()end
local function finite(v)return type(v)=='number' and v==v and math.abs(v)<1e9 end
local function vector(v)return v and finite(v.X) and finite(v.Y) and finite(v.Z)end
local cachedFont
local function fontObject(value)
    if not valid(value) or value:GetFullName():find('Default__',1,true) then return false end
    local class=value:GetClass()
    for _=1,8 do
        if not valid(class) then return false end
        if class:GetFullName()=='Class /Script/Engine.Font' then return true end
        class=class:GetSuperStruct()
    end
    return false
end
local function menuFont()
    if fontObject(cachedFont) then return cachedFont end
    for _,kind in ipairs({'GameEngine','Engine'})do
        for _,engine in ipairs(FindAllOf(kind) or {})do
            if valid(engine) and not engine:GetFullName():find('Default__',1,true) then
                for _,field in ipairs({'SmallFont','MediumFont','TinyFont'})do
                    local ok,font=pcall(function()return engine[field]end)
                    if ok and fontObject(font) then cachedFont=font;return font end
                end
            end
        end
    end
    local paths={'/Engine/EngineFonts/Roboto.Roboto','/Engine/EngineFonts/RobotoDistanceField.RobotoDistanceField','/Engine/EngineFonts/SmallFont.SmallFont'}
    for _,path in ipairs(paths)do
        local ok,font=pcall(StaticFindObject,path)
        if ok and fontObject(font) then cachedFont=font;return font end
    end
    for _,font in ipairs(FindAllOf('Font') or {})do
        if fontObject(font) then cachedFont=font;return font end
    end
    if type(LoadAsset)=='function' then
        for _,path in ipairs(paths)do
            local ok,font=pcall(LoadAsset,path)
            if ok and fontObject(font) then cachedFont=font;return font end
        end
    end
    error('No usable canvas font is available for the trainer menu',0)
end
function Engine.context()
    local ctx=adapter.playerContext()
    if not ctx or adapter.gameplay():IsGamePaused(ctx.pawn) or ctx.controller.bShowMouseCursor
        or ctx.controller:IsMoveInputIgnored() or ctx.controller:IsLookInputIgnored() then return nil end
    return {pc=ctx.controller,pawn=ctx.pawn,pcId=id(ctx.controller),pawnId=id(ctx.pawn)}
end
function Engine.current(saved)
    local ctx=adapter.playerContext()
    return ctx and id(ctx.controller)==saved.pcId and id(ctx.pawn)==saved.pawnId
        and not adapter.gameplay():IsGamePaused(ctx.pawn) and not ctx.controller.bShowMouseCursor
end
function Engine.capture(saved)
    return {pc=saved.pc,pcId=saved.pcId}
end
function Engine.lock(state)
    state.pc:SetIgnoreMoveInput(true);state.move=true
    state.pc:SetIgnoreLookInput(true);state.look=true
    adapter.menuOpen=true
end
function Engine.unlock(state)
    adapter.menuOpen=false
    if not valid(state.pc) or id(state.pc)~=state.pcId then return end
    if state.look then state.pc:SetIgnoreLookInput(false);state.look=false end
    if state.move then state.pc:SetIgnoreMoveInput(false);state.move=false end
end
function Engine.input(saved)
    local function down(name)return saved.pc:IsInputKeyDown({KeyName=FName(name,EFindName.FNAME_Find)})end
    return {up=down('Up'),down=down('Down'),left=down('Left'),right=down('Right'),accept=down('Enter'),back=down('BackSpace')}
end
function Engine.present(saved,text,duration)
    local hud=saved.pc:GetHUD()
    assert(valid(hud) and valid(hud.PlayerOwner) and id(hud.PlayerOwner)==saved.pcId,'The local player has no native HUD')
    -- UE4SS 3.0.1 doesn't consume scalar out-parameter tables: both values
    -- are written into the first one. One shared table supports that ABI and
    -- engines/loaders that correctly consume each supplied output argument.
    local size={};saved.pc:GetViewportSize(size,size)
    local width,height=size.SizeX,size.SizeY
    assert(finite(width) and finite(height) and width>=320 and height>=240,'The game viewport is unavailable')
    local origin,direction={},{}
    assert(saved.pc:DeprojectScreenPositionToWorld(32,40,origin,direction) and vector(origin) and vector(direction),'Could not position native HUD menu')
    local point={X=origin.X+direction.X*1000,Y=origin.Y+direction.Y*1000,Z=origin.Z+direction.Z*1000}
    -- Use the HUD actor as our text key, not the pawn or another gameplay actor.
    -- Flat vectors/color avoid the pinned loader's nested-struct marshaling bug.
    local font=menuFont()
    local scale=math.max(1,math.min(2,height/720))
    -- A nil ObjectProperty is not consumed by the stable loader. Passing nil
    -- here shifts the following float argument and silently makes FontScale=0.
    hud:AddDebugText(text,hud,duration,point,point,{R=225,G=255,B=235,A=255},false,true,false,font,scale,true)
    saved.hud=hud;saved.hudId=id(hud)
    local readable,queue=pcall(function()
        local entries=hud.DebugTextList
        local count=entries:GetArrayNum()
        assert(finite(count) and count>=0 and count<=4096,'Unreadable native text queue')
        for i=1,count do
            local entry=entries[i]
            if valid(entry.SrcActor) and id(entry.SrcActor)==saved.hudId then return {scale=entry.FontScale,font=entry.Font}end
        end
        return nil
    end)
    local nativeScale=readable and queue and queue.scale or 'unavailable'
    local diagnostic=saved.hudId..' '..width..'x'..height..' font='..font:GetFullName()..' requested-scale='..scale..' native-scale='..tostring(nativeScale)
    if Engine.lastDiagnostic~=diagnostic then
        Engine.lastDiagnostic=diagnostic
        -- Technical diagnostics belong in the log, not in the menu's notices.
        print('[Lost Budapest menu] '..diagnostic..'\n')
    end
    if readable and queue then assert(finite(queue.scale) and queue.scale>0,'The native HUD text scale is zero')end
end
function Engine.clear(saved)
    if saved and valid(saved.hud) and id(saved.hud)==saved.hudId then saved.hud:RemoveDebugText(saved.hud,false)end
end
return Engine
