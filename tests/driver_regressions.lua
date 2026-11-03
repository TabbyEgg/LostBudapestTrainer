return function(check,case)
local function fixture()
    package.loaded.driver=nil
    local f={nextId=0}
    local function object(name)
        f.nextId=f.nextId+1
        local v={name=name,id=f.nextId,alive=true}
        function v:IsValid()return self.alive end
        function v:GetAddress()return self.id end
        function v:GetFullName()return self.name end
        return v
    end
    local function bone(name)return {ToString=function()return name end}end
    f.actor=object('Abel_Car_C /World.Converted')
    function f.actor:GetClass()return {GetFullName=function()return 'BlueprintGeneratedClass /Game/Autok/Abel_Car.Abel_Car_C'end}end
    f.actor.Mesh=object('SkeletalMeshComponent /World.Converted.VehicleMesh')
    f.part=object('SkeletalMeshComponent /World.Converted.Driver')
    f.asset=object('SkeletalMesh /Game/Characters/Driver')
    f.part.SkeletalMesh=f.asset
    f.owner=f.actor
    f.names={'root','pelvis','spine_01','neck_01','head','hand_l','hand_r','eye_l'}
    f.parents={pelvis='root',spine_01='pelvis',neck_01='spine_01',head='neck_01',hand_l='spine_01',hand_r='spine_01',eye_l='head'}
    f.hidden=false;f.writes=0;f.headName='head';f.physics={collision=3,animation='native',visible=true}
    function f.part:GetOwner()return f.owner end
    function f.part:GetNumBones()return #f.names end
    function f.part:GetBoneName(index)return bone(f.names[index+1])end
    function f.part:GetParentBone(name)return bone(f.parents[name:ToString()] or 'None')end
    function f.part:IsBoneHiddenByName(name)assert(name:ToString()==f.headName);return f.hidden end
    function f.part:HideBoneByName(name,operation)
        assert(name:ToString()==f.headName and operation==0,'Only the head is hidden; physics bodies are retained')
        f.writes=f.writes+1
        if f.fail then error('injected API failure')end
        if not f.refuse then f.hidden=true end
    end
    for _,name in ipairs({'SetCollisionEnabled','SetVisibility','SetHiddenInGame','SetSkeletalMesh','SetAnimInstanceClass','K2_SetRelativeLocation'})do
        f.part[name]=function()error('Driver head fallback must not call '..name)end
    end
    f.driver=require('driver')
    return f
end

case('converted-driver head hiding preserves the body, hands and native systems',function()
    local f=fixture()
    local hidden,report=f.driver.hideHead(f.actor,f.part)
    check(hidden and report.status=='hidden' and f.hidden and f.writes==1,'recognized owned humanoid head is hidden')
    check(f.physics.collision==3 and f.physics.animation=='native' and f.physics.visible,'collision, whole-mesh visibility and animation remain unchanged')
    f.driver.maintain();check(f.writes==1,'already hidden head is not rewritten every tick')
    f.hidden=false;f.driver.maintain();check(f.hidden and f.writes==2,'native unhide is corrected on the owned instance')
end)
case('driver fallback recognizes actual Mixamo names while preserving hierarchy checks',function()
    for _,prefix in ipairs({'','mixamorig:'})do
        local function alternate()
            local f=fixture()
            local names={root=prefix..'Root',pelvis=prefix..'Hips',spine_01=prefix..'Spine',neck_01=prefix..'Neck',
                head=prefix..'Head',hand_l=prefix..'LeftHand',hand_r=prefix..'RightHand',eye_l=prefix..'LeftEye'}
            for index,name in ipairs(f.names)do f.names[index]=names[name]end
            local parents={}
            for name,parent in pairs(f.parents)do parents[names[name]]=names[parent]end
            f.parents=parents;f.headName=names.head
            return f,names
        end
        local f,names=alternate()
        local hidden,report=f.driver.hideHead(f.actor,f.part)
        check(hidden and report.bone==names.head and f.writes==1,'actual returned head FName is used for '..prefix..'Mixamo')
        f.driver.maintain();check(f.writes==1,'alternate hidden head is left alone')
        f,names=alternate();f.parents[names.hand_r]=names.head
        check(not f.driver.hideHead(f.actor,f.part) and f.writes==0,'Mixamo hand below head is rejected')
        f,names=alternate();f.parents[names.head]=names.root
        check(not f.driver.hideHead(f.actor,f.part) and f.writes==0,'Mixamo head outside torso hierarchy is rejected')
    end
end)
case('driver fallback rejects vehicle geometry, other actors and unsafe skeletons',function()
    local f=fixture()
    check(not f.driver.hideHead(f.actor,f.actor.Mesh) and f.writes==0,'selected car body is excluded')
    f.owner=f.actor.Mesh
    check(not f.driver.hideHead(f.actor,f.part) and f.writes==0,'another owner is excluded')
    f.owner=f.actor;f.names[7]='wheel_r'
    check(not f.driver.hideHead(f.actor,f.part) and f.writes==0,'nonhumanoid mesh is unchanged')
    f.names[7]='hand_r';f.parents.hand_l='head'
    check(not f.driver.hideHead(f.actor,f.part) and f.writes==0,'head ancestor of a hand cannot be hidden')
    f.parents.hand_l='root'
    check(not f.driver.hideHead(f.actor,f.part) and f.writes==0,'hands outside the common torso are rejected')
    f.parents.hand_l='spine_01';f.parents.head='root'
    check(not f.driver.hideHead(f.actor,f.part) and f.writes==0,'unknown seat/body skeleton is unchanged')
end)
case('driver maintenance stops before touching replaced or recycled components',function()
    for _,kind in ipairs({'actor destroyed','part recycled','owner changed','asset changed','part becomes body'})do
        local f=fixture();assert(f.driver.hideHead(f.actor,f.part));f.hidden=false
        if kind=='actor destroyed' then f.actor.alive=false
        elseif kind=='part recycled' then f.part.name='SkeletalMeshComponent /World.Reused'
        elseif kind=='owner changed' then f.owner=f.actor.Mesh
        elseif kind=='asset changed' then f.part.SkeletalMesh=f.actor.Mesh
        else f.actor.Mesh=f.part end
        f.driver.maintain()
        check(f.writes==1 and not f.driver.hasWork(),'changed target is discarded without writing: '..kind)
    end
end)
case('driver fallback reports missing APIs, refused writes and bounded errors',function()
    local f=fixture();f.part.GetNumBones=nil
    local ok,report=f.driver.hideHead(f.actor,f.part)
    check(not ok and report.status=='unavailable' and not f.driver.hasWork(),'missing metadata is reported before mutation')
    f=fixture();f.refuse=true;ok,report=f.driver.hideHead(f.actor,f.part)
    check(not ok and report.status=='failed' and not f.driver.hasWork(),'refused head hide is reported without tracking')
    f=fixture();assert(f.driver.hideHead(f.actor,f.part));f.hidden=false;f.fail=true
    local logs={};f.driver.maintain(function(message)logs[#logs+1]=message end);f.driver.maintain()
    check(not f.driver.hasWork() and #logs==1 and f.writes==2,'maintenance failure stops retries and logs once')
end)
end
