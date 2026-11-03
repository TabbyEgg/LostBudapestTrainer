local Vehicles = {}
Vehicles.__index = Vehicles
Vehicles.catalog = {
    {name="Abel's car",path="/Game/Autok/Abel_Car.Abel_Car_C"},
    {name="Estate",path="/Game/Traffic_AI_System/Cars/Estate/BP_Estate.BP_Estate_C"},
    {name="Hatchback",path="/Game/Traffic_AI_System/Cars/Hatch/BP_Hatch.BP_Hatch_C"},
    {name="Liftback",path="/Game/Traffic_AI_System/Cars/Liftback/BP_Liftback.BP_Liftback_C"},
    {name="Luxury",path="/Game/Traffic_AI_System/Cars/Luxury/BP_Luxury.BP_Luxury_C"},
    {name="Van 1",path="/Game/Traffic_AI_System/Cars/Van/BP_Van_1.BP_Van_1_C"},
    {name="Van 2",path="/Game/Traffic_AI_System/Cars/Van/BP_Van_2.BP_Van_2_C"},
}
function Vehicles.new(api)
    local catalog={}
    for i,entry in ipairs(Vehicles.catalog)do catalog[i]={name=entry.name,path=entry.path}end
    return setmetatable({api=api,catalog=catalog,selected=1,spawned={},driver=nil,boostIndex=1,boostSpeeds={0,60,100,150,200,300}},Vehicles)
end
function Vehicles:refreshCatalog()
    local ok,catalog,selected=pcall(function()
        local discovery=require('catalog')
        local current=self.catalog[self.selected]
        return discovery.merge(self.catalog,discovery.discover(),current and current.path)
    end)
    if not ok then return false end
    self.catalog,self.selected=catalog,selected
    return true
end

function Vehicles:count()
    local count=0
    for _,actor in ipairs(self.spawned) do if self.api.valid(actor) then count=count+1 end end
    return count
end
function Vehicles:hasWork() return (self.driver~=nil and not self.driverFailed) or self.boostIndex>1 end
function Vehicles:boost(direction)
    self.boostIndex=math.max(1,math.min(#self.boostSpeeds,self.boostIndex+(direction or 1)))
    local speed=self.boostSpeeds[self.boostIndex]
    self.api.log(speed==0 and "Vehicle boost off." or ("Vehicle boost target: "..speed.." km/h. Hold Shift + W while driving."))
end
local function startDriving(self,interaction)
    local state
    local stage,targetName='find walking player','unknown vehicle'
    local ok,err=pcall(function()
        local ctx
        if interaction then ctx=self.api.interactionContext() else ctx=self.api.player()end
        if interaction and not ctx then return end -- Native F already entered, or controls are unavailable.
        assert(ctx,"Enter a level on foot first")
        stage='select nearby vehicle'
        local target
        if interaction then
            target=self.api.interactionTarget(ctx,self.spawned)
            if not target then return end -- Leave normal game interactions alone.
        else target=assert((self.api.entryTarget or self.api.repairTarget)(ctx,self.spawned),"Stand within 25 metres of a trainer car (12 metres for Abel's original car)")end
        local named,value=pcall(function()return target:GetFullName()end)
        if named and type(value)=='string' then targetName=value end
        self.api.log('Entering '..targetName..(interaction and ' through nearby F fallback.' or ' through F5.'))
        stage='capture character state'
        state=self.api.captureDriver(ctx,target)
        state.interactionFallback=interaction==true
        stage='possess selected vehicle'
        self.api.enterDriver(state)
        self.driver=state;self.driverFailed=false
        self.api.log(state.native and (interaction and "Native car controls active. F or F5 exits." or "Abel car native controls and camera active. F5 exits.") or "Trainer driving on. W forward; S reverse; A/D steer; Space brake; F5 exit.")
    end)
    if not ok then
        if state then
            local restored,result=pcall(self.api.exitDriver,state)
            if not restored or result==false then self.driver=state end
        end
        self.api.log("Could not start trainer driving at "..stage.." for "..targetName..": "..tostring(err));return false
    end
    return self.driver~=nil
end
function Vehicles:drive()
    if self.driver then
        local ok,result=pcall(self.api.exitDriver,self.driver)
        if ok and result~=false then self.driver=nil;self.driverFailed=false;self.api.log("Trainer driving off; returned to your character.");return true end
        self.api.log("Could not leave trainer driving safely; try F5 again.");return false
    end
    return startDriving(self,false)
end
function Vehicles:interact()
    if self.driver then return self:drive()end
    return startDriving(self,true)
end
function Vehicles:tick()
    if not self.driver then
        if self.boostIndex>1 and self.api.boostControlled then
            local ok,err=pcall(self.api.boostControlled,self.boostSpeeds[self.boostIndex])
            if not ok then self.boostIndex=1;self.api.log("Vehicle boost stopped: "..tostring(err)) end
        end
        return
    end
    if self.driverFailed then return end
    local ok,err=pcall(self.api.driveTick,self.driver,self.boostSpeeds[self.boostIndex])
    if not ok then
        self.driverFailed=true
        self.api.log("Trainer driving stopped: "..tostring(err))
        self:drive()
    end
end
function Vehicles:cycle(direction)
    self.selected=(self.selected-1+(direction or 1)) % #self.catalog+1
    self.api.log("Selected vehicle: "..self.catalog[self.selected].name..". F9 spawns; F3 selects next.")
end
function Vehicles:spawn()
    local alive={}
    for _,actor in ipairs(self.spawned) do if self.api.valid(actor) then alive[#alive+1]=actor end end
    self.spawned=alive
    local actor
    local stage="player availability"
    local ok,err=xpcall(function()
        local ctx=assert(self.api.player(),"Enter a level before spawning a vehicle")
        local option=self.catalog[self.selected]
        stage="resolve loaded class: "..option.name
        local class=assert(self.api.class(option.path),"This car blueprint is not loaded in this level; select another")
        stage="player spawn transform"
        local transform=self.api.spawnTransform(ctx)
        stage="native engine spawn: "..option.name
        actor=self.api.begin(ctx,class,transform)
        assert(self.api.valid(actor),"No clear spawn position; move to an open area")
        stage="configure new vehicle"
        self.api.prepare(actor)
        stage="finish vehicle construction"
        local finished=self.api.finish(actor,transform)
        assert(self.api.valid(finished),"The game did not finish constructing the car")
        actor=finished
        self.spawned[#self.spawned+1]=actor
        self.api.log("Spawned "..option.name..". F5 enters/exits the nearby trainer vehicle.")
    end,function(e)return debug.traceback(tostring(e),2)end)
    if not ok then
        if actor and self.api.valid(actor) then pcall(self.api.destroy,actor) end
        self.api.log("Vehicle spawn cancelled at "..stage..": "..tostring(err));return false
    end
    return true
end
function Vehicles:repair()
    local ok,err=pcall(function()
        local ctx=assert(self.api.player(),"Enter a level first")
        local actor=assert(self.api.repairTarget(ctx,self.spawned),"Get within 12 metres of Abel's car or a trainer-spawned vehicle")
        local result=self.api.repair(actor)
        self.api.log(result)
    end)
    if not ok then self.api.log("Vehicle recovery stopped: "..tostring(err));return false end
    return true
end
return Vehicles
