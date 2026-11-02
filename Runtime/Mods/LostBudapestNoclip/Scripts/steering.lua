-- Native keyboard-axis correction. Call only from queued game-thread work.
-- Rebuild copies temporary defaults into PlayerInput, then defaults are restored
-- immediately. Never call InvertAxis/SaveConfig/SaveKeyMappings: they persist data.
local Steering={};Steering.__index=Steering
local function valid(v)return v~=nil and v:IsValid()end
local function identity(v)return tostring(v:GetAddress())..':'..v:GetFullName()end
local function finite(v)return type(v)=='number' and v==v and math.abs(v)<1000000 end
function Steering.new(log)
    return setmetatable({active=false,needsRebuild=false,log=log or function()end},Steering)
end
local function restore(changes)
    local errors={}
    for i=#changes,1,-1 do
        local c=changes[i]
        if c.touched then
            local ok,err=pcall(function()
                assert(c.mapping.AxisName:ToString()==c.axis and c.mapping.Key.KeyName:ToString()==c.key,'The owned axis mapping changed')
                local value=c.mapping.Scale
                assert(value==c.original or value==-c.original,'The owned axis scale changed')
                if value~=c.original then c.mapping.Scale=c.original end
            end)
            if ok then c.touched=false else errors[#errors+1]=tostring(err)end
        end
    end
    return #errors==0,table.concat(errors,'; ')
end
local function restoreTwice(changes)
    local ok,err=restore(changes)
    if not ok then ok,err=restore(changes)end
    return ok,err
end
function Steering:report(err)
    err=tostring(err);self.failed=err
    if self.lastError~=err then self.lastError=err;self.log('Native keyboard steering correction unavailable: '..err)end
    return false,err
end
function Steering:settingsObject()
    if not self.settings or (not valid(self.settings) and not self.active and not self.pending and not self.needsRebuild) then
        self.settings=StaticFindObject('/Script/Engine.Default__InputSettings')
        assert(valid(self.settings),'InputSettings defaults are not available')
        self.settingsId=identity(self.settings)
    end
    assert(valid(self.settings) and identity(self.settings)==self.settingsId,'InputSettings defaults changed')
    return self.settings
end
function Steering:reset()
    if not self.active and not self.pending and not self.needsRebuild then self.failed=nil;self.lastError=nil;return true end
    local ok,err=pcall(function()
        local settings=self:settingsObject()
        if self.pending then
            local restored,why=restoreTwice(self.pending)
            assert(restored,'Could not restore temporary input defaults: '..tostring(why))
            self.pending=nil
        end
        if self.active or self.needsRebuild then
            self.needsRebuild=true
            settings:ForceRebuildKeymaps()
        end
        self.active=false;self.needsRebuild=false
    end)
    if not ok then return self:report(err)end
    self.failed=nil;self.lastError=nil;return true
end
local function changesFor(settings)
    local array=settings.AxisMappings;local count=array:GetArrayNum()
    assert(finite(count) and count>=0 and count<=4096 and count%1==0,'Unsupported native axis mapping array')
    local groups={}
    for i=1,count do
        local mapping=array[i]
        local key=mapping.Key.KeyName:ToString()
        if key=='A' or key=='D' then
            local axis=mapping.AxisName:ToString();local scale=mapping.Scale
            assert(finite(scale),'Invalid native axis scale')
            if axis~='None' and axis~='' and scale~=0 then
                local g=groups[axis] or {A={},D={}};groups[axis]=g
                g[key][#g[key]+1]={mapping=mapping,original=scale,axis=axis,key=key}
            end
        end
    end
    local changes={}
    for _,g in pairs(groups)do
        if #g.A==1 and #g.D==1 and g.A[1].original*g.D[1].original<0 then
            changes[#changes+1]=g.A[1];changes[#changes+1]=g.D[1]
        end
    end
    assert(#changes>0,'No unique opposite A/D axis mapping pair is available')
    return changes
end
function Steering:update(enabled)
    if not enabled then return self:reset()end
    if self.failed then return false,self.failed end
    if self.active then return true end
    local ok,err=pcall(function()
        local settings=self:settingsObject()
        self.pending=changesFor(settings)
        for _,c in ipairs(self.pending)do
            c.touched=true;c.mapping.Scale=-c.original
        end
        self.needsRebuild=true
        settings:ForceRebuildKeymaps()
    end)
    local restored,why=true,nil
    if self.pending then restored,why=restoreTwice(self.pending);if restored then self.pending=nil end end
    if not restored then return self:report('Could not restore temporary input defaults: '..tostring(why))end
    if not ok then
        -- A rebuild may have copied only some players before failing. Rebuild
        -- normal defaults again after rollback rather than leaving inverted input.
        if self.needsRebuild then
            local recovered,recoveryError=pcall(function()self:settingsObject():ForceRebuildKeymaps()end)
            if recovered then self.needsRebuild=false else err=tostring(err)..'; recovery rebuild: '..tostring(recoveryError)end
        end
        return self:report(err)
    end
    self.active=true;self.needsRebuild=false;self.lastError=nil
    return true
end
return Steering
