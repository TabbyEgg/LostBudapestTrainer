-- Discover already-loaded vehicle blueprints. Importing this module is pure Lua.
-- All engine reads belong in the queued game-thread action calling discover().
local Catalog={}
local TRAFFIC='/Game/Traffic_AI_System/Cars/'
local ABEL='/Game/Autok/Abel_Car.Abel_Car_C'
local names={
    [ABEL]="Abel's car",
    [TRAFFIC..'Coupe/BP_Coupe.BP_Coupe_C']='Coupe (small Fiat)',
    [TRAFFIC..'Estate/BP_Estate.BP_Estate_C']='Estate',
    [TRAFFIC..'Hatch/BP_Hatch.BP_Hatch_C']='Hatchback',
    [TRAFFIC..'Liftback/BP_Liftback.BP_Liftback_C']='Liftback',
    [TRAFFIC..'Luxury/BP_Luxury.BP_Luxury_C']='Luxury',
    [TRAFFIC..'Van/BP_Van_1.BP_Van_1_C']='Van 1',
    [TRAFFIC..'Van/BP_Van_2.BP_Van_2_C']='Van 2',
}
local function valid(value)
    local ok,result=pcall(function()return value~=nil and value:IsValid()end)
    return ok and result
end
local function pathOf(class)
    if not valid(class)then return end
    local path=class:GetFullName():match('^[^ ]+ (/Game/[^ ]+)$')
    if not path or (path~=ABEL and path:sub(1,#TRAFFIC)~=TRAFFIC)then return end
    local leaf=path:match('%.([^%.]+)$')
    if not leaf or leaf:sub(-2)~='_C' or leaf:find('REINST_',1,true) or leaf:find('SKEL_',1,true)
        or leaf:lower()=='bp_traffic_car_parent_c' then return end
    return path
end
local function wheeledClass(class)
    local seen={}
    for _=1,16 do
        if not valid(class)then return false end
        local full=class:GetFullName()
        if full=='Class /Script/PhysXVehicles.WheeledVehicle'then return true end
        if seen[full]then return false end
        seen[full]=true
        class=class:GetSuperStruct()
    end
    return false
end
local function finite(value)return type(value)=='number' and value==value and value>0 and value<1000000 end
local function usable(source)
    if not valid(source)then return false end
    local mesh,movement=source.Mesh,source.VehicleMovement
    if not valid(mesh) or not valid(movement) or not valid(mesh.SkeletalMesh) or mesh.AnimationMode~=0 then return false end
    local animation=mesh.AnimClass
    local instance=mesh:GetAnimInstance()
    if valid(instance)then animation=instance:GetClass()end
    if not valid(animation)then return false end
    local scale=mesh.RelativeScale3D
    if not scale or not finite(scale.X) or not finite(scale.Y) or not finite(scale.Z)then return false end
    local wheels=movement.WheelSetups
    local count=wheels:GetArrayNum()
    if type(count)~='number' or count%1~=0 or count<2 or count>8 then return false end
    local seen={}
    for i=1,count do -- Native TArray is one-based and must never be resized.
        local wheel=wheels[i]
        local bone=wheel.BoneName:ToString()
        if bone=='' or bone=='None' or seen[bone] or not valid(wheel.WheelClass)
            or type(wheel.bDisableSteering)~='boolean' or mesh:GetBoneIndex(wheel.BoneName)<0 then return false end
        seen[bone]=true
    end
    return true
end
local function friendly(path)
    if names[path]then return names[path]end
    local label=path:match('%.([^%.]+)$') or path
    label=label:gsub('_C$',''):gsub('^BP_',''):gsub('(%u)(%u%l)','%1 %2'):gsub('(%l)(%u)','%1 %2')
    return label:gsub('_',' '):gsub('%s+',' '):match('^%s*(.-)%s*$')
end
local function list(kind)
    local ok,result=pcall(FindAllOf,kind)
    return ok and type(result)=='table' and result or {}
end

function Catalog.discover()
    local candidates={}
    local function add(class,source)
        local ok,path=pcall(pathOf,class)
        if not ok or not path then return end
        local candidate=candidates[path]
        if not candidate then candidate={class=class,sources={}};candidates[path]=candidate end
        if source then candidate.sources[#candidate.sources+1]=source end
    end
    -- Matching live actors can hold body/animation assets chosen by construction
    -- that are absent from their class defaults. Never change those actors.
    for i,actor in ipairs(list('WheeledVehicle'))do
        if i>8192 then break end
        if valid(actor)then pcall(function()add(actor:GetClass(),actor)end)end
    end
    for i,class in ipairs(list('BlueprintGeneratedClass'))do
        if i>16384 then break end
        add(class)
    end
    local result={}
    for path,candidate in pairs(candidates)do
        local ok,isVehicle=pcall(wheeledClass,candidate.class)
        if ok and isVehicle then
            local supported=false
            for _,source in ipairs(candidate.sources)do
                local readable,value=pcall(usable,source)
                if readable and value then supported=true;break end
            end
            if not supported then
                local readable,value=pcall(function()return usable(candidate.class:GetCDO())end)
                supported=readable and value
            end
            if supported then result[#result+1]={name=friendly(path),path=path}end
        end
    end
    local counts={}
    for _,entry in ipairs(result)do local key=entry.name:lower();counts[key]=(counts[key]or 0)+1 end
    for _,entry in ipairs(result)do
        if counts[entry.name:lower()]>1 then
            local folder=entry.path:match('/([^/]+)/[^/]+$') or entry.path
            entry.name=entry.name..' ('..folder..')'
        end
    end
    table.sort(result,function(a,b)
        local x,y=a.name:lower(),b.name:lower()
        return x==y and a.path<b.path or x<y
    end)
    return result
end

-- Keep the original catalog order and explicit names, then append newly loaded
-- models in sorted order. Returns a new list and the selected path's new index.
function Catalog.merge(existing,discovered,selectedPath)
    local result,seen={},{}
    local function append(entry)
        if type(entry)=='table' and type(entry.path)=='string' and type(entry.name)=='string'
            and not seen[entry.path:lower()] then
            seen[entry.path:lower()]=true
            result[#result+1]={name=entry.name,path=entry.path}
        end
    end
    for _,entry in ipairs(existing or {})do append(entry)end
    local added={}
    for _,entry in ipairs(discovered or {})do
        if type(entry)=='table' and type(entry.path)=='string' and type(entry.name)=='string'then added[#added+1]=entry end
    end
    table.sort(added,function(a,b)
        local x,y=a.name:lower(),b.name:lower()
        return x==y and a.path<b.path or x<y
    end)
    for _,entry in ipairs(added)do append(entry)end
    local selected=1
    for i,entry in ipairs(result)do if entry.path==selectedPath then selected=i;break end end
    return result,selected
end
return Catalog
