-- Cosmetic fallback for replacement bodies without a verified seat transform.
-- Native USkinnedMeshComponent APIs; no asset, animation or physics edits.
local Driver={}
local tracked={}
local function valid(v)return v~=nil and v:IsValid()end
local function identity(v)
    assert(valid(v),'Object is unavailable')
    return tostring(v:GetAddress())..':'..v:GetFullName()
end
local function boneName(v)return v:ToString():lower()end
local function inspect(actor,part)
    assert(valid(actor) and valid(part),'Driver component is unavailable')
    if actor:GetClass():GetFullName()~='BlueprintGeneratedClass /Game/Autok/Abel_Car.Abel_Car_C'
        or actor:GetFullName():find('Default__',1,true) then return nil,'unsupported actor' end
    if identity(part:GetOwner())~=identity(actor) then return nil,'component belongs to another actor' end
    if identity(part)==identity(actor.Mesh) then return nil,'selected vehicle body' end
    local asset=part.SkeletalMesh
    if not valid(asset) then return nil,'not a skeletal driver mesh' end
    local count=part:GetNumBones()
    assert(type(count)=='number' and count%1==0 and count>0 and count<=1024,'Invalid driver bone count')
    local bones={}
    for i=0,count-1 do
        local bone=part:GetBoneName(i)
        local name=boneName(bone)
        if bones[name] then return nil,'ambiguous driver skeleton' end
        bones[name]=bone
    end
    local selected
    for _,names in ipairs({
        {head='head',pelvis='pelvis',spine='spine_01',left='hand_l',right='hand_r'},
        {head='mixamorig:head',pelvis='mixamorig:hips',spine='mixamorig:spine',left='mixamorig:lefthand',right='mixamorig:righthand'},
        {head='head',pelvis='hips',spine='spine',left='lefthand',right='righthand'},
    })do
        if bones[names.head] and bones[names.pelvis] and bones[names.spine] and bones[names.left] and bones[names.right] then
            selected=names;break
        end
    end
    if not selected then return nil,'unrecognized humanoid driver skeleton' end
    local function ancestry(bone)
        local seen={}
        for _=1,count do
            local parent=part:GetParentBone(bone)
            local name=boneName(parent)
            if name=='none' or name=='' then return seen end
            if seen[name] or not bones[name] then return nil end
            seen[name]=true;bone=parent
        end
    end
    local headParents=ancestry(bones[selected.head])
    if not headParents or not headParents[selected.spine] or not headParents[selected.pelvis] then
        return nil,'head is not above the recognized torso'
    end
    for _,name in ipairs({selected.pelvis,selected.spine,selected.left,selected.right})do
        local parents=ancestry(bones[name])
        if not parents or parents[selected.head] then return nil,'hiding this head could hide the torso or hands' end
        if (name==selected.left or name==selected.right) and (not parents[selected.spine] or not parents[selected.pelvis]) then
            return nil,'hands do not share the recognized torso'
        end
    end
    return {actor=actor,part=part,actorId=identity(actor),partId=identity(part),assetId=identity(asset),head=bones[selected.head]}
end
function Driver.hideHead(actor,part)
    local inspected,record,reason=pcall(inspect,actor,part)
    if not inspected then return false,{status='unavailable',reason=tostring(record)}end
    if not record then return false,{status='skipped',reason=reason}end
    local ok,err=pcall(function()
        if not part:IsBoneHiddenByName(record.head) then part:HideBoneByName(record.head,0)end
        assert(part:IsBoneHiddenByName(record.head),'The game refused to hide the driver head')
    end)
    if not ok then return false,{status='failed',reason=tostring(err)}end
    tracked[record.partId]=record
    return true,{status='hidden',bone=record.head:ToString()}
end
function Driver.hasWork()return next(tracked)~=nil end
function Driver.maintain(log)
    for key,record in pairs(tracked)do
        local ok,err=pcall(function()
            local actor,part=record.actor,record.part
            if not valid(actor) or not valid(part) or identity(actor)~=record.actorId or identity(part)~=record.partId
                or identity(part:GetOwner())~=record.actorId or identity(actor.Mesh)==record.partId
                or not valid(part.SkeletalMesh) or identity(part.SkeletalMesh)~=record.assetId then
                tracked[key]=nil;return
            end
            if not part:IsBoneHiddenByName(record.head) then
                part:HideBoneByName(record.head,0)
                assert(part:IsBoneHiddenByName(record.head),'The game refused to keep the driver head hidden')
            end
        end)
        if not ok then
            tracked[key]=nil
            if log then log('Driver head maintenance stopped: '..tostring(err))end
        end
    end
end
return Driver
