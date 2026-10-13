-- Mole v1.6.15: guided setup, selective tunnels, local coordinates, durable checkpoints, bounded vein mining.
-- Origin is the turtle's starting block. +Z is forward, +X is right, Y is down.
local VERSION='1.6.15'
local UPDATE_URL='https://raw.githubusercontent.com/Nom4d-temp/mole/main/mole.lua'
local argv = {...}
local print=print -- Keep optional output capture local to this program.
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
    ..'shell.run(program, "resume")\n'
end
local function generatedStartup(content,program)
  if not content then return false end
  local compact=content:gsub('%-%-[^\n]*',''):gsub('%s+','')
  return content==startupText(program) or content==startupText(program):gsub('shell%.run%(program, "resume"%)','shell.run(program)') or (content:find('-- Automatically resume the saved mining job.',1,true)==1
    and compact=='shell.run('..string.format('%q',program)..')')
    or compact=="iffs.exists('quarry-data/state.a')orfs.exists('quarry-data/state.b')thenshell.run('mole')end"
    or compact=="iffs.exists('quarry-data/state.a')orfs.exists('quarry-data/state.b')thenshell.run('mole','resume')end"
end
if argv[1]=='delete' then
  print('This removes Mole, its saved jobs, emergency data, and settings.')
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
  print('[Mole] Reset complete. Saved jobs, emergency data, and custom settings cleared.')
  print("To start a new job, place the turtle with a chest behind it and type 'mole new'.")
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
local function fuelText() return fuel()==math.huge and 'unlimited' or tostring(fuel())..' fuel units' end
local function depthText(p)
  return 'Y '..(s.startY-p.y)..' ('..p.y..' blocks below start)'
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
-- Optional networking: disabled unless explicitly paired. Network callbacks
-- only queue requests; the mining coroutine owns all turtle/checkpoint actions.
local net={protocol='mole-companion/1',queue={},seq={},active=false}
function net.clock() return os.epoch and os.epoch('utc')/1000 or os.time() end
function net.clean(v,n) return type(v)=='string' and v:gsub('[%c]',' '):sub(1,n or 160) or nil end
function net.validNumber(n) return type(n)=='number' and n==n and math.abs(n)~=math.huge and n%1==0 end
function net.readProfile()
  local ok,p=pcall(readFile,ROOT..'/companion')
  if ok and type(p)=='table' and p.enabled==true and net.validNumber(p.station) and p.station>=0
    and type(p.token)=='string' and #p.token>=8 and #p.token<=96 then return p end
end
function net.modem()
  if not peripheral.getNames or not rednet or not rednet.open then return nil end
  for _,name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name,'modem') then
      local p=peripheral.wrap(name);local ok,v=pcall(p.isWireless)
      if ok and v then rednet.open(name);return name end
    end
  end
end
function net.setup()
  net.profile=net.readProfile()
  if not net.profile then return end
  local ok,name=pcall(net.modem);if not ok or not name then return end
  net.modemName=name;net.active=true
  net.session=tostring(net.clock())..'-'..tostring(os.getComputerID())..'-'..math.random(100000,999999)
end
function net.packet(kind,body)
  if not net.active then return end
  net.seq[kind]=(net.seq[kind] or 0)+1
  body.v=1;body.kind=kind;body.token=net.profile.token;body.session=net.session;body.seq=net.seq[kind]
  return body
end
function net.send(kind,body)
  local p=net.packet(kind,body);if not p then return false end
  local ok,result=pcall(rednet.send,net.profile.station,p,net.protocol)
  return ok and result
end
function net.enqueue(kind,body)
  if not net.active then return end
  net.queue[#net.queue+1]={kind,body}
  if #net.queue>80 then table.remove(net.queue,1) end
end
function net.record(...)
  if not net.active then return end
  local parts={...};for i,v in ipairs(parts) do parts[i]=tostring(v) end
  local line=table.concat(parts,' '):gsub('[%c]',' ')
  if line:match('^%[Mole%] Tunnel progress:') or line:match('^%[Mole%] Mining tunnels at Y') then return end
  repeat net.enqueue('log',{text=line:sub(1,256)});line=line:sub(257) until #line==0
end
function net.status()
  if not net.active or not s or not s.startY then return end
  local names={work='Mining',home='Returning home',out='Returning to work',dock='At the chest',paused='Paused',done='Finished',recovery='Recovering position',emergency='Emergency escape',rescued='Waiting for retrieval'}
  -- A live journal entry is normal motion, not a lost pose. A pending
  -- entry after restart/error still requires the existing recovery routine.
  local moving=net.running and net.inFlight and not s.recovery
  local uncertain=s.recovery~=nil or s.pending~=nil and not moving
  local used=0;for slot=1,16 do if turtle.getItemCount(slot)>0 then used=used+1 end end
  local p=s.p;local detail=s.service and s.service.reason or nil
  local y=s.startY-p.y
  if s.emergency then
    y=(s.emergency.targetY or s.startY)-s.emergency.p.y
    detail='Emergency climb: '..s.emergency.p.y..' blocks left. Horizontal quarry position is unknown.'
    uncertain=true
  end
  net.send('status',{job=s.companionJob,phase=names[s.phase] or s.phase,y=y,depth=s.startY-y,
    right=p.x,forward=p.z,inventory=used,fuel=fuel()==math.huge and 'unlimited' or fuel(),uncertain=uncertain,moving=moving==true,detail=detail,
    progress='Tunnels: '..math.max(0,s.index-1)..(net.total and '/'..net.total or '')})
end
function net.flush()
  local queue=net.queue;net.queue={}
  for _,item in ipairs(queue) do net.send(item[1],item[2]) end
end
function net.receipt(id,result,detail)
  net.enqueue('ack',{request=id,result=result,detail=detail})
end
function net.handle(sender,msg,protocol)
  if not net.active or protocol~=net.protocol or sender~=net.profile.station or type(msg)~='table'
    or msg.v~=1 or msg.token~=net.profile.token or msg.kind~='command' or msg.action~='return'
    or type(msg.request)~='string' or #msg.request<1 or #msg.request>96 then return end
  for _,r in ipairs(s.companionRequests or {}) do
    if r.id==msg.request then net.receipt(r.id,r.result,r.detail);return end
  end
  local sent=tonumber(msg.request:match('^(%d+%.?%d*)%-'))
  if sent and net.clock()-sent>30 then net.receipt(msg.request,'rejected','Return request expired. Refresh status and try again.');return end
  if msg.session~=net.session then net.receipt(msg.request,'rejected','Turtle restarted. Refresh status and request return again.');return end
  if s.phase=='paused' and s.p.x==0 and s.p.y==0 and s.p.z==0 then net.receipt(msg.request,'completed','Already home and paused.');return end
  if s.phase=='recovery' or s.phase=='emergency' or s.phase=='rescued' or s.phase=='done' then
    net.receipt(msg.request,'rejected','Current state: '..s.phase..'. Check turtle status.');return
  end
  if net.pending and net.pending.id~=msg.request or s.companionReturn and s.companionReturn.result=='accepted' then
    net.receipt(msg.request,'rejected','Another return is already in progress.');return
  end
  net.pending={id=msg.request,received=net.clock()}
end
function net.isOre(id) return id:match('^minecraft:.*_ore$') or id=='minecraft:ancient_debris' end
function net.blocks(n) return n..' block'..(n==1 and '' or 's') end
function net.mining(block)
  if c.trash[block.name] or net.isOre(block.name) or net.lastBlock==block.name then return end
  net.lastBlock=block.name
  log('Mining unfamiliar block: '..block.name)
  net.flush()
end
function net.discovery(block)
  if not net.profile or not net.profile.enabled or not s or c.trash[block.name] then return end
  local known=net.isOre(block.name)
  if known then return end
  s.companionBlocks=s.companionBlocks or {}
  local old=s.companionBlocks[block.name]
  if not old then local n=0;for _ in pairs(s.companionBlocks) do n=n+1 end;if n>=128 then return end end
  local item={count=(old and old.count or 0)+1,name=net.clean(block.displayName,64)}
  s.companionBlocks[block.name]=item
  net.enqueue('discovery',{job=s.companionJob,block=block.name,name=item.name,count=item.count})
end
function net.replay()
  if not net.active or not s then return end
  for id,b in pairs(s.companionBlocks or {}) do net.send('discovery',{job=s.companionJob,block=id,name=b.name,count=b.count}) end
end
function net.run(main)
  if not net.profile then return main() end
  if not net.active then print('Companion offline; mining continues.') end
  if not s.companionJob then s.companionJob='quarry-'..tostring(net.clock())..'-'..s.seq..'-'..math.random(100000,999999) end
  local nativePrint=print
  print=function(...) nativePrint(...);pcall(net.record,...) end
  local function mining()
    net.running=true
    local result={main()}
    net.running=false
    pcall(net.status);pcall(net.flush)
    return table.unpack(result)
  end
  if not parallel or not parallel.waitForAny or not os.pullEvent or not rednet then return mining() end
  local function listener()
    local retrying=false
    while true do
      local ok,why=pcall(function()
        local nextStatus=0;local replayAt=0
        while true do
          if net.modemName and not peripheral.isPresent(net.modemName) then net.active=false end
          if not net.active then local found,name=pcall(net.modem);if found and name then net.active=true;net.modemName=name;net.session=net.session or tostring(net.clock())..'-'..os.getComputerID();nextStatus=0 end end
          if net.active then
            if net.clock()>=nextStatus then net.status();nextStatus=net.clock()+5 end
            if net.clock()>=replayAt then
              if replayAt==0 and s.companionReturn then net.receipt(s.companionReturn.id,s.companionReturn.result,s.companionReturn.detail) end
              net.replay();replayAt=net.clock()+15
            end
            net.flush()
          end
          local id,msg,protocol=rednet.receive(net.protocol,1)
          if retrying and net.active then pcall(nativePrint,'[Mole] Companion reporting restarted.');retrying=false end
          if id then net.handle(id,msg,protocol) end
        end
      end)
      if not ok and tostring(why)=='Terminated' then error(why,0) end
      net.active=false
      if not retrying then pcall(nativePrint,'[Mole] Companion reporting interrupted. Retrying; mining continues.') end
      retrying=true
      -- Yield during persistent failures without ending waitForAny or
      -- cancelling mining. pullEvent preserves normal Ctrl+T handling.
      local retryTimer=os.startTimer(3)
      repeat local event,id=os.pullEvent() until event=='timer' and id==retryTimer
    end
  end
  return parallel.waitForAny(mining,listener)
end
function net.checkConnection(profile)
  local nonce=tostring(net.clock())..'-'..math.random(100000,999999)
  local deadline=net.clock()+10
  local retry=0
  while net.clock()<deadline do
    if net.clock()>=retry then
      local ok,sent=pcall(rednet.send,profile.station,{v=1,kind='ping',token=profile.token,nonce=nonce},net.protocol)
      if not ok or not sent then return false end
      retry=net.clock()+3
    end
    local id,msg=rednet.receive(net.protocol,1)
    if id==profile.station and type(msg)=='table' and msg.v==1 and msg.kind=='pong' and msg.token==profile.token and msg.nonce==nonce then return true end
  end
  return false
end
function net.menu(station,code)
  while true do
    local current=net.readProfile()
    print('Mole companion (optional)')
    print(current and 'Paired station ID: '..current.station or 'Reporting: off')
    print('1 Pair / re-pair a station')
    print('2 Unpair')
    print('3 Check connection')
    print('4 Disable reporting')
    print('Enter or q: finish')
    local choice=station and '1' or answer('Choose:'):lower()
    if choice=='' or choice=='q' then return end
    if choice=='4' then
      local profile=current or {};profile.enabled=false;writeFile(ROOT..'/companion',profile);net.active=false;net.profile=nil
      print('Wireless reporting disabled.');return
    elseif choice=='2' then
      if fs.exists(ROOT..'/companion') then fs.delete(ROOT..'/companion') end
      net.active=false;net.profile=nil;net.pending=nil;net.queue={}
      print('Turtle unpaired. Reporting is off.')
      print('Quarry job and settings kept.')
      print('Use mole companion, then 1 to pair.')
      return
    elseif choice=='3' then
      local ok,name=pcall(net.modem)
      if not ok or not name then print('No wireless/Ender modem found.')
      elseif not current then print('Modem found. Choose 1 to pair.')
      else
        print("On station, run 'companion start'.")
        print('Checking station ID '..current.station..'...')
        print(net.checkConnection(current) and 'Connection checked. Station replied.' or 'No reply. Check station, range/chunks.')
      end
    elseif choice=='1' then
      print('Step 1/4: check turtle equipment')
      print('Keep this turtle near the station.')
      print('Keep pickaxe + wireless/Ender modem.')
      while true do
        local ok,name=pcall(net.modem);if ok and name then print('Wireless modem found.');break end
        print('No wireless/Ender modem found.')
        print('Equip it, then Enter to retry.')
        if answer('Enter: retry, q: cancel:'):lower()=='q' then return end
      end
      print('Step 2/4: enter station details')
      print('On the companion computer, press P.')
      print('Its screen shows station ID + code.')
      local id
      while true do
        local raw=station or answer('Station computer ID (q cancels):')
        if tostring(raw):lower()=='q' then return end
        id=tonumber(raw);if net.validNumber(id) and id>=0 then break end
        print('Use a whole station ID, or \'q\'.')
        if station then return end
      end
      local pin
      while true do
        pin=tostring(code or answer('Pairing code (q cancels):'))
        if pin:lower()=='q' then return end
        if pin:match('^%d%d%d%d%d%d$') then break end
        print('Use the six digits shown, or \'q\'.')
        if code then return end
      end
      local hello={v=1,kind='pair_hello',code=pin,wireless=true,name=os.getComputerLabel and os.getComputerLabel() or 'Mole '..os.getComputerID()}
      local ok,sent=pcall(rednet.send,id,hello,net.protocol)
      if not ok or not sent then print('No message sent. Check the modem.');return end
      print('Step 3/4: confirm on the computer')
      print('Station ID: '..id..' | Code: '..pin)
      print('Check turtle #'..os.getComputerID()..', then Y.')
      print('Choose its name on that computer.')
      print('Waiting up to five minutes...')
      local deadline=net.clock()+300;local nextHello=net.clock()+5
      while net.clock()<deadline do
        local received,msg=rednet.receive(net.protocol,1)
        if received==id and type(msg)=='table' and msg.v==1 and msg.kind=='paired' and msg.code==pin and msg.station==id
          and type(msg.token)=='string' and #msg.token>=8 and #msg.token<=96 then
          writeFile(ROOT..'/companion',{enabled=true,station=id,token=msg.token})
          print('Step 4/4: checking the connection')
          local verified=false;local finish=net.clock()+15;local nextReady=0
          while net.clock()<finish do
            if net.clock()>=nextReady then
              pcall(rednet.send,id,{v=1,kind='pair_ready',token=msg.token,code=pin},net.protocol);nextReady=net.clock()+3
            end
            local sender,reply=rednet.receive(net.protocol,1)
            if sender==id and type(reply)=='table' and reply.v==1 and reply.kind=='pair_verified' and reply.token==msg.token and reply.code==pin then verified=true;break end
          end
          print(verified and 'Connection checked. Pairing complete.' or 'Pairing saved; final reply not seen.')
          if not verified then print('Use option 3 to check connection.') end
          print('Use mole new or mole resume to mine.');return
        end
        if net.clock()>=nextHello then pcall(rednet.send,id,hello,net.protocol);nextHello=net.clock()+5 end
      end
      print('Confirmation not completed.')
      print('Check station screen, range/chunks.')
      print('Press P there, then try pairing again.')
      print('Previous pairing kept, if present.');return
    else print('Choose 1, 2, 3, 4, or Enter.') end
  end
end
pcall(net.setup)

local function ensureStartup()
  local program=shell.getRunningProgram()
  if s and s.program~=program then s.program=program; save() end
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
  if not own then
    if not fs.exists(INSTALL) then writeFile(INSTALL,{path=path,original=content}) end
    return
  end
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
  log('Automatic restart enabled.')
end
if argv[1]=='update' then
  local function update()
    print('Installed Mole: '..VERSION..'. Checking GitHub...')
    if not http or not http.get then print('HTTP downloads are disabled; ask the server owner to enable them.'); return end
    -- A branch URL may be cached after a recent release. Give each check a
    -- fresh URL and ask intermediaries to revalidate their cached response.
    local stamp=os.epoch and os.epoch('utc') or tostring(os.time())..'-'..math.floor(os.clock()*1000)
    local response,why,failed=http.get(UPDATE_URL..'?mole_update='..stamp,
      {['Cache-Control']='no-cache',['Pragma']='no-cache'})
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
    print('Job, settings, and startup backup kept.')
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
local function usage(full)
  print('Mole '..VERSION..' - tunnel miner')
  if s and not full then
    local names={work='Mining',home='Returning home',out='Returning to work',dock='At the chest',paused='Paused',done='Finished',recovery='Recovering position',emergency='Emergency escape',rescued='Waiting for retrieval'}
    print('Saved job: '..(names[s.phase] or s.phase)..'.')
  end
  print('mole new     Start a new quarry')
  print('mole resume  Continue or recover')
  print('mole status  Check progress')
  print('mole return  Go home and pause')
  if full then
    print('mole settings  Change trash list')
    print('mole update    Get latest version')
    print('mole reset     Clear job/settings')
    print('mole delete    Uninstall Mole')
    print('mole companion Wireless setup')
  else print('mole help    All commands') end
  print(full and 'Ctrl+T: stop' or 'Ctrl+T: stop; \'mole resume\': continue')

end
if not argv[1] then
  local installed=fs.exists(INSTALL)
  ensureStartup()
  if not installed then print('Ready. Chest behind; use \'mole new\'.') end
  usage();return
end
if argv[1]=='help' then usage(true);return end
if argv[1]=='companion' or argv[1]=='pair' then
  local ok,why=pcall(net.menu,argv[1]=='pair' and argv[2] or nil,argv[3])
  if not ok then print('Wireless setup stopped. Mining unchanged.');print('Check modems and try \'mole companion\'.') end
  return
end
local commands={new=true,resume=true,status=true,['return']=true,settings=true,config=true}
if not commands[argv[1]] then print('Unknown command: '..argv[1]);usage();return end
if argv[1]=='settings' or argv[1]=='config' then settingsMenu(); return end
-- Require a known starting elevation for every supported job.
if s and (type(s.startY)~='number' or s.startY~=s.startY or math.abs(s.startY)==math.huge or s.startY%1~=0) then
  log('Saved job has no valid starting Y. Retrieve the turtle, then use \'mole reset\' and start a new job.');return
end
if not s and argv[1]~='new' then print('No saved quarry. Run \'mole new\' to create one.');return end
local fresh=argv[1]=='new'
if fresh then
  if s and (s.pending or s.recovery or #s.route>0 or (s.phase~='done' and s.phase~='paused')) then
    print('Finish the job or return home before starting a new one.'); return
  end
  if term and term.clear and term.setCursorPos then term.clear();term.setCursorPos(1,1) end
  print('Setting up new quarry')
  print('Enter: dimension defaults. q: cancel.')
  print('Length goes forward; width goes to the right.')
  local length=numberQuestion('Length in blocks',c.length,64); if not length then return end
  local width=numberQuestion('Width in blocks',c.width,64); if not width then return end
  local startY
  while true do
    local raw=answer('Y coordinate of turtle (required):')
    if raw:lower()=='q' then return end
    local n=tonumber(raw)
    if n and n==n and n~=math.huge and n~=-math.huge and n%1==0 then startY=n; break end
    print('Enter the world Y of this turtle block as a whole number; negative numbers are allowed.')
  end
  local suggested=c.depth
  local safeDepth=startY+62
  print('Suggested lowest mining level: Y -62.')
  print('Depth available before Y -62: '..math.max(0,safeDepth)..' blocks below this turtle.')
  if safeDepth>=1 then suggested=math.min(suggested,safeDepth)
  else print('This starting position is already at or below Y -62.') end
  local depth=numberQuestion('Depth below the turtle',suggested,512); if not depth then return end
  if depth>safeDepth then
    print('Caution: below Y -62, dense bedrock may make mining and return routes difficult.')
    while true do
      print('Requested bottom: Y '..(startY-depth)..', below the suggested Y -62 limit.')
      local prompt=safeDepth>=1 and 'Enter to stop at Y -62, yes to go deeper, or q to cancel:'
        or 'Type yes to mine below Y -62 (other dimensions), or q/Enter to cancel:'
      local choice=answer(prompt):lower()
      if choice=='yes' then break end
      if choice=='q' or choice=='' and safeDepth<1 then return end
      if choice=='' then depth=safeDepth; break end
      print('Use Enter, \'yes\', or \'q\'.')
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
     layoutVersion=2,startY=startY,emergencyTargetY=startY,program=shell.getRunningProgram(),shape={w=c.width,l=c.length,h=c.depth}}
  save(); ensureStartup()
  log('Starting '..c.length..' long x '..c.width..' wide, '..c.depth..' blocks deep.')
  log('Start: '..depthText(s.p)..'. Planned bottom: '..depthText({y=c.depth})..'.')
  log('Job set up. Checking the chest and fuel before mining; no action needed.')
end
c.width=s.shape.w; c.length=s.shape.l; c.depth=s.shape.h
ensureStartup()
if argv[1]=='status' then
  local names={work='Mining',home='Returning to the chest',dock='At the starting chest',out='Returning to work',
    recovery='Recovering position',emergency='Emergency escape',rescued='Waiting for retrieval',paused='Paused at the chest',done='Finished'}
  log('Status: '..(s.pending and 'Recovering position on next launch' or names[s.phase] or s.phase))
  if s.emergency then
    log('Reason: '..s.emergency.reason)
    log('Climb remaining: '..s.emergency.p.y..' blocks. Fuel: '..fuelText()..'.')
    if s.emergency.targetY then log('Retrieval target: Y '..s.emergency.targetY) end
    log(s.phase=='rescued' and 'Retrieve and reposition the turtle, then run \'mole reset\'.' or 'Run \'mole resume\' to continue emergency escape.');return
  end
  log((s.pending or s.recovery) and 'Position is being checked. Fuel: '..fuelText()..'.' or depthText(s.p)..'. Fuel: '..fuelText()..'.')
  if s.phase=='done' then log('For a new job, reposition the turtle and chest, then run \'mole new\'.')
  elseif s.phase=='paused' then log('Run \'mole resume\' to resume, or \'mole new\' to start a new job.')
  else log('Run \'mole resume\' to '..((s.pending or s.recovery) and 'continue position recovery.' or 'resume the saved job.')) end
  return
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
  net.inFlight=true
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
  s.pending=nil;net.inFlight=false; save(); return ok,why
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
-- Conservative reserve for the return journey and obstacle detours.
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
        error('Trash drop blocked below start; clear the space underneath, then run \'mole resume\'.',0)
      end
      turtle.select(i)
      if not turtle.dropDown() or turtle.getItemCount(i)>0 then
        turtle.select(1)
        error('Trash could not be dropped below start; clear the space underneath, then run \'mole resume\'.',0)
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
  pcall(net.mining,b)
  local ok,why=dig(); if not ok then failure('DIG_BLOCKED','Cannot dig '..b.name..': '..tostring(why)) end
  pcall(net.discovery,b)
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
  -- the physical trail, so interruptions still have a truthful return route.
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
      log('Return tunnel blocked. Trying a digging detour home; no action needed yet.')
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
      for _,q in ipairs(path) do if not knownStep(q,'push') then break end;net.raiseReturn() end
    end
    return
  end
  -- New shaft and tunnel cells are excavated only inside the work footprint.
  while s.p.y~=p.y do
    step({x=s.p.x,y=s.p.y+(p.y>s.p.y and 1 or -1),z=s.p.z},'push');net.raiseReturn()
  end
  while s.p.x~=p.x do step({x=s.p.x+(p.x>s.p.x and 1 or -1),y=s.p.y,z=s.p.z},'push');net.raiseReturn() end
  while s.p.z~=p.z do step({x=s.p.x,y=s.p.y,z=s.p.z+(p.z>s.p.z and 1 or -1)},'push');net.raiseReturn() end
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
        if not empty then failure('CHEST_FULL','Chest needs an empty slot to organize fuel. Make room and run \'mole resume\'.') end
        local moved=inv.pushItems('front',target,contents[target].count,empty)
        if moved~=contents[target].count then failure('CHEST_CHANGED','Waiting at the starting chest. Stop other machines or players changing this chest, make room for output, then run \'mole resume\'.') end
      end
      local item=inv.list()[source]
      if not item or not c.fuel[item.name] then failure('CHEST_CHANGED','Waiting at the starting chest. Keep fuel together in the reserved slots from slot 1 and stop other chest transfers, then run \'mole resume\'.') end
      local moved=inv.pushItems('front',source,item.count,target)
      if moved~=item.count then failure('CHEST_CHANGED','Waiting at the starting chest. Leave an empty chest slot and stop other chest transfers, then run \'mole resume\'.') end
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
        if turtle.getItemCount(i)>0 and not turtle.drop() then failure('CHEST_FULL','Waiting at the starting chest. Make room in the chest, then run \'mole resume\'.') end
        if turtle.getItemCount(i)>0 then failure('CHEST_FULL','Waiting at the starting chest. Make room in the chest, then run \'mole resume\'.') end
      end
    end
  end
  turtle.select(1)
end
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
  local initialFuel=fuel()
  local problem
  for _,entry in ipairs(sequence) do
    if fuel()>=target then break end
    local listed=inv.list()
    for i=1,entry.slot-1 do
      if listed[i] then problem='Fuel slots changed while refueling. Stop other chest transfers, arrange fuel from slot 1, then run \'mole resume\'.'; break end
    end
    if problem then break end
    local live=listed[entry.slot]
    if not live or live.name~=entry.name or live.count~=entry.count then
      problem='Fuel changed while refueling. Stop other chest transfers, arrange fuel from slot 1, then run \'mole resume\'.'; break
    end
    local slot
    for i=1,16 do if turtle.getItemCount(i)==0 then slot=i; break end end
    if not slot then problem='Not enough turtle inventory space for fuel or empty buckets. Make room in the chest and turtle inventory, then run \'mole resume\'.'; break end
    turtle.select(slot)
    if not turtle.suck(math.min(entry.count,64)) then problem='Could not take fuel from the chest. Check that it can supply items and stop other transfers, then run \'mole resume\'.'; break end
    local taken=turtle.getItemDetail(slot)
    if not taken or taken.name~=entry.name or turtle.getItemCount(slot)~=math.min(entry.count,64) then
      problem='Received unexpected items from the chest; returning them. Stop other transfers and arrange fuel from slot 1, then run \'mole resume\'.'; break
    end
    local before=fuel(); refuelTo(target)
    if fuel()==before then problem='The configured fuel item does not refuel this turtle. Supply coal, charcoal, or lava buckets; correct custom fuel entries in quarry-data/config, then run \'mole resume\'.'; break end
    -- Keep empty buckets and unused fuel onboard until the sequence finishes.
  end
  if fuel()>initialFuel then log('Fuel after chest refueling: '..fuelText()..' (target: '..target..').') end
  unload()
  organizeFuel(inv)
  if problem then failure('CHEST_CHANGED',problem) end
  if fuel()<minimum then failure('NEED_FUEL','Waiting at the starting chest. Fuel: '..fuelText()..'; minimum needed: '..minimum..'. Add fuel to the reserved chest slots, starting at slot 1, then run \'mole resume\'.') end
  if fuel()<target then log('Fuel is below the preferred target, but the safe minimum '..minimum..' is met. Resuming mining.') end
end
local function requestService(reason, pause)
  local shortest=knownPath(origin,s.p)
  if shortest then s.route=shortest end
  log('Returning to starting chest: '..reason..' ('..#s.route..' steps; '..depthText(s.p)..'). No action needed yet.')
  s.service={path=copyPath(s.route),target=copy(s.p),at=0,pause=pause,reason=reason}
  s.phase='home'; save()
end
function net.raiseReturn()
  if net.pending and not s.pending and not s.recovery and s.phase~='emergency' then
    if net.clock()-net.pending.received>30 then net.receipt(net.pending.id,'rejected','Request expired before a safe checkpoint.');net.pending=nil;return end
    failure('REMOTE_RETURN','Companion requested return')
  end
end
function net.acceptReturn()
  local pending=net.pending;net.pending=nil;if not pending then return end
  local r={id=pending.id,result='accepted'}
  s.companionRequests=s.companionRequests or {}
  -- CC:Tweaked rejects repeated table references in saved data.
  s.companionRequests[#s.companionRequests+1]={id=r.id,result=r.result}
  if #s.companionRequests>16 then table.remove(s.companionRequests,1) end
  s.companionReturn=r
  if s.phase=='work' or s.phase=='out' then
    local destination=s.phase=='out' and copyPath(s.service.path) or nil
    requestService('User requested return',true)
    if destination then s.service.path=destination;s.service.target=copy(destination[#destination] or origin);save() end
  elseif s.service then
    s.service.pause=true;s.service.reason='User requested return';save()
  else
    r.result='rejected';r.detail='Cannot return in this state.'
    local receipt=s.companionRequests[#s.companionRequests];receipt.result=r.result;receipt.detail=r.detail;save()
  end
  net.receipt(r.id,r.result,r.detail)
end
local function service()
  if s.phase=='home' then
    while #s.route>0 do homeStep();net.raiseReturn() end
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
      s.phase='done'; save(); pcall(net.status);pcall(net.flush); log('Job finished. Haul unloaded. Remaining fuel: '..fuelText()..'. No refueling needed.'); log('To mine elsewhere, reposition the turtle and chest, then run \'mole new\'.'); return false
    end
    if s.service.pause then
      if s.companionReturn and s.companionReturn.result=='accepted' then
        s.companionReturn.result='completed'
        for _,r in ipairs(s.companionRequests or {}) do if r.id==s.companionReturn.id then r.result='completed' end end
        net.receipt(s.companionReturn.id,'completed','Home and paused.')
      end
      s.phase='paused'; save(); pcall(net.status);pcall(net.flush); log('Refueling deferred while paused. Fuel: '..fuelText()..'.')
      log(s.service.reason=='User requested return' and 'Returned home and paused as requested. Run \'mole resume\' to resume.' or 'Paused at the starting chest: '..s.service.reason..'. Resolve the issue, then run \'mole resume\'.'); return false
    end
    local target=s.service.target or s.service.path[#s.service.path] or origin
    local shortest=knownPath(origin,target)
    if shortest then s.service.path=shortest end
    s.service.target=copy(target); s.service.at=0; save()
    local n=#s.service.path
    local escapeNeeded=ascentDistance(target.y)
    local needed=n+math.max(reserve(n),escapeNeeded>0 and escapeNeeded+c.emergencyFuelMargin+32 or 0)+64
    assert(needed<=capacity() or fuel()==math.huge,'Route exceeds fuel capacity; reduce depth or vein limits.')
    local fuelTarget=math.min(capacity(),math.max(c.fuelTarget,needed))
    log('Fuel: '..fuelText()..'. Target: '..fuelTarget..'. Minimum to resume safely: '..needed..'.')
    log(fuel()>=fuelTarget and 'Fuel already meets the target; no additional fuel needed.'
      or 'Refueling from the chest. Whole fuel items may exceed the target.')
    chestFuel(fuelTarget,needed)
    log('Chest servicing complete. Returning to work automatically.')
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
      net.raiseReturn()
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
net.total=total
local progressInterval=math.max(8,math.min(64,math.ceil(total/20)))
local lastProgressTime=os.clock()
local lastVein;local lastVeinCount=0
local lastReportedY
local function reportProgress(deposit)
  local now=os.clock()
  if deposit then
    if lastVein~=s.vein then lastVein=s.vein;lastVeinCount=0 end
    if s.vein.count-lastVeinCount<16 and now-lastProgressTime<20 then return end
    lastVeinCount=s.vein.count
    if s.vein.count==0 then log('Checking nearby blocks.')
    else log((s.vein.other==false and 'Following a vein: ' or 'Collecting blocks: ')..net.blocks(s.vein.count)..' mined.') end
  else
    if (s.index-1)%progressInterval~=0 and now-lastProgressTime<20 then return end
    log('Tunnel progress: '..(s.index-1)..'/'..total..'.')
    if lastReportedY~=s.p.y then log('Mining tunnels at Y '..(s.startY-s.p.y)..'.');lastReportedY=s.p.y end
  end
  lastProgressTime=now
end
local function finishLevelTransition()
  local trail=knownPath(origin,s.p)
  if trail then s.route=trail;save() end
  gotoWork(s.levelTransition)
  s.route=knownPath(origin,s.p) or s.route
  s.levelTransition=nil;save()
end
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
  if not s.vein then net.lastBlock=nil;s.vein={stack={scanFrame(s.p)},count=0}; save() end
  while #s.vein.stack>0 do
    net.raiseReturn()
    local v=s.vein; local f=v.stack[#v.stack]
    local parent=v.stack[#v.stack-1]
    local returning=f.next>=6 or v.count>=c.veinLimit or #v.stack>c.veinDepth
    if v.count>=c.veinLimit then v.limited='collection'
    elseif #v.stack>c.veinDepth and v.limited~='collection' then v.limited='depth' end
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
          if not net.isOre(b.name) then v.other=true elseif v.count==0 and v.other==nil then v.other=false end
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
    reportProgress(true)
    refuelTo(reserve(#s.route+1)+4)
    if freeSlots()<2 or fuel()<=reserve(#s.route+1)+3 then
      requestService(freeSlots()<2 and 'Inventory nearly full' or 'Fuel reserve reached',false); return false
    end
  end
  local finished=s.vein
  if finished.count>0 then
    local limit=finished.limited
    if limit==true then limit=finished.count>=c.veinLimit and 'collection' or 'depth' end
    local label=limit=='collection' and 'Collection limit reached: ' or limit=='depth' and 'Search depth limit reached: ' or finished.other==false and 'Vein collected: ' or 'Collected: '
    log(label..net.blocks(finished.count)..(limit=='depth' and ' collected.' or '.'))
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
  log('Movement was interrupted. Checking my position by returning to the starting chest without digging. Leave the turtle and chest in place.')
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
  return false
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
    log('Checking a possible route to the starting chest: '..#h.route..' steps.')
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
        log('Position confirmed at the starting chest. Preparing to resume mining.')
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
  local deepest=-math.huge; local shallowest=math.huge
  local function include(depth)
    deepest=math.max(deepest,depth);shallowest=math.min(shallowest,depth)
  end
  if s.recovery then eachHypothesis(function(h) include(h.p.y) end)
  elseif s.pending then include(s.pending.before.y);include(s.pending.after.y)
  else include(s.p.y) end
  assert(deepest~=-math.huge,'No height estimate for emergency ascent; saved safely.')
  s.emergency={reason=reason,p={x=0,y=ascentDistance(deepest),z=0,d=0},blocked={},
    heightUncertainty=deepest-shallowest,targetY=s.emergencyTargetY or s.startY}
  s.phase='emergency';save()
  log('EMERGENCY ASCENT: '..reason)
  log('Trying to climb '..s.emergency.p.y..' blocks to '..('Y '..s.emergency.targetY)..'. Mining is suspended.')
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
  if freeSlots()<2 then error('No inventory space for emergency digging; valuables kept. Clear space and run \'mole resume\'.',0) end
  local occupied,block=inspect()
  if protectedBlock(occupied and block or nil,per) then return false end
  if not occupied or passable[block.name] then return true end
  pcall(net.mining,block)
  local dug=(side=='up' and turtle.digUp or turtle.dig)()
  if dug then pcall(net.discovery,block) end
  return dug
end
local function emergencyAscent()
  settleEmergency()
  local e=s.emergency
  while e.p.y>0 do
    refuelTo(e.p.y+c.emergencyFuelMargin+8)
    if fuel()<e.p.y then error('Insufficient fuel for emergency ascent; progress saved. Add fuel and run \'mole resume\'.',0) end
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
    if not moved then e.blocked[key(q)]=true;save();log('Emergency ascent blocked. Trying a sideways detour; no action needed yet.') end
  end
  s.phase='rescued';save()
  log('Emergency escape finished at the retrieval level. Mining remains stopped. Retrieve and reposition the turtle, then run \'mole reset\'.')
  if e.heightUncertainty>0 then log('Height was uncertain; the turtle may finish '..e.heightUncertainty..' block(s) above the target.') end
  log('Remaining fuel after emergency ascent: '..fuelText()..'.')
  log('This is a retrieval point, not confirmation of open sky. Use \'mole reset\' only after positioning the turtle for a new job.')
end
local emergencyFailures={NO_ROUTE=true,NO_HOME_ROUTE=true,INSUFFICIENT_RETURN_FUEL=true,
  RETURN_FUEL_LOW=true,NO_CHEST_CONFIRMATION=true,RETURN_RECOVERY_FUEL=true,RECOVERY_FUEL_LOW=true,
  MISSING_CHEST=true,INVENTORY_FULL=true,FUEL_RESERVE=true,NO_FUEL=true}
local function fallbackReason(why) return emergencyFailures[failureCode(why)]==true end
local function stoppedAdvice(err)
  local code=failureCode(err)
  if code=='CHEST_FULL' or code=='CHEST_CHANGED' or code=='NEED_FUEL' then
    log('Waiting at the starting chest. Follow the instructions above, then run \'mole resume\'.')
  else
    log('Progress saved at '..depthText(s.p)..'. Check the reported obstruction or error, then run \'mole resume\' to retry. Do not move or turn the turtle.')
    log('Use \'mole reset\' only after retrieving and repositioning the turtle.')
  end
end
local function attemptEmergency(why)
  local ok,err=pcall(function() if s.phase~='emergency' then startEmergency(tostring(why)) end;emergencyAscent() end)
  if not ok then log('Emergency escape saved: '..tostring(err)..'. Run \'mole resume\' to retry.') end
end
local function miningMain()
if s.phase=='rescued' then
  log('Emergency ascent already completed. Mining stays paused; retrieve the turtle and use \'mole reset\' at a safe starting point.');return
end
if s.phase=='emergency' then attemptEmergency(s.emergency.reason);return end

if s.phase=='done' then
  print('Mining finished! Items are in the chest.')
  print('For a new job, face into the new area, then \'mole new\'.'); return
end
if s.phase=='paused' then
  if argv[1]=='return' then print('Already paused at the starting chest.'); return end
  log('Paused: '..tostring(s.service and s.service.reason or 'User pause'))
  local prompt=s.service and s.service.reason=='User requested return' and 'Enter to resume mining, q to stay paused:' or 'After resolving the issue, Enter to resume, q to stay paused:'
  if answer(prompt):lower()=='q' then return end
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
      while #s.route>0 do homeStep();net.raiseReturn() end
      s.phase='dock'; save()
    end
    upgradeAtDock()
  end
  if s.index==1 and s.phase=='work' and #s.route==0 and not s.vein then
    requestService('Initial chest/fuel check',false)
  end
  while true do
    net.raiseReturn()
    if s.phase~='work' then if not service() then return end end
    if s.index>total then
      requestService('Quarry complete',true); s.service.reason='Quarry complete'; save()
      service(); return
    end
    refuelTo(reserve(#s.route+1)+64)
    if fuel()<=math.max(reserve(#s.route+1)+32,ascentDistance(s.p.y)+c.emergencyFuelMargin+64) or freeSlots()<2 then
      requestService(freeSlots()<2 and 'Inventory nearly full' or 'Fuel reserve reached',false)
    else
      if not s.vein then
        if s.levelTransition then finishLevelTransition() end
        local p=cell(s.index); gotoWork(p)
      end
      if vein() then
        s.index=s.index+1; save()
        reportProgress(false)
        if s.index<=total and plan[s.index].band~=plan[s.index-1].band then
          log('Tunnel level finished. Continuing to the next level.')
          -- Save the transition so refueling or a reload still reuses
          -- the cleared shaft before descending to the next level.
          s.levelTransition={x=0,y=plan[s.index-1].y,z=0};save()
          finishLevelTransition()
        end
      end
    end
  end
end)
if not ok and failureCode(err)=='REMOTE_RETURN' then
  ok,err=pcall(function() net.acceptReturn();return service() end)
end
if not ok then
  log(tostring(err))
  if s.pending or s.recovery then
    if fallbackReason(err) then attemptEmergency(err);return end
    log('Recovery saved. Run \'mole resume\' (or let startup run it) to retry automatic chest homing.'); return
  end
  -- An error during a return must not overwrite the original outbound route.
  if s.phase=='work' then
    requestService(tostring(err),failureCode(err)~='FUEL_RESERVE' and failureCode(err)~='INVENTORY_FULL')
    local safe,why=pcall(service)
    if not safe then
      if fallbackReason(why) then attemptEmergency(why)
      else log('Return stopped: '..tostring(why));stoppedAdvice(why) end
    end
  elseif fallbackReason(err) then attemptEmergency(err)
  else stoppedAdvice(err) end
end

end
net.run(miningMain)
