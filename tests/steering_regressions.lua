return function(check,case)
local Steering=require('steering')
local function fixture()
    local f={lookups=0,rebuilds=0,logs={},runtime={}}
    local function fname(s)return{ToString=function()return s end}end
    local function mapping(axis,key,scale)
        local data={Scale=scale};local m={AxisName=fname(axis),Key={KeyName=fname(key)}}
        return setmetatable(m,{__index=data,__newindex=function(_,name,value)
            assert(name=='Scale','only an existing scalar may change')
            if key=='D' and value==-1 and f.failApply then f.failApply=false;error('partial mapping write')end
            if key=='A' and value==-1 and (f.failRestore or 0)>0 then f.failRestore=f.failRestore-1;error('temporary restoration failure')end
            data[name]=value
        end})
    end
    f.entries={mapping('Steering','A',-1),mapping('Steering','D',1),mapping('Forward','W',1),mapping('Steering','Gamepad_LeftX',1)}
    f.settings={alive=true}
    function f.settings:IsValid()return self.alive end
    function f.settings:GetAddress()return 10 end
    function f.settings:GetFullName()return 'InputSettings /Script/Engine.Default__InputSettings'end
    f.settings.AxisMappings=setmetatable({GetArrayNum=function()return #f.entries end},{__index=function(_,i)return f.entries[i]end,__newindex=function()error('native array must not be resized')end})
    function f.settings:ForceRebuildKeymaps()
        f.rebuilds=f.rebuilds+1
        for _,m in ipairs(f.entries)do f.runtime[m.Key.KeyName:ToString()]=m.Scale end
        if (f.failRebuild or 0)>0 then f.failRebuild=f.failRebuild-1;error('partial rebuild failure')end
    end
    function f.settings:SaveConfig()error('must never save input configuration')end
    function f.settings:SaveKeyMappings()error('must never save input mappings')end
    f.oldFind=StaticFindObject
    StaticFindObject=function(path)
        assert(path=='/Script/Engine.Default__InputSettings');f.lookups=f.lookups+1;return f.settings
    end
    f.core=Steering.new(function(text)f.logs[#f.logs+1]=text end)
    function f.normalDefaults()return f.entries[1].Scale==-1 and f.entries[2].Scale==1 and f.entries[3].Scale==1 and f.entries[4].Scale==1 end
    function f.finish()StaticFindObject=f.oldFind end
    return f
end
local function run(fn)
    local f=fixture();local ok,err=pcall(fn,f);f.finish();if not ok then error(err)end
end
case('native steering changes runtime axis mappings and immediately restores defaults',function()
    run(function(f)
        check(f.core:update(false) and f.lookups==0 and f.rebuilds==0,'inactive steering never reads Unreal during startup')
        check(f.core:update(true) and f.core.active,'native axis inversion activates')
        check(f.runtime.A==1 and f.runtime.D==-1 and f.runtime.W==1 and f.runtime.Gamepad_LeftX==1,'only the paired keyboard scales are inverted in runtime mappings')
        check(f.normalDefaults() and f.core.pending==nil,'global defaults are restored before the queued update returns')
        f.core:update(true);f.core:update(true)
        check(f.lookups==1 and f.rebuilds==1,'holding the same controlled car does not rebuild every frame')
        check(f.core:reset() and f.runtime.A==-1 and f.runtime.D==1 and not f.core.active,'leaving a converted car restores the normal runtime mappings')
        f.core:reset();check(f.rebuilds==2 and f.normalDefaults(),'cleanup is repeatable without additional native writes')
    end)
end)
case('native steering rolls back partial mapping and runtime rebuild failures',function()
    run(function(f)
        f.failApply=true;local ok,err=f.core:update(true)
        check(not ok and err:find('partial mapping write',1,true) and f.normalDefaults(),'partial default writes roll back in reverse')
        check(f.rebuilds==0 and not f.core.active and #f.logs==1,'failed setup does not copy partial defaults into runtime input')
        f.core:update(true);check(f.rebuilds==0 and #f.logs==1,'failed activation does not repeat or flood logs each frame')
        f.core:reset();check(f.core:update(true),'explicit cleanup permits a later retry')
        f.core:reset()
    end)
    run(function(f)
        f.failRebuild=1;local ok=f.core:update(true)
        check(not ok and f.rebuilds==2 and f.normalDefaults(),'failed native rebuild triggers a recovery rebuild after default restoration')
        check(f.runtime.A==-1 and f.runtime.D==1 and not f.core.active and not f.core.needsRebuild,'a partial runtime update cannot remain inverted after recovery')
    end)
end)
case('native steering retains cleanup for failed restoration and refuses ambiguous input',function()
    run(function(f)
        f.failRestore=3
        check(not f.core:update(true) and f.core.pending~=nil,'persistent temporary-write failure retains its restoration record')
        check(f.core:reset() and f.core.pending==nil and f.normalDefaults(),'later cleanup retries restore exact defaults and clear pending state')
        check(f.runtime.A==-1 and f.runtime.D==1,'runtime mappings are reset only after defaults are normal again')
    end)
    run(function(f)
        f.entries[2].Scale=-1
        check(not f.core:update(true) and f.rebuilds==0,'same-sign A/D bindings are not guessed or modified')
        check(f.entries[1].Scale==-1 and f.entries[2].Scale==-1,'unrecognized user input mappings remain unchanged')
    end)
end)
end
