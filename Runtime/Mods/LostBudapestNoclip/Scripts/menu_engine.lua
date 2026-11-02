-- Queue native HUD text on the game thread; Unreal owns its PostRender drawing.
-- Does not require a Blueprint ReceiveDrawHUD implementation or canvas hooks.
local adapter=require('adapter')
local Engine={log=adapter.log}
local function valid(v)return v~=nil and v:IsValid()end
local function id(v)return tostring(v:GetAddress())..':'..v:GetFullName()end
local function finite(v)return type(v)=='number' and v==v and math.abs(v)<1e9 end
local function vector(v)return v and finite(v.X) and finite(v.Y) and finite(v.Z)end
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
    hud:AddDebugText(text,hud,duration,point,point,{R=225,G=255,B=235,A=255},false,true,false,nil,math.max(1,math.min(2,height/720)),true)
    saved.hud=hud;saved.hudId=id(hud)
end
function Engine.clear(saved)
    if saved and valid(saved.hud) and id(saved.hud)==saved.hudId then saved.hud:RemoveDebugText(saved.hud,false)end
end
return Engine
