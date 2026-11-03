-- Build a selected body on Abel's native player vehicle before physics creation.
-- Read source templates only. Restore every temporary player-template edit.
local Profile={};Profile.__index=Profile
local Paint=require('paint')
local Driver=require('driver')
local hiddenDoors={}
local convertedCars={}
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
    assert(scale.X>0 and scale.Y>0 and scale.Z>0,'Mirrored or zero-scale vehicle rigs are unsupported')
    local wheels=wheelData(movement,mesh)
    local count=mesh:GetNumMaterials()
    assert(count>=0 and count<=32,'Unsupported vehicle material count')
    local materials,paint={},{}
    for i=0,count-1 do
        materials[i],paint[i]=Paint.capture(mesh:GetMaterial(i))
    end
    return {mesh=mesh,body=body,animation=animation,scale=scale,wheels=wheels,materials=materials,paint=paint,materialCount=count}
end
local function selectSource(class)
    -- Prefer a real traffic instance: ConstructionScript may choose the final
    -- body/animation/rig. Read its assets without changing its AI or state.
    local className=class:GetFullName()
    local candidates={}
    for _,actor in ipairs(FindAllOf('WheeledVehicle') or {})do
        if valid(actor) and actor:GetClass():GetFullName()==className then
            candidates[#candidates+1]=actor
        end
    end
    -- Start with a random traffic instance to retain the game's varied
    -- material schemes, including colours with model-specific parameter names.
    local start=#candidates>0 and math.random(#candidates) or 1
    for offset=0,#candidates-1 do
        local usable,profile=pcall(readSource,candidates[(start+offset-1)%#candidates+1])
        if usable then return profile end
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
    local self=setmetatable({body=body,animation=animation,physics=mesh.PhysicsAssetOverride,scale=selected.scale,wheels=sourceWheels,materials=materials,paint=selected.paint,materialCount=materialCount,changes={}},Profile)
    self.hideDriverHead=sourceClass:GetFullName():find('/Cars/Hatch/',1,true)~=nil
    local function change(object,key,value)
        self.changes[#self.changes+1]={object=object,key=key,old=object[key],value=value}
    end
    change(target,'RelativeScale3D',selected.scale)
    self.changes[#self.changes].old=vector(target.RelativeScale3D)
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
        local ok,err=pcall(function()change.object[change.key]=change.value end)
        if not ok then error('Selected vehicle template field '..change.key..': '..tostring(err),0)end
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
local function partName(object)
    local name=(objectName(object) or ''):match('[^%.:/ ]+$') or ''
    return name:lower()
end
local function doorName(name)
    return (name:find('door',1,true) and not name:find('outdoor',1,true)) or name:find('ajt',1,true)
end
local function steeringName(name)
    for _,word in ipairs({'steer','volan','volán','kormany','kormány'})do if name:find(word,1,true)then return true end end
    return false
end
local function wheelName(name)
    for _,word in ipairs({'wheel','tire','tyre','hubcap','kerek','kerék','felni','gumi','abroncs'})do if name:find(word,1,true)then return true end end
    return name:match('^rim') or name:match('[^%a]rim')
end
local function cosmeticKind(part)
    local names={partName(part)}
    for _,field in ipairs({'StaticMesh','SkeletalMesh'})do
        local ok,asset=pcall(function()return part[field]end)
        if ok and valid(asset)then names[#names+1]=partName(asset)end
    end
    -- An interior steering wheel can use a generic wheel asset. Check all
    -- names for this exclusion before classifying any separate mesh as a tyre.
    for _,name in ipairs(names)do if steeringName(name)then return nil end end
    for _,name in ipairs(names)do if doorName(name)then return 'door' end end
    for _,name in ipairs(names)do if wheelName(name)then return 'wheel' end end
end
local function unwrap(value)
    local ok,result=pcall(function()return value:get()end)
    return ok and result or value
end
function Profile:hideExtraDoors(actor)
    for key,record in pairs(hiddenDoors)do
        if not valid(record.part) or not valid(record.actor) then hiddenDoors[key]=nil end
    end
    local entries={}
    local readable,parts=pcall(function()
        local class=StaticFindObject('/Script/Engine.MeshComponent')
        assert(valid(class),'Mesh component metadata is unavailable')
        local result=actor:GetComponentsByClass(class)
        if type(result)=='table' and rawget(result,'GetArrayNum')==nil then return result end
        local count=result:GetArrayNum()
        assert(type(count)=='number' and count>=0 and count<=4096 and count%1==0,'Invalid component array')
        local decoded={}
        for i=1,count do decoded[i]=result[i]end
        return decoded
    end)
    if readable then
        entries=parts
    else
        -- The stable loader can fail marshaling the component-return array.
        -- Its object-list helper returns stable UObject references instead.
        local actorPath=(objectName(actor) or ''):match('^[^ ]+ (.+)$') or objectName(actor)
        local seen={}
        for _,kind in ipairs({'StaticMeshComponent','SkeletalMeshComponent'})do
            for _,part in ipairs(FindAllOf(kind) or {})do
                if valid(part) and (objectName(part) or ''):find(actorPath..'.',1,true) and not seen[part:GetAddress()] then
                    seen[part:GetAddress()]=true;entries[#entries+1]=part
                end
            end
        end
    end
    self.hiddenDoorCount,self.hiddenWheelCount,self.hiddenHeadCount=0,0,0
    for _,entry in ipairs(entries)do
        local part=unwrap(entry)
        if valid(part) and objectName(part)~=objectName(actor.Mesh) and objectName(part:GetOwner())==objectName(actor) then
            if self.hideDriverHead then
                local hidden=Driver.hideHead(actor,part)
                if hidden then self.hiddenHeadCount=self.hiddenHeadCount+1 end
            end
            local kind=cosmeticKind(part)
            if kind then
                local oldCollision=part:GetCollisionEnabled()
                local queryCollision=kind=='door' and (oldCollision==1 or oldCollision==3) and 1 or 0
                hiddenDoors[part:GetAddress()]={part=part,actor=actor,name=objectName(part),owner=objectName(actor),collision=queryCollision}
                part:SetVisibility(false,true)
                part:SetHiddenInGame(true,true)
                part:SetCollisionEnabled(queryCollision)
                if kind=='door' then self.hiddenDoorCount=self.hiddenDoorCount+1
                else self.hiddenWheelCount=self.hiddenWheelCount+1 end
            end
        end
    end
end
function Profile.hasWork()return next(convertedCars)~=nil or next(hiddenDoors)~=nil or Driver.hasWork() end
function Profile.maintainDoors(log)
    Driver.maintain(log)
    -- Called only from the queued game-thread update. Never intercept native
    -- setters shared by the level loader, world props or other actors.
    for key,record in pairs(hiddenDoors)do
        local ok,err=pcall(function()
            local part=record.part
            if not valid(record.actor) or not valid(part) or objectName(record.actor)~=record.owner or objectName(part)~=record.name or objectName(part:GetOwner())~=record.owner then
                hiddenDoors[key]=nil;return
            end
            if part.bVisible~=false then part:SetVisibility(false,true)end
            if part.bHiddenInGame~=true then part:SetHiddenInGame(true,true)end
            if part:GetCollisionEnabled()~=record.collision then part:SetCollisionEnabled(record.collision)end
        end)
        if not ok then hiddenDoors[key]=nil;if log then log('Cosmetic component maintenance stopped for a changed component: '..tostring(err))end end
    end
    for key,record in pairs(convertedCars)do
        if not valid(record.actor) or objectName(record.actor)~=record.name then convertedCars[key]=nil end
    end
end
function Profile.steeringTarget(actor)
    if not valid(actor) then return false end
    local key=actor:GetAddress()
    local record=convertedCars[key]
    if not record then return false end
    if not valid(record.actor) or objectName(actor)~=record.name then convertedCars[key]=nil;return false end
    return true
end
function Profile.convertedMovement(actor)
    if not Profile.steeringTarget(actor) then return nil end
    local record=convertedCars[actor:GetAddress()]
    if not valid(record.movement) or objectName(actor.VehicleMovement)~=record.movementName or objectName(actor.Mesh)~=record.meshName or objectName(actor.Mesh.SkeletalMesh)~=record.bodyName then return nil end
    return record.movement
end
function Profile:validate(actor)
    assert(actor:GetClass():GetFullName()=='BlueprintGeneratedClass /Game/Autok/Abel_Car.Abel_Car_C','The spawned car is not the native player vehicle')
    local mesh,movement=actor.Mesh,actor.VehicleMovement
    assert(valid(mesh) and valid(movement),'The spawned car has no mesh/movement')
    local actualScale=vector(mesh.RelativeScale3D)
    for _,axis in ipairs({'X','Y','Z'})do assert(math.abs(actualScale[axis]-self.scale[axis])<=math.max(1e-6,self.scale[axis]*1e-4),'The game replaced the selected model scale before physics initialization')end
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
    local paintOk,paint=pcall(Paint.apply,mesh,self.paint)
    if not paintOk then self.paintWarning=tostring(paint)
    else
        self.randomizedPaintSlots=paint.randomizedSlots
        if #paint.issues>0 then self.paintWarning=table.concat(paint.issues,'; ')end
    end
    -- Extra doors/wheels are cosmetic. A missing component API must not
    -- discard an otherwise valid native vehicle with a matched physics rig.
    local doorOk,doorError=pcall(self.hideExtraDoors,self,actor)
    if not doorOk then self.doorWarning=tostring(doorError)end
    for key,record in pairs(convertedCars)do if not valid(record.actor) then convertedCars[key]=nil end end
    convertedCars[actor:GetAddress()]={actor=actor,name=objectName(actor),movement=movement,movementName=objectName(movement),meshName=objectName(mesh),bodyName=objectName(mesh.SkeletalMesh)}
end
return Profile
