-- Build a selected body on Abel's native player vehicle before physics creation.
-- Read source templates only. Restore every temporary player-template edit.
local Profile={};Profile.__index=Profile
local function valid(v)return v~=nil and v:IsValid()end
local function objectName(v)return valid(v) and v:GetFullName() or nil end
local function finite(v)return type(v)=='number' and v==v and math.abs(v)<1000000 end
local function vector(v)
    assert(v and finite(v.X) and finite(v.Y) and finite(v.Z),'Invalid wheel offset')
    return {X=v.X,Y=v.Y,Z=v.Z}
end
local function wheelData(movement,mesh,strict)
    local array=movement.WheelSetups
    local count=array:GetArrayNum()
    assert(type(count)=='number' and count>=2 and count<=8 and count%1==0,'Unsupported wheel count')
    local result,seen={},{ }
    for i=1,count do -- UE4SS TArray indexing is one-based; never resize an array.
        local wheel=array[i]
        local name=wheel.BoneName:ToString()
        if strict~=false then
            assert(name~='None' and not seen[name] and mesh:GetBoneIndex(wheel.BoneName)>=0,'Wheel bone is missing or duplicated: '..name)
            assert(valid(wheel.WheelClass),'Wheel class is unavailable')
        end
        seen[name]=true
        assert(type(wheel.bDisableSteering)=='boolean','Wheel steering flag is unavailable')
        result[i]={target=wheel,class=wheel.WheelClass,bone=wheel.BoneName,name=name,offset=vector(wheel.AdditionalOffset),disabled=wheel.bDisableSteering}
    end
    return result
end
local function sameWheels(actual,expected)
    if #actual~=#expected then return false end
    for i,wheel in ipairs(actual)do
        local source=expected[i]
        if objectName(wheel.class)~=objectName(source.class) or wheel.name~=source.name or wheel.disabled~=source.disabled then return false end
        for _,axis in ipairs({'X','Y','Z'})do if math.abs(wheel.offset[axis]-source.offset[axis])>.001 then return false end end
    end
    return true
end
local function readSource(source)
    assert(valid(source),'Source vehicle is unavailable')
    local mesh,movement=source.Mesh,source.VehicleMovement
    assert(valid(mesh) and valid(movement),'Source mesh or movement is unavailable')
    local body,animation=mesh.SkeletalMesh,mesh.AnimClass
    local instance=mesh:GetAnimInstance()
    if valid(instance) then animation=instance:GetClass()end
    assert(valid(body) and valid(animation) and mesh.AnimationMode==0,'This model needs an animated vehicle body')
    local scale=vector(mesh.RelativeScale3D)
    assert(math.abs(scale.X-1)<.001 and math.abs(scale.Y-1)<.001 and math.abs(scale.Z-1)<.001,'This model needs a separate scale mapping')
    local wheels=wheelData(movement,mesh)
    local count=mesh:GetNumMaterials()
    assert(count>=0 and count<=32,'Unsupported vehicle material count')
    local materials={}
    for i=0,count-1 do
        local material=mesh:GetMaterial(i)
        -- Never share a traffic actor's mutable paint material with a new player car.
        for depth=1,8 do
            if not valid(material) or material:GetClass():GetFullName()~='Class /Script/Engine.MaterialInstanceDynamic' then break end
            local ok,parent=pcall(function()return material.Parent end)
            if not ok or not valid(parent) or objectName(parent)==objectName(material) or depth==8 then material=nil;break end
            material=parent
        end
        materials[i]=material
    end
    return {mesh=mesh,body=body,animation=animation,wheels=wheels,materials=materials,materialCount=count}
end
local function selectSource(class)
    -- Prefer a real traffic instance: ConstructionScript may choose the final
    -- body/animation/rig. Read its assets without changing its AI or state.
    local className=class:GetFullName()
    for _,actor in ipairs(FindAllOf('WheeledVehicle') or {})do
        if valid(actor) and actor:GetClass():GetFullName()==className then
            local usable,profile=pcall(readSource,actor)
            if usable then return profile end
        end
    end
    local ok,data=pcall(readSource,class:GetCDO())
    if ok then return data end
    error('The selected model has no compatible loaded body/wheel rig: '..tostring(data),0)
end

function Profile.new(sourceClass,playerClass)
    assert(sourceClass:GetFullName():find('/Game/Traffic_AI_System/Cars/',1,true),'Unsupported source vehicle class')
    assert(playerClass:GetFullName()=='BlueprintGeneratedClass /Game/Autok/Abel_Car.Abel_Car_C','Player template must be Abel car')
    local selected=selectSource(sourceClass)
    local player=playerClass:GetCDO()
    assert(valid(player),'Player vehicle defaults are unavailable')
    local mesh,target=selected.mesh,player.Mesh
    local nativeMovement=player.VehicleMovement
    assert(valid(target) and valid(nativeMovement),'Player mesh or movement template is unavailable')
    local body,animation=selected.body,selected.animation
    local sourceWheels=selected.wheels
    local playerWheels=wheelData(nativeMovement,target,false)
    assert(#sourceWheels==#playerWheels,'This model has an incompatible player wheel count')
    local materialCount,materials=selected.materialCount,selected.materials
    local self=setmetatable({body=body,animation=animation,physics=mesh.PhysicsAssetOverride,wheels=sourceWheels,materials=materials,materialCount=materialCount,changes={}},Profile)
    local function change(object,key,value)
        self.changes[#self.changes+1]={object=object,key=key,old=object[key],value=value}
    end
    change(target,'SkeletalMesh',body)
    change(target,'AnimClass',animation)
    change(target,'AnimationMode',mesh.AnimationMode)
    change(target,'PhysicsAssetOverride',mesh.PhysicsAssetOverride)
    for i,wheel in ipairs(playerWheels)do
        local selected=sourceWheels[i]
        change(wheel.target,'WheelClass',selected.class)
        change(wheel.target,'BoneName',selected.bone)
        change(wheel.target,'AdditionalOffset',selected.offset)
        -- A live struct wrapper would observe later writes: keep the old vector by value.
        self.changes[#self.changes].old=wheel.offset
        change(wheel.target,'bDisableSteering',selected.disabled)
    end
    return self
end
function Profile:apply()
    for _,change in ipairs(self.changes)do
        change.touched=true
        change.object[change.key]=change.value
    end
end
function Profile:restore()
    local errors={}
    for i=#self.changes,1,-1 do
        local change=self.changes[i]
        if change.touched then
            local ok,err=pcall(function()change.object[change.key]=change.old end)
            if ok then change.touched=false else errors[#errors+1]=tostring(err)end
        end
    end
    if #errors>0 then error(table.concat(errors,'; '),0)end
end
function Profile:validate(actor)
    assert(actor:GetClass():GetFullName()=='BlueprintGeneratedClass /Game/Autok/Abel_Car.Abel_Car_C','The spawned car is not the native player vehicle')
    local mesh,movement=actor.Mesh,actor.VehicleMovement
    assert(valid(mesh) and valid(movement),'The spawned car has no mesh/movement')
    assert(objectName(mesh.SkeletalMesh)==objectName(self.body) and objectName(mesh.AnimClass)==objectName(self.animation) and mesh.AnimationMode==0,'The game replaced the selected body or animation during construction')
    assert(objectName(mesh.PhysicsAssetOverride)==objectName(self.physics),'The game replaced the selected physics asset during construction')
    assert(sameWheels(wheelData(movement,mesh),self.wheels),'The game replaced the selected wheel setup during construction')
    local instance=mesh:GetAnimInstance()
    if valid(instance) then assert(objectName(instance:GetClass())==objectName(self.animation),'The game initialized an incompatible animation instance')end
    local exposed,wheels=pcall(function()return movement.Wheels end)
    if exposed and wheels then
        local readable,count=pcall(function()return wheels:GetArrayNum()end)
        if readable and count>0 then
            assert(count==#self.wheels,'The game created an incompatible number of physics wheels')
            for i=1,count do
                assert(valid(wheels[i]) and objectName(wheels[i]:GetClass())==objectName(self.wheels[i].class),'The game created an incompatible physics wheel class')
            end
        end
    end
    local oldCount=mesh:GetNumMaterials()
    assert(oldCount>=0 and oldCount<=32,'Unsupported spawned material count')
    for i=0,math.max(oldCount,self.materialCount)-1 do mesh:SetMaterial(i,self.materials[i])end
end
return Profile
