from pathlib import Path
import tempfile,json,hashlib,shutil,subprocess,os,argparse
parser=argparse.ArgumentParser(description='Run installer filesystem fixtures; does not execute the game.')
parser.add_argument('--powershell',default=shutil.which('pwsh'))
parser.add_argument('--game-exe',type=Path,required=True)
parser.add_argument('--temp-root',type=Path,help='Writable directory on the game EXE filesystem, used for hardlinks.')
parser.add_argument('--report',type=Path,default=Path(__file__).resolve().parent/'installer-results.json')
args=parser.parse_args()
if not args.powershell: parser.error('PowerShell 7 was not found; use --powershell.')
PWSH=Path(args.powershell).resolve()
ROOT=Path(__file__).resolve().parents[1];EXE=args.game_exe.resolve()
if hashlib.sha256(EXE.read_bytes()).hexdigest()!='2e5f4d5b66da873a488287b580c2ba3dd91ed892727cfd71ecbd610d6a08f284':
 parser.error('The fixture requires the approved game build.')
checks=[]
def check(value,name):
 checks.append({'name':name,'pass':bool(value)})
 if not value: raise AssertionError(name)
def run(package,game,uninstall=False,update=False):
 return subprocess.run([str(PWSH),'-NoLogo','-NoProfile','-File',str(package/('uninstall.ps1' if uninstall else 'install.ps1')),'-GameDirectory',str(game)]+(['-Update'] if update else []),capture_output=True,text=True)
def fixture(folder):
 folder.mkdir();pkg=folder/'package';pkg.mkdir();game=folder/'game';win=game/'Eltunt_Budapest3/Binaries/Win64';win.mkdir(parents=True);os.link(EXE,win/EXE.name)
 for name in ['install.ps1','uninstall.ps1']:shutil.copy2(ROOT/name,pkg/name)
 files={'UE4SS.dll':b'official-test-loader','dwmapi.dll':b'official-test-proxy','UE4SS-settings.ini':b'[General]\nEnableHotReloadSystem = 1\n[Debug]\nConsoleEnabled = 1\nGuiConsoleEnabled = 1\nGuiConsoleVisible = 1\n[EngineVersionOverride]\nMajorVersion = 0\nMinorVersion = 0\n'}
 for name in ['main.lua','controller.lua','adapter.lua','config.lua','protection.lua','vehicles.lua','vehicle_engine.lua','native_spawn.lua','menu.lua','menu_engine.lua','player_vehicle.lua']:files['Mods/LostBudapestNoclip/Scripts/'+name]=b'-- test '+name.encode()
 records=[]
 for rel,data in files.items():
  p=pkg/'Runtime'/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data);records.append({'path':rel,'size':len(data),'sha256':hashlib.sha256(data).hexdigest()})
 (pkg/'payload-manifest.json').write_text(json.dumps({'format':1,'files':records}));return pkg,game,win,files
with tempfile.TemporaryDirectory(prefix='lbn-install-tests-',dir=args.temp_root or EXE.parent) as tmp:
 tmp=Path(tmp)
 pkg,game,win,files=fixture(tmp/'fresh');r=run(pkg,game);check(r.returncode==0,'fresh installation completes: '+r.stdout+r.stderr)
 check((win/'dwmapi.dll').read_bytes()==files['dwmapi.dll'],'fresh proxy bytes match approved payload')
 check((win/'Mods/mods.txt').read_text().strip()=='LostBudapestNoclip : 1','fresh mod entry enabled')
 ini=(win/'UE4SS-settings.ini').read_text();check('EnableHotReloadSystem = 0' in ini and 'MajorVersion = 4' in ini and 'MinorVersion = 27' in ini and 'ConsoleEnabled = 0' in ini,'fresh required INI settings applied')
 receipt=json.loads((win/'LostBudapestNoclip.install.json').read_text());check(len(receipt['files'])==15,'fresh receipt lists all fourteen payloads plus merged mod list')
 r=run(pkg,game);check(r.returncode==1 and 'receipt already exists' in r.stdout,'second install refuses original backup chain overwrite')
 r=run(pkg,game,True);check(r.returncode==0,'fresh uninstall completes: '+r.stdout+r.stderr)
 check(not (win/'dwmapi.dll').exists() and not (win/'Mods').exists() and not (win/'LostBudapestNoclip.install.json').exists(),'fresh uninstall removes only newly installed content and receipt')
 pkg,game,win,files=fixture(tmp/'existing')
 (win/'UE4SS.dll').write_bytes(files['UE4SS.dll']);settings=b'[General]\nEnableHotReloadSystem=1\nKeepMe = 73\n[Debug]\nConsoleEnabled=1\n[EngineVersionOverride]\nMajorVersion=5\nMinorVersion=2\n'
 (win/'UE4SS-settings.ini').write_bytes(settings);(win/'Mods/OtherMod/Scripts').mkdir(parents=True);other=win/'Mods/OtherMod/Scripts/main.lua';other.write_bytes(b'untouched other mod');mods=b'OtherMod : 1\nLostBudapestNoclip : 0\nAnotherMod : 0\n';(win/'Mods/mods.txt').write_bytes(mods)
 r=run(pkg,win);check(r.returncode==0,'Win64 direct install with existing loader/config completes: '+r.stdout+r.stderr)
 ini=(win/'UE4SS-settings.ini').read_text();check('KeepMe = 73' in ini and 'ConsoleEnabled=1' in ini and 'EnableHotReloadSystem = 0' in ini,'existing unrelated settings and console preference preserved')
 check((win/'Mods/mods.txt').read_text().splitlines()==['OtherMod : 1','LostBudapestNoclip : 1','AnotherMod : 0'],'mod entry merge preserves other enabled/disabled mods')
 rec=json.loads((win/'LostBudapestNoclip.install.json').read_text());check(not any(x['path']=='UE4SS.dll' for x in rec['files']),'identical pre-existing loader is not claimed')
 r=run(pkg,game,True);check(r.returncode==0,'existing install uninstall completes: '+r.stdout+r.stderr)
 check((win/'UE4SS-settings.ini').read_bytes()==settings and (win/'Mods/mods.txt').read_bytes()==mods,'uninstall restores original configuration bytes exactly')
 check((win/'UE4SS.dll').read_bytes()==files['UE4SS.dll'] and other.read_bytes()==b'untouched other mod','uninstall leaves pre-existing loader and unrelated mod untouched')
 pkg,game,win,files=fixture(tmp/'conflict');(win/'dwmapi.dll').write_bytes(b'other mod proxy');r=run(pkg,game);check(r.returncode==1 and (win/'dwmapi.dll').read_bytes()==b'other mod proxy' and not (win/'Mods').exists(),'different existing proxy rejected before any game modification')
 pkg,game,win,files=fixture(tmp/'wrongbuild');(win/EXE.name).unlink();(win/EXE.name).write_bytes(b'MZwrong-game');r=run(pkg,game);check(r.returncode==1 and not (win/'Mods').exists() and not (win/'dwmapi.dll').exists(),'different game hash rejected before writes')
 pkg,game,win,files=fixture(tmp/'badpayload');(pkg/'Runtime/dwmapi.dll').write_bytes(b'corrupt');r=run(pkg,game);check(r.returncode==1 and 'integrity' in r.stdout and not (win/'Mods').exists(),'tampered payload rejected before writes')
 pkg,game,win,files=fixture(tmp/'unlisted');(pkg/'Runtime/unlisted.bin').write_bytes(b'extra');r=run(pkg,game);check(r.returncode==1 and 'Unmanifested' in r.stdout and not (win/'Mods').exists(),'unmanifested payload rejected before writes')
 pkg,game,win,files=fixture(tmp/'traversal');manifest=json.loads((pkg/'payload-manifest.json').read_text());manifest['files'][0]['path']='../outside';(pkg/'payload-manifest.json').write_text(json.dumps(manifest));r=run(pkg,game);check(r.returncode==1 and 'Unsafe' in r.stdout and not (win/'Mods').exists(),'payload path traversal rejected before writes')
 pkg,game,win,files=fixture(tmp/'duplicate');manifest=json.loads((pkg/'payload-manifest.json').read_text());manifest['files'].append(manifest['files'][0]);(pkg/'payload-manifest.json').write_text(json.dumps(manifest));r=run(pkg,game);check(r.returncode==1 and 'duplicate' in r.stdout and not (win/'Mods').exists(),'duplicate manifest entries rejected before writes')
 pkg,game,win,files=fixture(tmp/'edited');r=run(pkg,game);check(r.returncode==0,'edit preservation fixture installs')
 own=win/'Mods/LostBudapestNoclip/Scripts/config.lua';own.write_bytes(b'user changes');r=run(pkg,game,True);check(r.returncode==2 and own.read_bytes()==b'user changes' and (win/'LostBudapestNoclip.install.json').exists(),'edited trainer file retained with partial uninstall receipt')
 check(not (win/'dwmapi.dll').exists(),'partial uninstall still removes unchanged owned loader')
 pkg,game,win,files=fixture(tmp/'editedmods');r=run(pkg,game);check(r.returncode==0,'edited mod list fixture installs')
 (win/'Mods/mods.txt').write_bytes(b'LostBudapestNoclip : 1\nNewUserMod : 1\n');r=run(pkg,game,True);check(r.returncode==2 and b'NewUserMod : 1' in (win/'Mods/mods.txt').read_bytes(),'post-install mod list edits are preserved')
 pkg,game,win,files=fixture(tmp/'badreceipt');r=run(pkg,game);check(r.returncode==0,'bad receipt fixture installs')
 rp=win/'LostBudapestNoclip.install.json';j=json.loads(rp.read_text());j['files'][0]['path']='../../outside';rp.write_text(json.dumps(j));r=run(pkg,game,True);check(r.returncode==1 and 'Unsafe' in r.stdout and (win/'dwmapi.dll').exists(),'uninstall traversal rejected before removing any file')
 pkg,game,win,files=fixture(tmp/'rollback');(win/'Mods').write_bytes(b'existing wrong-layout file');r=run(pkg,game);check(r.returncode==1 and not (win/'dwmapi.dll').exists() and (win/'Mods').read_bytes()==b'existing wrong-layout file' and not (win/'LostBudapestNoclip.install.json').exists(),'partial failure rolls proxy back and preserves original obstructing file')
 pkg,game,win,files=fixture(tmp/'custommods');(win/'UE4SS-settings.ini').write_bytes(b'[Overrides]\nModsFolderPath = D:\\My Mods\n');r=run(pkg,game);check(r.returncode==1 and 'custom ModsFolderPath' in r.stdout and not (win/'dwmapi.dll').exists() and (win/'UE4SS-settings.ini').read_bytes()==b'[Overrides]\nModsFolderPath = D:\\My Mods\n','custom external mod path rejected without modifications')
 pkg,game,win,files=fixture(tmp/'sharedloader');r=run(pkg,game);check(r.returncode==0,'shared loader fixture installs');(win/'Mods/NewUserMod/Scripts').mkdir(parents=True);(win/'Mods/NewUserMod/Scripts/main.lua').write_bytes(b'new mod');r=run(pkg,game,True);check(r.returncode==0 and (win/'dwmapi.dll').exists() and (win/'UE4SS.dll').exists() and (win/'UE4SS-settings.ini').exists() and (win/'Mods/NewUserMod/Scripts/main.lua').read_bytes()==b'new mod','new other mod keeps shared loader/configuration on uninstall')
 pkg,game,win,files=fixture(tmp/'resumerestore');original=b'[General]\nKeepMe = 59\n';(win/'UE4SS-settings.ini').write_bytes(original);r=run(pkg,game);check(r.returncode==0,'interrupted restore fixture installs');(win/'UE4SS-settings.ini').write_bytes(original);r=run(pkg,game,True);check(r.returncode==0 and (win/'UE4SS-settings.ini').read_bytes()==original and not (win/'LostBudapestNoclip.install.json').exists(),'uninstall recognizes already-restored original bytes and finishes safely')

# Exercise actual previous-version receipt migration, rather than uninstall/reinstall.
def refresh_manifest(pkg):
 records=[]
 for file in sorted((pkg/'Runtime').rglob('*')):
  if file.is_file(): records.append({'path':file.relative_to(pkg/'Runtime').as_posix(),'size':file.stat().st_size,'sha256':hashlib.sha256(file.read_bytes()).hexdigest()})
 (pkg/'payload-manifest.json').write_text(json.dumps({'format':1,'files':records}))
def prior_fixture(folder):
 pkg,game,win,files=fixture(folder)
 old=(ROOT/'tests/fixtures/install-0.1.3.ps1').read_bytes()
 (pkg/'install.ps1').write_bytes(old)
 for name in ['protection.lua','vehicles.lua','vehicle_engine.lua','native_spawn.lua','menu.lua','menu_engine.lua','player_vehicle.lua']:(pkg/'Runtime/Mods/LostBudapestNoclip/Scripts'/name).unlink()
 refresh_manifest(pkg)
 original=b'[General]\nEnableHotReloadSystem=1\nMySetting=71\n'
 (win/'UE4SS-settings.ini').write_bytes(original)
 check(run(pkg,game).returncode==0,'previous-version install creates a real legacy receipt')
 prior=(win/'LostBudapestNoclip.install.json').read_bytes()
 shutil.copyfile(ROOT/'install.ps1',pkg/'install.ps1')
 for name in ['protection.lua','vehicles.lua','vehicle_engine.lua','native_spawn.lua','menu.lua','menu_engine.lua','player_vehicle.lua']:(pkg/'Runtime/Mods/LostBudapestNoclip/Scripts'/name).write_bytes(b'-- new '+name.encode())
 (pkg/'Runtime/Mods/LostBudapestNoclip/Scripts/main.lua').write_bytes(b'-- updated main')
 refresh_manifest(pkg)
 return pkg,game,win,original,prior
with tempfile.TemporaryDirectory(prefix='lbn-update-tests-',dir=args.temp_root or EXE.parent) as tmp:
 tmp=Path(tmp)
 pkg,game,win,original,prior=prior_fixture(tmp/'clean')
 check(run(pkg,game,update=True).returncode==0,'Update upgrades legacy receipt directly without uninstall')
 new=json.loads((win/'LostBudapestNoclip.install.json').read_text());old=json.loads(prior)
 check(new['backupDirectory']==old['backupDirectory'],'Update retains original uninstall backup chain')
 check((win/'Mods/LostBudapestNoclip/Scripts/main.lua').read_bytes()==b'-- updated main','Update replaces old trainer code')
 check(all((win/'Mods/LostBudapestNoclip/Scripts'/n).exists() for n in ['protection.lua','vehicles.lua','vehicle_engine.lua','native_spawn.lua','menu.lua','menu_engine.lua','player_vehicle.lua']),'Update adds new modules')
 check(run(pkg,game,update=True).returncode==0,'same-version Update is idempotent')
 check(run(pkg,game,True).returncode==0 and (win/'UE4SS-settings.ini').read_bytes()==original,'uninstall after Update restores pre-first-install settings')
 check(not (win/'LostBudapestNoclip.install.json').exists() and not (win/'Mods').exists(),'uninstall after Update removes new and old owned trainer files')
 pkg,game,win,original,prior=prior_fixture(tmp/'config')
 config=win/'Mods/LostBudapestNoclip/Scripts/config.lua';config.write_bytes(b'-- user speed preferences')
 check(run(pkg,game,update=True).returncode==0 and config.read_bytes()==b'-- user speed preferences','Update preserves edited trainer configuration')
 check(run(pkg,game,True).returncode==2 and config.read_bytes()==b'-- user speed preferences','uninstall after Update still preserves user edits')
 pkg,game,win,original,prior=prior_fixture(tmp/'badpackage')
 (pkg/'Runtime/Mods/LostBudapestNoclip/Scripts/main.lua').write_bytes(b'corrupt incoming code')
 check(run(pkg,game,update=True).returncode==1 and (win/'LostBudapestNoclip.install.json').read_bytes()==prior and (win/'Mods/LostBudapestNoclip/Scripts/main.lua').read_bytes()!=b'corrupt incoming code','bad update package leaves old installation intact')
 pkg,game,win,original,prior=prior_fixture(tmp/'editedcode')
 main=win/'Mods/LostBudapestNoclip/Scripts/main.lua';main.write_bytes(b'-- edited Lua implementation')
 check(run(pkg,game,update=True).returncode==1 and main.read_bytes()==b'-- edited Lua implementation' and (win/'LostBudapestNoclip.install.json').read_bytes()==prior,'Update refuses to overwrite edited implementation code')
 pkg,game,win,original,prior=prior_fixture(tmp/'rollback')
 obstruct=win/'Mods/LostBudapestNoclip/Scripts/NewDir';obstruct.write_bytes(b'original obstruction')
 extra=pkg/'Runtime/Mods/LostBudapestNoclip/Scripts/NewDir/extra.lua';extra.parent.mkdir();extra.write_bytes(b'new')
 refresh_manifest(pkg)
 oldmain=(win/'Mods/LostBudapestNoclip/Scripts/main.lua').read_bytes()
 check(run(pkg,game,update=True).returncode==1,'failed Update reports failure')
 check((win/'Mods/LostBudapestNoclip/Scripts/main.lua').read_bytes()==oldmain and (win/'LostBudapestNoclip.install.json').read_bytes()==prior and obstruct.read_bytes()==b'original obstruction','failed Update rolls back code and retains old receipt plus obstruction')

with tempfile.TemporaryDirectory(prefix='lbn-loader-update-',dir=args.temp_root or EXE.parent) as tmp:
 pkg,game,win,original,prior=prior_fixture(Path(tmp)/'owned')
 (pkg/'Runtime/UE4SS.dll').write_bytes(b'new approved test loader');refresh_manifest(pkg)
 check(run(pkg,game,update=True).returncode==0 and (win/'UE4SS.dll').read_bytes()==b'new approved test loader','Update can replace its own unchanged loader while preserving external-loader protection')
 check(run(pkg,game,True).returncode==0 and not (win/'UE4SS.dll').exists(),'uninstall after loader upgrade retains original ownership semantics')
report={'powershell_version':subprocess.check_output([str(PWSH),'-NoLogo','-NoProfile','-Command','$PSVersionTable.PSVersion.ToString()'],text=True).strip(),'host':'Linux; Windows paths/folder picker/game runtime not executed','assertions':len(checks),'failures':sum(not x['pass'] for x in checks),'checks':checks,'source_sha256':{n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest() for n in ['install.ps1','uninstall.ps1','Install.cmd','Uninstall.cmd','Update.cmd','update.ps1']}}
args.report.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
