-- Offline mock tests: run with Lua 5.4, not on the turtle.
local programFile=assert(io.open('mole.lua') or io.open('mole/mole.lua'))
local program=programFile:read('*a');programFile:close()
local scenarioCount=0
local originalPrint=print
local originalClock=os.clock
local networkOriginal={epoch=os.epoch,id=os.getComputerID,label=os.getComputerLabel,pull=os.pullEvent}
local companionCore
local companionSource=io.open('mole-companion/companion.lua')
if companionSource then local src=companionSource:read('*a');companionSource:close();companionCore=assert(load(src))('--test') end
local function scenario(opts)
  scenarioCount=scenarioCount+1
  rednet=nil;parallel=nil
  os.epoch=networkOriginal.epoch;os.getComputerID=networkOriginal.id;os.getComputerLabel=networkOriginal.label;os.pullEvent=networkOriginal.pull
  local mockTime=0
  os.clock=opts.slowProgress and function() mockTime=mockTime+21;return mockTime end or originalClock
  fs=nil;turtle=nil;peripheral=nil;textutils=nil;read=nil;write=nil;print=originalPrint;collectgarbage('collect')
  http=nil
  local messages={}
  local clears=0
  term={clear=function() clears=clears+1 end,setCursorPos=function(x,y) assert(x==1 and y==1) end}
  print=function(...) local parts={...};for i,v in ipairs(parts) do parts[i]=tostring(v) end;messages[#messages+1]=table.concat(parts,' ');if os.getenv('MOLE_VERBOSE')=='1' then originalPrint(...) end end
  local files,objects={},{}; local seq=0
  local width=opts.width or 3; local length=opts.length or 3; local depth=opts.depth or 6
  local prompts=0; local dimensionPrompts=0; local promptText={}; local inputs=opts.inputs or {tostring(length),tostring(width),tostring(opts.startY or 64),tostring(depth),opts.heightOverride or '', ''}
  write=function(text)
    promptText[#promptText+1]=text
    if text:find(' in blocks',1,true) or text:find('Depth below',1,true) then dimensionPrompts=dimensionPrompts+1 end
  end
  read=function() prompts=prompts+1; return table.remove(inputs,1) or '' end
  shell={getRunningProgram=function() return 'mole' end}
  if opts.existingStartup then files['startup.lua']='existing startup' end
  if opts.legacyStartup then files['startup.lua']='shell.run("quarry")' end
  if opts.legacyGuard then files['startup.lua']="if fs.exists('quarry-data/state.a') or fs.exists('quarry-data/state.b') then\n shell.run('quarry')\nend" end
  if opts.resumeStartup then files['startup.lua']="if fs.exists('quarry-data/state.a') or fs.exists('quarry-data/state.b') then shell.run('mole', 'resume') end" end
  local originalStartup=files['startup.lua']
  local function clone(t) if type(t)~='table' then return t end local o={} for k,v in pairs(t) do o[k]=clone(v) end return o end
  textutils={serialize=function(t) seq=seq+1; objects[tostring(seq)]=clone(t); return tostring(seq) end,
    unserialize=function(t) return clone(objects[t]) end}
  local updateFailed=false
  fs={makeDir=function() end,move=function(from,to)
    assert(files[from]~=nil and files[to]==nil,'Invalid mock file move')
    if opts.updateMoveFail and from=='mole.update-download' and not updateFailed then updateFailed=true;error('simulated install failure') end
    files[to]=files[from];files[from]=nil
    if opts.updateUnload and to=='mole.update-backup' then error('simulated unload during installation') end
  end,delete=function(path) for k in pairs(files) do if k==path or k:sub(1,#path+1)==path..'/' then files[k]=nil end end end,exists=function(p) return files[p]~=nil end,
    open=function(p,m) return {readAll=function() return files[p] end,write=function(v) if opts.fuelChest and objects[v] and objects[v].phase=='out' then error('fuel fixture stop after docking') end;if opts.updateWriteFail and p=='mole.update-download' then error('simulated disk full') end;files[p]=v;local keep={};for _,saved in pairs(files) do keep[saved]=true end;for id in pairs(objects) do if not keep[id] then objects[id]=nil end end end,close=function() end} end}
  local p={x=0,y=0,z=0,d=0}; local world={}; local dug={}; local amount=0; local f=opts.fuel or 10000; local coal=opts.carriedCoal or 0;local chestCoal=opts.chestCoal or 0;local coalSlot=2;local selected=1;local consumed=0; local crash=opts.crash or opts.crashAfter or opts.turnCrash; local actions=0; local turns=0; local leftTurns=0; local inspections=0; local moves=0; local detailQueries=0; local countQueries=0; local injected=false; local recoveryCrash=opts.recoveryCrash; local recoveryMoveCrash=opts.recoveryMoveCrash
  local dx={0,1,0,-1}; local dz={1,0,-1,0}
  for x=0,width-1 do for z=0,length-1 do for y=1,depth do world[x..','..y..','..z]='minecraft:stone' end end end
  if width>=3 and length>=3 and depth>=6 then
    world['1,2,1']='mod:ore'; world['1,3,1']='mod:ore'; world['1,4,1']='mod:ore'
    world['1,6,0']='mod:hidden_ore'
  end
  if opts.stoneOnly then
    for k in pairs(world) do world[k]='minecraft:stone' end
  end
  if opts.fluid then for k,v in pairs(world) do if v=='minecraft:stone' then world[k]='mod:oil' end end end
  if opts.air then world={} end
  if opts.protected then world['0,1,0']='minecraft:chest' end
  if opts.protectedScan then world['0,1,1']='minecraft:bedrock' end
  local function target(side) return {x=p.x+(side==0 and dx[p.d+1] or 0),y=p.y+side,z=p.z+(side==0 and dz[p.d+1] or 0)} end
  local function key(q) return q.x..','..q.y..','..q.z end
  local checkpointState
  local function inspect(side)
    inspections=inspections+1
    local state=checkpointState and checkpointState()
    if state and state.phase=='home' and state.service.reason=='Band complete' and not injected then
      if opts.injectReturnFuel then f=0;coal=2;coalSlot=2;injected=true end
      if opts.blockShortcut then world['1,2,1']='minecraft:bedrock'; injected=true end
      if opts.blockBridge then world['0,1,0']=opts.breakableBridge and 'minecraft:stone' or 'minecraft:bedrock'; injected=true end
    end
    if opts.trashBlocked and side==1 and p.y==0 and amount>0 then return true,{name='minecraft:stone'} end
    local state=checkpointState and checkpointState()
    if not injected and state and (opts.injectRecoveryFuel and state.phase=='recovery' or opts.injectEscapeFuel and state.phase=='emergency') then f=0;coal=2;coalSlot=2;injected=true end
    local b=world[key(target(side))]; return b~=nil,b and {name=b}
  end
  local function dig(side)
    assert(not files['quarry-data/state.a'] or checkpointState==nil or checkpointState().phase~='recovery','Dug while uncertain')
    local q=target(side); local k=key(q); if world[k] then
    assert(world[k]~='mod:oil','Tried digging a traversable fluid')
    assert(world[k]~='minecraft:bedrock','Attempted to dig a changed unbreakable tunnel')
    assert(checkpointState().phase~='out','Dug an outbound passage')
    assert(checkpointState().phase=='emergency' or q.x>=0 and q.x<=(checkpointState().phase=='home' and width or width-1) and q.z>=0 and q.z<=(checkpointState().phase=='home' and length or length-1) and q.y>=(checkpointState().phase=='home' and 0 or 1) and q.y<=depth,'Boundary violation')
    dug[k]=true; world[k]=nil; amount=amount+1
  end return true end
  checkpointState=function()
    local a=files['quarry-data/state.a'] and textutils.unserialize(files['quarry-data/state.a'])
    local b=files['quarry-data/state.b'] and textutils.unserialize(files['quarry-data/state.b'])
    return (not b or a and a.seq>b.seq) and a or b
  end
  local function move(side)
    if opts.falseFuelError and checkpointState().phase=='home' and not injected then injected=true;error('Fuel reserve reached',0) end
    actions=actions+1
    local recoveryInterrupt=recoveryMoveCrash and checkpointState().phase=='recovery'
    if recoveryInterrupt and not opts.recoveryAfter then recoveryMoveCrash=false; error('unload before recovery movement') end
    local interrupt=crash and not opts.turnCrash and (opts.detourCrash and checkpointState().service and checkpointState().service.excavating or not opts.detourCrash and (opts.networkAcceptedCrash and checkpointState().companionReturn and checkpointState().companionReturn.result=='accepted' or not opts.networkAcceptedCrash and actions>=(opts.at or 1)))
    if interrupt and not opts.crashAfter then crash=false; error('simulated unload before movement') end
    local q=target(side); if world[key(q)] and world[key(q)]~='mod:oil' then return false end
    if f<=0 then return false end moves=moves+1; f=f-1; p.x=q.x;p.y=q.y;p.z=q.z; if recoveryInterrupt then recoveryMoveCrash=false; error('unload after recovery movement') end; if interrupt then crash=false; error('simulated unload after movement') end; return true
  end
  local function turn(delta)
      turns=turns+1; if delta==-1 then leftTurns=leftTurns+1 end
      actions=actions+1
      local interrupt=crash and opts.turnCrash and actions>=(opts.at or 1)
        and (not opts.forceLeftCrash or delta==-1)
      local recoveryInterrupt=recoveryCrash and checkpointState().phase=='recovery'
      if recoveryInterrupt and not opts.recoveryAfter then recoveryCrash=false; error('unload before recovery turn') end
      if interrupt and not opts.crashAfter then crash=false; error('unload before turn') end
      p.d=(p.d+delta)%4
      if recoveryInterrupt then recoveryCrash=false; error('unload after recovery turn') end
      if interrupt then crash=false; error('unload after turn') end
      return true
  end
  turtle={turnRight=function() return turn(1) end,turnLeft=function() return turn(-1) end,
    forward=function() return move(0) end,up=function() return move(-1) end,down=function() return move(1) end,
    inspect=function() return inspect(0) end,inspectUp=function() return inspect(-1) end,inspectDown=function() return inspect(1) end,
    dig=function() return dig(0) end,digUp=function() return dig(-1) end,digDown=function() return dig(1) end,
    getFuelLevel=function() return opts.unlimited and 'unlimited' or f end,getFuelLimit=function() return opts.unlimited and 'unlimited' or 20000 end,select=function(i) selected=i end,
    getItemDetail=function(i) detailQueries=detailQueries+1; if i==coalSlot and coal>0 then return {name='minecraft:coal'} end; if i==1 and amount>0 then return {name=opts.trashCargo and 'minecraft:stone' or 'mod:ore'} end end,
    getItemCount=function(i) countQueries=countQueries+1; if i==coalSlot and coal>0 then return coal end; return i==1 and amount or 0 end,
    refuel=function() if selected==coalSlot and coal>0 then coal=coal-1;f=f+80;consumed=consumed+1;return true end return false end,dropDown=function() assert(checkpointState().phase=='emergency' or p.x==0 and p.y==0 and p.z==0,'Dropped trash away from start');assert(opts.trashCargo,'Dropped valuable cargo');if opts.trashDropFail then return false end;amount=0;return true end,
    drop=function() if opts.full then return false end
      if selected==coalSlot and coal>0 then chestCoal=chestCoal+coal;coal=0 else assert(not opts.trashCargo or amount==0 or opts.keepTrash,'Trash entered chest');amount=0 end;return true end,
    suck=function() if chestCoal>0 then coal=chestCoal;chestCoal=0;coalSlot=selected;return true end return false end}
  local function isChest(side)
    if opts.missing and checkpointState() and checkpointState().phase=='recovery' then return false end
    return p.x==0 and p.y==0 and p.z==0 and ((side=='front' and p.d==2) or (side=='back' and p.d==0))
  end
  peripheral={isPresent=function(side) return isChest(side) end,hasType=function(side,t) return isChest(side) end,
    getType=function() return 'minecraft:chest' end,
    wrap=function() return {size=function() return 27 end,list=function() if chestCoal>0 then return {[1]={name='minecraft:coal',count=chestCoal}} end;return {} end} end}
  local fuelConsumed,bucketsReturned,pulls=0,0,0
  local chestListCalls=0
  local chestSlots
  if opts.fuelChest then
    chestSlots=clone(opts.fuelChest);local cargo={}
    turtle.getItemDetail=function(i) return cargo[i] and {name=cargo[i].name,count=cargo[i].count} end
    turtle.getItemCount=function(i) return cargo[i] and cargo[i].count or 0 end
    turtle.suck=function(count)
      for i=1,27 do if chestSlots[i] then
        local item=chestSlots[i];local n=math.min(count or 64,item.count)
        cargo[selected]={name=item.name,count=n};item.count=item.count-n
        if item.count==0 then chestSlots[i]=nil end
        pulls=pulls+1
        if opts.changedFuel and pulls==1 then chestSlots[1]={name='minecraft:dirt',count=1} end
        return true
      end end
      return false
    end
    turtle.refuel=function()
      local item=cargo[selected]
      if not item or (item.name~='minecraft:coal' and item.name~='minecraft:charcoal' and item.name~='minecraft:lava_bucket') then return false end
      local lava=item.name=='minecraft:lava_bucket'
      f=f+(lava and 1000 or 80);fuelConsumed=fuelConsumed+1
      if lava then cargo[selected]={name='minecraft:bucket',count=1}
      else item.count=item.count-1;if item.count==0 then cargo[selected]=nil end end
      return true
    end
    turtle.drop=function()
      local item=cargo[selected];if not item then return true end
      if item.name=='minecraft:bucket' then
        bucketsReturned=bucketsReturned+item.count
        if opts.bucketExpected then assert(f>=opts.expectedFuel,'Returned empty bucket before fuel target reached') end
      end
      for i=1,27 do if not chestSlots[i] then chestSlots[i]=clone(item);cargo[selected]=nil;return true end end
      return false
    end
    peripheral.wrap=function() return {size=function() return 27 end,list=function() chestListCalls=chestListCalls+1;return clone(chestSlots) end,
      pushItems=function(name,from,count,to)
        assert(name=='front' and from~=to,'Invalid self inventory transfer')
        local item=chestSlots[from];if not item or chestSlots[to] then return 0 end
        local n=math.min(count,item.count);chestSlots[to]={name=item.name,count=n};item.count=item.count-n
        if item.count==0 then chestSlots[from]=nil end;return n
      end} end
  end
  sleep=function() end
  local function rawRun(...) return assert(load(program,'mole'))(...) end
  local function run(...)
    if select('#',...)==0 then return rawRun(checkpointState() and 'resume' or 'new') end
    return rawRun(...)
  end
  local c={width=width,length=length,depth=depth,fuelTarget=opts.fuelChest and (opts.fuelGoal or 2560) or opts.oldFuelDefault and 2000 or 100,fuelMargin=10,retries=12,veinLimit=128,veinDepth=24,
    fuelSchemaVersion=2,discardTrash=not opts.keepTrash,fuel={['minecraft:coal']=true,['minecraft:charcoal']=true,['minecraft:lava_bucket']=true},
    trash={['minecraft:stone']=true},protected={['minecraft:chest']=true,['minecraft:bedrock']=true}}
  if opts.oldFuelSchema then c.fuelSchemaVersion=nil;c.fuel['minecraft:lava_bucket']=nil;if opts.disableLava then c.fuel['minecraft:lava_bucket']=false end end
  if not opts.defaultConfig then files['quarry-data/config']=textutils.serialize(c) end
  local wirelessPackets={};local wirelessClock=1000;local wirelessRequest;local injectedWireless=false
  local companionState=companionCore and companionCore.new({{id=4,name='Test Mole',token='test-network-token'}})
  if opts.network or opts.networkDisabled then
    files['quarry-data/companion']=textutils.serialize({enabled=not (opts.networkDisabled or opts.pairMenu),station=7,token='test-network-token'})
    local oldNames=peripheral.getNames;local oldType=peripheral.hasType;local oldWrap=peripheral.wrap;local oldPresent=peripheral.isPresent
    peripheral.getNames=function() if opts.networkDisabled then error('Disabled feature probed modems') end;return opts.networkDetach and actions>=3 and {} or {'left'} end
    peripheral.hasType=function(side,kind) return side=='left' and kind=='modem' or oldType(side,kind) end
    peripheral.wrap=function(side) if side=='left' then return {isWireless=function() return true end} end;return oldWrap(side) end
    peripheral.isPresent=function(side) if side=='left' then return not (opts.networkDetach and actions>=3) end;return oldPresent(side) end
    os.epoch=function() return wirelessClock*1000 end;os.getComputerID=function() return 4 end
    os.getComputerLabel=function() return 'Test Mole' end
    os.pullEvent=function() coroutine.yield('idle') end
    rednet={open=function(side) assert(side=='left') end,
      send=function(id,msg,protocol)
        if opts.pairMenu then assert(id==7 and msg.kind=='pair_hello' and msg.code=='123456' and msg.wireless==true);return true end
        if opts.networkSendThrow then error('Disconnected modem') end
        assert(id==7 and protocol=='mole-companion/1' and msg.token=='test-network-token','Incorrect pairing target')
        if msg.kind=='status' then assert(msg.job and msg.y and msg.depth and msg.right and msg.forward,'Incomplete status') end
        wirelessPackets[#wirelessPackets+1]=clone(msg)
        if companionState then companionCore.receive(companionState,4,msg,wirelessClock) end
        return true
      end,
      receive=function()
        if opts.pairMenu then wirelessClock=wirelessClock+1;return opts.badPairSender and 99 or 7,{v=1,kind='paired',code='123456',station=7,token='new-pair-token'},'mole-companion/1' end
        if opts.networkReceiveThrow then error('Listener failed') end
        coroutine.yield('receive');wirelessClock=wirelessClock+0.2
        if (opts.networkReturn or opts.networkRecoveryReturn or opts.networkEmergencyReturn or opts.networkBadSender or opts.networkBadAction) and not injectedWireless and actions>=3 and checkpointState().phase==(opts.networkRecoveryReturn and 'recovery' or opts.networkEmergencyReturn and 'emergency' or 'work') then
          injectedWireless=true
          if companionState then wirelessRequest=assert(companionCore.command(companionState,4,wirelessClock))
          else
            local status;for _,p in ipairs(wirelessPackets) do if p.kind=='status' then status=p end end
            wirelessRequest={v=1,kind='command',action='return',request='return-once',token='test-network-token',session=status.session}
          end
          if opts.networkBadAction then wirelessRequest.action='reset' end
          return opts.networkBadSender and 99 or 7,wirelessRequest,'mole-companion/1'
        end
        if opts.networkReturn and injectedWireless and checkpointState().companionReturn then return 7,wirelessRequest,'mole-companion/1' end
      end}
    parallel={waitForAny=function(main,listener)
      local workers={coroutine.create(main),coroutine.create(listener)}
      for cycle=1,20000 do
        for _,worker in ipairs(workers) do
          local ok,err=coroutine.resume(worker);if not ok then error(err,0) end
          if coroutine.status(worker)=='dead' then return end
        end
      end
      error('Wireless scheduler did not finish')
    end}
    if not opts.networkDisabled then for _,name in ipairs({'forward','up','down','turnLeft','turnRight'}) do
      local actual=turtle[name]
      turtle[name]=function(...) local result={actual(...)};coroutine.yield('physical action finished');return table.unpack(result) end
    end
    end
    if opts.networkDisabled then parallel=nil end
  end
  if opts.update then
    files['mole']=program
    files['quarry-data/state.a']=textutils.serialize({seq=4,phase='recovery',pending={}})
    files['quarry-data/previous-job']='previous job'
    if not opts.existingStartup then files['startup.lua']='-- Automatically resume the saved mining job.\nshell.run("mole")\n' end
    local before=clone(files)
    local source=program:gsub('1%.6%.0','9.0.0')
    if opts.updateSame then source=program end
    if opts.updateOlder then source=program:gsub('1%.6%.0','0.9.9') end
    if opts.updateBad then source='not a program' end
    if opts.updateSyntax then source='-- Mole v9.0.0\nlocal =' end
    local closed=false
    if not opts.updateDisabled then
      http={get=function(url,headers)
        assert(url:match('^https://raw%.githubusercontent%.com/Nom4d%-temp/mole/main/mole%.lua%?mole_update=.+$'),'Update URL lacks fresh timestamp')
        assert(headers and headers['Cache-Control']=='no-cache' and headers.Pragma=='no-cache','Update does not request cache revalidation')
        if opts.updateOffline then return nil,'HTTP 404' end
        local downloaded=opts.updateCached and not url:find('?mole_update=',1,true) and program or source
        return {readAll=function() return downloaded end,close=function() closed=true end}
      end}
    end
    run('update')
    for _,name in ipairs({'quarry-data/config','quarry-data/state.a','quarry-data/previous-job'}) do assert(files[name]==before[name],'Update changed job/settings') end
    assert(actions==0 and prompts==0,'Update moved or prompted')
    if opts.updateUnload then
      assert(not files['mole'] and files['mole.update-backup']==program,'Interrupted install lost backup')
      local booted=false
      assert(load(files['startup.lua'],'startup','t',{fs=fs,shell={run=function(path,command) assert(path=='mole' and command=='resume');booted=true end}}))()
      assert(booted and files['mole']==program,'Startup did not restore interrupted install')
    elseif opts.updateSame or opts.updateOlder or opts.updateBad or opts.updateSyntax or opts.updateOffline or opts.updateDisabled or opts.updateMoveFail or opts.updateWriteFail then
      assert(files['mole']==program,'Failed/unnecessary update changed executable')
    else
      assert(files['mole']==source and files['mole.update-backup']==program,'New version or rollback copy missing')
      if opts.existingStartup then assert(files['startup.lua']==before['startup.lua'],'Changed custom startup') end
    end
    if not opts.updateOffline and not opts.updateDisabled then assert(closed,'HTTP response left open') end
    return
  end
  if opts.reset then
    files['quarry-data/state.a']=textutils.serialize({seq=4,pending={before={}},phase='recovery'})
    files['quarry-data/state.b']='damaged save'
    files['quarry-data/state']='legacy save';files['quarry-data/previous-job']='old job'
    if opts.corruptReset then files['quarry-data/config']='damaged config' end
    p.y=3
    run('reset')
    local config=textutils.unserialize(files['quarry-data/config'])
    assert(config.width==16 and config.length==16 and config.depth==64 and config.fuelTarget==2560 and config.discardTrash,'Defaults not restored')
    assert(config.trash['minecraft:deepslate'] and config.protected['minecraft:bedrock'],'Default lists not restored')
    for k in pairs(files) do assert(k:sub(1,12)~='quarry-data/' or k=='quarry-data/config','Old data survived reset') end
    assert(actions==0 and prompts==0 and p.y==3 and f==(opts.fuel or 10000),'Reset moved/refueled or prompted')
    if opts.existingStartup then assert(files['startup.lua']=='existing startup','Reset changed unrelated startup') end
    if not opts.resetResume then return end
    p.y=0;run();assert(checkpointState().phase=='done','Could not start after reset');return
  end
  if opts.legacy then
    p.y=2;world['0,1,0']=nil;world['0,2,0']=nil
    local old={seq=10,p=clone(p),route={{x=0,y=1,z=0,d=0},{x=0,y=2,z=0,d=0}},
      index=6,phase='work',seen={},shape={w=width,l=length,h=depth}}
    files['quarry-data/state.a']=textutils.serialize(old)
    inputs={}
  end
  if opts.outboundObstacle then
    local tunnels={['0,0,0']=true};local cleared={
      {x=0,y=1,z=0},{x=0,y=2,z=0},{x=0,y=2,z=1},{x=1,y=2,z=1},
      {x=2,y=2,z=1},{x=2,y=2,z=0},{x=0,y=2,z=2},{x=1,y=2,z=2},{x=2,y=2,z=2}}
    for _,q in ipairs(cleared) do tunnels[key(q)]=true;world[key(q)]=nil;dug[key(q)]=true end
    world['1,3,1']=nil;world['1,4,1']=nil;world['1,2,1']='minecraft:bedrock'
    p.d=2
    local old={seq=10,p=clone(p),route={},index=8,phase='out',seen={},tunnels=tunnels,
      layoutVersion=2,anchor={type='minecraft:chest',size=27},shape={w=width,l=length,h=depth},
      startY=64,emergencyTargetY=64,service={path={cleared[1],cleared[2],cleared[3],cleared[4],cleared[5],cleared[6]},at=0,
        target=cleared[6],reason='Inventory or fuel reserve'}}
    files['quarry-data/state.a']=textutils.serialize(old)
  end
  if opts.emergencyCase then
    p.x=2;p.y=6;p.z=1;p.d=0;f=opts.escapeFuel or 30
    local trail={}
    for y=1,6 do trail[#trail+1]={x=0,y=y,z=0};world['0,'..y..',0']=nil end
    for x=1,2 do trail[#trail+1]={x=x,y=6,z=0};world[x..',6,0']=nil end
    trail[#trail+1]={x=2,y=6,z=1};world['2,6,1']=nil;world['2,6,0']='minecraft:bedrock'
    if opts.escapeCeiling then world['2,5,1']='minecraft:bedrock' end
    if opts.escapeRoof then for x=-6,10 do for z=-7,9 do world[x..',5,'..z]='minecraft:bedrock' end end end
    local saved={startY=64,emergencyTargetY=64,seq=10,p=clone(p),route=trail,index=10,phase='home',seen={},layoutVersion=2,
      shape={w=width,l=length,h=depth},service={path=clone(trail),target=clone(p),at=0,reason='Inventory or fuel reserve'}}
    if opts.escapeHigher then saved.startY=10;saved.emergencyTargetY=12 end
    if opts.unlimited then saved.phase='emergency';saved.emergency={reason='Test interrupted escape',p={x=0,y=6,z=0,d=0},blocked={},heightUncertainty=0} end
    files['quarry-data/state.a']=textutils.serialize(saved)
    if opts.escapeInterrupt then
      crash=false;local interrupted=false;local actualMove=move
      turtle.up=function()
        if checkpointState().phase=='emergency' and not interrupted then
          if opts.escapeBeforeInterrupt then interrupted=true;error('unload before emergency upward move') end
          local ok=actualMove(-1)
          if ok then interrupted=true;error('unload after emergency upward move') end
          return ok
        end
        return actualMove(-1)
      end
    end
    if opts.escapeTurnInterrupt then
      local interrupted=false;local actualTurn=turtle.turnRight
      turtle.turnRight=function()
        local ok=actualTurn()
        if checkpointState().phase=='emergency' and not interrupted then interrupted=true;error('unload after emergency turn') end
        return ok
      end
    end
    local emergencyCargo
    if opts.escapeFullInventory then
      emergencyCargo={}
      world['2,7,1']='minecraft:stone'
      for i=1,16 do emergencyCargo[i]={name=i<=2 and not opts.escapeAllValuable and 'minecraft:stone' or 'mod:ore',count=64} end
      turtle.getItemDetail=function(i) return emergencyCargo[i] end
      turtle.getItemCount=function(i) return emergencyCargo[i] and emergencyCargo[i].count or 0 end
      turtle.dropDown=function()
        assert(checkpointState().phase=='emergency','Dumped inventory outside escape')
        assert(emergencyCargo[selected] and emergencyCargo[selected].name=='minecraft:stone','Dumped valuable item')
        if opts.escapeDropFails then return false end
        emergencyCargo[selected]=nil;return true
      end
      turtle.drop=turtle.dropDown;turtle.dropUp=turtle.dropDown
    end
    run()
    if opts.escapeInterrupt or opts.escapeTurnInterrupt then run() end
    local state=checkpointState()
    if opts.escapeRoof or opts.escapeDropFails or opts.escapeAllValuable or opts.escapeFuel and opts.escapeFuel<6 then
      assert(state.phase=='emergency' and state.emergency,'Emergency failure did not remain resumable')
      assert(f>0,'Emergency detour exhausted fuel')
    else
      assert(state.phase=='rescued','Emergency ascent did not finish: '..state.phase)
      assert(p.y==(opts.unlimited and opts.escapeInterrupt and not opts.escapeBeforeInterrupt and -1 or opts.escapeHigher and -2 or 0),'Emergency reached wrong elevation: '..p.y)
      assert(state.emergency.p.y==0,'Emergency progress not checkpointed')
      if opts.escapeCeiling then assert(p.x~=2 or p.z~=1,'Did not bypass blocked upward cell') end
      local beforeActions=actions;run();assert(actions==beforeActions,'Rescued turtle resumed mining')
    end
    if emergencyCargo then for i=3,16 do assert(emergencyCargo[i] and emergencyCargo[i].name=='mod:ore','Lost valuables during trash disposal') end end
    if opts.injectEscapeFuel then assert(injected and consumed>0,'Emergency ascent did not use carried fuel') end
    if opts.network and companionState then
      assert(companionState.turtles[4].status.uncertain,'Emergency telemetry claimed confirmed quarry coordinates')
      if opts.networkEmergencyReturn then assert(injectedWireless and companionState.turtles[4].command.result=='rejected','Emergency routine accepted normal return') end
    end
    assert(world['2,6,0']=='minecraft:bedrock','Mined protected original return blockage')
    return
  end
  if opts.pairMenu then
    inputs={'1','7','123456'}
    if opts.pairAlias then run('pair','7','123456') else run('companion') end
    local paired=textutils.unserialize(files['quarry-data/companion'])
    assert(paired.enabled==not opts.badPairSender,'Pairing did not validate reply sender')
    assert(actions==0 and not checkpointState(),'Pairing changed quarry or turtle position')
    return
  end
  if opts.companionMenu then
    inputs=opts.companionMenu
    run('companion')
    assert(actions==0 and not checkpointState(),'Companion setup moved the turtle or made a job')
    if opts.networkDisabled or opts.network then
      local p=textutils.unserialize(files['quarry-data/companion'])
      assert(not p.enabled,'Companion disable did not persist')
    else assert(table.concat(messages,'\n'):find('No wireless/Ender modem found.',1,true),'Missing modem guidance absent') end
    return
  end
  if opts.commandFlow then
    local firstLine=#messages+1
    rawRun();assert(actions==0 and prompts==0 and not checkpointState(),'Plain mole started a quarry')
    local rows=0
    for i=firstLine,#messages do rows=rows+math.max(1,math.ceil(#messages[i]/39)) end
    assert(rows<=11,'First launch guide does not fit 39x12 terminal')
    for i=firstLine,#messages do assert(#messages[i]<=39,'Guide line wraps on turtle terminal') end

    assert(files['mole-install-data'],'First launch did not initialize installation')
    if opts.existingStartup then assert(files['startup.lua']=='existing startup','Installation overwrote custom startup')
    else assert(files['startup.lua']:find('shell.run(program, "resume")',1,true),'Startup does not resume') end
    local previous=prompts;rawRun('resume');assert(prompts==previous and not checkpointState(),'Resume started a new job')
    firstLine=#messages+1;rawRun();assert(actions==0 and prompts==0,'Repeated plain mole started a job')
    assert(#messages-firstLine+1<=11,'Guide leaves no shell prompt space')
    for i=firstLine,#messages do assert(#messages[i]<=39,'Repeated guide line wraps') end
  end
  if opts.deleteCorrupt then files['quarry-data/config']='damaged config' else run() end
  if opts.commandFlow then
    local before=actions;local beforePrompts=prompts;local beforeClears=clears
    rawRun();rawRun('help');rawRun('resume')
    assert(actions==before and prompts==beforePrompts,'Finished job restarted without new')
    assert(clears==beforeClears and clears==1,'Cleared useful output outside new setup')
  end
  if checkpointState() and checkpointState().pending then
    local before=actions;local beforePrompts=prompts;local beforeClears=clears
    rawRun();rawRun('new');assert(actions==before and prompts==beforePrompts and clears==beforeClears,'Plain mole or new acted on interrupted job')
  end

  if opts.fuelChest then
    if opts.expectedPulls==0 then assert(not table.concat(messages,'\n'):find('Fuel after chest refueling:',1,true),'Reported refueling when no fuel was consumed') end
    assert(f==opts.expectedFuel,'Wrong fuel amount from chest sequence: '..f)
    assert(pulls==opts.expectedPulls,'Scanned beyond fuel sequence or pulled too much')
    assert(bucketsReturned==(opts.expectedBuckets or 0),'Lost empty buckets')
    assert(p.y==0,'Fuel test moved away from chest')
    if opts.remainingBucket then assert(chestSlots[1] and chestSlots[1].name=='minecraft:lava_bucket','Consumed unneeded lava bucket') end
    if opts.secondFuelPass then
      f=1500;opts.expectedFuel=2500;run();assert(f==2500 and fuelConsumed==4,'Could not use remaining lava bucket automatically on second visit')
      assert(table.concat(messages,'\n'):find('safe minimum',1,true),'No below-target departure report')
    end
    return {chestListCalls=chestListCalls,fuel=f,pulls=pulls,buckets=bucketsReturned}
  end
  if opts.delete then
    files['mole']='program contents'
    if opts.changedStartup then files['startup.lua']='separately edited startup' end
    if opts.oldInstall then files['mole-install-data']=nil end
    if opts.resetBeforeDelete then run('reset') end
    local before=clone(files);local beforeActions=actions;local beforeFuel=f
    inputs={opts.deleteAnswer or 'yes'}
    run('delete')
    assert(actions==beforeActions and f==beforeFuel,'Uninstall moved or refueled')
    if opts.deleteAnswer and opts.deleteAnswer~='yes' then
      for k,v in pairs(before) do assert(files[k]==v,'Cancelled uninstall changed files') end
      for k,v in pairs(files) do assert(before[k]==v,'Cancelled uninstall added files') end
    else
      assert(not files['mole'] and not files['quarry-data/config'] and not files['quarry-data/state.a'] and not files['quarry-data/state.b'] and not files['mole-install-data'],'Uninstall left Mole files')
      if opts.changedStartup then assert(files['startup.lua']=='separately edited startup','Overwrote separately changed startup')
      else assert(files['startup.lua']==originalStartup,'Original startup not restored') end
    end
    return
  end
  if opts.legacy then
    assert(actions==0 and prompts==0,'Unsupported save moved or asked for Y')
    assert(table.concat(messages,'\n'):find('no valid starting Y',1,true),'Missing unsupported-save instructions');return
  end
  if opts.falseFuelError then
    assert(not checkpointState().emergency and checkpointState().pending,'Message text caused a false emergency')
    run();assert(checkpointState().phase=='done','Could not recover from ordinary unclassified error');return
  end
  if opts.restoreBridge then world['0,1,0']=nil;run() end
  if opts.cancel then
    assert(not checkpointState(),'Cancelled setup created a job'); assert(actions==0,'Moved during cancelled setup');return
  end
  if opts.oldFuelSchema then
    local upgraded=textutils.unserialize(files['quarry-data/config'])
    assert(upgraded.fuelSchemaVersion==2 and upgraded.fuel['minecraft:lava_bucket']==not opts.disableLava,'Fuel schema migration failed')
  end
  if opts.oldFuelDefault then assert(textutils.unserialize(files['quarry-data/config']).fuelTarget==2560,'Old fuel default not upgraded') end
  if dimensionPrompts>0 then
    for _,prompt in ipairs(promptText) do assert(not prompt:find('Emergency target Y',1,true),'Asked removed emergency target question') end
    assert(checkpointState().startY~=nil,'New job missing required starting Y')
    assert(checkpointState().emergencyTargetY==checkpointState().startY,'New emergency target differs from starting Y')
  end
  local setupPrompts=dimensionPrompts
  if opts.defaultConfig then
    assert(promptText[1]:find('[16]',1,true) and promptText[2]:find('[16]',1,true) and promptText[4]:find('[64]',1,true),'Wrong fresh-install defaults')
  end
  if opts.starve then f=0 end
  if opts.crash or opts.crashAfter or opts.turnCrash then
    if opts.returnDuringRecovery then
      run('return'); assert(checkpointState().phase=='paused' and p.y==0,'Return request not honored during recovery')
      assert(table.concat(messages,'\n'):find('Returned home and paused as requested. Run mole resume to resume.',1,true),'Requested pause sounds like an error')
      run()
    else run() end
  end
  if opts.recoveryCrash or opts.recoveryMoveCrash then run() end
  if opts.restoreChest then opts.missing=false; run() end
  if opts.newJob then
    p.d=0; inputs={tostring(length),tostring(width),tostring(opts.startY or 64),tostring(depth),opts.heightOverride or '', ''}; run('new')
    assert(files['quarry-data/previous-job'],'Previous job not archived')
    setupPrompts=dimensionPrompts
  end
  local a=files['quarry-data/state.a'] and textutils.unserialize(files['quarry-data/state.a'])
  local b=files['quarry-data/state.b'] and textutils.unserialize(files['quarry-data/state.b'])
  local s=(not b or a and a.seq>b.seq) and a or b
  if opts.chestCoal or opts.carriedCoal then
    local report=table.concat(messages,'\n')
    assert(report:find('Target: 100.',1,true),'Missing fuel target')
    assert(report:find('Fuel after chest refueling: 160 fuel units',1,true),'Missing fuel after refueling')
    assert(report:find('Remaining fuel:',1,true) and report:find('No refueling needed.',1,true),'Missing final fuel report')
  end
  if opts.trashBlocked or opts.trashDropFail then
    assert(s.phase=='dock' and p.y==0 and amount>0,'Failed trash drop did not retain trash at home')
  elseif opts.detourCrash then
    assert(s.phase=='rescued' or s.phase=='emergency','Interrupted detour did not preserve uncertain-position recovery')
  elseif opts.blockBridge and not opts.restoreBridge and not opts.breakableBridge then
    assert(s.phase=='done' or s.phase=='paused','Did not reach home after excavating a return detour');assert(p.y==0,'Did not return to surface')
    assert(s.tunnels['1,1,0'] or s.tunnels['0,1,1'],'Did not bypass blocked shaft')
    assert(world['0,1,0']=='minecraft:bedrock','Destroyed the blocked route')
  elseif opts.networkReturn then
    if opts.networkAcceptedCrash then assert(not crash,'Accepted remote return interruption was not exercised') end
    assert(s.phase=='paused' and p.y==0,'Remote return did not reach home and pause')
    assert(s.companionReturn and s.companionReturn.result=='completed','Remote return completion not persisted')
    assert(s.companionRequests[#s.companionRequests].result=='completed','Duplicate receipt did not persist completion')
    if companionState then assert(companionState.turtles[4].command.result=='completed','Companion did not receive completion') end
    local before=actions;inputs={'q'};run('resume')
    assert(actions==before,'Completed return receipt restarted movement on resume')
    local stored=checkpointState();assert(stored.companionReturn.result=='completed' and stored.companionRequests[#stored.companionRequests].result=='completed','Completed receipt lost after reloading serialized state')
  elseif opts.starve then assert(s.phase=='emergency'); assert(s.recovery)
  elseif opts.missing or opts.restoreChest then assert(s.phase=='rescued'); assert(s.recovery)
  elseif opts.protected then assert(s.phase=='paused'); assert(world['0,1,0']=='minecraft:chest')
  elseif opts.full then assert(s.phase=='dock')
  elseif opts.fuel and not opts.chestCoal and not opts.carriedCoal then assert(s.phase=='dock')
  else
    assert(s.phase=='done','Expected done, got '..s.phase)
    if opts.protectedScan then assert(world['0,1,1']=='minecraft:bedrock','Mined protected scan neighbor') end
    if opts.injectReturnFuel or opts.injectRecoveryFuel then assert(injected and consumed>0 and table.concat(messages,'\n'):find('Return fuel safety: used carried fuel',1,true),'Return did not consume carried fuel') end
    if not opts.air and not opts.stoneOnly and width>=3 and length>=3 and s.shape.h>=6 then
      assert((world['1,2,1']==nil or (opts.blockShortcut or opts.outboundObstacle) and world['1,2,1']=='minecraft:bedrock') and world['1,3,1']==nil and world['1,4,1']==nil,'Exposed ore vein remains')
      assert(world['1,6,0']=='mod:hidden_ore','Dug an unexposed isolated ore')
      assert(world['2,1,1']==(opts.fluid and 'mod:oil' or 'minecraft:stone'),'Dug a trash roof unnecessarily')
      local removed=0; for _ in pairs(dug) do removed=removed+1 end
      assert(removed<width*length*depth/2,'Excavated too much trash')
    end
    if opts.slowProgress then assert(table.concat(messages,'\n'):find('Searching a deposit:',1,true),'Long deposit search did not report activity') end
    assert(p.x==0 and p.y==0 and p.z==0,'Not home')
    assert(s.layoutVersion==2,'Tunnel layout not recorded')
    if opts.startY then
      assert(s.startY==opts.startY,'Starting Y not persisted')
      if opts.expectedTarget then assert(s.emergencyTargetY==opts.expectedTarget,'Emergency target not persisted') end
      assert(s.shape.h==(opts.expectedDepth or depth),'Height guidance produced wrong depth')
      local report=table.concat(messages,'\n')
      assert(report:find('Planned bottom: Y '..(opts.startY-s.shape.h),1,true),'Missing world Y report')
      assert(report:find('Depth available before Y -62: '..math.max(0,opts.startY+62)..' blocks',1,true),'Missing available depth')
      local warned=report:find('Caution: below Y -62',1,true)~=nil
      assert(warned==(depth>opts.startY+62),'Bedrock caution shown at wrong depth')
      local priorPrompts=prompts;run('status');assert(prompts==priorPrompts,'Status asked setup questions')
      assert(messages[#messages-1]:find('Y '..opts.startY,1,true),'Status missing world Y')
      assert(messages[#messages-2]:find('Status: Finished',1,true),'Status uses internal state name')
      assert(messages[#messages]:find('mole new',1,true),'Finished status missing next action')
    end
    if opts.stoneOnly and width==16 and length==16 and depth==6 then
      local removed=0; for _ in pairs(dug) do removed=removed+1 end
      assert(removed==215,'Wrong pure-stone tunnel layout: '..removed)
    end
  end
  if opts.network and not opts.networkReturn and not opts.networkSendThrow and not opts.networkReceiveThrow and not opts.networkDetach then
    local found=false;for _,packet in ipairs(wirelessPackets) do if packet.kind=='discovery' and packet.block=='mod:ore' then found=true end end
    assert(found,'Unknown mined block was not reported')
    if companionState then assert(companionState.turtles[4].status.phase=='Finished','Companion did not receive finished status') end
  end
  if opts.networkRecoveryReturn then assert(injectedWireless and (not companionState or companionState.turtles[4].command.result=='rejected'),'Recovery accepted normal return request') end
  if opts.networkBadSender or opts.networkBadAction then assert(not s.companionReturn,'Invalid wireless command affected quarry state') end
  if opts.networkDisabled then assert(#wirelessPackets==0,'Disabled feature sent packets') end
  if opts.chestCoal or opts.carriedCoal then assert(consumed==2 and coal+chestCoal==(opts.chestCoal or 0)+(opts.carriedCoal or 0)-2,'Incorrect smart refueling') end
  if opts.forceLeftCrash then assert(not crash,'Left-turn interruption was never exercised') end
  assert(dimensionPrompts==setupPrompts,'Resume asked setup questions again')
  if opts.legacyStartup or opts.legacyGuard or opts.resumeStartup then
    assert(files['startup.lua']:find('local program="mole"',1,true) and files['startup.lua']:find('shell.run(program, "resume")',1,true),'Old startup not updated to Mole')
  end
  if opts.settings then
    inputs={'1','mod:ignore_me','2','minecraft:stone','4',''};run('settings')
    local changed=textutils.unserialize(files['quarry-data/config'])
    assert(changed.trash['mod:ignore_me'] and not changed.trash['minecraft:stone'] and changed.discardTrash==false,'Settings not saved')
  end
  if opts.existingStartup then assert(files['startup.lua']=='existing startup','Overwrote existing startup')
  elseif not opts.legacy then assert(files['startup.lua'],'No automatic startup created') end
  return {turns=turns,leftTurns=leftTurns,inspections=inspections,moves=moves,detailQueries=detailQueries,countQueries=countQueries}
end
-- Named groups keep failures identifiable; set MOLE_VERBOSE=1 for turtle logs.
local function check(name,options)
  local ok,why=pcall(scenario,options)
  if not ok then error(name..': '..tostring(why),0) end
  return why
end
local lava={name='minecraft:lava_bucket',count=1}
local dirt={name='minecraft:dirt',count=1}

-- Mining and navigation
check('Mining and navigation 1',{})
check('Mining and navigation 2',{protected=true})
check('Mining and navigation 3',{full=true})
check('Mining and navigation 4',{slowProgress=true})
check('Mining and navigation 5',{width=16,length=16,depth=6})
check('Mining and navigation 6',{width=1,length=1,depth=1})
check('Mining and navigation 7',{width=5,length=4,depth=4})
check('Mining and navigation 8',{width=16,length=16,depth=6,stoneOnly=true})
check('Mining and navigation 9',{blockShortcut=true})
check('Mining and navigation 10',{protectedScan=true})
check('Mining and navigation 11',{fluid=true})
check('Mining and navigation 12',{blockBridge=true})
check('Mining and navigation 13',{blockBridge=true,width=1,length=1})
check('Mining and navigation 14',{blockBridge=true,breakableBridge=true})
check('Mining and navigation 15',{blockBridge=true,restoreBridge=true})
check('Mining and navigation 16',{outboundObstacle=true})

-- Setup and commands
check('Setup and commands 1',{inputs={'','','64',''}})
check('Setup and commands 2',{inputs={'bad','0','3','3','','64','6',''}})
check('Setup and commands 3',{inputs={'q'},cancel=true})
check('Setup and commands 4',{commandFlow=true})
check('Setup and commands 5',{legacy=true})
check('Setup and commands 6',{settings=true})
check('Setup and commands 7',{newJob=true})
check('Setup and commands 8',{defaultConfig=true})
check('Setup and commands 9',{startY=10,expectedTarget=10,inputs={'3','3','10','6',''}})
check('Setup and commands 10',{startY=10,expectedTarget=10,inputs={'3','3','','bad','1.5','10','6',''}})
check('Setup and commands 11',{inputs={'3','3','q'},cancel=true})
check('Setup and commands 12',{startY=-56})
check('Setup and commands 13',{startY=-59,expectedDepth=3})
check('Setup and commands 14',{startY=-59,heightOverride='yes'})
check('Setup and commands 15',{startY=-62,heightOverride='yes'})
check('Setup and commands 16',{startY=-63,heightOverride='yes'})
check('Setup and commands 17',{inputs={'3','3','bad','-56','6','',''}})
check('Setup and commands 18',{startY=-62,cancel=true})

-- Fuel and inventory
check('Fuel and inventory 1',{fuel=0})
check('Fuel and inventory 2',{fuel=0,fuelChest={lava,lava,lava,lava},expectedFuel=3000,expectedPulls=3,expectedBuckets=3,remainingBucket=4,bucketExpected=true})
check('Fuel and inventory 3',{fuel=0,fuelChest={[1]=lava,[3]=lava},expectedFuel=1000,expectedPulls=1,expectedBuckets=1})
check('Fuel and inventory 4',{fuel=0,fuelChest={lava,dirt,lava},expectedFuel=1000,expectedPulls=1,expectedBuckets=1})
check('Fuel and inventory 5',{fuel=0,fuelChest={[2]=lava},expectedFuel=0,expectedPulls=0})
check('Fuel and inventory 6',{fuel=0,fuelChest={{name='minecraft:coal',count=10},lava,lava},expectedFuel=2800,expectedPulls=3,expectedBuckets=2,bucketExpected=true})
check('Fuel and inventory 7',{fuel=3000,fuelChest={lava},expectedFuel=3000,expectedPulls=0,remainingBucket=1})
check('Fuel and inventory 8',{fuel=0,fuelChest={lava,lava,lava},changedFuel=true,expectedFuel=1000,expectedPulls=1,expectedBuckets=1})
check('Fuel and inventory 9',{oldFuelSchema=true})
check('Fuel and inventory 10',{oldFuelSchema=true,disableLava=true})
check('Fuel and inventory 11',{falseFuelError=true})
check('Fuel and inventory 12',{fuel=0,fuelChest={lava,lava,lava,lava},expectedFuel=3000,expectedPulls=3,expectedBuckets=3,secondFuelPass=true,bucketExpected=true})
check('Fuel and inventory 13',{fuel=500,fuelChest={},expectedFuel=500,expectedPulls=0})
check('Fuel and inventory 14',{fuel=0,fuelChest={},expectedFuel=0,expectedPulls=0})
check('Fuel and inventory 15',{injectReturnFuel=true})
check('Fuel and inventory 16',{injectRecoveryFuel=true,crashAfter=true,at=3})
check('Fuel and inventory 17',{oldFuelDefault=true})
check('Fuel and inventory 18',{trashCargo=true})
check('Fuel and inventory 19',{trashCargo=true,trashBlocked=true})
check('Fuel and inventory 20',{trashCargo=true,trashDropFail=true})
check('Fuel and inventory 21',{trashCargo=true,keepTrash=true})
check('Fuel and inventory 22',{fuel=0,chestCoal=64})
check('Fuel and inventory 23',{fuel=0,carriedCoal=64})

-- Emergency escape
check('Emergency escape 1',{emergencyCase=true,injectEscapeFuel=true})
check('Emergency escape 2',{emergencyCase=true,escapeFullInventory=true})
check('Emergency escape 3',{emergencyCase=true,escapeFullInventory=true,keepTrash=true})
check('Emergency escape 4',{emergencyCase=true,escapeFullInventory=true,escapeDropFails=true})
check('Emergency escape 5',{emergencyCase=true,escapeFullInventory=true,escapeAllValuable=true})
check('Emergency escape 6',{emergencyCase=true})
check('Emergency escape 7',{emergencyCase=true,escapeCeiling=true})
check('Emergency escape 8',{emergencyCase=true,escapeRoof=true})
check('Emergency escape 9',{emergencyCase=true,escapeFuel=5})
check('Emergency escape 10',{emergencyCase=true,escapeFuel=10})
check('Emergency escape 11',{emergencyCase=true,escapeHigher=true})
check('Emergency escape 12',{emergencyCase=true,escapeInterrupt=true})
check('Emergency escape 13',{emergencyCase=true,escapeInterrupt=true,escapeBeforeInterrupt=true})
check('Emergency escape 14',{emergencyCase=true,escapeCeiling=true,escapeTurnInterrupt=true})
check('Emergency escape 15',{emergencyCase=true,escapeInterrupt=true,unlimited=true})

-- Recovery
check('Recovery 1',{turnCrash=true,at=30,recoveryCrash=true})
check('Recovery 2',{turnCrash=true,at=30,missing=true})
check('Recovery 3',{turnCrash=true,crashAfter=true,at=30,air=true})
check('Recovery 4',{turnCrash=true,crashAfter=true,at=30,missing=true,restoreChest=true})
check('Recovery 5',{unlimited=true,crashAfter=true,at=45})
check('Recovery 6',{turnCrash=true,at=30,recoveryCrash=true,recoveryAfter=true})
check('Recovery 7',{crashAfter=true,at=45,recoveryMoveCrash=true})
check('Recovery 8',{crashAfter=true,at=45,recoveryMoveCrash=true,recoveryAfter=true})
check('Recovery 9',{crashAfter=true,at=45,starve=true})
check('Recovery 10',{crashAfter=true,at=45,returnDuringRecovery=true})
check('Recovery 11',{turnCrash=true,forceLeftCrash=true})
check('Recovery 12',{turnCrash=true,forceLeftCrash=true,crashAfter=true})
check('Recovery 13',{fluid=true,crash=true,at=3})
check('Recovery 14',{fluid=true,crashAfter=true,at=3})
check('Recovery 15',{fluid=true,turnCrash=true,at=3})
check('Recovery 16',{blockBridge=true,detourCrash=true,crash=true})
check('Recovery 17',{blockBridge=true,detourCrash=true,crashAfter=true})
check('Recovery 18',{outboundObstacle=true,crashAfter=true,at=3})
check('Recovery 19',{blockShortcut=true,turnCrash=true,at=1})

-- Installation and updates
check('Installation and updates 1',{commandFlow=true,existingStartup=true})
check('Installation and updates 2',{resumeStartup=true})
check('Installation and updates 3',{existingStartup=true})
check('Installation and updates 4',{legacyStartup=true})
check('Installation and updates 5',{legacyGuard=true})
check('Installation and updates 6',{update=true})
check('Installation and updates 7',{update=true,updateCached=true})
check('Installation and updates 8',{update=true,existingStartup=true})
check('Installation and updates 9',{update=true,updateSame=true})
check('Installation and updates 10',{update=true,updateOlder=true})
check('Installation and updates 11',{update=true,updateBad=true})
check('Installation and updates 12',{update=true,updateSyntax=true})
check('Installation and updates 13',{update=true,updateOffline=true})
check('Installation and updates 14',{update=true,updateDisabled=true})
check('Installation and updates 15',{update=true,updateMoveFail=true})
check('Installation and updates 16',{update=true,updateWriteFail=true})
check('Installation and updates 17',{update=true,updateUnload=true})
check('Installation and updates 18',{delete=true})
check('Installation and updates 19',{delete=true,deleteAnswer='no'})
check('Installation and updates 20',{delete=true,deleteAnswer=''})
check('Installation and updates 21',{delete=true,existingStartup=true})
check('Installation and updates 22',{delete=true,legacyStartup=true})
check('Installation and updates 23',{delete=true,legacyGuard=true})
check('Installation and updates 24',{delete=true,changedStartup=true})
check('Installation and updates 25',{delete=true,resetBeforeDelete=true})
check('Installation and updates 26',{delete=true,deleteCorrupt=true})
check('Installation and updates 27',{delete=true,oldInstall=true})
check('Installation and updates 28',{reset=true})
check('Installation and updates 29',{reset=true,corruptReset=true})
check('Installation and updates 30',{reset=true,existingStartup=true})
check('Installation and updates 31',{reset=true,resetResume=true})

-- Optional wireless integration, including live companion protocol validation when available.
local standaloneMetrics=check('Standalone reference for wireless',{})
local wirelessMetrics=check('Wireless telemetry and discoveries',{network=true})
assert(standaloneMetrics.moves==wirelessMetrics.moves and standaloneMetrics.turns==wirelessMetrics.turns and standaloneMetrics.inspections==wirelessMetrics.inspections,'Optional reporting changed mining actions')
check('Remote return and duplicate requests',{network=true,networkReturn=true})
check('Accepted remote return survives interrupted movement',{network=true,networkReturn=true,networkAcceptedCrash=true,crashAfter=true})
check('Wireless send failure keeps mining',{network=true,networkSendThrow=true})
check('Wireless listener failure keeps mining',{network=true,networkReceiveThrow=true})
check('Modem detach keeps mining',{network=true,networkDetach=true})
check('Disabled wireless never probes hardware',{networkDisabled=true})
check('Companion menu missing modem',{companionMenu={'1'}})
check('Companion menu disables reporting',{network=true,companionMenu={'2'}})
check('Guided companion pairing',{network=true,pairMenu=true})
check('Station pairing command',{network=true,pairMenu=true,pairAlias=true})
check('Wrong station pairing reply rejected',{network=true,pairMenu=true,badPairSender=true})
check('Wireless emergency position reporting',{network=true,emergencyCase=true})
check('Emergency rejects ordinary remote return',{network=true,emergencyCase=true,networkEmergencyReturn=true})
check('Recovery rejects ordinary remote return',{network=true,crashAfter=true,at=45,networkRecoveryReturn=true})
check('Wrong station commands ignored',{network=true,networkBadSender=true})
check('Arbitrary wireless actions ignored',{network=true,networkBadAction=true})

-- Every action offset remains covered, before/after movement and turning.
for at=1,140 do
  check('Move before interruption '..at,{crash=true,at=at})
  check('Move after interruption '..at,{crashAfter=true,at=at})
  check('Turn before interruption '..at,{turnCrash=true,at=at})
  check('Turn after interruption '..at,{turnCrash=true,crashAfter=true,at=at})
end
originalPrint('PASS: '..scenarioCount..' scenarios: mining, commands, fuel, emergency escape, recovery, installation and updates')
