-- Menu model and hit testing are independent of Unreal. Native writes live in menu_engine.
local Menu={};Menu.__index=Menu
local colors={panel={R=.035,G=.045,B=.065,A=.96},row={R=.07,G=.085,B=.11,A=1},
    selected={R=.12,G=.23,B=.25,A=1},accent={R=.28,G=.88,B=.65,A=1},text={R=.92,G=.95,B=.97,A=1},
    muted={R=.62,G=.69,B=.74,A=1}}
function Menu.new(api,status,request)
    return setmetatable({api=api,status=status,request=request,open=false,selected=1,stale=0,
        previous={},message='Ready. Select a feature below.'},Menu)
end
function Menu:notice(text)
    self.message=tostring(text):gsub('[\r\n]',' '):sub(1,240);self.toastFrames=300
end
function Menu:hasWork()return self.open or (self.locked~=nil and (self.restoreAttempts or 0)<4) end
function Menu:close()
    self.open=false;self.context=nil;self.previous={};self.stale=0
    if self.locked then
        local ok,err=pcall(self.api.unlock,self.locked)
        if ok then self.locked=nil;self.restoreAttempts=0
        else
            self.restoreAttempts=(self.restoreAttempts or 0)+1
            if self.restoreAttempts==1 then self.api.log('Menu input restoration pending: '..tostring(err)) end
        end
    end
end
function Menu:toggle()
    if self.open or self.locked then self:close();return end
    local ok,ctx=pcall(self.api.context)
    if not ok or not ctx then self.api.log('Close the game menu and enter a level before opening the trainer menu.');return end
    self.context=ctx;self.open=true;self.stale=0;self.previous={};self.primed=false;self.drew=false
    self.api.log('Trainer menu requested; waiting for the HUD. F2 closes it.')
end
function Menu:tick()
    if self.locked and not self.open then
        if (self.restoreAttempts or 0)<4 then self:close() end
        return
    end
    if not self.open then return end
    local ok,current=pcall(self.api.current,self.context)
    self.stale=self.stale+1
    if not ok or not current or self.stale>180 then
        self:close()
        self.api.log('Trainer menu closed: player changed or HUD drawing unavailable. Hotkeys remain available.')
    end
end
function Menu:rows()
    local s=self.status()
    return {
        {label='Noclip',value=s.flying and 'ON' or 'OFF',action='toggle'},
        {label='God mode',value=s.god and 'ON' or (s.protected and 'AUTO GUARD' or 'OFF'),action='godmode',stay=true},
        {label='Flight speed',value=string.format('<  %g m/s  >',s.speed/100),action='faster',left='slower',right='faster',stay=true},
        {label='Return to flight start',value='F10',action='return'},
        {label='Vehicle model',value='<  '..s.model..'  >',action='cycleVehicle',left='previousVehicle',right='cycleVehicle',stay=true},
        {label='Vehicle boost',value=(s.boost or 0)>0 and ('<  '..s.boost..' km/h  >') or '<  OFF  >',action='boostFaster',left='boostSlower',right='boostFaster',stay=true},
        {label='Steering correction',value=s.steeringReady==false and 'UNAVAILABLE' or (s.steering and 'ON' or 'OFF'),action='steering',stay=true},
        {label='Spawn selected vehicle',value=string.format('%d spawned   F9',s.spawned or 0),action='spawnVehicle'},
        {label=s.driving and 'Exit trainer driving' or 'Enter nearby vehicle',value='F5',action='drive'},
        {label='Recover / repair vehicle',value='F1',action='repair'},
        {label='Write vehicle diagnostics',value='Home',action='diagnose'},
        {label='Close menu',value='F2 / Backspace',action='close'},
    }
end
function Menu:activate(row,direction)
    local action=direction=='left' and row.left or direction=='right' and row.right or row.action
    if not action then return end
    if action=='close' then self:close();return end
    -- Native actions needing a playable context run after our input locks clear.
    if not row.stay then self:close() end
    self.request(action)
end
function Menu:toast(raw)
    if (self.toastFrames or 0)<=0 then return end
    self.toastFrames=self.toastFrames-1
    local ok=pcall(function()
        local ctx=self.api.context()
        if not ctx then return end
        local hud,width,height=self.api.hud(raw,ctx)
        if not hud or type(width)~='number' or type(height)~='number' or width<320 or height<240 then return end
        local scale=math.min(1,width/800,height/500)
        self.api.rect(hud,colors.panel,24*scale,height-100*scale,740*scale,76*scale)
        for i=1,3 do
            self.api.text(hud,self.message:sub((i-1)*100+1,i*100),colors.text,38*scale,height-(88-(i-1)*21)*scale,.75*scale)
        end
    end)
    if not ok then self.toastFrames=0 end -- A render failure must not spam or affect gameplay.
end
function Menu:frame(raw)
    if not self.open then self:toast(raw);return end
    local ok,err=pcall(function()
        if not self.api.current(self.context) then self:close();return end
        local hud,width,height=self.api.hud(raw,self.context)
        if not hud or type(width)~='number' or type(height)~='number' or width<320 or height<240 then return end
        self.stale=0
        local rows=self:rows()
        local extra=math.max(0,#rows-10)*39
        local scale=math.max(.3,math.min(1.5,width/560,height/(690+extra)))
        local x,y=28*scale,28*scale
        local w,top,rh=500*scale,100*scale,39*scale
        local input=self.api.input(self.context)
        -- Ignore keys held when opening, including the mouse button that opened a game menu.
        if not self.primed then self.previous=input;self.primed=true end
        local function pressed(key)return input[key] and not self.previous[key] end
        if not self.locked then
            self.locked=self.api.capture(self.context)
            self.api.lock(self.locked)
        end
        if pressed('back') then self:close();return end
        if pressed('up') then self.selected=(self.selected-2)%#rows+1 end
        if pressed('down') then self.selected=self.selected%#rows+1 end
        local hover=nil
        if type(input.x)=='number' and type(input.y)=='number' and input.x>=x and input.x<x+w then
            local n=math.floor((input.y-y-top)/rh)+1
            if n>=1 and n<=#rows then hover=n end
        end
        if hover and (input.x~=self.previous.x or input.y~=self.previous.y) then self.selected=hover end
        local selected=rows[self.selected]
        if pressed('left') then self:activate(selected,'left')
        elseif pressed('right') then self:activate(selected,'right')
        elseif pressed('accept') then self:activate(selected)
        elseif hover and pressed('click') then
            self.selected=hover
            local direction=rows[hover].left and (input.x<x+w*.63 and 'left' or 'right') or nil
            self:activate(rows[hover],direction)
        end
        self.previous=input
        if not self.open then return end
        local function rect(c,a,b,cw,ch)self.api.rect(hud,c,a,b,cw,ch)end
        local function text(t,c,a,b,size)self.api.text(hud,t,c,a,b,size*scale)end
        rect(colors.panel,x,y,w,(608+extra)*scale)
        rect(colors.accent,x,y,4*scale,(608+extra)*scale)
        text('LOST BUDAPEST',colors.accent,x+20*scale,y+17*scale,1.15)
        text('TRAINER  /  0.4.1',colors.text,x+20*scale,y+48*scale,.85)
        text('F3: next car  |  F9: spawn  |  arrows + Enter',colors.muted,x+20*scale,y+75*scale,.72)
        for i,row in ipairs(rows) do
            local yy=y+top+(i-1)*rh
            rect(i==self.selected and colors.selected or colors.row,x+10*scale,yy,w-20*scale,rh-3*scale)
            text(row.label,colors.text,x+20*scale,yy+9*scale,.78)
            text(row.value,colors.accent,x+265*scale,yy+9*scale,.71)
        end
        text('LATEST MESSAGE',colors.muted,x+20*scale,y+(505+extra)*scale,.68)
        local message=self.message
        for i=1,3 do text(message:sub((i-1)*64+1,i*64),colors.text,x+20*scale,y+(525+extra+(i-1)*21)*scale,.67) end
        if not self.drew then self.drew=true;self.api.log('Trainer menu drawn successfully.')end
    end)
    if not ok then self:close();self.api.log('Trainer menu stopped safely: '..tostring(err)) end
end
return Menu
