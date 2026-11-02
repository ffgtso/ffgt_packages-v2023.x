return function(test, core)
local controller = require 'offline-manager.controller'
local ssid = require 'offline-manager.ssid'
local function count(list, name)
 local n=0; for _,v in ipairs(list) do if v==name then n=n+1 end end; return n
end
local function old(now, since, attempt)
 return {boot='boot', checked=now-60, since=since, last_attempt=attempt}
end
local function fake(now, state, gateways)
 local o={calls={}, now=now, state=state, gateways=gateways, flags={}}
 local function call(n) o.calls[#o.calls+1]=n end
 o.uptime=function() return o.now end
 o.boot_id=function() return 'boot' end
 o.load_state=function() return o.state end
 o.save_state=function(s) o.state=s; call('save') end
 o.has_gateways=function() return o.gateways end
 o.gateway_status=function() return o.gateways, o.tq or (o.gateways and 255 or 0) end
 o.option=function(k) return o.flags[k]~=false end
 o.autoupdate_enabled=function() return true end
 o.upgrading=function() return false end
 o.autoupdater_busy=function() return false end
 o.lock=function(n) assert(n=='action'); call('lock'); return 7 end
 o.unlock=function(fd) assert(fd==7); call('unlock') end
 o.ssid=function(online) call(online == nil and 'ssid-keep' or (online and 'ssid-online' or 'ssid-offline')) end
 o.spawn_worker=function() call('spawn'); return true end
 o.reboot=function() call('reboot'); return true end
 o.log=function() end
 return o
end
test('First missing gateway starts interval', function()
 local o=fake(1000,nil,false); assert(controller.tick(o))
 assert(o.state.since==1000 and count(o.calls,'spawn')==0 and count(o.calls,'ssid-offline')==1)
end)
test('Strict thresholds and ten minute cooldown', function()
 assert(core.action({since=0},3600)=='none')
 assert(core.action({since=0},3601)=='update')
 assert(core.action({since=0,last_attempt=3601},4200)=='none')
 assert(core.action({since=0,last_attempt=3601},4201)=='update')
 assert(core.action({since=0},5700)=='update')
 assert(core.action({since=0},5701)=='reboot')
end)
test('Fifteen minute boot grace still records gateways', function()
 local o=fake(899,nil,false); assert(controller.tick(o))
 assert(#o.calls==1 and o.calls[1]=='save')
end)
test('Complete minute cadence: four attempts then reboot', function()
 local o=fake(18,nil,false); local attempts,reboot={},nil
 o.spawn_worker=function() attempts[#attempts+1]=o.now; return true end
 o.reboot=function() reboot=o.now; return true end
 for t=18,5778,60 do o.now=t; assert(controller.tick(o)) end
 assert(#attempts==4 and attempts[1]==3678 and attempts[2]==4278 and attempts[3]==4878 and attempts[4]==5478)
 assert(reboot==5778)
end)
test('Gateway return resets outage and cooldown', function()
 local o=fake(4000,old(4000,0,3700),true); assert(controller.tick(o))
 assert(o.state.since==nil and o.state.last_attempt==nil and count(o.calls,'ssid-online')==1)
 o.now=4060; o.gateways=false; assert(controller.tick(o)); assert(o.state.since==4060)
end)
test('Unknown gateways invalidate state without disruptive action', function()
 local o=fake(6000,old(6000,0),nil); assert(not controller.tick(o))
 assert(o.state.since==nil and #o.calls==1)
end)
test('Observation gaps reboot and invalid timestamps reset continuity', function()
 for _,s in ipairs({{boot='boot',checked=3849,since=0},{boot='other',checked=3999,since=0},
 {boot='boot',checked=4001,since=0},{boot='boot',checked=3999,since=-1},
 {boot='boot',checked=3999,since=4000}}) do
  assert(core.observe(s,4000,'boot',false).since==4000)
 end
 assert(core.observe({boot='boot',checked=3850,since=0},4000,'boot',false).since==0)
end)
test('Worker lock permits minute observations but blocks mutations', function()
 local o=fake(6000,old(6000,0),false); o.lock=function() return nil end
 assert(controller.tick(o)); assert(o.state.since==0 and o.state.checked==6000)
 assert(count(o.calls,'reboot')==0 and count(o.calls,'ssid-offline')==0)
end)
test('External updater and upgrade marker protect against reboot', function()
 for _,key in ipairs({'autoupdater_busy','upgrading'}) do
  local o=fake(6000,old(6000,0),false); o[key]=function() return true end
  assert(controller.tick(o)); assert(count(o.calls,'reboot')==0 and count(o.calls,'ssid-offline')==0)
 end
end)
test('Reboot takes priority over another update after 95 minutes', function()
 local o=fake(5701,old(5701,0),false); assert(controller.tick(o))
 assert(count(o.calls,'reboot')==1 and count(o.calls,'spawn')==0)
end)
test('Last-second gateway return prevents reboot', function()
 local o=fake(6000,old(6000,0),false)
 o.has_gateways=function() return true end
 assert(controller.tick(o)); assert(count(o.calls,'reboot')==0)
end)
test('Cooldown persisted and lock released before worker starts', function()
 local o=fake(4000,old(4000,0),false)
 o.spawn_worker=function() assert(o.state.last_attempt==4000 and o.calls[#o.calls]=='unlock'); return true end
 assert(controller.tick(o))
end)
test('Disabled autoupdate keeps watchdog and SSID function', function()
 local o=fake(4000,old(4000,0),false); o.flags.autoupdate_enabled=false
 assert(controller.tick(o)); assert(count(o.calls,'spawn')==0)
 o.now=6000; o.state=old(6000,0); assert(controller.tick(o)); assert(count(o.calls,'reboot')==1)
end)
test('SSID errors release action lock', function()
 local o=fake(6000,old(6000,0),false); o.ssid=function() error('write failed') end
 assert(not controller.tick(o)); assert(o.calls[#o.calls]=='unlock' and count(o.calls,'reboot')==0)
end)
test('Open and OWE are independent SSIDs; private BSS is untouched', function()
 local text='interface=client0\nssid=old\n'..
 'bss=owe0\nssid2=00\nwpa_key_mgmt=OWE\nignore_broadcast_ssid=0\n'..
 'bss=private0\nssid=private\nwpa_passphrase=secret\n'
 local map={client0={ssid='Open'},owe0={ssid='OWE'}}
 local result=ssid.rewrite(text,map)
 assert(result:find('ssid2=4f70656e',1,true) and result:find('ssid2=4f5745',1,true))
 assert(result:find('wpa_key_mgmt=OWE\nignore_broadcast_ssid=0',1,true))
 assert(result:find('bss=private0\nssid=private\nwpa_passphrase=secret\n',1,true))
 assert(not result:find('owe_transition',1,true))
 assert(ssid.rewrite(result,map)==result)
end)
test('TQ boundaries: 15 offline, 16 through 29 keep, 30 online', function()
 for _,tq in ipairs({0,1,14,15}) do assert(core.ssid_online(tq)==false) end
 for tq=16,29 do assert(core.ssid_online(tq)==nil) end
 for _,tq in ipairs({30,31,255}) do assert(core.ssid_online(tq)==true) end
 assert(core.ssid_online(nil)==nil)
end)
test('Very weak listed gateway changes SSIDs but prevents update and reboot', function()
 for _,tq in ipairs({0,1,15}) do
  local o=fake(6000,old(6000,0),true); o.tq=tq
  assert(controller.tick(o)); assert(o.state.since==nil)
  assert(count(o.calls,'ssid-offline')==1 and count(o.calls,'spawn')==0 and count(o.calls,'reboot')==0)
 end
end)
test('Hysteresis keeps SSIDs and gateway presence clears outage', function()
 local o=fake(6000,old(6000,0),true); o.tq=20
 assert(controller.tick(o)); assert(count(o.calls,'ssid-keep')==1 and o.state.since==nil)
end)
test('Presence considers all gateways, quality only selected gateway', function()
 local yes,tq=core.gateway_status('  aa:bb:cc:dd:ee:ff (255)\n* 00:11:22:33:44:55 ( 15)\n')
 assert(yes and tq==15)
 yes,tq=core.gateway_status('aa:bb:cc:dd:ee:ff (255)\n'); assert(yes and tq==0)
 yes,tq=core.gateway_status('=> aa:bb:cc:dd:ee:ff (bad)\n'); assert(yes and tq==nil)
 yes,tq=core.gateway_status('No gateways in range.\n'); assert(yes==false and tq==0)
 assert(core.gateway_status('unexpected error')==nil)
end)
test('SSID length and escaping', function()
 assert(not ssid.valid('a\nb') and not ssid.valid('a\0b') and not ssid.valid(string.rep('x',33)))
 assert(ssid.rewrite('interface=client0\nssid=old\n',{client0={ssid='"$;&\\'}})==
 'interface=client0\nssid2=22243b265c\n')
 assert(#ssid.offline_name('FF_OFFLINE_',string.rep('a',100))==32)
 assert(#ssid.offline_name('FF_OFF_OWE_',string.rep('a',100))==32)
end)
end
