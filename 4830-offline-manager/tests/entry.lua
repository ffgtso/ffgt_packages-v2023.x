return function(test, core)
local saved_runtime = package.loaded['offline-manager.runtime']
local saved_core = package.loaded['offline-manager.core']
local function entry(options)
 local calls={}; local now=options.now or 4000
 local o={uci={get=function() return 'stable' end}, lock=function() return 7 end,
  install_signals=function() end, uptime=function() return now end,
  load_state=function() return {boot='b',checked=now,since=0} end, boot_id=function() return 'b' end,
  option=function() return true end, autoupdate_enabled=function() return true end,
  upgrading=function() return options.upgrading or false end,
  autoupdater_busy=function() return options.busy or false end,
  has_gateways=function() return options.gateway or false end,
  set_deadline=function(d) calls.deadline=d end,
  pump_uplink_enabled=function() return options.pump or false end,
  wifi_state=function() return options.wifi or 'active', {} end,
  branch_exists=function() return true end, scan=function() calls.scan=true; return {} end,
  cancelled=function() return false end, log=function() end}
 package.loaded['offline-manager.runtime']=o
 package.loaded['offline-manager.core']={outage_valid=core.outage_valid,
  wan_round=function(_,pump) if pump then calls.pump=true;options.upgrading=options.pump_upgrade;options.gateway=options.pump_gateway else calls.wan=true end; return true end,
  round=function() calls.round=true; return true end}
 local exit=os.exit; os.exit=function(code) error({exit=code}) end
 local ok,err=pcall(dofile,'luasrc/usr/lib/4830-offline-manager/worker')
 os.exit=exit; package.loaded['offline-manager.runtime']=saved_runtime
 package.loaded['offline-manager.core']=saved_core
 assert(not ok and type(err)=='table' and err.exit~=nil,tostring(err))
 calls.exit=err.exit; return calls
end
test('Worker without WLAN goes to WAN without scanning',function()
 local c=entry({wifi='absent'}); assert(c.wan and not c.scan and c.exit==0)
end)
test('Worker tries PUMP uplink before WiFi scan',function()
 local c=entry({pump=true}); assert(c.pump and c.scan and c.round and not c.wan)
end)
test('PUMP update handoff prevents subsequent scan',function()
 local c=entry({pump=true,pump_upgrade=true}); assert(c.pump and not c.scan and not c.round and c.exit==0)
end)
test('PUMP gateway recovery prevents subsequent scan',function()
 local c=entry({pump=true,pump_gateway=true}); assert(c.pump and not c.scan and not c.round and c.exit==0)
end)
test('Worker respects gateway update and reboot guards',function()
 for _,o in ipairs({{gateway=true},{upgrading=true},{busy=true},{now=3600},{now=5701}}) do
  local c=entry(o); assert(not c.deadline and not c.scan and not c.wan)
 end
end)
test('Worker preparation budget ends before next cadence or reboot threshold',function()
 assert(entry({now=4000}).deadline==4540)
 assert(entry({now=5500}).deadline==5700)
end)
-- Execute the real migration against a minimal UCI double.
test('Migration preserves disabled updater and removes old schedules',function()
 local fake, data, removed={}, {}, {}
 data['autoupdater-wifi-fallback/settings/enabled']='0'
 fake.get=function(_,c,s,o) return data[c..'/'..s..(o and '/'..o or '')] end
 fake.get_bool=function(self,c,s,o) return self:get(c,s,o)=='1' end
 fake.set=function(_,c,s,o,v) data[c..'/'..s..'/'..o]=v end
 fake.section=function(_,c,typ,s,v) data[c..'/'..s]=v end
 fake.delete=function() end
 fake.save=function() end
 local uci=package.loaded['simple-uci']; package.loaded['simple-uci']={cursor=function() return fake end}
 local remove=os.remove; os.remove=function(p) removed[p]=true; return true end
 local ok,err=pcall(dofile,'luasrc/lib/gluon/upgrade/510-4830-offline-manager')
 os.remove=remove; package.loaded['simple-uci']=uci; assert(ok,err)
 assert(data['4830-offline-manager/settings/autoupdate_enabled']==false)
 assert(data['network/offline_wifi6'].ifname=='offlinewifi')
 assert(data['network/offline_wifi6'].auto==false)
 assert(data['firewall/offline_manager'].network[1]=='offline_wifi6')
 assert(data['firewall/offline_manager_dhcp6'].dest_port=='546')
 for _,s in ipairs({'ssid-changer','autoupdater-wifi-fallback','4830-node-watchdog'}) do
  assert(removed['/usr/lib/micron.d/'..s])
 end
end)
end
