return function(test, runtime, uci)
local ssid = require 'offline-manager.ssid'
local util = package.loaded['gluon.util']
local expected_reload = 'killall -HUP hostapd'
local function with_hostapd(fn)
 local paths = {'/var/run/hostapd-phy0.conf', '/var/run/hostapd-phy1.0.conf'}
 local text = 'driver=nl80211\ninterface=client0\nssid=Open\nconfig_id=open-hash\n' ..
  'bss=owe0\nssid=Secure\nconfig_id=owe-hash\nwpa_key_mgmt=OWE\nignore_broadcast_ssid=0\n' ..
  'bss=private0\nssid=Private\nconfig_id=private-hash\nwpa_passphrase=secret\n'
 local files = {[paths[1]]=text, [paths[2]]=text:gsub('client0','client1'):gsub('owe0','owe1'):gsub('private0','private1'),
  ['/proc/sys/kernel/hostname']='router\n'}
 local pending='/tmp/4830-offline-manager.ssid-reload'
 local calls, fail = {}, false
 local saved={readfile=util.readfile,glob=util.glob,foreach=uci.foreach,open=io.open,rename=os.rename,remove=os.remove,command=runtime.command}
 util.readfile=function(p) return files[p] end
 util.glob=function(p) assert(p=='/var/run/hostapd-phy*.conf');return paths end
 uci.foreach=function(_,config,kind,cb)
  assert(config=='wireless' and kind=='wifi-iface')
  for i=0,1 do
   cb({['.name']='client_radio'..i,ifname='client'..i,ssid='Open'})
   cb({['.name']='owe_radio'..i,ifname='owe'..i,ssid='Secure'})
   cb({['.name']='wan_radio'..i,ifname='private'..i,ssid='Private'})
  end
 end
 io.open=function(p,mode)
  assert(mode=='w');files[p]=''
  return {write=function(self,s)files[p]=files[p]..s;return self end,close=function()return true end}
 end
 os.rename=function(a,b)assert(files[a]);files[b]=files[a];files[a]=nil;return true end
 os.remove=function(p)files[p]=nil;return true end
 runtime.command=function(argv,timeout)
  if argv[1]=='cp' then assert(argv[2]=='-p');files[argv[4]]=assert(files[argv[3]]);return 0 end
  assert(table.concat(argv,' ') == expected_reload)
  -- Every radio must be written before requesting the reload.
  assert(files[paths[1]]:find('ssid2=',1,true) and files[paths[2]]:find('ssid2=',1,true))
  calls[#calls+1]=argv
  return fail and 1 or 0
 end
 local ok,err=pcall(fn,files,paths,pending,calls,function(v)fail=v end,text)
 util.readfile=saved.readfile;util.glob=saved.glob;uci.foreach=saved.foreach
 io.open=saved.open;os.rename=saved.rename;os.remove=saved.remove;runtime.command=saved.command
 assert(ok,err)
end

test('Compatibility: independent Open and OWE SSIDs reload after all radio writes',function()
 with_hostapd(function(files,paths,pending,calls)
  runtime.ssid(false)
  for _,p in ipairs(paths) do
   assert(files[p]:find('ssid2=46465f4f46464c494e455f726f75746572',1,true))
   assert(files[p]:find('ssid2=46465f4f46465f4f57455f726f75746572',1,true))
   assert(files[p]:find('wpa_key_mgmt=OWE\nignore_broadcast_ssid=0',1,true))
   assert(files[p]:find('ssid=Private\nconfig_id=private-hash\nwpa_passphrase=secret',1,true))
   assert(not files[p]:find('owe_transition',1,true))
  end
  assert(#calls==1 and files[pending]==nil)
  runtime.ssid(false);assert(#calls==1)
  runtime.ssid(true);assert(#calls==2)
  for _,p in ipairs(paths) do
   assert(files[p]:find('ssid2=4f70656e',1,true) and files[p]:find('ssid2=536563757265',1,true))
  end
 end)
end)
test('Compatibility: failed hostapd reload is retried during TQ hysteresis',function()
 with_hostapd(function(files,paths,pending,calls,set_fail)
  set_fail(true);runtime.ssid(false);assert(#calls==1 and files[pending]~=nil)
  local offline=files[paths[1]]
  set_fail(false);runtime.ssid(nil);assert(#calls==2 and files[pending]==nil)
  assert(files[paths[1]]==offline)
  runtime.ssid(nil);assert(#calls==2)
 end)
end)
test('Compatibility: hysteresis alone leaves hostapd and private BSS unchanged',function()
 with_hostapd(function(files,paths,pending,calls,_,original)
  runtime.ssid(nil);assert(#calls==0 and files[pending]==nil and files[paths[1]]==original)
 end)
end)
test('Compatibility: SSID change invalidates its BSS config ID only',function()
 local original='interface=client0\nssid=Open\nconfig_id=original\nbss=private0\nssid=Private\nconfig_id=private\n'
 local offline=ssid.rewrite(original,{client0={ssid='Offline'}})
 assert(offline:find('config_id=offline-manager-4f66666c696e65',1,true))
 assert(offline:find('bss=private0\nssid=Private\nconfig_id=private',1,true))
 assert(ssid.rewrite(offline,{client0={ssid='Offline'}})==offline)
 local online=ssid.rewrite(offline,{client0={ssid='Open'}})
 assert(online:find('config_id=offline-manager-4f70656e',1,true))
end)
end
