local uci = require('simple-uci').cursor()
local wireless = require 'gluon.wireless'
local pump = require 'gluon.pump'

local f = Form(translate('PUMP'))

local s = f:section(Section, nil, translate(
	'PUMP (Premium Ultra Mesh Plus) creates an encrypted infrastructure WLAN and ' ..
	'uses it as a batman-adv transport. Use AP mode on the central side of a ' ..
	'planned link and STA mode on the remote side. The SSID and passphrase are ' ..
	'derived from the site configuration and cannot be changed here.'
))

local ssid = s:option(DummyValue, '_ssid', translate('Name (SSID)'))
function ssid:cfgvalue()
	return pump.ssid()
end

local key = s:option(DummyValue, '_key', translate('Passphrase'))
function key:cfgvalue()
	return pump.key()
end

local warnings = {}
if not pump.ssid_is_valid() then
	table.insert(warnings, translate('The generated PUMP SSID is longer than 32 characters. Shorten the domain_names value in the site configuration.'))
end
if not pump.key_is_valid() then
	table.insert(warnings, translate('The generated PUMP passphrase is not a valid WPA key. prefix6 must be 8-63 printable ASCII characters.'))
end

if #warnings > 0 then
	s:element('model/warning', {
		content = table.concat(warnings, '\n'),
		hide = false,
	}, 'warning')
end

local enabled = s:option(Flag, 'enabled', translate('Enabled'))
enabled.default = uci:get_bool('pump', 'settings', 'enabled') and pump.config_is_valid()

local mode = s:option(ListValue, 'mode', translate('Mode'))
mode:depends(enabled, true)
mode:value('ap', translate('Access point (AP)'))
mode:value('sta', translate('Station (STA)'))
mode.default = uci:get('pump', 'settings', 'mode') or 'ap'

local radio = s:option(ListValue, 'radio', translate('Radio'))
radio:depends(enabled, true)
radio:value('all', translate('All radios'))
wireless.foreach_radio(uci, function(r)
	local radio_name = r['.name']
	local band = r.band or translate('unknown band')
	radio:value(radio_name, radio_name .. ' (' .. band .. ')')
end)
radio.default = uci:get('pump', 'settings', 'radio') or 'all'

function f:write()
	if not uci:get('pump', 'settings') then
		uci:section('pump', 'settings', 'settings', {})
	end

	uci:set('pump', 'settings', 'enabled', enabled.data and pump.config_is_valid())
	uci:set('pump', 'settings', 'mode', mode.data == 'sta' and 'sta' or 'ap')
	uci:set('pump', 'settings', 'radio', radio.data or 'all')

	uci:commit('pump')
	os.execute('/lib/gluon/upgrade/335-gluon-pump')
	uci:commit('network')
	uci:commit('wireless')
end

return f
