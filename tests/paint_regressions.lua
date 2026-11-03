return function(check,case)
local Paint=require('paint')
local function fixture()
    local f={ids=0}
    local function object(label,kind)
        f.ids=f.ids+1
        local v={label=label,alive=true,id=f.ids}
        function v:IsValid()return self.alive end
        function v:GetFullName()return self.label end
        function v:GetClass()return {GetFullName=function()return 'Class /Script/Engine.'..kind end}end
        return v
    end
    local function fname(value)return {ToString=function()return value end}end
    function f.array(entries)
        return setmetatable({GetArrayNum=function()return #entries end},{__index=function(_,i)
            assert(type(i)=='number' and i>=1 and i<=#entries,'Native TArray access must remain one-based and in bounds')
            return entries[i]
        end,__newindex=function()error('Source array is read-only')end})
    end
    function f.parameter(label,r,g,b,a,association)
        return {ParameterInfo={Name=fname(label),Association=association or 2},ParameterValue={R=r,G=g,B=b,A=a or 1}}
    end
    function f.material(label,entries,parent,dynamic)
        local v=object(label,dynamic and 'MaterialInstanceDynamic' or 'MaterialInstanceConstant')
        v.Parent=parent;v.VectorParameterValues=f.array(entries or {})
        function v:SetVectorParameterValue()error('Source materials must never be modified')end
        return v
    end
    f.oldFName,f.oldEnum=FName,EFindName
    EFindName={FNAME_Find=0}
    FName=function(value,mode)assert(mode==0);return fname(value)end
    f.mesh=object('MeshComponent /World.NewCar.Mesh','SkeletalMeshComponent');f.mesh.created={};f.mesh.slots={}
    function f.mesh:CreateDynamicMaterialInstance(slot,parent,optionalName)
        assert(parent and optionalName:ToString()=='None','Native MID arguments must include parent and FName None')
        if self.failCreate then error('Injected MID creation failure')end
        local v=object('MaterialInstanceDynamic /World.NewCar.Paint'..(#self.created+1),'MaterialInstanceDynamic')
        v.Parent=parent;v.writes={}
        function v:SetVectorParameterValue(parameter,value)
            self.writes[parameter:ToString()]={R=value.R,G=value.G,B=value.B,A=value.A}
        end
        self.created[#self.created+1]=v;self.slots[slot]=v
        return v
    end
    function f.finish()FName,EFindName=f.oldFName,f.oldEnum end
    return f
end
local function run(fn)
    local f=fixture();local ok,err=pcall(fn,f);f.finish();if not ok then error(err)end
end
case('traffic paint capture detaches values and respects outer overrides and native array bounds',function()
    run(function(f)
        local base=f.material('MaterialInstanceConstant /Game/CarPaint.CarPaint',{f.parameter('BodyColor',.4,.4,.4),f.parameter('RoofColor',.02,.02,.02)})
        local sourceColor=f.parameter('BodyColor',.7,.5,.2,.8)
        local source=f.material('MaterialInstanceDynamic /World.Traffic.Paint',{sourceColor,f.parameter('IgnoredLayerColor',1,0,0,1,0),f.parameter('IgnoredBlendColor',1,0,0,1,1)},base,true)
        local parent,snapshot=Paint.capture(source)
        check(parent==base and snapshot.parent==base,'First immutable parent replaces mutable traffic material')
        check(#snapshot.vectors==2,'Global overrides only; duplicate inherited paint values collapse')
        sourceColor.ParameterValue.R=.01
        local body
        for _,entry in ipairs(snapshot.vectors)do if entry.name=='BodyColor'then body=entry end end
        check(body.value.R==.7 and body.value.A==.8,'Snapshot owns scalar colour components rather than live struct views')
        check(body.paint,'Explicit observed body paint parameter is eligible for variation')
    end)
end)
case('generic runtime MID paint names are resolved through their immutable parent',function()
    run(function(f)
        local base=f.material('MaterialInstanceConstant /Game/CarPaint.CarPaint',{})
        local source=f.material('MaterialInstanceDynamic /World.MaterialInstanceDynamic_45',{f.parameter('Color',.8,.5,.2)},base,true)
        local _,snapshot=Paint.capture(source)
        check(snapshot.vectors[1].paint,'Global Color on a generated MID inherits its paint material identity')
        local report=Paint.apply(f.mesh,{[0]=snapshot},function()return 1 end)
        check(report.randomizedSlots==1,'Observed generic paint colour is randomized on the new car')
        local glass=f.material('MaterialInstanceConstant /Game/Glass.Glass',{})
        source=f.material('MaterialInstanceDynamic /World.BodyPaint',{f.parameter('BodyColor',.8,.5,.2)},glass,true)
        _,snapshot=Paint.capture(source)
        check(not snapshot.vectors[1].paint,'A misleading MID name cannot override a glass parent exclusion')
    end)
end)
case('spawned cars get independent coherent body paint while trim and alpha survive',function()
    run(function(f)
        local parent=f.material('MaterialInstanceConstant /Game/CarPaint.CarPaint',{f.parameter('BodyColor',.7,.5,.2,.6),f.parameter('RoofColor',.01,.01,.01),f.parameter('GlassTint',.1,.2,.3,.4)})
        local _,first=Paint.capture(parent)
        local other=f.material('MaterialInstanceConstant /Game/BodyPaint.BodyPaint',{f.parameter('PaintColor',.3,.3,.3,.9)})
        local _,second=Paint.capture(other)
        local report=Paint.apply(f.mesh,{[0]=first,[2]=second},function(n)return n end)
        local a,b=f.mesh.slots[0],f.mesh.slots[2]
        check(report.appliedSlots==2 and report.randomizedSlots==2 and #report.issues==0,'Both body slots have private randomized materials')
        check(a~=b and a.Parent==parent and b.Parent==other,'Mesh slots do not share mutable materials')
        check(a.writes.BodyColor.R==b.writes.PaintColor.R and a.writes.BodyColor.G==b.writes.PaintColor.G,'One colour scheme is used across body paint slots')
        check(a.writes.BodyColor.A==.6 and b.writes.PaintColor.A==.9,'Opacity remains the source value')
        check(a.writes.RoofColor.R==.01 and a.writes.GlassTint.A==.4,'Roof and glass parameter values are copied unchanged')
        check(first.vectors[1].value.R==.7,'Application does not edit the detached source snapshot')
        local firstRed=a.writes.BodyColor.R
        local nextReport=Paint.apply(f.mesh,{[0]=first},function(n)return n end)
        check(nextReport.randomizedSlots==1 and f.mesh.slots[0]~=a,'A later spawn receives a separate MID')
        check(f.mesh.slots[0].writes.BodyColor.R~=firstRed,'Consecutive spawns do not repeat the same palette choice')
        check(a.writes.BodyColor.R==firstRed,'Changing the next car does not repaint an earlier car')
    end)
end)
case('glass chrome tires and unknown vector names are preserved without guessed parameter writes',function()
    run(function(f)
        for _,label in ipairs({'Glass','Chrome','Tire','Interior','Headlight'})do
            local mat=f.material('MaterialInstanceConstant /Game/'..label..'.'..label,{f.parameter('CarColor',.2,.3,.4,.5)})
            local _,snapshot=Paint.capture(mat)
            local report=Paint.apply(f.mesh,{[0]=snapshot},function()error('Excluded material must not choose a random colour')end)
            check(report.randomizedSlots==0 and f.mesh.slots[0].writes.CarColor.R==.2,label..' material is preserved')
        end
        local mat=f.material('MaterialInstanceConstant /Game/Other.Other',{f.parameter('UnrelatedVector',1,2,3)})
        local _,snapshot=Paint.capture(mat)
        Paint.apply(f.mesh,{[0]=snapshot})
        check(f.mesh.slots[0].writes.BodyColor==nil and f.mesh.slots[0].writes.UnrelatedVector.B==3,'Only captured native parameter names are written')
    end)
end)
case('missing paint metadata and native failures stay cosmetic and never write traffic materials',function()
    run(function(f)
        local mat=f.material('MaterialInstanceConstant /Game/CarPaint.CarPaint',{})
        mat.VectorParameterValues=nil
        local parent,snapshot=Paint.capture(mat)
        local report=Paint.apply(f.mesh,{[0]=snapshot})
        check(parent==mat and report.appliedSlots==0 and #f.mesh.created==0,'Missing metadata preserves immutable base appearance')
        local broken=f.material('MaterialInstanceDynamic /World.BrokenMID',{},nil,true)
        local unsafe,bad=Paint.capture(broken)
        check(unsafe==nil and bad.parent==nil,'Unresolved mutable parent cannot be reused')
        mat.VectorParameterValues=f.array({f.parameter('BodyColor',.3,.4,.5)})
        _,snapshot=Paint.capture(mat)
        f.mesh.failCreate=true
        report=Paint.apply(f.mesh,{[0]=snapshot},function()return 1 end)
        check(report.appliedSlots==0 and #report.issues>0,'Native cosmetic failure is reported without aborting vehicle creation')
    end)
end)
end
