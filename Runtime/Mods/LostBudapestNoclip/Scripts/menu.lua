-- Keyboard menu model. The adapter submits text to Unreal's native HUD queue.
local Menu={};Menu.__index=Menu
function Menu.new(api,status,request)
    return setmetatable({api=api,status=status,request=request,open=false,selected=1,previous={},message='Ready.'},Menu)
end
function Menu:notice(text)
    self.message=tostring(text):gsub('[\r\n]',' '):sub(1,210);self.dirty=true
end
function Menu:hasWork()return self.open or (self.locked~=nil and (self.restoreAttempts or 0)<4)end
function Menu:close()
    self.open=false;self.previous={}
    if self.context then pcall(self.api.clear,self.context)end
    self.context=nil
    if self.locked then
        local ok,err=pcall(self.api.unlock,self.locked)
        if ok then self.locked=nil;self.restoreAttempts=0
        else
            self.restoreAttempts=(self.restoreAttempts or 0)+1
            if self.restoreAttempts==1 then self.api.log('Menu input restoration pending: '..tostring(err))end
        end
    end
end
function Menu:toggle()
    if self.open or self.locked then self:close();return end
    local ok,ctx=pcall(self.api.context)
    if not ok or not ctx then self.api.log('Close the game menu and enter a level before opening the trainer menu.');return end
    self.context=ctx;self.open=true;self.previous={};self.primed=false;self.submitted=false
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
        {label='Keyboard steering fix',value=s.steering and 'ON' or 'OFF',action='steering',stay=true},
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
function Menu:contents()
    local lines={'LOST BUDAPEST TRAINER 0.4.4','F2 / Backspace: close | Arrows: select / adjust | Enter: activate',''}
    for i,row in ipairs(self:rows())do lines[#lines+1]=(i==self.selected and '> ' or '  ')..row.label..'  ['..row.value..']'end
    lines[#lines+1]='';lines[#lines+1]='F3: next car | F9: spawn selected'
    for i=1,3 do lines[#lines+1]=self.message:sub((i-1)*70+1,i*70)end
    return table.concat(lines,'\n')
end
function Menu:tick()
    if self.locked and not self.open then if (self.restoreAttempts or 0)<4 then self:close()end;return end
    if not self.open then
        -- Notices are submitted only when an existing queued action calls tick.
        -- Startup logs must not start polling the world or build a callback queue.
        if self.dirty then
            self.dirty=false
            pcall(function()local ctx=self.api.context();if ctx then self.api.present(ctx,self.message,2.5)end end)
        end
        return
    end
    local ok,err=pcall(function()
        if not self.api.current(self.context) then self:close();return end
        local input=self.api.input(self.context)
        if not self.primed then self.previous=input;self.primed=true end
        local function pressed(key)return input[key] and not self.previous[key]end
        local rows=self:rows()
        if pressed('back') then self:close();return end
        if pressed('up') then self.selected=(self.selected-2)%#rows+1 end
        if pressed('down') then self.selected=self.selected%#rows+1 end
        local row=rows[self.selected]
        if pressed('left') then self:activate(row,'left')
        elseif pressed('right') then self:activate(row,'right')
        elseif pressed('accept') then self:activate(row)end
        self.previous=input
        if not self.open then return end
        self.api.present(self.context,self:contents(),.5)
        if not self.locked then self.locked=self.api.capture(self.context);self.api.lock(self.locked)end
        self.dirty=false
        if not self.submitted then self.submitted=true;self.api.log('Menu submitted to native HUD text renderer.')end
    end)
    if not ok then self:close();self.api.log('Trainer menu unavailable: '..tostring(err))end
end
return Menu
