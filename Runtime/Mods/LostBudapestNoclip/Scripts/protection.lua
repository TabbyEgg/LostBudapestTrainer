local Protection = {}
Protection.__index = Protection
function Protection.new(api)
    return setmetatable({api=api,manual=false,flight=false,landing=false,saved=nil,settled=nil},Protection)
end
function Protection:hasWork() return self.manual or self.landing or self.saved~=nil end
function Protection:restore()
    if self.saved then
        local ok,err=pcall(self.api.restoreDamage,self.saved)
        if not ok then self.api.log("Damage protection restoration pending: "..tostring(err));return false end
        self.saved=nil
    end
    self.settled=nil
end
function Protection:reset()
    self:restore()
    self.manual,self.flight,self.landing=false,false,false
end
function Protection:toggle()
    self.manual=not self.manual
    if not self.manual then self.landing=true end
    self.api.log(self.manual and "God mode on (player damage disabled)." or "God mode off; landing protection clears after reaching the ground.")
end
function Protection:tick(flying)
    if self.flight and not flying then self.landing=true end
    self.flight=flying
    local ctx=self.api.resolve()
    if self.saved and (not ctx or not self.api.same(ctx,self.saved)) then self:restore() end
    if not ctx then return end
    if self.manual or flying or self.landing then
        if not self.saved then
            local captured=self.api.captureDamage(ctx)
            if not captured then return end
            self.saved=captured
        end
        self.api.disableDamage(ctx)
    end
    if self.landing and not flying then
        if self.api.grounded(ctx) then
            local now=self.api.time(ctx)
            if not self.settled or now<self.settled then self.settled=now end
            if now-self.settled>=0.75 then self.landing=false;self.settled=nil end
        else self.settled=nil end
    end
    if not self.manual and not flying and not self.landing then self:restore() end
end
return Protection
