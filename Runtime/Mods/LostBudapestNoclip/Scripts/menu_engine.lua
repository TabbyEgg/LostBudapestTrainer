-- Native HUD canvas adapter for UE4SS 3.0.1. Runs only on the game thread.
local adapter=require('adapter')
local Engine={log=adapter.log}
local watched={}
local function valid(v)return v~=nil and v:IsValid() end
local function id(v)return tostring(v:GetAddress())..':'..v:GetFullName() end
local function unwrap(v)
    if type(v)=='number' then return v end
    local ok,result=pcall(function()return v:get()end)
    return ok and result or v
end
function Engine.context()
    local ctx=adapter.playerContext()
    if not ctx or adapter.gameplay():IsGamePaused(ctx.pawn) or ctx.controller.bShowMouseCursor
        or ctx.controller:IsMoveInputIgnored() or ctx.controller:IsLookInputIgnored() then return nil end
    -- Blueprint event fast calls can enter the HUD ubergraph directly, bypassing
    -- the ReceiveDrawHUD stub. Also watch its real loaded class's ubergraph.
    if Engine.callback then
        for _,hud in ipairs(FindAllOf('HUD') or {}) do
            if valid(hud) then
                local name=hud:GetClass():GetFullName():match('%.([^%.]+)_C$')
                if name and not watched[name] then
                    watched[name]=true
                    local ok,err=pcall(RegisterCustomEvent,'ExecuteUbergraph_'..name,Engine.callback)
                    if not ok then Engine.log('HUD graph callback unavailable: '..tostring(err))end
                end
            end
        end
    end
    return {pc=ctx.controller,pawn=ctx.pawn,pcId=id(ctx.controller),pawnId=id(ctx.pawn)}
end
function Engine.current(saved)
    local ctx=adapter.playerContext()
    return ctx and id(ctx.controller)==saved.pcId and id(ctx.pawn)==saved.pawnId
end
function Engine.hud(raw,saved)
    local hud=unwrap(raw)
    if not valid(hud) or not valid(hud.PlayerOwner) or id(hud.PlayerOwner)~=saved.pcId then return nil end
    local canvas=hud.Canvas
    if not valid(canvas) then return nil end
    return hud,tonumber(canvas.SizeX),tonumber(canvas.SizeY)
end
function Engine.capture(saved)
    assert(type(saved.pc.bShowMouseCursor)=='boolean','Cannot capture cursor state')
    return {pc=saved.pc,pcId=saved.pcId,cursor=saved.pc.bShowMouseCursor}
end
function Engine.lock(state)
    state.pc:SetIgnoreMoveInput(true);state.move=true
    state.pc:SetIgnoreLookInput(true);state.look=true
    state.pc.bShowMouseCursor=true
    adapter.menuOpen=true
end
function Engine.unlock(state)
    adapter.menuOpen=false
    if not valid(state.pc) or id(state.pc)~=state.pcId then return end
    -- Pair our own ignore-input increments; never reset the game's full stack.
    if state.look then state.pc:SetIgnoreLookInput(false);state.look=false end
    if state.move then state.pc:SetIgnoreMoveInput(false);state.move=false end
    if state.pc.bShowMouseCursor==true then state.pc.bShowMouseCursor=state.cursor end
end
function Engine.input(saved)
    local x,y={},{}
    local hasMouse=saved.pc:GetMousePosition(x,y)
    local function down(name)
        return saved.pc:IsInputKeyDown({KeyName=FName(name,EFindName.FNAME_Find)})
    end
    return {x=hasMouse and x.LocationX or nil,y=hasMouse and y.LocationY or nil,
        click=down('LeftMouseButton'),up=down('Up'),down=down('Down'),left=down('Left'),right=down('Right'),
        accept=down('Enter'),back=down('BackSpace')}
end
function Engine.rect(hud,color,x,y,w,h)hud:DrawRect(color,x,y,w,h)end
function Engine.text(hud,text,color,x,y,scale)hud:DrawText(text,color,x,y,nil,scale,false)end
function Engine.register(callback)
    assert(type(RegisterCustomEvent)=='function','This loader does not expose HUD event callbacks')
    Engine.callback=callback
    RegisterCustomEvent('ReceiveDrawHUD',callback)
end
return Engine
