return function(test, core, r, uci)
local util,json=package.loaded['gluon.util'],package.loaded.jsonc
local function v4()return {up=true,['ipv4-address']={{address='192.168.8.42'}},route={{target='0.0.0.0',mask=0}},['dns-server']={'192.168.8.1'}}end
local function isolated(fn)
 local old={command=r.command,parse=json.parse,get=uci.get,get_bool=uci.get_bool,open=io.open,readfile=util.readfile}
 local ok,err=pcall(fn)
 r.command=old.command;json.parse=old.parse;uci.get=old.get;uci.get_bool=old.get_bool;io.open=old.open;util.readfile=old.readfile
 assert(ok,err)
end
test('PUMP: IPv4 readiness requires usable address default route and DNS',function()
 assert(core.ipv4_ready(v4()))
 for _,k in ipairs({'ipv4-address','route','dns-server'})do local s=v4();s[k]={};assert(not core.ipv4_ready(s))end
 for _,a in ipairs({'169.254.1.1','127.0.0.1','0.0.0.0','999.1.1.1','224.1.1.1'})do local s=v4();s['ipv4-address'][1].address=a;assert(not core.ipv4_ready(s))end
end)
test('PUMP: IPv4-only fallback works without IPv6',function()isolated(function()
 json.parse=function(t)return t=='v4' and v4() or {up=false}end
 r.command=function(a)return 0,a[3]=='network.interface.offline_wifi4' and 'v4' or 'down'end
 local f=r.ready();assert(f[4] and not f[6])
end)end)
test('PUMP: IPv4 prefers offline4 otherwise uses configured branch without timeout',function()isolated(function()
 local branch='offline4';uci.get=function(_,c,n)return n==branch and 'branch' or nil end
 r.command=function(a,t)assert(a[4]==branch and t==nil);return 0 end
 assert(r.update('stable',{[4]=true})==0);branch='stable'
 assert(r.update('stable',{[4]=true})==0 and r.update('stable',{[6]=true})==0)
end)end)
test('PUMP: both protocols require external registration before up',function()isolated(function()
 local reg,up={},{}
 r.command=function(a)
  if a[4]=='link' then return 0,'Connected to 00:11:22:33:44:55'end
  if a[4]=='add_device'then reg[a[3]]=true;assert(a[5]=='{"name":"offlinewifi","link-ext":true}')end
  if a[4]=='up'then assert(reg[a[3]]);up[a[3]]=true end
  return 0,''
 end
 assert(r.connect({phy='phy0',ssid='Freifunk',bssid='00:11:22:33:44:55'}))
 assert(up['network.interface.offline_wifi4'] and up['network.interface.offline_wifi6'])
end)end)
test('PUMP: route requires enabled uplink live device and matching netifd state',function()isolated(function()
 local enabled,six,dev=true,true,'pumpwan'
 uci.get_bool=function()return enabled end;uci.get=function()return dev end
 util.readfile=function(p)
  if p=='/sys/class/net/pumpwan/ifindex'then return '42'end
  if p=='/proc/net/route'then return 'pumpwan 00000000 0100000A 0003 0 0 10 00000000 0 0 0\n'end
  if p=='/proc/net/ipv6_route'then return string.rep('0',32)..' 00 '..string.rep('0',32)..' 00 fe800000000000000000000000000001 00000400 0 0 00000003 pumpwan\n'end
 end
 json.parse=function(s)return {up=s=='four' or six,l3_device='pumpwan'}end
 r.command=function(a)return 0,a[3]=='network.interface.pump_wan' and 'four' or 'six'end
 local f=r.pump_routes();assert(f[4] and f[6]);six=false;f=r.pump_routes();assert(f[4] and not f[6])
 dev='br-wan';assert(not next(r.pump_routes()))
 dev='pumpwan';json.parse=function()return 7 end;assert(not next(r.pump_routes()));enabled=false
 r.command=function()error('disabled uplink must not query netifd')end;assert(not next(r.pump_routes()))
end)end)
test('PUMP: existing uplink uses default branch if offline branches are absent',function()
 local calls={};local o={pump_routes=function()return {[4]=true,[6]=true}end,wan_routes=function()error('wrong device')end,
 branch_exists=function(b)return b=='stable'end,default_branch=function()return 'stable'end,log=function()end,
 cancelled=function()return false end,upgrading=function()return false end,has_gateways=function()return false end,
 update_wan=function(b)calls[#calls+1]=b;return 0 end}
 assert(core.wan_round(o,true) and #calls==2 and calls[1]=='stable')
 o.has_gateways=function()return true end;assert(core.wan_round(o,true) and #calls==2)
 o.has_gateways=function()return nil end;assert(not core.wan_round(o,true) and #calls==2)
end)
for _,fail in ipairs({false,true})do
test('PUMP: actual runtime cleanup with update exception '..tostring(fail),function()isolated(function()
 local calls,up,saved={}, {}, {}
 local writes={'set','set_list','delete','delete_all','section','save','commit','revert'}
 for _,k in ipairs(writes)do saved[k]=uci[k];uci[k]=function()error('must preserve PUMP UCI')end end
 local open=io.open;io.open=function(p,m)if p=='/sys/class/net/offlinewifi/ifindex'then return {close=function()end}end;return open(p,m)end
 json.parse=function(t)return t=='ready' and {up=true,['ipv6-address']={{address='2001:db8::1'}},route={{target='::',mask=0}},['dns-server']={'2001:db8::53'}} or {up=false,pending=false}end
 r.command=function(a)
  calls[#calls+1]=table.concat(a,' ')
  if a[1]=='batctl'then return 0,''end
  if a[1]=='iw' and a[4]=='link'then return 0,'Connected to 00:11:22:33:44:55'end
  if a[1]=='iw'then return 0,'phy#0'end
  if a[1]=='ifdown'then up['network.interface.'..a[2]]=false end
  if a[1]=='ubus' and a[4]=='up'then up[a[3]]=true end
  if a[1]=='ubus' and a[4]=='status'then return 0,up[a[3]] and 'ready' or 'down'end
  if a[1]=='/usr/sbin/autoupdater' and fail then error('test updater error')end
  return 0,''
 end
 local ok,result=pcall(core.round,r,{{phy='phy0',ssid='Freifunk',bssid='00:11:22:33:44:55'}},'stable')
 for _,k in ipairs(writes)do uci[k]=saved[k]end
 assert(ok and result==not fail);assert(calls[1]=='wifi down' and calls[#calls]=='wifi up')
 local c=table.concat(calls,'\n');assert(c:find('ifdown offline_wifi4',1,true) and c:find('ifdown offline_wifi6',1,true) and c:find('iw dev offlinewifi del',1,true))
end)end)
end
test('PUMP: gateway returning after association prevents autoupdater',function()
 local updates=0;local o={upgrading=function()return false end,cancelled=function()return false end,
 down=function()return true end,stop=function()return true end,up=function()return true end,connect=function()return true end,
 ready=function()return true end,has_gateways=function()return true end,update=function()updates=updates+1 end,log=function()end}
 assert(core.round(o,{{phy='phy0',bssid='00:11:22:33:44:55',ssid='Freifunk'}},'stable') and updates==0)
end)
for _,case in ipairs({{pump='0',old='1',want=false},{pump='1',old='0',want=true},{pump='1',old='1',current=false,want=false}})do
test('PUMP: activation migration '..tostring(case.want)..'/'..tostring(case.current),function()
 local data={['pump-autoupdater-wifi-fallback/settings/enabled']=case.pump,['autoupdater-wifi-fallback/settings/enabled']=case.old,['4830-offline-manager/settings/autoupdate_enabled']=case.current}
 local removed,fake={},{}
 fake.get=function(_,c,s,o)return data[c..'/'..s..(o and '/'..o or '')]end
 fake.get_bool=function(self,c,s,o)return self:get(c,s,o)=='1'end
 fake.set=function(_,c,s,o,v)data[c..'/'..s..'/'..o]=v end;fake.section=function(_,c,t,s,v)data[c..'/'..s]=v end
 fake.delete=function(_,c,s)assert(c~='pump' and s~='pump_wan' and s~='pump_wan6' and s~='pump_uplink')end
 fake.save=function(_,c)assert(c~='pump' and c~='tunneldigger')end
 local old=package.loaded['simple-uci'];package.loaded['simple-uci']={cursor=function()return fake end}
 local remove=os.remove;os.remove=function(p)removed[p]=true;return true end
 local ok,err=pcall(dofile,'luasrc/lib/gluon/upgrade/510-4830-offline-manager')
 package.loaded['simple-uci']=old;os.remove=remove;assert(ok,err)
 assert(data['4830-offline-manager/settings/autoupdate_enabled']==case.want)
 assert(removed['/usr/lib/micron.d/pump-autoupdater-wifi-fallback'])
 assert(data['network/offline_wifi4'].proto=='dhcp' and data['firewall/offline_manager_dhcp4'].dest_port=='68')
end)
end
end
