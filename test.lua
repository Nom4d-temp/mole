-- Offline mock tests: run with Lua 5.4, not on the turtle.
local programFile=assert(io.open('mole.lua') or io.open('mole/mole.lua'))
local program=programFile:read('*a');programFile:close()
local scenarioCount=0
local originalPrint=print
local function scenario(opts)
  scenarioCount=scenarioCount+1
  fs=nil;turtle=nil;peripheral=nil;textutils=nil;read=nil;write=nil;print=originalPrint;collectgarbage('collect')
  http=nil
  local messages={}
  print=function(...) local parts={...};for i,v in ipairs(parts) do parts[i]=tostring(v) end;messages[#messages+1]=table.concat(parts,' ');originalPrint(...) end
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
    local interrupt=crash and not opts.turnCrash and (opts.detourCrash and checkpointState().service and checkpointState().service.excavating or not opts.detourCrash and actions>=(opts.at or 1))
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
  local function run(...) return assert(load(program,'mole'))(...) end
  local c={width=width,length=length,depth=depth,fuelTarget=opts.fuelChest and (opts.fuelGoal or 2560) or opts.oldFuelDefault and 2000 or 100,fuelMargin=10,retries=12,veinLimit=128,veinDepth=24,
    fuelSchemaVersion=2,discardTrash=not opts.keepTrash,fuel={['minecraft:coal']=true,['minecraft:charcoal']=true,['minecraft:lava_bucket']=true},
    trash={['minecraft:stone']=true},protected={['minecraft:chest']=true,['minecraft:bedrock']=true}}
  if opts.oldFuelSchema then c.fuelSchemaVersion=nil;c.fuel['minecraft:lava_bucket']=nil;if opts.disableLava then c.fuel['minecraft:lava_bucket']=false end end
  if not opts.defaultConfig then files['quarry-data/config']=textutils.serialize(c) end
  if opts.update then
    files['mole']=program
    files['quarry-data/state.a']=textutils.serialize({seq=4,phase='recovery',pending={}})
    files['quarry-data/previous-job']='previous job'
    if not opts.existingStartup then files['startup.lua']='-- Automatically resume the saved mining job.\nshell.run("mole")\n' end
    local before=clone(files)
    local source=program:gsub('1%.4%.5','9.0.0')
    if opts.updateSame then source=program end
    if opts.updateOlder then source=program:gsub('1%.4%.5','0.9.9') end
    if opts.updateBad then source='not a program' end
    if opts.updateSyntax then source='-- Mole v9.0.0\nlocal =' end
    local closed=false
    if not opts.updateDisabled then
      http={get=function(url)
        assert(url=='https://raw.githubusercontent.com/Nom4d-temp/mole/main/mole.lua','Wrong update URL')
        if opts.updateOffline then return nil,'HTTP 404' end
        return {readAll=function() return source end,close=function() closed=true end}
      end}
    end
    run('update')
    for _,name in ipairs({'quarry-data/config','quarry-data/state.a','quarry-data/previous-job'}) do assert(files[name]==before[name],'Update changed job/settings') end
    assert(actions==0 and prompts==0,'Update moved or prompted')
    if opts.updateUnload then
      assert(not files['mole'] and files['mole.update-backup']==program,'Interrupted install lost backup')
      local booted=false
      assert(load(files['startup.lua'],'startup','t',{fs=fs,shell={run=function(path) assert(path=='mole');booted=true end}}))()
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
  if opts.activeLegacyFrame then
    p.y=2;p.z=1;world['0,1,0']=nil;world['0,2,0']=nil;world['0,2,1']=nil
    local old={seq=10,p=clone(p),route={{x=0,y=1,z=0,d=0},{x=0,y=2,z=0,d=0},{x=0,y=2,z=1,d=0}},
      index=3,phase='work',seen={},layoutVersion=2,anchor={type='minecraft:chest',size=27},shape={w=width,l=length,h=depth},
      vein={stack={{p=clone(p),next=0}},count=0}}
    files['quarry-data/state.a']=textutils.serialize(old)
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
      service={path={cleared[1],cleared[2],cleared[3],cleared[4],cleared[5],cleared[6]},at=0,
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
    local saved={seq=10,p=clone(p),route=trail,index=10,phase='home',seen={},layoutVersion=2,
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
    assert(world['2,6,0']=='minecraft:bedrock','Mined protected original return blockage')
    return
  end
  if opts.deleteCorrupt then files['quarry-data/config']='damaged config' else run() end
  if opts.fuelChest then
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
  if opts.legacy or opts.activeLegacyFrame then
    assert(prompts==0,'Existing job without Y asked setup questions')
    assert(checkpointState().startY==nil,'Existing job was assigned an invented Y')
  elseif dimensionPrompts>0 then
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
    assert(report:find('Fuel target: 100 units',1,true),'Missing fuel target')
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
    end
    if opts.stoneOnly and width==16 and length==16 and depth==6 then
      local removed=0; for _ in pairs(dug) do removed=removed+1 end
      assert(removed==215,'Wrong pure-stone tunnel layout: '..removed)
    end
  end
  if opts.chestCoal or opts.carriedCoal then assert(consumed==2 and coal+chestCoal==(opts.chestCoal or 0)+(opts.carriedCoal or 0)-2,'Incorrect smart refueling') end
  if opts.forceLeftCrash then assert(not crash,'Left-turn interruption was never exercised') end
  assert(dimensionPrompts==setupPrompts,'Resume asked setup questions again')
  if opts.legacyStartup or opts.legacyGuard then
    assert(files['startup.lua']:find('local program="mole"',1,true) and files['startup.lua']:find('shell.run(program)',1,true),'Old startup not updated to Mole')
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
scenario({});scenario({crash=true});scenario({crashAfter=true});
scenario({turnCrash=true,at=30});scenario({turnCrash=true,crashAfter=true,at=30});
scenario({crash=true,at=45});scenario({crashAfter=true,at=45});
scenario({turnCrash=true,at=30,recoveryCrash=true});
scenario({turnCrash=true,at=30,missing=true});
scenario({protected=true});scenario({full=true});scenario({fuel=0})
scenario({turnCrash=true,crashAfter=true,at=30,air=true});
scenario({turnCrash=true,crashAfter=true,at=30,missing=true,restoreChest=true});
scenario({unlimited=true,crashAfter=true,at=45});
scenario({turnCrash=true,at=30,recoveryCrash=true,recoveryAfter=true});
scenario({crashAfter=true,at=45,recoveryMoveCrash=true});
scenario({crashAfter=true,at=45,recoveryMoveCrash=true,recoveryAfter=true});
scenario({crashAfter=true,at=45,starve=true});
scenario({inputs={'','','64',''}});
scenario({inputs={'bad','0','3','3','','64','6',''}});
scenario({inputs={'q'},cancel=true});
scenario({existingStartup=true});scenario({legacy=true});
scenario({width=16,length=16,depth=6});
scenario({width=1,length=1,depth=1});
scenario({width=5,length=4,depth=4});
scenario({width=16,length=16,depth=6,stoneOnly=true});
scenario({settings=true});scenario({newJob=true});
scenario({defaultConfig=true});
scenario({crashAfter=true,at=45,returnDuringRecovery=true});
scenario({legacyStartup=true});scenario({legacyGuard=true});
scenario({activeLegacyFrame=true});
scenario({activeLegacyFrame=true,crashAfter=true});
scenario({turnCrash=true,forceLeftCrash=true});
scenario({turnCrash=true,forceLeftCrash=true,crashAfter=true});
scenario({blockShortcut=true});
local lava={name='minecraft:lava_bucket',count=1};local dirt={name='minecraft:dirt',count=1}
scenario({fuel=0,fuelChest={lava,lava,lava,lava},expectedFuel=3000,expectedPulls=3,expectedBuckets=3,remainingBucket=4,bucketExpected=true});
scenario({fuel=0,fuelChest={[1]=lava,[3]=lava},expectedFuel=1000,expectedPulls=1,expectedBuckets=1});
scenario({fuel=0,fuelChest={lava,dirt,lava},expectedFuel=1000,expectedPulls=1,expectedBuckets=1});
scenario({fuel=0,fuelChest={[2]=lava},expectedFuel=0,expectedPulls=0});
scenario({fuel=0,fuelChest={{name='minecraft:coal',count=10},lava,lava},expectedFuel=2800,expectedPulls=3,expectedBuckets=2,bucketExpected=true});
scenario({fuel=3000,fuelChest={lava},expectedFuel=3000,expectedPulls=0,remainingBucket=1});
scenario({fuel=0,fuelChest={lava,lava,lava},changedFuel=true,expectedFuel=1000,expectedPulls=1,expectedBuckets=1});scenario({oldFuelSchema=true});scenario({oldFuelSchema=true,disableLava=true});scenario({falseFuelError=true});scenario({protectedScan=true});scenario({fuel=0,fuelChest={lava,lava,lava,lava},expectedFuel=3000,expectedPulls=3,expectedBuckets=3,secondFuelPass=true,bucketExpected=true});scenario({fuel=500,fuelChest={},expectedFuel=500,expectedPulls=0});scenario({fuel=0,fuelChest={},expectedFuel=0,expectedPulls=0});scenario({injectReturnFuel=true});scenario({injectRecoveryFuel=true,crashAfter=true,at=3});scenario({emergencyCase=true,injectEscapeFuel=true});scenario({emergencyCase=true,escapeFullInventory=true});scenario({emergencyCase=true,escapeFullInventory=true,keepTrash=true});scenario({emergencyCase=true,escapeFullInventory=true,escapeDropFails=true});scenario({emergencyCase=true,escapeFullInventory=true,escapeAllValuable=true});scenario({emergencyCase=true});scenario({emergencyCase=true,escapeCeiling=true});scenario({emergencyCase=true,escapeRoof=true});scenario({emergencyCase=true,escapeFuel=5});scenario({emergencyCase=true,escapeFuel=10});scenario({emergencyCase=true,escapeHigher=true});scenario({emergencyCase=true,escapeInterrupt=true});scenario({emergencyCase=true,escapeInterrupt=true,escapeBeforeInterrupt=true});scenario({emergencyCase=true,escapeCeiling=true,escapeTurnInterrupt=true});scenario({emergencyCase=true,escapeInterrupt=true,unlimited=true});scenario({startY=10,expectedTarget=10,inputs={'3','3','10','6',''}});scenario({startY=10,expectedTarget=10,inputs={'3','3','','bad','1.5','10','6',''}});scenario({inputs={'3','3','q'},cancel=true});scenario({oldFuelDefault=true});scenario({startY=-56});scenario({startY=-59,expectedDepth=3});scenario({startY=-59,heightOverride='yes'});scenario({startY=-62,heightOverride='yes'});scenario({startY=-63,heightOverride='yes'});scenario({inputs={'3','3','bad','-56','6','',''}});scenario({startY=-62,cancel=true});scenario({update=true});scenario({update=true,existingStartup=true});scenario({update=true,updateSame=true});scenario({update=true,updateOlder=true});scenario({update=true,updateBad=true});scenario({update=true,updateSyntax=true});scenario({update=true,updateOffline=true});scenario({update=true,updateDisabled=true});scenario({update=true,updateMoveFail=true});scenario({update=true,updateWriteFail=true});scenario({update=true,updateUnload=true});scenario({delete=true});scenario({delete=true,deleteAnswer='no'});scenario({delete=true,deleteAnswer=''});scenario({delete=true,existingStartup=true});scenario({delete=true,legacyStartup=true});scenario({delete=true,legacyGuard=true});scenario({delete=true,changedStartup=true});scenario({delete=true,resetBeforeDelete=true});scenario({delete=true,deleteCorrupt=true});scenario({delete=true,oldInstall=true});scenario({reset=true});scenario({reset=true,corruptReset=true});scenario({reset=true,existingStartup=true});scenario({reset=true,resetResume=true});scenario({fluid=true});scenario({fluid=true,crash=true,at=3});scenario({fluid=true,crashAfter=true,at=3});scenario({fluid=true,turnCrash=true,at=3});scenario({trashCargo=true});scenario({trashCargo=true,trashBlocked=true});scenario({trashCargo=true,trashDropFail=true});scenario({trashCargo=true,keepTrash=true});scenario({blockBridge=true});scenario({blockBridge=true,width=1,length=1});scenario({blockBridge=true,detourCrash=true,crash=true});scenario({blockBridge=true,detourCrash=true,crashAfter=true});scenario({blockBridge=true,breakableBridge=true});scenario({blockBridge=true,restoreBridge=true});
scenario({outboundObstacle=true});
scenario({fuel=0,chestCoal=64});scenario({fuel=0,carriedCoal=64});
scenario({outboundObstacle=true,crashAfter=true,at=3});
scenario({blockShortcut=true,turnCrash=true,at=1});
-- Sweep action offsets across quarrying, veins, band returns and docking.
for at=1,140 do
  scenario({crash=true,at=at}); scenario({crashAfter=true,at=at});
  scenario({turnCrash=true,at=at}); scenario({turnCrash=true,crashAfter=true,at=at});
end
print('PASS: '..scenarioCount..' scenarios, guided setup, input validation/cancel, resume without prompts, startup preservation, legacy upgrade, tunnel trash retained, exposed veins, hidden ores left, bounds, automatic chest recovery, fuel and chest failures')

-- Optional comparison against a prior source file, outside the deliverable.
local baseline=os.getenv('MOLE_BASELINE')
if baseline then
  local current=program
  program=assert(io.open(baseline)):read('*a')
  local before=scenario({width=16,length=16,depth=6,stoneOnly=true})
  program=current
  local after=scenario({width=16,length=16,depth=6,stoneOnly=true})
  assert(after.turns<=before.turns,'Turning regressed')
  assert(after.leftTurns>0,'No shortest-left turns exercised')
  assert(after.moves==before.moves,'Changed movement path')
  assert(after.inspections==before.inspections,'Changed inspection coverage')
  assert(after.detailQueries<before.detailQueries,'Fuel inventory scans did not decrease')
  assert(after.countQueries<before.countQueries,'Space inventory scans did not decrease')
  print(string.format('INVENTORY: item-detail queries %d -> %d; item-count queries %d -> %d',before.detailQueries,after.detailQueries,before.countQueries,after.countQueries))
  print(string.format('BENCHMARK: turns %d -> %d; block inspections %d -> %d; moves %d -> %d',before.turns,after.turns,before.inspections,after.inspections,before.moves,after.moves))
end

if baseline then
  local current=program
  program=assert(io.open(baseline)):read('*a');local before=scenario({})
  program=current;local after=scenario({})
  assert(after.moves<before.moves,'Known tunnel shortcuts did not reduce travel')
  print(string.format('KNOWN-TUNNEL LOOP: movements %d -> %d',before.moves,after.moves))
end
