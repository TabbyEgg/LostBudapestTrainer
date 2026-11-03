-- Read traffic paint by value, then create a private MID on each spawned car.
-- Call capture/apply on the game thread, alongside the vehicle profile work.
local Paint={}
local DYNAMIC='Class /Script/Engine.MaterialInstanceDynamic'
local CONSTANT='Class /Script/Engine.MaterialInstanceConstant'
local function finite(v)return type(v)=='number' and v==v and math.abs(v)<1000000 end
local function valid(v)
    local ok,result=pcall(function()return v~=nil and v:IsValid()end)
    return ok and result
end
local function name(v)
    local ok,result=pcall(function()return v:GetFullName()end)
    return ok and type(result)=='string' and result or ''
end
local function class(v)
    local ok,result=pcall(function()return v:GetClass():GetFullName()end)
    return ok and result or ''
end
local function color(v)
    local ok,result=pcall(function()
        if not v or not finite(v.R) or not finite(v.G) or not finite(v.B) or not finite(v.A) then return nil end
        return {R=v.R,G=v.G,B=v.B,A=v.A}
    end)
    return ok and result or nil
end
local function normalize(v)return v:lower():gsub('[^%w]','')end
local function contains(v,words)
    for _,word in ipairs(words)do if v:find(word,1,true)then return true end end
    return false
end
local function bodyPaint(parameter,materialName)
    local p=normalize(parameter)
    local material=normalize(materialName:match('[^/%. ]+$') or materialName)
    -- A parameter called Color also occurs on glass, tyres, lights and trim.
    -- Only a named body-paint parameter or a paint/body material may vary.
    if contains(material,{'glass','window','chrome','rubber','tire','tyre','wheel','seat','interior','driver','steering','light','lamp','ablak','kerek'})then return false end
    if contains(p,{'glass','window','chrome','rubber','tire','tyre','wheel','seat','interior','light','lamp','roof','secondary','accent','trim'})then return false end
    local isColor=contains(p,{'color','colour','tint','szin'})
    if isColor and contains(p,{'paint','body','car','vehicle','karossz','festek'})then return true end
    if p=='primarycolor' or p=='primarycolour' then return true end
    local generic=p=='color' or p=='colour' or p=='basecolor' or p=='basecolour'
        or p=='diffusecolor' or p=='diffusecolour' or p=='albedocolor' or p=='albedocolour' or p=='tint'
    return generic and contains(material,{'paint','body','car','karossz','festek'})
end
local function readVectors(material,values,issues)
    local ok,array=pcall(function()return material.VectorParameterValues end)
    if not ok or not array then return end -- Some cooked base materials have none.
    local readable,count=pcall(function()return array:GetArrayNum()end)
    if not readable or not finite(count) or count<0 or count>256 or count%1~=0 then
        issues[#issues+1]='Unsupported vector parameter array';return
    end
    for i=1,count do -- Native TArray is one-based; never probe past its size.
        local readable,entry=pcall(function()
            local source=array[i]
            local info=source.ParameterInfo
            -- SetVectorParameterValue(FName,...) addresses global parameters.
            -- Layer/blend parameters require a different native API.
            -- EMaterialParameterAssociation: Layer=0, Blend=1, Global=2.
            if not info or info.Association~=2 then return nil end
            local parameter=info.Name:ToString()
            if type(parameter)~='string' or parameter=='' or parameter=='None' or #parameter>128 then return nil end
            local value=color(source.ParameterValue)
            if not value then return nil end
            return {name=parameter,value=value,paint=bodyPaint(parameter,name(material))}
        end)
        if readable and entry then
            local key=entry.name:lower() -- FName comparison is case insensitive.
            if values[key]==nil then values[key]=entry end -- outer MID overrides win
        elseif not readable then issues[#issues+1]='Unreadable vector parameter' end
    end
end

-- Returns the first immutable parent plus a detached Lua snapshot. No live
-- array/struct wrapper or mutable traffic MID is retained in the snapshot.
function Paint.capture(material)
    local snapshot={parent=nil,vectors={},issues={}}
    local values,seen={},{}
    local current,parent=material,nil
    for depth=1,16 do
        if not valid(current) then break end
        local identity=name(current)
        if seen[current] or (identity~='' and seen[identity])then
            snapshot.issues[#snapshot.issues+1]='Cyclic material parent chain';break
        end
        seen[current]=true;if identity~='' then seen[identity]=true end
        local kind=class(current)
        if kind~=DYNAMIC and parent==nil then parent=current end
        if kind~=DYNAMIC and kind~=CONSTANT then break end
        readVectors(current,values,snapshot.issues)
        local readable,nextParent=pcall(function()return current.Parent end)
        if not readable or not valid(nextParent)then break end
        current=nextParent
        if depth==16 then snapshot.issues[#snapshot.issues+1]='Material parent chain is too deep' end
    end
    snapshot.parent=parent
    for _,entry in pairs(values)do
        -- Runtime MIDs often have generic generated names. The immutable
        -- parent identifies whether their generic Color belongs to car paint.
        entry.paint=bodyPaint(entry.name,name(parent))
        snapshot.vectors[#snapshot.vectors+1]=entry
    end
    table.sort(snapshot.vectors,function(a,b)return a.name:lower()<b.name:lower()end)
    return parent,snapshot
end

-- Linear-space colours suited to the game's period traffic. A single choice
-- is reused across all observed body-paint parameters on one spawned car;
-- original glass/trim/roof colours and every parameter's alpha are preserved.
local palette={
    {R=.025,G=.029,B=.032}, -- charcoal
    {R=.15,G=.025,B=.025},  -- burgundy
    {R=.025,G=.09,B=.045},  -- forest green
    {R=.025,G=.055,B=.13},  -- navy
    {R=.18,G=.20,B=.08},    -- olive
    {R=.68,G=.60,B=.40},    -- cream
    {R=.37,G=.23,B=.12},    -- tan
    {R=.12,G=.065,B=.035},  -- brown
    {R=.25,G=.28,B=.29},    -- grey
    {R=.54,G=.55,B=.47},    -- pale grey-green
}
local lastPalette
local function choose(rng)
    local count=lastPalette and #palette-1 or #palette
    local index=(rng or math.random)(count)
    assert(finite(index) and index%1==0 and index>=1 and index<=count,'Invalid paint random choice')
    if lastPalette and index>=lastPalette then index=index+1 end
    lastPalette=index
    return palette[index]
end
local function existingName(value)
    local result=FName(value,EFindName.FNAME_Find)
    assert(result:ToString()~='None' or value=='None','Paint parameter name is unavailable')
    return result
end

-- snapshots is a Lua table indexed by the mesh's zero-based material slots.
-- rng, when supplied, returns an integer from 1 through its numeric argument.
-- Cosmetic failures are returned to the caller; they never invalidate a car.
function Paint.apply(mesh,snapshots,rng)
    local report={appliedSlots=0,randomizedSlots=0,issues={}}
    local slots,hasPaint={},false
    for slot,snapshot in pairs(snapshots or {})do
        if type(slot)=='number' and slot>=0 and slot%1==0 and slot<32 and type(snapshot)=='table' then
            slots[#slots+1]=slot
            for _,entry in ipairs(snapshot.vectors or {})do if entry.paint then hasPaint=true end end
            for _,issue in ipairs(snapshot.issues or {})do report.issues[#report.issues+1]=issue end
        end
    end
    table.sort(slots)
    local selected
    if hasPaint then
        local ok,result=pcall(choose,rng)
        if ok then selected=result else report.issues[#report.issues+1]=tostring(result)end
    end
    for _,slot in ipairs(slots)do
        local snapshot=snapshots[slot]
        if valid(snapshot.parent) and #(snapshot.vectors or {})>0 then
            local ok,randomized=pcall(function()
                assert(class(snapshot.parent)~=DYNAMIC,'Mutable paint parent rejected')
                -- UE4.27: (int32, UMaterialInterface*, FName). Pass all three
                -- arguments; nil UObject arguments shift later UE4SS arguments.
                local target=mesh:CreateDynamicMaterialInstance(slot,snapshot.parent,existingName('None'))
                assert(valid(target) and class(target)==DYNAMIC and name(target)~=name(snapshot.parent),'Private paint material was not created')
                local changed=false
                for _,entry in ipairs(snapshot.vectors)do
                    local value=assert(color(entry.value),'Invalid captured paint colour')
                    if selected and entry.paint then value.R,value.G,value.B=selected.R,selected.G,selected.B;changed=true end
                    -- Both arguments are flat UE values; no FMaterialParameterInfo
                    -- marshaling and no unobserved parameter-name guesses.
                    target:SetVectorParameterValue(existingName(entry.name),value)
                end
                return changed
            end)
            if ok then
                report.appliedSlots=report.appliedSlots+1
                if randomized then report.randomizedSlots=report.randomizedSlots+1 end
            else report.issues[#report.issues+1]='Paint slot '..slot..': '..tostring(randomized)end
        end
    end
    return report
end

return Paint
