-- Mole v1.4.4: guided setup, selective tunnels, local coordinates, durable checkpoints, bounded vein mining.
-- Origin is the turtle's starting block. +Z is forward, +X is right, Y is down.
local VERSION='1.4.4'
local UPDATE_URL='https://raw.githubusercontent.com/Nom4d-temp/mole/main/mole.lua'
local argv = {...}
local ROOT = 'quarry-data'
fs.makeDir(ROOT)
local function readFile(p)
  if not fs.exists(p) then return nil end
  local h = assert(fs.open(p, 'r')); local s = h.readAll(); h.close()
  return assert(textutils.unserialize(s), 'Invalid file: '..p)
end
local function writeFile(p, v)
  local h = assert(fs.open(p, 'w')); h.write(textutils.serialize(v)); h.close()
end
local defaults = {
  width=16, length=16, depth=64, fuelMargin=64, fuelTarget=2560,
  emergencyRadius=8, emergencyFuelMargin=16, retries=12, veinLimit=128, veinDepth=24, discardTrash=true,
  fuelSchemaVersion=2, fuel={['minecraft:coal']=true, ['minecraft:charcoal']=true, ['minecraft:lava_bucket']=true},
  trash={['minecraft:dirt']=true, ['minecraft:grass_block']=true,
    ['minecraft:cobblestone']=true, ['minecraft:stone']=true,
    ['minecraft:gravel']=true, ['minecraft:andesite']=true,
    ['minecraft:diorite']=true, ['minecraft:granite']=true,
    ['minecraft:cobbled_deepslate']=true, ['minecraft:deepslate']=true,
    ['minecraft:tuff']=true, ['minecraft:netherrack']=true},
  protected={['minecraft:bedrock']=true, ['minecraft:chest']=true,
    ['minecraft:trapped_chest']=true, ['minecraft:barrel']=true,
    ['minecraft:spawner']=true, ['minecraft:end_portal_frame']=true},
}
-- Installation metadata stays separate so resetting a job retains startup backup.
local INSTALL='mole-install-data'
local function rawFile(path)
  if not fs.exists(path) then return nil end
  local h=assert(fs.open(path,'r')); local text=h.readAll(); h.close(); return text
end
local function startupText(program)
  return '-- Automatically resume the saved mining job.\n'
    ..'local program='..string.format('%q',program)..'\n'
    .."local backup=program..'.update-backup'\n"
    ..'if not fs.exists(program) and fs.exists(backup) then fs.move(backup,program) end\n'
    ..'shell.run(program)\n'
end
local function generatedStartup(content,program)
  if not content then return false end
  local compact=content:gsub('%-%-[^\n]*',''):gsub('%s+','')
  return content==startupText(program) or (content:find('-- Automatically resume the saved mining job.',1,true)==1
    and compact=='shell.run('..string.format('%q',program)..')')
    or compact=="iffs.exists('quarry-data/state.a')orfs.exists('quarry-data/state.b')thenshell.run('mole')end"
end
if argv[1]=='delete' then
  print('This removes Mole, its saved jobs, recovery data, and settings.')
  write('Are you sure? yes/no: ')
  if read():match('^%s*(.-)%s*$'):lower()~='yes' then print('Deletion cancelled.'); return end
  local program=shell.getRunningProgram()
  local installation
  if fs.exists(INSTALL) then
    local ok,result=pcall(readFile,INSTALL)
    if not ok or type(result)~='table' or (result.path~='startup' and result.path~='startup.lua') then
      print('Installation record is damaged; deletion stopped to preserve the startup backup.'); return
    end
    installation=result
  end
  if installation then
    local current=rawFile(installation.path)
    if current==installation.installed then
      if installation.original~=nil then
        local h=assert(fs.open(installation.path,'w')); h.write(installation.original); h.close()
        print('Original startup file restored.')
      else fs.delete(installation.path); print('Mole startup file removed.') end
    else print('Startup was changed separately; keeping the current startup file.') end
  else
    -- Older installations had no backup. Remove only recognizable Mole startup.
    for _,path in ipairs({'startup.lua','startup'}) do
      if generatedStartup(rawFile(path),program) then fs.delete(path); print('Mole startup file removed.') end
    end
  end
  fs.delete(ROOT)
  if fs.exists(INSTALL) then fs.delete(INSTALL) end
  for _,suffix in ipairs({'.update-backup','.update-download'}) do
    if fs.exists(program..suffix) then fs.delete(program..suffix) end
  end
  fs.delete(program)
  print('Mole successfully uninstalled')
  return
end
local CP=ROOT..'/config'; local SP=ROOT..'/state'
-- Reset before loading or validating old files: damaged saves must not block it.
if argv[1]=='reset' then
  fs.delete(ROOT); fs.makeDir(ROOT); writeFile(CP,defaults)
  print('[Mole] Reset complete. Saved jobs, recovery data, and custom settings cleared.')
  print('Fuel and carried items are still in the turtle. No movement was made.')
  print('Place the turtle at your chosen start with a chest behind it, then run mole.')
  return
end
if not fs.exists(CP) then writeFile(CP, defaults) end
local c=readFile(CP)
-- Upgrade the former default while preserving deliberately different targets.
if c.fuelTarget==2000 then c.fuelTarget=2560; writeFile(CP,c) end
if c.fuelSchemaVersion==nil and type(c.fuel)=='table' then
  if c.fuel['minecraft:lava_bucket']==nil then c.fuel['minecraft:lava_bucket']=true end
  c.fuelSchemaVersion=2; writeFile(CP,c)
end
for _,k in ipairs({'width','length','depth','fuelMargin','fuelTarget','retries','veinLimit','veinDepth'}) do
  assert(type(c[k])=='number' and c[k]>=1 and c[k]%1==0, 'Invalid config: '..k)
end
c.emergencyRadius=c.emergencyRadius or 8; c.emergencyFuelMargin=c.emergencyFuelMargin or 16
assert(type(c.emergencyRadius)=='number' and c.emergencyRadius>=1 and c.emergencyRadius<=32 and c.emergencyRadius%1==0,'Invalid emergency radius')
assert(type(c.emergencyFuelMargin)=='number' and c.emergencyFuelMargin>=0 and c.emergencyFuelMargin%1==0,'Invalid emergency fuel margin')
assert(type(c.trash)=='table' and type(c.fuel)=='table' and type(c.protected)=='table')
-- Alternating files keep the preceding complete checkpoint after interrupted writes.
local s
for _,p in ipairs({SP..'.a',SP..'.b'}) do
  local ok,v=pcall(readFile,p)
  if ok and v and type(v.seq)=='number' and (not s or v.seq>s.seq) then s=v end
end
local function save()
  s.seq=s.seq+1; writeFile(SP..(s.seq%2==0 and '.a' or '.b'),s)
end
local function failure(code,message)
  error(setmetatable({code=code,message=message},{__tostring=function(e) return e.message end}),0)
end
local function failureCode(why) return type(why)=='table' and why.code or nil end
local function log(msg) print('[Mole] '..msg) end
local function copy(v) return {x=v.x,y=v.y,z=v.z,d=v.d} end
local function same(a,b) return a.x==b.x and a.y==b.y and a.z==b.z end
local function key(p) return p.x..','..p.y..','..p.z end
local function fuel() local f=turtle.getFuelLevel(); return f=='unlimited' and math.huge or f end
local function capacity() local f=turtle.getFuelLimit(); return f=='unlimited' and math.huge or f end
local function depthText(p)
  local relative=tostring(p.y)..' blocks below start'
  if s and type(s.startY)=='number' then return 'Y '..(s.startY-p.y)..' ('..relative..')' end
  return relative..' (world Y unknown)'
end
local function ascentDistance(depth)
  local extra=s and s.startY and s.emergencyTargetY and math.max(0,s.emergencyTargetY-s.startY) or 0
  return math.max(0,depth+extra)
end
local function answer(prompt)
  write(prompt..' ')
  local v=read(); return v:match('^%s*(.-)%s*$')
end
local function numberQuestion(label,default,maximum)
  while true do
    local raw=answer(label..' ['..default..']:')
    if raw=='' then return default end
    if raw:lower()=='q' then return nil end
    local n=tonumber(raw)
    if n and n>=1 and n<=maximum and n%1==0 then return n end
    print('Enter a whole number from 1 to '..maximum..'.')
  end
end
local function ensureStartup()
  local program=shell.getRunningProgram()
  if s.program~=program then s.program=program; save() end
  local path=fs.exists('startup.lua') and 'startup.lua' or fs.exists('startup') and 'startup' or 'startup.lua'
  local content
  if fs.exists(path) then
    local h=assert(fs.open(path,'r')); content=h.readAll(); h.close()
  end
  -- Update only our own generated startup, or a single legacy shell.run line.
  local compact=content and content:gsub('%-%-[^\n]*',''):gsub('%s+','')
  local own=not content or generatedStartup(content,program) or compact=='shell.run("quarry")' or compact=="shell.run('quarry')"
    or compact=="iffs.exists('quarry-data/state.a')orfs.exists('quarry-data/state.b')thenshell.run('quarry')end"
    or compact=='shell.run("mole")' or compact=="shell.run('mole')"
    or (content:find('-- Automatically resume the saved mining job.',1,true)==1
        and compact:match('^shell%.run%(["\'][%w_./%-]+["\']%)$'))
  if not own then return end
  local updated=startupText(program)
  local installation=fs.exists(INSTALL) and readFile(INSTALL) or nil
  if not installation then
    installation={path=path,original=content,installed=updated}
    if generatedStartup(content,program) then installation.original=nil end
  elseif installation.path~=path then
    log('Startup location changed; preserving the previous startup backup.'); return
  end
  installation.installed=updated; writeFile(INSTALL,installation)
  if content==updated then return end
  local h=assert(fs.open(path,'w'));  h.write(updated); h.close()
  log('Automatic restart enabled for Mole.')
end
if argv[1]=='update' then
  local function update()
    print('Installed Mole: '..VERSION..'. Checking GitHub...')
    if not http or not http.get then print('HTTP downloads are disabled; ask the server owner to enable them.'); return end
    local response,why,failed=http.get(UPDATE_URL)
    if not response then
      if failed then failed.close() end
      print('Update check failed: '..tostring(why)..'. Current program kept.'); return
    end
    local ok,source=pcall(response.readAll); response.close()
    if not ok or type(source)~='string' then print('Download failed. Current program kept.'); return end
    local major,minor,patch=source:match('^%-%- Mole v(%d+)%.(%d+)%.(%d+)')
    if not major then print('Download is not a versioned Mole program. Current program kept.'); return end
    local remote={tonumber(major),tonumber(minor),tonumber(patch)}
    local current={}; for n in VERSION:gmatch('%d+') do current[#current+1]=tonumber(n) end
    local newer=false
    for i=1,3 do
      if remote[i]~=current[i] then newer=remote[i]>current[i]; break end
    end
    local version=major..'.'..minor..'.'..patch
    if not newer then print('Already up to date. GitHub version: '..version..'.'); return end
    if not load(source,'@Mole update','t',_ENV) then print('Downloaded program has invalid Lua syntax. Current program kept.'); return end
    local program=shell.getRunningProgram()
    local temp,backup=program..'.update-download',program..'.update-backup'
    print('New version: '..version..'. Validating download before installing...')
    if fs.exists(temp) then fs.delete(temp) end
    local h=assert(fs.open(temp,'w'),'Cannot save update download'); h.write(source); h.close()
    assert(rawFile(temp)==source,'Saved download did not match; current program kept.')
    -- Upgrade only owned startup, preserving its original backup. It can restore
    -- the old executable if a chunk unload occurs between the two file moves.
    local installation=fs.exists(INSTALL) and readFile(INSTALL) or nil
    local path=installation and installation.path or (fs.exists('startup.lua') and 'startup.lua' or 'startup')
    local content=rawFile(path)
    if generatedStartup(content,program) or installation and content==installation.installed then
      installation=installation or {path=path}
      local text=startupText(program)
      installation.installed=text; writeFile(INSTALL,installation)
      if content~=text then
        local startup=assert(fs.open(path,'w')); startup.write(text); startup.close()
      end
    end
    if fs.exists(backup) then fs.delete(backup) end
    fs.move(program,backup)
    local installed,err=pcall(fs.move,temp,program)
    if not installed then
      local restored=pcall(fs.move,backup,program)
      if restored then print('Installation failed; old program restored: '..tostring(err))
      else print('Installation failed. Restore '..backup..' to '..program..' before restarting.') end
      return
    end
    print('Updated Mole to '..version..'. Previous program saved as '..backup..'.')
    print('Job, settings, and startup backup kept. Run '..program..' to resume.')
  end
  local ok,why=pcall(update)
  if not ok then print('Update stopped: '..tostring(why)..'. Check the program and its .update-backup before restarting.') end
  return
end
local function settingsMenu()
  while true do
    print('\nTrash settings')
    print('1 Add a block to trash (ignore it)')
    print('2 Remove a block from trash (keep it)')
    print('3 Show the trash list')
    print('4 Toggle dropping trash: '..(c.discardTrash and 'ON' or 'OFF'))
    print('Enter or q: finish')
    local v=answer('Choose:'):lower()
    if v=='' or v=='q' then return end
    if v=='1' or v=='2' then
      local name=answer('Block/item ID (example minecraft:stone):')
      if name:match('^[%w_]+:[%w_/%.-]+$') then
        if v=='1' then c.trash[name]=true else c.trash[name]=nil end
        writeFile(CP,c); print('Saved.')
      else print('Use a full block/item ID, with a colon.') end
    elseif v=='3' then
      local names={}; for name,enabled in pairs(c.trash) do if enabled then names[#names+1]=name end end
      table.sort(names); for _,name in ipairs(names) do print(name) end
    elseif v=='4' then c.discardTrash=not c.discardTrash; writeFile(CP,c)
    else print('Choose 1, 2, 3 or 4.') end
  end
end
if argv[1]=='help' then
  print('Mole '..VERSION..' - tunnel miner')
  print('mole            Start or resume')
  print('mole status   Show progress')
  print('mole settings Change the trash list')
  print('mole return   Go home and pause')
  print('mole new      Set up a new job at home')
  print('mole reset    Clear all saved jobs and restore default settings')
  print('mole delete   Uninstall Mole (asks yes/no)')
  print('mole update   Check GitHub and install a newer version')
  print('Hold Ctrl+T to stop the running program.')
  return
end
if argv[1]=='settings' or argv[1]=='config' then settingsMenu(); return end
local fresh=not s or argv[1]=='new'
if fresh then
  if argv[1] and argv[1]~='new' and argv[1]~='init' then
    print('No saved job yet. Run mole to set up.'); return
  end
  if s and (s.pending or s.recovery or #s.route>0 or (s.phase~='done' and s.phase~='paused')) then
    print('Finish the job or return home before starting a new one.'); return
  end
  print('\nMole 1.4.4 - first-time setup')
  print('We dig tunnels and collect nearby ores.')
  print('Press Enter for each default, or q to cancel.')
  print('Length goes forward; width goes to the right.')
  local length=numberQuestion('Length in blocks',c.length,64); if not length then return end
  local width=numberQuestion('Width in blocks',c.width,64); if not width then return end
  local startY
  while true do
    local raw=answer('Starting world Y coordinate [Enter = unknown]:')
    if raw:lower()=='q' then return end
    if raw=='' then break end
    local n=tonumber(raw)
    if n and n==n and n~=math.huge and n~=-math.huge and n%1==0 then startY=n; break end
    print('Enter a whole Y coordinate, including negative numbers, or leave blank.')
  end
  local suggested=c.depth
  local safeDepth=startY and startY+62 or nil
  if safeDepth then
    print('Suggested lowest mining level: Y -62.')
    print('Depth available before Y -62: '..math.max(0,safeDepth)..' blocks below this turtle.')
    if safeDepth>=1 then suggested=math.min(suggested,safeDepth)
    else print('This starting position is already at or below Y -62.') end
  end
  local depth=numberQuestion('Depth below the turtle',suggested,512); if not depth then return end
  if safeDepth and depth>safeDepth then
    print('Caution: below Y -62, dense bedrock may make mining and return routes difficult.')
    while true do
      print('Requested bottom: Y '..(startY-depth)..', below the suggested Y -62 limit.')
      local prompt=safeDepth>=1 and 'Enter to stop at Y -62, yes to go deeper, or q to cancel:'
        or 'Type yes to mine below Y -62 (other dimensions), or q/Enter to cancel:'
      local choice=answer(prompt):lower()
      if choice=='yes' then break end
      if choice=='q' or choice=='' and safeDepth<1 then return end
      if choice=='' then depth=safeDepth; break end
      print('Use Enter, yes, or q.')
    end
  end
  local emergencyTargetY=startY
  if startY then
    while true do
      local raw=answer('Emergency target Y ['..startY..' = starting elevation]:')
      if raw:lower()=='q' then return end
      if raw=='' then break end
      local n=tonumber(raw)
      if n and n==n and n~=math.huge and n%1==0 and n>=startY then emergencyTargetY=n; break end
      print('Enter a whole Y at or above the starting Y, or leave blank.')
    end
  end
  print('\nPlace a chest directly BEHIND this turtle.')
  print('Put coal, charcoal, or lava buckets in consecutive chest slots, starting at slot 1.')
  print('Face the turtle into the mining area.')
  print('Check that the area is safe to dig.')
  while true do
    local v=answer('Enter to start, or q to cancel:'):lower()
    if v=='q' then return end
    if peripheral.hasType('back','inventory') then break end
    print('No chest behind the turtle. Place it, then retry.')
  end
  local previousSeq=s and s.seq or 0
  if s then writeFile(ROOT..'/previous-job',s) end
  c.length=length; c.width=width; c.depth=depth; writeFile(CP,c)
  local anchor={type=peripheral.getType('back'),size=peripheral.wrap('back').size()}
  s={anchor=anchor,seq=previousSeq,p={x=0,y=0,z=0,d=0},route={},index=1,phase='work',seen={},vein=nil,
     layoutVersion=2,startY=startY,emergencyTargetY=emergencyTargetY,program=shell.getRunningProgram(),shape={w=c.width,l=c.length,h=c.depth}}
  save(); ensureStartup()
  log('Starting '..c.length..' long x '..c.width..' wide, '..c.depth..' blocks deep.')
  log('Start: '..depthText(s.p)..'. Planned bottom: '..depthText({y=c.depth})..'.')
elseif argv[1]=='init' then
  print('Already set up. Run mole to resume.'); return
end
c.width=s.shape.w; c.length=s.shape.l; c.depth=s.shape.h
ensureStartup()
if argv[1]=='status' then
  if s.emergency then
    log('State: '..s.phase..'; emergency reason: '..s.emergency.reason)
    log('Upward moves still required (conservative estimate): '..s.emergency.p.y..'; fuel '..fuel())
    if s.emergency.targetY then log('Emergency target: Y '..s.emergency.targetY) end
    log('Emergency position is relative to the escape start; the mining job stays paused.'); return
  end
  log('Saved step '..s.index..'; fuel '..fuel())
  log('State: '..s.phase..'; '..((s.pending or s.recovery) and 'saved estimate: ' or '')..depthText(s.p))
  if s.recovery then
    for i,h in ipairs(s.recovery.hypotheses) do
      log('Recovery hypothesis '..i..': '..key(h.p)..', facing '..h.p.d..', route '..#h.route)
    end
  else log('Local tunnel position '..key(s.p)..', facing '..s.p.d) end
  if s.pending then print(textutils.serialize(s.pending)) end
  return
end
if argv[1]=='recover' then
  assert(s.pending,'No original uncertain action; run mole for automatic chest recovery.')
  assert(argv[2]=='before' or argv[2]=='after','Use mole recover before|after after checking the physical pose.')
  if argv[2]=='after' then
    s.p=copy(s.pending.after)
    if s.pending.route=='push' then s.route[#s.route+1]=copy(s.p)
    elseif s.pending.route=='pop' then table.remove(s.route)
    elseif s.pending.route=='out' then
      s.service.at=s.service.at+1
      s.route={}; for i=1,s.service.at do s.route[i]=copy(s.service.path[i]) end
    end
  end
  s.pending=nil; save(); log('Pose confirmed; run mole to continue.'); return
end
local dx={0,1,0,-1}; local dz={1,0,-1,0}
-- Only cells reached by a successful move become route-planning nodes.
-- Nearby visited cells may be connected, but every move still rechecks them.
s.tunnels=s.tunnels or {}; s.blocked={}
local origin={x=0,y=0,z=0}
local function recordCell(p) s.tunnels[key(p)]=true; s.blocked[key(p)]=nil end
recordCell(origin)
for _,p in ipairs(s.route) do recordCell(p) end
local function adjacent(p)
  return {{x=p.x+1,y=p.y,z=p.z},{x=p.x-1,y=p.y,z=p.z},
    {x=p.x,y=p.y+1,z=p.z},{x=p.x,y=p.y-1,z=p.z},
    {x=p.x,y=p.y,z=p.z+1},{x=p.x,y=p.y,z=p.z-1}}
end
local function knownPath(start,goal)
  local sk,gk=key(start),key(goal)
  if not s.tunnels[sk] or not s.tunnels[gk] or s.blocked[gk] then return nil end
  if sk==gk then return {} end
  local queue={copy(start)}; local at=1; local previous={[sk]=false}; local positions={[sk]=copy(start)}
  while at<=#queue do
    local p=queue[at]; at=at+1
    for _,q in ipairs(adjacent(p)) do
      local k=key(q)
      if s.tunnels[k] and not s.blocked[k] and previous[k]==nil then
        previous[k]=key(p); positions[k]=q; queue[#queue+1]=q
        if k==gk then
          local reverse={}; local current=k
          while current~=sk do reverse[#reverse+1]=positions[current]; current=previous[current] end
          local path={}; for i=#reverse,1,-1 do path[#path+1]=copy(reverse[i]) end
          return path
        end
      end
    end
  end
end
local function copyPath(path)
  local result={}; for i,p in ipairs(path) do result[i]=copy(p) end; return result
end
local function obstruction(why)
  local code=failureCode(why)
  return code=='PATH_BLOCKED' or code=='MOVE_BLOCKED'
end
local function inside(p) return p.x>=0 and p.x<c.width and p.z>=0 and p.z<c.length and p.y>=1 and p.y<=c.depth end
-- Persist intent before physical actions; unfinished actions trigger chest homing.
local passable={['minecraft:water']=true,['minecraft:lava']=true}
local function protectedBlock(b,per)
  return peripheral.isPresent(per) or b and (c.protected[b.name]
    or b.name:find('shulker_box',1,true) or b.name:find('turtle',1,true))
end
local function action(fn, after, route, probe)
  s.pending={before=copy(s.p),after=copy(after),route=route,probe=probe,fuel=turtle.getFuelLevel()}; save()
  local ok,why=fn()
  if ok then
    s.p=copy(after); recordCell(s.p)
    if probe then passable[probe]=true end
    if route=='push' then s.route[#s.route+1]=copy(s.p)
    elseif route=='pop' then table.remove(s.route)
    elseif route=='out' then
      s.service.at=s.service.at+1
      s.route={}; for i=1,s.service.at do s.route[i]=copy(s.service.path[i]) end
    end
  end
  s.pending=nil; save(); return ok,why
end
local function face(d)
  while s.p.d~=d do
    local p=copy(s.p)
    local left=(d-p.d)%4==3
    p.d=(p.d+(left and -1 or 1))%4
    assert(action(left and turtle.turnLeft or turtle.turnRight,p),'Turn failed')
  end
end
local function refuelTo(n)
  n=math.min(n,capacity())
  local before=fuel()
  if before>=n then turtle.select(1); return end -- Keep the fuel check; skip needless item queries.
  for i=1,16 do
    if fuel()>=n then break end
    local item=turtle.getItemDetail(i)
    if item and c.fuel[item.name] then
      turtle.select(i)
      while fuel()<n and turtle.getItemCount(i)>0 do
        if not turtle.refuel(1) then break end
      end
    end
  end
  turtle.select(1)
  if s and (s.phase=='home' or s.phase=='recovery' or s.phase=='emergency') and fuel()>before then
    log('Return fuel safety: used carried fuel ('..before..' -> '..fuel()..' units).')
  end
end
-- Enough for a failed hypothesis, retracing it, and the correct return.
local function reserve(n) return 3*(n+2)+c.fuelMargin end
local function freeSlots()
  local n=0
  for i=1,16 do
    if turtle.getItemCount(i)==0 then n=n+1; if n==2 then return n end end
  end
  return n -- Callers only need to know whether at least two slots are empty.
end
local function trash()
  if not c.discardTrash or not same(s.p,origin) then return end
  for i=1,16 do
    local v=turtle.getItemDetail(i)
    if v and c.trash[v.name] and not c.fuel[v.name] then
      local occupied=turtle.inspectDown()
      if occupied or peripheral.isPresent('bottom') then
        turtle.select(1)
        error('Trash drop blocked below start; clear the space underneath, then run mole.',0)
      end
      turtle.select(i)
      if not turtle.dropDown() or turtle.getItemCount(i)>0 then
        turtle.select(1)
        error('Trash could not be dropped below start; clear the space underneath, then run mole.',0)
      end
    end
  end
  turtle.select(1)
end
local function guardedDig(side)
  local inspect=side=='up' and turtle.inspectUp or side=='down' and turtle.inspectDown or turtle.inspect
  local dig=side=='up' and turtle.digUp or side=='down' and turtle.digDown or turtle.dig
  local per=side=='up' and 'top' or side=='down' and 'bottom' or 'front'
  local exists,b=inspect()
  if not exists then return true end
  if b.name=='minecraft:water' or b.name=='minecraft:lava' then return true end
  if c.protected[b.name] or peripheral.isPresent(per)
    or b.name:find('shulker_box',1,true) or b.name:find('turtle',1,true) then
    failure('PROTECTED_BLOCK','Protected block: '..b.name)
  end
  if freeSlots()<2 then failure('INVENTORY_FULL','Inventory reserve reached') end
  local ok,why=dig(); if not ok then failure('DIG_BLOCKED','Cannot dig '..b.name..': '..tostring(why)) end
  return true
end
local function step(target, mode, clearedOnly)
  local side='front'; local move=turtle.forward
  if target.y<s.p.y then side='up'; move=turtle.up
  elseif target.y>s.p.y then side='down'; move=turtle.down
  elseif target.x~=s.p.x then face(target.x>s.p.x and 1 or 3)
  else face(target.z>s.p.z and 0 or 2) end
  assert(math.abs(target.x-s.p.x)+math.abs(target.y-s.p.y)+math.abs(target.z-s.p.z)==1,'Nonadjacent route')
  refuelTo(reserve(#s.route+1)+2)
  if (mode=='push' or mode=='out') and fuel()<=math.max(reserve(#s.route+1),ascentDistance(target.y)+c.emergencyFuelMargin+32) then
    failure('FUEL_RESERVE','Fuel reserve reached')
  end
  if mode=='pop' and #s.route>ascentDistance(s.p.y) and fuel()<=ascentDistance(s.p.y)+c.emergencyFuelMargin+8 then
    failure('RETURN_FUEL_LOW','Return would consume the emergency ascent reserve')
  end
  if mode=='pop' and fuel()<#s.route+c.fuelMargin then
    failure('INSUFFICIENT_RETURN_FUEL','Insufficient fuel for the remaining known return route; stopped safely.')
  end
  if fuel()<1 then failure('NO_FUEL','Out of fuel; stopped at '..key(s.p)) end
  for _=1,c.retries do
    refuelTo(reserve(#s.route+1)+2)
    local inspect=side=='up' and turtle.inspectUp or side=='down' and turtle.inspectDown or turtle.inspect
    local exists,b=inspect()
    local per=side=='up' and 'top' or side=='down' and 'bottom' or 'front'
    if protectedBlock(exists and b or nil,per) then
      if clearedOnly then failure('PATH_BLOCKED','Known tunnel blocked: '..key(target)..' (protected block or peripheral)') end
      failure('PROTECTED_BLOCK','Protected block: '..(b and b.name or 'peripheral'))
    end
    local p=copy(target); p.d=s.p.d
    -- Unknown solids and modded fluids are distinguished by a real, journaled
    -- movement attempt. Never cache failure: it might be an entity obstruction.
    if exists and not passable[b.name] and not c.trash[b.name] then
      if action(move,p,mode,b.name) then return true end
    elseif exists and passable[b.name] then
      if action(move,p,mode,b.name) then return true end
    end
    if not (exists and passable[b.name]) then
      if clearedOnly then
        if exists then failure('PATH_BLOCKED','Known tunnel blocked: '..key(target)..' ('..b.name..')') end
      else guardedDig(side) end
      if action(move,p,mode) then return false end
    end
    sleep(0.2) -- Wait for falling gravel or an entity; do not attack mobs.
  end
  failure('MOVE_BLOCKED','Movement blocked at '..key(target))
end
local function knownStep(target,mode)
  local ok,why=pcall(step,target,mode,true)
  if ok then return true end
  if s.pending or not obstruction(why) then error(why,0) end
  s.blocked[key(target)]=true; save()
  log(tostring(why)..'; looking for another visited route.')
  return false,why
end
-- Shared A* search with a stable binary heap. Equal-cost choices keep their
-- insertion order; the caller supplies movement bounds, obstacles and budget.
local function findPath(start,goal,neighbors,allowed,estimate,budget)
  local heap={};local sequence=0
  local function earlier(a,b) return a.score<b.score or a.score==b.score and a.order<b.order end
  local function push(p,cost)
    sequence=sequence+1
    local item={p=p,cost=cost,score=cost+estimate(p),order=sequence};local i=#heap+1
    while i>1 do
      local parent=math.floor(i/2)
      if not earlier(item,heap[parent]) then break end
      heap[i]=heap[parent];i=parent
    end
    heap[i]=item
  end
  local function pop()
    local first=heap[1];local last=table.remove(heap)
    if #heap>0 then
      local i=1
      while i*2<=#heap do
        local child=i*2
        if child+1<=#heap and earlier(heap[child+1],heap[child]) then child=child+1 end
        if not earlier(heap[child],last) then break end
        heap[i]=heap[child];i=child
      end
      heap[i]=last
    end
    return first
  end
  local sk=key(start);local costs={[sk]=0};local previous={};local positions={[sk]=copy(start)};local closed={}
  push(copy(start),0)
  while #heap>0 do
    local item=pop();local p=item.p;local pk=key(p)
    if not closed[pk] and item.cost==costs[pk] then
      closed[pk]=true
      if goal(p) then
        local reverse={};local k=pk
        while k~=sk do reverse[#reverse+1]=positions[k];k=previous[k] end
        local path={};for i=#reverse,1,-1 do path[#path+1]=copy(reverse[i]) end
        return path
      end
      for _,q in ipairs(neighbors(p)) do
        local k=key(q);local n=item.cost+1
        if not closed[k] and allowed(q) and n+estimate(q)<=budget and (not costs[k] or n<costs[k]) then
          costs[k]=n;previous[k]=pk;positions[k]=q;push(q,n)
        end
      end
    end
  end
end
-- Optimistic A* plans emergency excavation; each cell is inspected before digging.
-- A one-cell positive-edge margin lets even a single-column shaft be bypassed.
local function escapePath()
  return findPath(s.p,function(p) return same(p,origin) end,adjacent,
    function(p) return p.x>=0 and p.x<=c.width and p.z>=0 and p.z<=c.length
      and p.y>=0 and p.y<=c.depth and not s.blocked[key(p)] end,
    function(p) return math.abs(p.x)+math.abs(p.y)+math.abs(p.z) end,fuel()-c.fuelMargin)
end
local function excavateHome()
  local path=escapePath()
  if not path or #path==0 then failure('NO_HOME_ROUTE','Unable to find a return detour within the area and remaining fuel.') end
  local q=path[1]
  local ok,why=pcall(step,q,'push',false)
  if not ok then
    if s.pending or not (obstruction(why) or failureCode(why)=='PROTECTED_BLOCK' or failureCode(why)=='DIG_BLOCKED') then error(why,0) end
    s.blocked[key(q)]=true; save()
    log('Return detour blocked; trying another approach.')
  end
  -- Never journal an optimistic path as visited. Successful moves alone extend
  -- the physical trail, so interruptions still have a truthful recovery route.
  local connected=knownPath(origin,s.p)
  if connected then s.route=connected; s.service.excavating=nil; save() end
end
local function homeStep()
  local n=#s.route
  if n==0 then return end
  if s.service.excavating then excavateHome(); return end
  local target=n==1 and origin or s.route[n-1]
  local ok,why=knownStep(target,'pop')
  if not ok then
    local alternate=knownPath(origin,s.p)
    if not alternate then
      -- Try reopening the original passage before excavating around it.
      local reopened,err=pcall(step,target,'pop',false)
      if reopened then return end
      if s.pending or not (obstruction(err) or failureCode(err)=='PROTECTED_BLOCK' or failureCode(err)=='DIG_BLOCKED') then error(err,0) end
      s.service.excavating=true; save()
      log('No clear recorded route; excavating a detour toward home.')
      excavateHome(); return
    end
    s.route=alternate; save()
    log('Alternative return route: '..#s.route..' steps.')
  end
end
local function gotoWork(p)
  if s.tunnels[key(p)] then
    while not same(s.p,p) do
      local path=knownPath(s.p,p)
      if not path then failure('NO_ROUTE','No clear known route to the saved work position.') end
      for _,q in ipairs(path) do if not knownStep(q,'push') then break end end
    end
    return
  end
  -- New shaft and tunnel cells are excavated only inside the work footprint.
  while s.p.y~=p.y do
    step({x=s.p.x,y=s.p.y+(p.y>s.p.y and 1 or -1),z=s.p.z},'push')
  end
  while s.p.x~=p.x do step({x=s.p.x+(p.x>s.p.x and 1 or -1),y=s.p.y,z=s.p.z},'push') end
  while s.p.z~=p.z do step({x=s.p.x,y=s.p.y,z=s.p.z+(p.z>s.p.z and 1 or -1)},'push') end
end
local function chest()
  face(2)
  if not peripheral.hasType('front','inventory') then failure('MISSING_CHEST','Output chest missing or unsupported; replace it behind origin.') end
  if not s.anchor then
    s.anchor={type=peripheral.getType('front'),size=peripheral.wrap('front').size()}; save()
  end
end
local function organizeFuel(inv)
  local contents=inv.list();local prefix=0
  for i=1,inv.size() do if not contents[i] or not c.fuel[contents[i].name] then break end;prefix=i end
  local zone=math.min(inv.size(),math.max(s.fuelZone or 0,prefix))
  if s.fuelZone~=zone then s.fuelZone=zone;save() end
  if zone==0 or type(inv.pushItems)~='function' then return end
  local remaining=0
  for i=1,zone do if contents[i] and c.fuel[contents[i].name] then remaining=remaining+1 end end
  if remaining==prefix then return end -- Already organized; avoid repeated peripheral reads.
  for target=1,zone do
    contents=inv.list();local source
    for i=target,zone do if contents[i] and c.fuel[contents[i].name] then source=i;break end end
    if not source then break end
    if source~=target then
      if contents[target] then
        local empty
        for i=inv.size(),1,-1 do if i~=target and not contents[i] then empty=i;break end end
        if not empty then failure('CHEST_FULL','Chest needs an empty slot to organize fuel. Make room and run mole.') end
        local moved=inv.pushItems('front',target,contents[target].count,empty)
        if moved~=contents[target].count then failure('CHEST_CHANGED','Chest changed while moving output away from fuel; retry.') end
      end
      local item=inv.list()[source]
      if not item or not c.fuel[item.name] then failure('CHEST_CHANGED','Chest fuel changed during organization; retry.') end
      local moved=inv.pushItems('front',source,item.count,target)
      if moved~=item.count then failure('CHEST_CHANGED','Could not organize the chest fuel; retry.') end
    end
  end
end
local function unload()
  chest()
  trash()
  -- Return fuel first, so cargo cannot occupy the first available fuel slots.
  for pass=1,2 do
    for i=1,16 do
      local item=turtle.getItemDetail(i)
      if item and ((pass==1 and c.fuel[item.name]) or (pass==2 and not c.fuel[item.name])) then
        turtle.select(i)
        if turtle.getItemCount(i)>0 and not turtle.drop() then failure('CHEST_FULL','Output chest full; empty it and run mole.') end
        if turtle.getItemCount(i)>0 then failure('CHEST_FULL','Output chest full; empty it and run mole.') end
      end
    end
  end
  turtle.select(1)
end
local function fuelText() return fuel()==math.huge and 'unlimited' or tostring(fuel())..' fuel units' end
local function chestFuel(target,minimum)
  chest(); local inv=peripheral.wrap('front')
  organizeFuel(inv)
  refuelTo(target)
  local sequence={}; local contents=inv.list()
  for i=1,inv.size() do
    local item=contents[i]
    if not item or not c.fuel[item.name] then break end
    sequence[#sequence+1]={slot=i,name=item.name,count=item.count}
  end
  local problem
  for _,entry in ipairs(sequence) do
    if fuel()>=target then break end
    local listed=inv.list()
    for i=1,entry.slot-1 do
      if listed[i] then problem='Chest fuel order changed while refueling; check the first slots and retry.'; break end
    end
    if problem then break end
    local live=listed[entry.slot]
    if not live or live.name~=entry.name or live.count~=entry.count then
      problem='Chest fuel changed while refueling; check the first slots and retry.'; break
    end
    local slot
    for i=1,16 do if turtle.getItemCount(i)==0 then slot=i; break end end
    if not slot then problem='No space for more fuel or empty buckets; rearrange the chest fuel and retry.'; break end
    turtle.select(slot)
    if not turtle.suck(math.min(entry.count,64)) then problem='Could not take the next fuel item; check the chest and retry.'; break end
    local taken=turtle.getItemDetail(slot)
    if not taken or taken.name~=entry.name or turtle.getItemCount(slot)~=math.min(entry.count,64) then
      problem='Chest extraction did not match the fuel sequence; items will be returned. Check the chest and retry.'; break
    end
    local before=fuel(); refuelTo(target)
    if fuel()==before then problem='This configured fuel cannot refuel the turtle; check the fuel list.'; break end
    -- Keep empty buckets and unused fuel onboard until the sequence finishes.
  end
  log('Fuel after chest refueling: '..fuelText()..' (target: '..target..').')
  unload()
  organizeFuel(inv)
  if problem then failure('CHEST_CHANGED',problem) end
  if fuel()<minimum then failure('NEED_FUEL','Need more fuel for a safe departure: '..minimum..' units required. Refill the front fuel area and run mole.') end
  if fuel()<target then log('Preferred fuel target not reached; safe minimum '..minimum..' is met, so mining can continue.') end
end
local function requestService(reason, pause)
  local trail=#s.route
  local shortest=knownPath(origin,s.p)
  if shortest then s.route=shortest end
  log('Returning to starting chest: '..reason..' ('..#s.route..' steps; trail was '..trail..'; '..depthText(s.p)..')')
  s.service={path=copyPath(s.route),target=copy(s.p),at=0,pause=pause,reason=reason}
  s.phase='home'; save()
end
local function service()
  if s.phase=='home' then
    while #s.route>0 do homeStep() end
    if s.service.reset then s.service.path={}; s.service.target=copy(origin) end
    s.phase='dock'; save()
  end
  if s.phase=='dock' then
    log('At starting chest: '..s.service.reason..'. Fuel: '..fuelText()..'.')
    log(c.discardTrash and 'Unloading: trash goes below the turtle; kept items go into the chest.'
      or 'Unloading all items into the chest (trash dropping is off).')
    chest();organizeFuel(peripheral.wrap('front'))
    unload()
    organizeFuel(peripheral.wrap('front'))
    if s.service.reason=='Quarry complete' then
      s.phase='done'; save(); log('Complete; inventory unloaded. Remaining fuel: '..fuelText()..'. No refueling needed.'); return false
    end
    if s.service.pause then
      s.phase='paused'; save(); log('Refueling deferred while paused. Fuel: '..fuelText()..'.')
      log('Paused: '..s.service.reason..'. Fix it, then run mole.'); return false
    end
    local target=s.service.target or s.service.path[#s.service.path] or origin
    local shortest=knownPath(origin,target)
    if shortest then s.service.path=shortest end
    s.service.target=copy(target); s.service.at=0; save()
    local n=#s.service.path
    local escapeNeeded=ascentDistance(target.y)
    local needed=n+math.max(reserve(n),escapeNeeded>0 and escapeNeeded+c.emergencyFuelMargin+32 or 0)+64
    assert(needed<=capacity() or fuel()==math.huge,'Route exceeds fuel capacity; reduce depth, emergency target Y, or vein limits.')
    local fuelTarget=math.min(capacity(),math.max(c.fuelTarget,needed))
    log('Fuel target: '..fuelTarget..' units, for '..n..' moves back to work, a safe return/recovery reserve, and more mining.')
    if fuel()>=fuelTarget then
      log('Fuel already meets the target; no additional fuel needed.')
    else
      log('Taking fuel from consecutive chest slots until the target is reached. Whole items may take fuel above the target.')
    end
    log('Minimum fuel for safe departure: '..needed..' units.')
    chestFuel(fuelTarget,needed)
    s.phase='out'; save()
  end
  if s.phase=='out' then
    while s.service.at<#s.service.path do
      local p=s.service.path[s.service.at+1]
      if not knownStep(p,'out') then
        local target=s.service.target or s.service.path[#s.service.path]
        local tail=knownPath(s.p,target)
        if not tail then
          s.phase='home'; s.service.pause=true; s.service.reason='Work route blocked; returned home for safety'; save()
          return service()
        end
        s.service.path=copyPath(s.route); s.service.at=#s.route
        for _,q in ipairs(tail) do s.service.path[#s.service.path+1]=copy(q) end
        save()
      end
      -- Route is the completed outbound prefix, reconstructed after each checkpoint.
      s.route={}; for i=1,s.service.at do s.route[i]=copy(s.service.path[i]) end; save()
    end
    s.phase='work'; s.service=nil; save()
  end
  return true
end
-- A one-block-high tunnel grid. Two stone columns stay between long
-- tunnels; endpoint connectors and the entry shaft are scanned too.
local plan,bandStarts={},{}
local rows={}
for x=0,c.width-1,3 do rows[#rows+1]=x end
if c.width-1>rows[#rows]+1 then rows[#rows+1]=c.width-1 end
local previousDepth=0
for band=0,math.ceil(c.depth/3)-1 do
  local y=math.min(2+3*band,c.depth)
  bandStarts[band+1]=#plan+1
  for shaftY=previousDepth+1,y do plan[#plan+1]={x=0,y=shaftY,z=0,band=band+1} end
  local lastX=0
  for row,x in ipairs(rows) do
    local startZ=row%2==1 and 0 or c.length-1
    if row>1 then
      for connectorX=lastX+1,x do plan[#plan+1]={x=connectorX,y=y,z=startZ,band=band+1} end
    end
    -- The first point is already the shaft or connector endpoint.
    for offset=1,c.length-1 do
      local z=row%2==1 and offset or c.length-1-offset
      plan[#plan+1]={x=x,y=y,z=z,band=band+1}
    end
    lastX=x
  end
  previousDepth=y
end
local total=#plan
local function cell(i) return plan[i] end
-- Old excavation checkpoints used a different cell numbering scheme.
-- Remember their vertical band; convert only after reaching the chest.
if not s.layoutVersion and s.upgradeBand==nil then
  s.upgradeBand=math.floor((s.index-1)/(c.width*c.length)); save()
end
local function upgradeAtDock()
  if s.upgradeBand==nil then return end
  assert(#s.route==0 and s.p.x==0 and s.p.y==0 and s.p.z==0,'Update requires the starting chest.')
  s.index=bandStarts[s.upgradeBand+1] or total+1
  s.upgradeBand=nil; s.layoutVersion=2; s.vein=nil
  if s.service then s.service.path={}; s.service.target=copy(origin); s.service.at=0 end
  save(); log('Updated to tunnel mining. Existing depth progress kept.')
end
local function neighbour(p,d)
  local q=copy(p)
  if d==4 then q.y=q.y-1 elseif d==5 then q.y=q.y+1
  else q.x=q.x+dx[d+1]; q.z=q.z+dz[d+1] end
  return q
end
-- Keep the scan order in each saved frame so a restart resumes the same
-- neighbor. Legacy frames retain their original absolute direction order.
local function scanDirection(frame) return frame.order and frame.order[frame.next+1] or frame.next end
local function scanFrame(p)
  local d=p.d
  return {p=copy(p),next=0,order={4,5,d,(d+1)%4,(d+2)%4,(d+3)%4}}
end
local function vein()
  if not s.vein then s.vein={stack={scanFrame(s.p)},count=0}; save() end
  while #s.vein.stack>0 do
    local v=s.vein; local f=v.stack[#v.stack]
    local parent=v.stack[#v.stack-1]
    local returning=f.next>=6 or v.count>=c.veinLimit or #v.stack>c.veinDepth
    if not same(s.p,f.p) and not (returning and parent and same(s.p,parent.p)) then gotoWork(f.p) end
    if f.next>=6 or v.count>=c.veinLimit or #v.stack>c.veinDepth then
      local parent=v.stack[#v.stack-1]
      if parent and not same(s.p,parent.p) then step(parent.p,'pop') end
      table.remove(v.stack); save()
    else
      local d=scanDirection(f); local q=neighbour(f.p,d)
      if inside(q) and not s.seen[key(q)] then
        local inspect
        if d==4 then inspect=turtle.inspectUp elseif d==5 then inspect=turtle.inspectDown
        else face(d); inspect=turtle.inspect end
        local ok,b=inspect()
        local per=d==4 and 'top' or d==5 and 'bottom' or 'front'
        if ok and not protectedBlock(b,per) and not passable[b.name] and not c.trash[b.name] then
          local traversed=step(q,'push'); s.seen[key(q)]=true
          if traversed then
            -- This was a fluid/passable block, not a deposit to follow.
            step(f.p,'pop',true); f.next=f.next+1; save()
          else
            v.count=v.count+1
            f.next=f.next+1; v.stack[#v.stack+1]=scanFrame(s.p); save()
          end
        else f.next=f.next+1; save() end
      else f.next=f.next+1; save() end
    end
    refuelTo(reserve(#s.route+1)+4)
    if freeSlots()<2 or fuel()<=reserve(#s.route+1)+3 then
      requestService('Inventory or fuel reserve',false); return false
    end
  end
  s.vein=nil; save(); return true
end
-- Recovery keeps both pose hypotheses and updates them with the same physical
-- actions. Failed trials are naturally retraced by the next candidate's trail.
local function clone(v)
  if type(v)~='table' then return v end
  local t={}; for k,x in pairs(v) do t[k]=clone(x) end; return t
end
local function applyRecovery(h,op)
  if op=='right' or op=='left' then h.p.d=(h.p.d+(op=='left' and -1 or 1))%4; return end
  local q=copy(h.p)
  if op=='up' then q.y=q.y-1 elseif op=='down' then q.y=q.y+1
  else q.x=q.x+dx[q.d+1]; q.z=q.z+dz[q.d+1] end
  -- Erase loops in the physical trace, preserving a route rooted at origin.
  local found
  if q.x==0 and q.y==0 and q.z==0 then found=0
  else for i=#h.route,1,-1 do if same(q,h.route[i]) then found=i; break end end end
  if found then for i=#h.route,found+1,-1 do h.route[i]=nil end
  else h.route[#h.route+1]=copy(q) end
  h.p=q
end
local function eachHypothesis(fn)
  for _,h in ipairs(s.recovery.hypotheses) do fn(h) end
  for _,h in ipairs(s.recovery.failed or {}) do fn(h) end
end
local function compactHypotheses()
  local seen,unique={},{}
  for _,h in ipairs(s.recovery.hypotheses) do
    local k=key(h.p)..':'..h.p.d
    for _,p in ipairs(h.route) do k=k..';'..key(p) end
    if not seen[k] then seen[k]=true; unique[#unique+1]=h end
  end
  s.recovery.hypotheses=unique
  assert(#unique+#(s.recovery.failed or {})<=16,'Repeated recovery interruptions produced too many hypotheses; saved safely.')
end
local function beginRecovery()
  local pending=s.pending
  if not pending then return end
  local before={p=copy(pending.before),route=clone(s.route)}
  local after={p=copy(pending.after),route=clone(s.route)}
  if pending.route=='push' then after.route[#after.route+1]=copy(after.p)
  elseif pending.route=='pop' then table.remove(after.route)
  elseif pending.route=='out' then
    after.route={}
    for i=1,s.service.at+1 do after.route[i]=copy(s.service.path[i]) end
  end
  local hypotheses={before,after}
  -- Fuel is a useful ordering hint for movement, not a required dependency.
  if type(pending.fuel)=='number' and fuel()==pending.fuel-1 then hypotheses={after,before} end
  local resumePath=clone(s.service and s.service.path or s.route)
  if s.service and s.service.reset then resumePath={} end
  local resumeVein=clone(s.vein)
  -- Digging precedes the move. Even if the move never happened, its target
  -- is cleared; preserve the DFS branch so ores beyond that block are found.
  if s.phase=='work' and resumeVein and pending.route=='push' and not pending.probe then
    local frame=resumeVein.stack[#resumeVein.stack]
    if frame and frame.next<6 and same(pending.before,frame.p)
      and same(pending.after,neighbour(frame.p,scanDirection(frame))) then
      resumePath=clone(after.route)
      frame.next=frame.next+1; resumeVein.count=resumeVein.count+1
      resumeVein.stack[#resumeVein.stack+1]=scanFrame(pending.after)
      s.seen[key(pending.after)]=true
    end
  end
  s.recovery={hypotheses=hypotheses,pause=s.service and s.service.pause or false,
    resumePath=resumePath,resumeVein=resumeVein,
    reason=s.service and s.service.reason or 'Interrupted action recovery'}
  s.pending=nil; s.phase='recovery'; compactHypotheses(); save()
  log('Uncertain action: homing to the starting chest without digging.')
end
local function settleRecoveryAction()
  local r=s.recovery; local pending=r.pending
  if not pending then return end
  local current=turtle.getFuelLevel()
  if pending.op~='right' and pending.op~='left' and type(pending.fuel)=='number' and type(current)=='number' then
    -- Recovery never refuels between recording intent and settling its result.
    if current==pending.fuel-1 then
      eachHypothesis(function(h) applyRecovery(h,pending.op) end)
    elseif current~=pending.fuel then
      error('Fuel changed externally during recovery; stopped safely.',0)
    end
  else
    for _,list in ipairs({r.hypotheses,r.failed or {}}) do
      local n=#list
      for i=1,n do
        local moved=clone(list[i]); applyRecovery(moved,pending.op)
        list[#list+1]=moved
      end
    end
  end
  r.pending=nil; compactHypotheses(); save()
end
local function recoveryAction(op)
  if op~='right' and op~='left' then refuelTo(c.fuelMargin+1) end
  local r=s.recovery
  r.pending={op=op,fuel=turtle.getFuelLevel()}; save()
  local fn=op=='right' and turtle.turnRight or op=='left' and turtle.turnLeft or op=='up' and turtle.up
    or op=='down' and turtle.down or turtle.forward
  local ok=fn()
  if ok then eachHypothesis(function(h) applyRecovery(h,op) end) end
  r.pending=nil; save(); return ok
end
local function recoveryFace(h,d)
  while h.p.d~=d do
    local op=(d-h.p.d)%4==3 and 'left' or 'right'
    assert(recoveryAction(op),'Recovery turn failed')
  end
end
local function anchorMatches()
  if not peripheral.hasType('front','inventory') then return false end
  if s.anchor then
    return peripheral.getType('front')==s.anchor.type and peripheral.wrap('front').size()==s.anchor.size
  end
  -- Legacy jobs created before v1.1 did not record a chest signature.
  local ok,b=turtle.inspect()
  return ok and (b.name=='minecraft:chest' or b.name=='minecraft:trapped_chest' or b.name=='minecraft:barrel')
end
local function homeRecovery()
  if s.pending then beginRecovery() end
  settleRecoveryAction()
  local r=s.recovery
  -- Check a pessimistic budget before starting any uncertain travel.
  local budget,shortest=0,math.huge
  for _,h in ipairs(r.hypotheses) do budget=budget+#h.route; shortest=math.min(shortest,#h.route) end
  if #r.hypotheses>0 then budget=2*budget-shortest end
  refuelTo(budget+c.fuelMargin)
  if fuel()<budget+c.fuelMargin then failure('RETURN_RECOVERY_FUEL','Insufficient fuel for chest recovery; saved hypotheses retained.') end
  while #r.hypotheses>0 do
    local h=r.hypotheses[1]; local reachable=true
    log('Recovery trial: '..#h.route..' steps to the predicted origin.')
    while #h.route>0 do
      local n=#h.route; local q=n==1 and {x=0,y=0,z=0} or h.route[n-1]
      assert(math.abs(q.x-h.p.x)+math.abs(q.y-h.p.y)+math.abs(q.z-h.p.z)==1,
        'Invalid recovery trail; stopped safely.')
      local op,inspect
      if q.y<h.p.y then op='up'; inspect=turtle.inspectUp
      elseif q.y>h.p.y then op='down'; inspect=turtle.inspectDown
      else
        recoveryFace(h,q.x~=h.p.x and (q.x>h.p.x and 1 or 3) or (q.z>h.p.z and 0 or 2))
        op='forward'; inspect=turtle.inspect
      end
      local moved=false
      for _=1,c.retries do
        local exists,b=inspect()
        local per=op=='up' and 'top' or op=='down' and 'bottom' or 'front'
        if protectedBlock(exists and b or nil,per) then break end
        if exists and not passable[b.name] and c.trash[b.name] then break end
        local deepest=-math.huge
        eachHypothesis(function(candidate) deepest=math.max(deepest,candidate.p.y) end)
        local climb=ascentDistance(deepest)
        refuelTo(math.max(#h.route+c.fuelMargin,climb+c.emergencyFuelMargin+9))
        if #h.route>climb and fuel()<=climb+c.emergencyFuelMargin+8 then
          failure('RETURN_FUEL_LOW','Recovery would consume the emergency ascent reserve')
        end
        if fuel()<=c.fuelMargin then failure('RECOVERY_FUEL_LOW','Recovery fuel margin reached; stopped safely.') end
        if recoveryAction(op) then
          if exists then passable[b.name]=true end
          moved=true; break
        end
        sleep(0.2)
      end
      if not moved then reachable=false; break end
    end
    if reachable then
      recoveryFace(h,2)
      if anchorMatches() then
        -- Reanchor, then replay the saved cleared route to the pending vein
        -- branch. A tunnel miner must not lose ores behind already mined air.
        s.p={x=0,y=0,z=0,d=2}; s.route={}; s.vein=r.resumeVein
        s.service={path=r.resumePath or {},at=0,pause=r.pause,reason=r.reason}
        s.phase='dock'; s.recovery=nil; save()
        log('Starting chest found. Resuming saved tunnel step '..s.index..'.')
        return
      end
    end
    -- Keep the failed candidate too: if an obstruction was temporary, the
    -- player can clear it and retry without reconstructing the turtle's pose.
    r.failed=r.failed or {}; r.failed[#r.failed+1]=table.remove(r.hypotheses,1); save()
  end
  r.hypotheses=r.failed or {}; r.failed=nil; save()
  failure('NO_CHEST_CONFIRMATION','Starting chest not found on any cleared route. No blocks were dug during normal recovery.')
end

-- Last-resort escape uses its own relative coordinates and action journal.
-- Physical up is independent of uncertain mining X/Z or facing. A conservative
-- height across all recovery hypotheses avoids stopping below the target.
local function startEmergency(reason)
  local depths={s.p.y}
  if s.recovery then
    depths={}
    for _,list in ipairs({s.recovery.hypotheses or {},s.recovery.failed or {}}) do
      for _,h in ipairs(list) do depths[#depths+1]=h.p.y end
    end
  elseif s.pending then depths={s.pending.before.y,s.pending.after.y} end
  local deepest=-math.huge; local shallowest=math.huge
  for _,d in ipairs(depths) do deepest=math.max(deepest,d);shallowest=math.min(shallowest,d) end
  assert(deepest~=-math.huge,'No height estimate for emergency ascent; saved safely.')
  s.emergency={reason=reason,p={x=0,y=ascentDistance(deepest),z=0,d=0},blocked={},
    heightUncertainty=deepest-shallowest,targetY=s.emergencyTargetY or s.startY}
  s.phase='emergency';save()
  log('EMERGENCY ASCENT: '..reason)
  log('Trying to climb '..s.emergency.p.y..' blocks to '..(s.emergency.targetY and 'Y '..s.emergency.targetY or 'the starting elevation')..'. Mining is suspended.')
end
local function emergencyAction(op,q)
  if op~='right' and op~='left' then refuelTo(1) end
  local e=s.emergency
  e.pending={before=copy(e.p),after=copy(q),op=op,fuel=turtle.getFuelLevel()};save()
  local fn=op=='up' and turtle.up or op=='right' and turtle.turnRight or op=='left' and turtle.turnLeft or turtle.forward
  local ok=fn()
  if ok then e.p=copy(q) end
  e.pending=nil;save();return ok
end
local function settleEmergency()
  local e=s.emergency;local pending=e.pending
  if not pending then return end
  if pending.op=='right' or pending.op=='left' then
    -- A turn consumes no fuel. Reanchor the horizontal map to actual facing;
    -- absolute orientation is unnecessary for a vertical retrieval escape.
    e.p={x=0,y=pending.before.y,z=0,d=0};e.blocked={}
  elseif type(pending.fuel)=='number' and fuel()~=math.huge then
    if fuel()==pending.fuel-1 then e.p=copy(pending.after)
    elseif fuel()==pending.fuel then e.p=copy(pending.before)
    else error('Fuel changed externally during emergency recovery; saved safely.',0) end
  else
    e.p={x=0,y=math.max(pending.before.y,pending.after.y),z=0,d=0};e.blocked={}
    if pending.op=='up' then e.heightUncertainty=e.heightUncertainty+1 end
  end
  e.pending=nil;save()
end
local function emergencyPath()
  local e=s.emergency
  local available=fuel()-math.min(c.emergencyFuelMargin,math.max(0,fuel()-e.p.y-8))
  local path=findPath(e.p,function(p) return p.y==0 end,
    function(p) return {{x=p.x,y=p.y-1,z=p.z},{x=p.x+1,y=p.y,z=p.z},
      {x=p.x-1,y=p.y,z=p.z},{x=p.x,y=p.y,z=p.z+1},{x=p.x,y=p.y,z=p.z-1}} end,
    function(p) return p.y>=0 and math.abs(p.x)<=c.emergencyRadius and math.abs(p.z)<=c.emergencyRadius
      and not e.blocked[key(p)] end,
    function(p) return p.y end,available)
  return path and path[1]
end
local function emergencyTrash()
  local urgent=freeSlots()<2
  if not c.discardTrash and not urgent then return end
  local directions={
    {inspect=turtle.inspectDown,drop=turtle.dropDown,per='bottom'},
    {inspect=turtle.inspect,drop=turtle.drop,per='front'},
    {inspect=turtle.inspectUp,drop=turtle.dropUp,per='top'},
  }
  for _,side in ipairs(directions) do
    local occupied,block=side.inspect()
    -- Dropping trash against ordinary stone is allowed in an emergency.
    -- Never insert it into a detected inventory or a protected/unknown block.
    if not protectedBlock(occupied and block or nil,side.per)
      and (not occupied or passable[block.name] or c.trash[block.name]) then
      for i=1,16 do
        if urgent and freeSlots()>=2 then turtle.select(1);return end
        local item=turtle.getItemDetail(i)
        if item and c.trash[item.name] and not c.fuel[item.name] then
          turtle.select(i);local before=turtle.getItemCount(i)
          side.drop()
          if turtle.getItemCount(i)<before then log('Emergency escape: discarded trash to make inventory space.') end
        end
      end
    end
  end
  turtle.select(1)
end
local function emergencyDig(side,inspect,per)
  emergencyTrash()
  if freeSlots()<2 then error('No inventory space for emergency digging; valuables kept. Clear space and run mole.',0) end
  local occupied,block=inspect()
  if protectedBlock(occupied and block or nil,per) then return false end
  if not occupied or passable[block.name] then return true end
  return (side=='up' and turtle.digUp or turtle.dig)()
end
local function emergencyAscent()
  settleEmergency()
  local e=s.emergency
  while e.p.y>0 do
    refuelTo(e.p.y+c.emergencyFuelMargin+8)
    if fuel()<e.p.y then error('Insufficient fuel for emergency ascent; progress saved. Add fuel and run mole.',0) end
    local q=emergencyPath()
    if not q then error('No emergency ascent route within the detour radius and remaining fuel; progress saved.',0) end
    local side='up';local op='up'
    if q.y==e.p.y then
      side='front';op='forward'
      local d=q.x~=e.p.x and (q.x>e.p.x and 1 or 3) or (q.z>e.p.z and 0 or 2)
      while e.p.d~=d do
        local left=(d-e.p.d)%4==3;local turn=copy(e.p);turn.d=(turn.d+(left and -1 or 1))%4
        assert(emergencyAction(left and 'left' or 'right',turn),'Emergency turn failed')
      end
    end
    local inspect=side=='up' and turtle.inspectUp or turtle.inspect
    local exists,b=inspect();local per=side=='up' and 'top' or 'front'
    local moved=false
    if not protectedBlock(exists and b or nil,per) then
      local after=copy(q);after.d=e.p.d
      -- Try traversal first; this supports vanilla and modded fluids.
      moved=emergencyAction(op,after)
      if not moved and exists and not passable[b.name] then
        local dug=emergencyDig(side,inspect,per)
        if dug then
          for _=1,c.retries do
            local solid,block=inspect()
            if protectedBlock(solid and block or nil,per) then break end
            if solid and not passable[block.name] then
              if not emergencyDig(side,inspect,per) then break end
            end
            if emergencyAction(op,after) then moved=true;break end
            sleep(0.2)
          end
        end
      elseif not moved then
        for _=1,c.retries do
          sleep(0.2)
          if emergencyAction(op,after) then moved=true;break end
        end
      end
    end
    if not moved then e.blocked[key(q)]=true;save();log('Emergency ascent blocked; trying a sideways detour.') end
  end
  s.phase='rescued';save()
  log('Emergency ascent complete. Mining paused. Turtle needs to be returned to its starting chest.')
  log('Remaining fuel after emergency ascent: '..fuelText()..'.')
  if e.heightUncertainty>0 then log('Height was uncertain; the turtle may finish '..e.heightUncertainty..' block(s) above the target.') end
  log('This is a retrieval point, not confirmation of open sky. Use mole reset only after positioning the turtle for a new job.')
end
local emergencyFailures={NO_ROUTE=true,NO_HOME_ROUTE=true,INSUFFICIENT_RETURN_FUEL=true,
  RETURN_FUEL_LOW=true,NO_CHEST_CONFIRMATION=true,RETURN_RECOVERY_FUEL=true,RECOVERY_FUEL_LOW=true,
  MISSING_CHEST=true,INVENTORY_FULL=true,FUEL_RESERVE=true,NO_FUEL=true}
local function fallbackReason(why) return emergencyFailures[failureCode(why)]==true end
local function attemptEmergency(why)
  local ok,err=pcall(function() if s.phase~='emergency' then startEmergency(tostring(why)) end;emergencyAscent() end)
  if not ok then log('Emergency escape saved: '..tostring(err)..'. Run mole to retry.') end
end
if s.phase=='rescued' then
  log('Emergency ascent already completed. Mining stays paused; retrieve the turtle and use mole reset at a safe starting point.');return
end
if s.phase=='emergency' then attemptEmergency(s.emergency.reason);return end

if argv[1]=='continue' and s.phase=='paused' then
  s.service.pause=false; s.phase='dock'; save()
end
if s.phase=='done' then
  print('Mining finished! Items are in the chest.')
  print('For a new job, face into the new area, then mole new.'); return
end
if s.phase=='paused' then
  if argv[1]=='return' then print('Already paused at the starting chest.'); return end
  log('Paused: '..tostring(s.service and s.service.reason or 'User pause'))
  if answer('Fixed the issue? Enter to resume, q to exit:'):lower()=='q' then return end
  s.service.pause=false; s.phase='dock'; save()
end
-- Resume first services the saved route, then resumes a saved vein or quarry cell.
local ok,err=pcall(function()
  if s.pending or s.recovery then homeRecovery() end
  if argv[1]=='return' then
    if s.phase=='work' or s.phase=='out' then
      local destination=s.phase=='out' and clone(s.service.path) or nil
      requestService('User requested return',true)
      if destination then s.service.path=destination; s.service.target=copy(destination[#destination] or origin); save() end
    elseif s.service then
      s.service.pause=true; s.service.reason='User requested return'; save()
    end
  end
  if s.upgradeBand~=nil then
    if s.phase~='dock' then
      requestService('Updating to tunnel mining',false); s.service.reset=true; save()
      while #s.route>0 do homeStep() end
      s.phase='dock'; save()
    end
    upgradeAtDock()
  end
  if s.index==1 and s.phase=='work' and #s.route==0 and not s.vein then
    requestService('Initial chest/fuel check',false)
  end
  while true do
    if s.phase~='work' then if not service() then return end end
    if s.index>total then
      requestService('Quarry complete',true); s.service.reason='Quarry complete'; save()
      service(); return
    end
    refuelTo(reserve(#s.route+1)+64)
    if fuel()<=math.max(reserve(#s.route+1)+32,ascentDistance(s.p.y)+c.emergencyFuelMargin+64) or freeSlots()<2 then
      requestService('Inventory or fuel reserve',false)
    else
      if not s.vein then
        local p=cell(s.index); gotoWork(p)
      end
      if vein() then
        s.index=s.index+1; save()
        if s.index%16==0 then log('Tunnel progress: '..(s.index-1)..'/'..total..'; '..depthText(s.p)) end
        if s.index<=total and plan[s.index].band~=plan[s.index-1].band then
          log('Tunnel level finished. Returning to the chest.')
          -- Reset to origin each band: shorter, predictable return paths.
          requestService('Band complete',false); s.service.reset=true; save()
        end
      end
    end
  end
end)
if not ok then
  log(tostring(err))
  if s.pending or s.recovery then
    if fallbackReason(err) then attemptEmergency(err);return end
    log('Recovery saved. Run mole (or let startup run it) to retry automatic chest homing.'); return
  end
  -- An error during a return must not overwrite the original outbound route.
  if s.phase=='work' then
    requestService(tostring(err),failureCode(err)~='FUEL_RESERVE' and failureCode(err)~='INVENTORY_FULL')
    local safe,why=pcall(service)
    if not safe then
      if fallbackReason(why) then attemptEmergency(why)
      else log('Return stopped: '..tostring(why)..'. Position '..key(s.p)..'; run mole after fixing.') end
    end
  elseif fallbackReason(err) then attemptEmergency(err)
  else log('Job saved at '..key(s.p)..'; fix issue and run mole.') end
end
