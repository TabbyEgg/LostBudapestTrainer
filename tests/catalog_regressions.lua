return function(check,case)
local Catalog=require('catalog')
local TRAFFIC='/Game/Traffic_AI_System/Cars/'
local function fixture()
    local f={classes={},actors={}}
    local function object(label)
        local value={alive=true,label=label}
        function value:IsValid()return self.alive end
        function value:GetFullName()return self.label end
        return value
    end
    f.base=object('Class /Script/PhysXVehicles.WheeledVehicle')
    f.otherBase=object('Class /Script/Engine.Actor')
    function f.otherBase:GetSuperStruct()return nil end
    function f.source()
        local mesh=object('SkeletalMeshComponent /World.ReadOnly.Mesh')
        mesh.SkeletalMesh=object('SkeletalMesh /Game/Body.Body');mesh.AnimClass=object('AnimBlueprintGeneratedClass /Game/Anim.Anim_C')
        mesh.AnimationMode=0;mesh.RelativeScale3D={X=1,Y=1,Z=1}
        function mesh:GetAnimInstance()return nil end
        function mesh:GetBoneIndex(name)return name:ToString():match('wheel[1-4]')and 1 or -1 end
        local movement=object('WheeledVehicleMovementComponent /World.ReadOnly.Movement')
        local values={}
        for i=1,4 do
            local bone='wheel'..i
            values[i]={BoneName={ToString=function()return bone end},WheelClass=object('BlueprintGeneratedClass /Game/Wheel.Wheel_C'),bDisableSteering=i>2}
        end
        movement.WheelSetups=setmetatable({GetArrayNum=function()return #values end},{__index=function(_,i)
            assert(i>=1 and i<=#values and i%1==0,'Wheel reads remain one-based and bounded');return values[i]
        end,__newindex=function()error('Wheel arrays are read-only')end})
        local source=object('WheeledVehicle /World.ReadOnly');source.Mesh=mesh;source.VehicleMovement=movement
        return source
    end
    function f.class(relative,source,base)
        local path=relative:sub(1,1)=='/'and relative or TRAFFIC..relative
        local class=object('BlueprintGeneratedClass '..path)
        function class:GetSuperStruct()return base or f.base end
        function class:GetCDO()return source end
        f.classes[#f.classes+1]=class
        return class
    end
    function f.live(class,source)
        function source:GetClass()return class end
        f.actors[#f.actors+1]=source
        return source
    end
    f.oldFind=FindAllOf
    FindAllOf=function(kind)
        f.reads=(f.reads or 0)+1
        if kind=='WheeledVehicle'then return f.actors end
        assert(kind=='BlueprintGeneratedClass')
        if f.failClasses then error('Class scan unavailable')end
        return f.classes
    end
    function f.finish()FindAllOf=f.oldFind end
    return f
end
local function run(fn)
    local f=fixture();local ok,err=pcall(fn,f);f.finish();if not ok then error(err)end
end
case('vehicle catalog import never probes a loading world',function()
    local previous,oldFind=package.loaded.catalog,FindAllOf
    package.loaded.catalog=nil
    FindAllOf=function()error('No engine reads during module import')end
    local ok,module=pcall(require,'catalog')
    FindAllOf=oldFind;package.loaded.catalog=previous
    check(ok and type(module.discover)=='function','Import defines discovery without querying classes or actors')
end)
case('loaded supported vehicle classes are discovered with deterministic names and paths',function()
    run(function(f)
        f.class('Van/BP_Van_2.BP_Van_2_C',f.source())
        f.class('Service/BP_DeliveryTruck.BP_DeliveryTruck_C',f.source())
        f.class('Hatch/BP_Hatch.BP_Hatch_C',f.source())
        f.class('Coupe/BP_Coupe.BP_Coupe_C',f.source())
        f.class('SUV/BP_SUV.BP_SUV_C',f.source())
        f.class('Sedan/BP_Sedan.BP_Sedan_C',f.source())
        f.class('/Game/Autok/Abel_Car.Abel_Car_C',f.source())
        f.class('Service/BP_DeliveryTruck.BP_DeliveryTruck_C',f.source())
        local list=Catalog.discover()
        check(#list==7,'Repeated loaded class references collapse by asset path')
        check(list[1].name=="Abel's car"and list[2].name=='Coupe (small Fiat)'and list[3].name=='Delivery Truck'and list[4].name=='Hatchback'and list[7].name=='Van 2','Known labels and readable unknown model names sort consistently')
        check(list[5].name=='Sedan'and list[6].name=='SUV','The missing Coupe Sedan and SUV classes found in the user log become selectable')
        check(list[3].path==TRAFFIC..'Service/BP_DeliveryTruck.BP_DeliveryTruck_C','The selectable path is the exact loaded class asset')
        check(f.reads==2,'Discovery performs bounded class and live-actor scans only when called')
    end)
end)
case('catalog refuses parent unrelated stale and unsupported models without edits',function()
    run(function(f)
        f.class('BP_Traffic_car_parent.BP_Traffic_car_parent_C',f.source())
        f.class('/Game/Scenery/BP_Car.BP_Car_C',f.source())
        f.class('Fake/BP_Fake.BP_Fake_C',f.source(),f.otherBase)
        f.class('Broken/BP_Broken.BP_Broken_C',nil)
        local scale=f.source();scale.Mesh.RelativeScale3D.X=-1;f.class('Mirror/BP_Mirror.BP_Mirror_C',scale)
        local missing=f.source();missing.Mesh.AnimClass=nil;f.class('NoAnim/BP_NoAnim.BP_NoAnim_C',missing)
        local wheels=f.source();wheels.VehicleMovement.WheelSetups.GetArrayNum=function()return 10000 end;f.class('BadWheels/BP_BadWheels.BP_BadWheels_C',wheels)
        local stale=f.class('Stale/BP_Stale.BP_Stale_C',f.source());stale.alive=false
        local cyclic=f.class('Cycle/BP_Cycle.BP_Cycle_C',f.source());function cyclic:GetSuperStruct()return self end
        local broken=f.class('Opaque/BP_Opaque.BP_Opaque_C',f.source());function broken:GetCDO()error('Unreadable cooked defaults')end
        local good=f.source();local material={};good.Mesh.material=material
        f.class('Estate/BP_Estate.BP_Estate_C',good)
        local list=Catalog.discover()
        check(#list==1 and list[1].name=='Estate','Only a valid car subclass with a supported animated rig is selectable')
        check(scale.Mesh.RelativeScale3D.X==-1 and good.Mesh.material==material and good.Mesh.AnimationMode==0,'Discovery leaves source transforms materials and animation untouched')
        check(#f.classes==11,'Discovery does not rewrite the loaded class list')
    end)
end)
case('live construction assets and class-scan failure do not hide available models',function()
    run(function(f)
        local class=f.class('Taxi/BP_CityTaxi.BP_CityTaxi_C',nil)
        local source=f.source();source.Mesh.AnimClass=nil
        local animation={IsValid=function()return true end}
        function source.Mesh:GetAnimInstance()return{IsValid=function()return true end,GetClass=function()return animation end}end
        f.live(class,source);f.failClasses=true
        local list=Catalog.discover()
        check(#list==1 and list[1].name=='City Taxi','Matching live actors supply construction-only body and animation metadata')
        check(source.Mesh.AnimClass==nil and #f.actors==1,'No asset loading or source assignment is required')
        f.actors={};check(#Catalog.discover()==0,'Unavailable scans fail closed without fabricated vehicle options')
    end)
end)
case('duplicate model labels are distinguished and merges preserve existing selection',function()
    run(function(f)
        f.class('Cargo/BP_Truck.BP_Truck_C',f.source());f.class('Service/BP_Truck.BP_Truck_C',f.source())
        local found=Catalog.discover()
        check(found[1].name=='Truck (Cargo)'and found[2].name=='Truck (Service)','Identical blueprint names retain their folder distinction')
        local existing={{name="Abel's car",path='/Game/Autok/Abel_Car.Abel_Car_C'},{name='Custom retained name',path=found[2].path}}
        local before=existing[2]
        local merged,selected=Catalog.merge(existing,{found[2],found[1],{name='Invalid'}},found[2].path)
        check(#merged==3 and selected==2 and merged[2].name=='Custom retained name','Merging adds missing models and retains the selected path and explicit label')
        check(merged[3].path==found[1].path and existing[2]==before and #existing==2,'New catalog entries never mutate the original list')
        local again,index=Catalog.merge(merged,found,found[1].path)
        check(#again==3 and index==3,'Repeated refresh is idempotent and preserves a discovered selection')
        check(select(2,Catalog.merge(existing,{},'/missing'))==1,'A vanished or unknown selected path falls back to the first entry')
    end)
end)
end
