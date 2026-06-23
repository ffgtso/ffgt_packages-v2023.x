local iwinfo = require 'iwinfo'
local uci = require('simple-uci').cursor()
local wireless = require 'gluon.wireless'
local pump = require 'gluon.pump'

local f = Form(translate('PUMP'))

local s = f:section(Section, nil, translate(
	'PUMP (Premium Ultra Mesh Plus) creates an encrypted infrastructure WLAN and ' ..
	'uses it as a batman-adv transport. Use AP mode on the central side of a ' ..
	'planned link and STA mode on the remote side. The SSID and passphrase are ' ..
	'derived from the site/domain configuration and cannot be changed here.'
))

local ssid = s:option(Value, '_ssid', translate('Name (SSID)'))
ssid.readonly = true
function ssid:cfgvalue()
	return pump.ssid()
end
function ssid:write()
	-- derived from gluon.core.domain; deliberately not stored through config mode
end

local key = s:option(Value, '_key', translate('Passphrase'))
key.readonly = true
function key:cfgvalue()
	return pump.key()
end
function key:write()
	-- derived from site.conf prefix6; deliberately not stored through config mode
end

local warnings = {}
if not pump.ssid_is_valid() then
	table.insert(warnings, translate('The generated PUMP SSID is longer than 32 characters. Shorten the domain code in gluon.core.domain.'))
end
if not pump.key_is_valid() then
	table.insert(warnings, translate('The generated PUMP passphrase is not a valid WPA key. prefix6 must be 8-63 printable ASCII characters.'))
end

if #warnings > 0 then
	f:section(Section, translate('Configuration warning'), table.concat(warnings, '\n'))
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

local channel_options = {}

local function channel_label(entry)
	local channel = tostring(entry.channel)
	local mhz = entry.mhz and tostring(entry.mhz) or nil

	if mhz then
		return translate('Channel') .. ' ' .. channel .. ' (' .. mhz .. ' MHz)'
	end

	return translate('Channel') .. ' ' .. channel
end

local function add_channel_values(option, radio_config)
	option:value('auto', translate('(automatic)'))

	local phy = wireless.find_phy(radio_config)
	if not phy then
		return
	end

	local seen = {}
	local freqlist = iwinfo.nl80211.freqlist(phy) or {}
	table.sort(freqlist, function(a, b)
		return (tonumber(a.channel) or 0) < (tonumber(b.channel) or 0)
	end)

	for _, entry in ipairs(freqlist) do
		local channel = tostring(entry.channel)
		if not seen[channel] then
			option:value(channel, channel_label(entry))
			seen[channel] = true
		end
	end
end

wireless.foreach_radio(uci, function(r)
	local radio_name = r['.name']
	local band = r.band or translate('unknown band')
	radio:value(radio_name, radio_name .. ' (' .. band .. ')')
end)
radio.default = uci:get('pump', 'settings', 'radio') or 'all'

wireless.foreach_radio(uci, function(r)
	local radio_name = r['.name']
	local band = r.band or translate('unknown band')
	local title = translate('Channel') .. ' - ' .. radio_name .. ' (' .. band .. ')'
	local channel = s:option(ListValue, radio_name .. '_channel', title)
	channel:depends(enabled, true)
	channel.default = uci:get('wireless', radio_name, 'channel') or 'auto'
	add_channel_values(channel, r)
	channel_options[radio_name] = channel
end)

local function selected_radio_matches(radio_name)
	local selected = radio.data or uci:get('pump', 'settings', 'radio') or 'all'
	return selected == 'all' or selected == radio_name
end

local function ensure_gluon_wireless()
	if not uci:get('gluon', 'wireless') then
		uci:section('gluon', 'wireless', 'wireless', {})
	end
end

local function write_channel(radio_name, option)
	if not enabled.data then
		return
	end

	if not selected_radio_matches(radio_name) then
		return
	end

	local data = option.data
	if data == nil or data == '' then
		return
	end

	ensure_gluon_wireless()
	uci:set('wireless', radio_name, 'channel', data)
	uci:set('gluon', 'wireless', 'preserve_channels', '1')
end

function f:write()
	if not uci:get('pump', 'settings') then
		uci:section('pump', 'settings', 'settings', {})
	end

	uci:set('pump', 'settings', 'enabled', enabled.data and pump.config_is_valid())
	uci:set('pump', 'settings', 'mode', mode.data == 'sta' and 'sta' or 'ap')
	uci:set('pump', 'settings', 'radio', radio.data or 'all')

	for radio_name, option in pairs(channel_options) do
		write_channel(radio_name, option)
	end

	uci:commit('pump')
	uci:commit('gluon')
	os.execute('/lib/gluon/upgrade/335-gluon-pump')
	uci:commit('network')
	uci:commit('wireless')
end

return f
