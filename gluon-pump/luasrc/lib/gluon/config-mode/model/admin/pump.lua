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

local radio_options = {}
local radio_configs = {}

local function channel_label(entry)
	local channel = tostring(entry.channel)
	local mhz = entry.mhz and tostring(entry.mhz) or nil

	if mhz then
		return translate('Channel') .. ' ' .. channel .. ' (' .. mhz .. ' MHz)'
	end

	return translate('Channel') .. ' ' .. channel
end

local function add_radio_depends(option, radio_name)
	-- Each depends() call is an alternative dependency set; the table form keeps
	-- the individual predicates for enabled + selected radio together.
	option:depends({ [enabled] = true, [radio] = 'all' })
	option:depends({ [enabled] = true, [radio] = radio_name })
end

local function add_ap_radio_depends(option, radio_name)
	option:depends({ [enabled] = true, [mode] = 'ap', [radio] = 'all' })
	option:depends({ [enabled] = true, [mode] = 'ap', [radio] = radio_name })
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

local function add_htmode_values(option, radio_config)
	option:value('auto', translate('(automatic / best available)'))

	local phy = wireless.find_phy(radio_config)
	if not phy then
		return
	end

	local htmodelist = iwinfo.nl80211.htmodelist(phy) or {}
	local preferred_order = {
		'HE160', 'HE80', 'HE40', 'HE20',
		'VHT160', 'VHT80', 'VHT40', 'VHT20',
		'HT40', 'HT20',
	}
	local seen = {}

	for _, htmode in ipairs(preferred_order) do
		if htmodelist[htmode] then
			option:value(htmode, htmode)
			seen[htmode] = true
		end
	end

	for htmode, available in pairs(htmodelist) do
		if available and not seen[htmode] then
			option:value(htmode, htmode)
		end
	end
end

local function best_htmode(radio_config)
	local phy = wireless.find_phy(radio_config)
	if not phy then
		return nil
	end

	local htmodelist = iwinfo.nl80211.htmodelist(phy) or {}
	local preferred_order = {
		'HE160', 'HE80', 'HE40', 'HE20',
		'VHT160', 'VHT80', 'VHT40', 'VHT20',
		'HT40', 'HT20',
	}

	for _, htmode in ipairs(preferred_order) do
		if htmodelist[htmode] then
			return htmode
		end
	end

	return nil
end

wireless.foreach_radio(uci, function(r)
	local radio_name = r['.name']
	local band = r.band or translate('unknown band')
	radio:value(radio_name, radio_name .. ' (' .. band .. ')')
	radio_configs[radio_name] = r
end)
radio.default = uci:get('pump', 'settings', 'radio') or 'all'

wireless.foreach_radio(uci, function(r)
	local radio_name = r['.name']
	local band = r.band or translate('unknown band')
	radio_options[radio_name] = {}

	local channel = s:option(ListValue, radio_name .. '_channel', translate('Channel') .. ' - ' .. radio_name .. ' (' .. band .. ')')
	add_ap_radio_depends(channel, radio_name)
	channel.default = uci:get('pump', 'settings', radio_name .. '_channel') or uci:get('wireless', radio_name, 'channel') or 'auto'
	add_channel_values(channel, r)
	radio_options[radio_name].channel = channel

	local htmode = s:option(ListValue, radio_name .. '_htmode', translate('HT mode') .. ' - ' .. radio_name .. ' (' .. band .. ')')
	add_radio_depends(htmode, radio_name)
	htmode.default = uci:get('pump', 'settings', radio_name .. '_htmode') or uci:get('wireless', radio_name, 'htmode') or 'auto'
	add_htmode_values(htmode, r)
	radio_options[radio_name].htmode = htmode
end)

local function selected_radio_matches(radio_name)
	local selected = radio.data or uci:get('pump', 'settings', 'radio') or 'all'
	return pump.radio_selected(selected, radio_name)
end

local function ensure_gluon_wireless()
	if not uci:get('gluon', 'wireless') then
		uci:section('gluon', 'wireless', 'wireless', {})
	end
end

local own_preserve_channels = uci:get_bool('pump', 'settings', 'preserve_channels')

local function ensure_preserve_channels()
	ensure_gluon_wireless()
	if not uci:get_bool('gluon', 'wireless', 'preserve_channels') then
		own_preserve_channels = true
	end
	uci:set('gluon', 'wireless', 'preserve_channels', '1')
	uci:set('pump', 'settings', 'preserve_channels', own_preserve_channels and '1' or '0')
end

local function restore_site_wireless_if_owned()
	if own_preserve_channels then
		uci:delete('gluon', 'wireless', 'preserve_channels')
		uci:set('pump', 'settings', 'preserve_channels', '0')
		own_preserve_channels = false
		return true
	end

	return false
end

local function write_radio_options(radio_name, options)
	if not enabled.data then
		return
	end

	if not selected_radio_matches(radio_name) then
		return
	end

	local selected_mode = mode.data == 'sta' and 'sta' or 'ap'
	local channel_data = options.channel and options.channel.data or nil
	local htmode_data = options.htmode and options.htmode.data or nil

	ensure_preserve_channels()

	if selected_mode == 'sta' then
		-- In station mode, the AP shall determine the channel. Setting channel=auto
		-- makes the STA scan and associate to any matching PUMP AP.
		uci:set('wireless', radio_name, 'channel', 'auto')
		uci:delete('pump', 'settings', radio_name .. '_channel')
	else
		if channel_data == nil or channel_data == '' then
			channel_data = uci:get('wireless', radio_name, 'channel') or 'auto'
		end
		uci:set('wireless', radio_name, 'channel', channel_data)
		uci:set('pump', 'settings', radio_name .. '_channel', channel_data)
	end

	if htmode_data == nil or htmode_data == '' or htmode_data == 'auto' then
		htmode_data = best_htmode(radio_configs[radio_name]) or uci:get('wireless', radio_name, 'htmode') or 'HT20'
		uci:set('pump', 'settings', radio_name .. '_htmode', 'auto')
	else
		uci:set('pump', 'settings', radio_name .. '_htmode', htmode_data)
	end

	uci:set('wireless', radio_name, 'htmode', htmode_data)
end

function f:write()
	if not uci:get('pump', 'settings') then
		uci:section('pump', 'settings', 'settings', {})
	end

	local new_enabled = enabled.data and pump.config_is_valid()
	local new_mode = mode.data == 'sta' and 'sta' or 'ap'
	local new_radio = radio.data or 'all'

	uci:set('pump', 'settings', 'enabled', new_enabled and '1' or '0')
	uci:set('pump', 'settings', 'mode', new_mode)
	uci:set('pump', 'settings', 'radio', new_radio)

	local should_restore_site_wireless = false
	if new_enabled then
		for radio_name, options in pairs(radio_options) do
			write_radio_options(radio_name, options)
		end
	else
		should_restore_site_wireless = restore_site_wireless_if_owned()
	end

	uci:commit('pump')
	uci:commit('gluon')
	uci:commit('wireless')

	if should_restore_site_wireless then
		os.execute('/lib/gluon/upgrade/200-wireless')
		uci:commit('network')
		uci:commit('wireless')
	end

	os.execute('/lib/gluon/upgrade/335-gluon-pump')
	uci:commit('network')
	uci:commit('wireless')
end

return f
