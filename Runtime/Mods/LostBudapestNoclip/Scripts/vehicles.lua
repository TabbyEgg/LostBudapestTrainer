local Vehicles = {}
Vehicles.__index = Vehicles
Vehicles.catalog = {
    {name="Abel's car",path="/Game/Autok/Abel_Car.Abel_Car_C"},
    {name="Estate (traffic)",path="/Game/Traffic_AI_System/Cars/Estate/BP_Estate.BP_Estate_C"},
    {name="Hatchback (traffic)",path="/Game/Traffic_AI_System/Cars/Hatch/BP_Hatch.BP_Hatch_C"},
    {name="Liftback (traffic)",path="/Game/Traffic_AI_System/Cars/Liftback/BP_Liftback.BP_Liftback_C"},
    {name="Luxury (traffic)",path="/Game/Traffic_AI_System/Cars/Luxury/BP_Luxury.BP_Luxury_C"},
    {name="Van 1 (traffic)",path="/Game/Traffic_AI_System/Cars/Van/BP_Van_1.BP_Van_1_C"},
    {name="Van 2 (traffic)",path="/Game/Traffic_AI_System/Cars/Van/BP_Van_2.BP_Van_2_C"},
}
function Vehicles.new(api) return setmetatable({api=api,selected=1,spawned={},driver=nil},Vehicles) end
function Vehicles:hasWork() return self.driver~=nil and not self.driverFailed end
function Vehicles:drive()
    if self.driver then
        local ok,result=pcall(self.api.exitDriver,self.driver)
        if ok and result~=false then self.driver=nil;self.driverFailed=false;self.api.log("Trainer driving off; returned to your character.");return true end
        self.api.log("Could not leave trainer driving safely; try F5 again.");return false
    end
    local state
    local ok,err=pcall(function()
        local ctx=assert(self.api.player(),"Enter a level on foot first")
        local target=assert(self.api.repairTarget(ctx,self.spawned),"Stand near Abel's car or a trainer-spawned car")
        state=self.api.captureDriver(ctx,target)
        self.api.enterDriver(state)
        self.driver=state;self.driverFailed=false
        self.api.log("Trainer driving on. W forward; S reverse; A/D steer; Space brake; F5 exit.")
    end)
    if not ok then
        if state then
            local restored,result=pcall(self.api.exitDriver,state)
            if not restored or result==false then self.driver=state end
        end
        self.api.log("Could not start trainer driving: "..tostring(err));return false
    end
    return true
end
function Vehicles:tick()
    if not self.driver or self.driverFailed then return end
    local ok,err=pcall(self.api.driveTick,self.driver)
    if not ok then
        self.driverFailed=true
        self.api.log("Trainer driving stopped: "..tostring(err))
        self:drive()
    end
end
function Vehicles:cycle(direction)
    self.selected=(self.selected-1+(direction or 1)) % #self.catalog+1
    self.api.log("Selected vehicle: "..self.catalog[self.selected].name..". F9 spawns; F2 selects next.")
end
function Vehicles:spawn()
    local alive={}
    for _,actor in ipairs(self.spawned) do if self.api.valid(actor) then alive[#alive+1]=actor end end
    self.spawned=alive
    if #alive>=5 then self.api.log("Five trainer-spawned vehicles are still loaded; spawn limit reached.");return false end
    local actor
    local stage="player availability"
    local ok,err=xpcall(function()
        local ctx=assert(self.api.player(),"Enter a level before spawning a vehicle")
        local option=self.catalog[self.selected]
        stage="resolve loaded class: "..option.name
        local class=assert(self.api.class(option.path),"This car blueprint is not loaded in this level; select another")
        stage="player spawn transform"
        local transform=self.api.spawnTransform(ctx)
        stage="native engine spawn"
        actor=self.api.begin(ctx,class,transform)
        assert(self.api.valid(actor),"No clear spawn position; move to an open area")
        stage="configure new vehicle"
        self.api.prepare(actor)
        stage="finish vehicle construction"
        local finished=self.api.finish(actor,transform)
        assert(self.api.valid(finished),"The game did not finish constructing the car")
        actor=finished
        self.spawned[#self.spawned+1]=actor
        self.api.log("Spawned "..option.name..". Use the game's normal enter-vehicle interaction. Traffic cars may not support player entry; F5 provides trainer driving.")
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
