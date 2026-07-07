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

local function write_radio_options(radio_name, options, uplink_radio_name)
	if not enabled.data then
		return
	end

	if uplink_radio_name == radio_name then
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

local function table_to_string(value)
	if type(value) ~= 'table' then
		return tostring(value or '')
	end

	local parts = {}
	for _, v in pairs(value) do
		parts[#parts + 1] = tostring(v)
	end
	return table.concat(parts, ' ')
end

local function encryption_description(entry)
	local enc = entry.encryption
	if not enc or not enc.enabled then
		return translate('open')
	end

	if enc.description and enc.description ~= '' then
		return tostring(enc.description)
	end

	local auth = table_to_string(enc.auth_suites or enc.authentication):upper()
	if auth:match('SAE') and auth:match('PSK') then
		return 'WPA2/WPA3 PSK/SAE'
	elseif auth:match('SAE') then
		return 'WPA3 SAE'
	elseif tonumber(enc.wpa) and tonumber(enc.wpa) >= 2 then
		return 'WPA2 PSK'
	elseif tonumber(enc.wpa) and tonumber(enc.wpa) == 1 then
		return 'WPA PSK'
	end

	return translate('encrypted')
end

local function encryption_to_uci(entry)
	local enc = entry.encryption
	if not enc or not enc.enabled then
		return 'none'
	end

	local auth = table_to_string(enc.auth_suites or enc.authentication):upper()
	if auth:match('802%.1X') or auth:match('EAP') then
		return nil
	end

	if auth:match('SAE') and auth:match('PSK') then
		return 'sae-mixed'
	elseif auth:match('SAE') then
		return 'sae'
	elseif tonumber(enc.wpa) and tonumber(enc.wpa) >= 2 then
		return 'psk2'
	elseif tonumber(enc.wpa) and tonumber(enc.wpa) == 1 then
		return 'psk'
	end

	-- Most personal WLANs expose enough scan metadata to be detected above. If
	-- metadata is incomplete but the BSS is encrypted, use WPA2-PSK as the least
	-- surprising fallback for a home/office uplink.
	return 'psk2'
end

local scan_entries = {}
local scan_order = {}

local function scan_radio_networks(radio_name, radio_config)
	local phy = wireless.find_phy(radio_config)
	if not phy then
		return
	end

	local ok, scanlist = pcall(iwinfo.nl80211.scanlist, phy)
	if not ok or not scanlist then
		return
	end

	for _, entry in ipairs(scanlist) do
		local entry_ssid = pump.non_empty(entry.ssid)
		local bssid = pump.non_empty(entry.bssid)
		local uci_encryption = encryption_to_uci(entry)

		if entry_ssid and bssid and uci_encryption then
			local value = radio_name .. '|' .. bssid
			local channel = entry.channel and ('ch ' .. tostring(entry.channel)) or translate('channel unknown')
			local signal = entry.signal and (tostring(entry.signal) .. ' dBm') or translate('signal unknown')
			local label = string.format('%s: %s (%s, %s, %s, %s)', radio_name, entry_ssid, bssid, channel, signal, encryption_description(entry))

			scan_entries[value] = {
				radio = radio_name,
				ssid = entry_ssid,
				bssid = bssid,
				encryption = uci_encryption,
				label = label,
			}
			scan_order[#scan_order + 1] = value
		end
	end
end

for radio_name, radio_config in pairs(radio_configs) do
	scan_radio_networks(radio_name, radio_config)
end

table.sort(scan_order, function(a, b)
	local ea = scan_entries[a]
	local eb = scan_entries[b]
	if ea.radio == eb.radio then
		return ea.ssid < eb.ssid
	end
	return ea.radio < eb.radio
end)

local us = f:section(Section, translate('WiFi uplink'), translate(
	'Select one of the received WLANs as a WAN uplink. The selected radio is used ' ..
	'exclusively for this WAN replacement; all other wireless interfaces on that radio ' ..
	'are disabled while the WiFi uplink is active.'
))

local uplink_enabled = us:option(Flag, 'uplink_enabled', translate('Enabled'))
uplink_enabled.default = uci:get_bool('pump', 'settings', 'uplink_enabled') and pump.uplink_config_is_valid()

local uplink_network = us:option(ListValue, '_uplink_network', translate('Upstream network'))
uplink_network:depends(uplink_enabled, true)

local stored_uplink_radio = pump.non_empty(uci:get('pump', 'settings', 'uplink_radio'))
local stored_uplink_ssid = pump.non_empty(uci:get('pump', 'settings', 'uplink_ssid'))
local stored_uplink_bssid = pump.non_empty(uci:get('pump', 'settings', 'uplink_bssid'))
local stored_uplink_bssid_lock = pump.uplink_bssid_locked()
local stored_uplink_encryption = pump.normalize_encryption(uci:get('pump', 'settings', 'uplink_encryption'))

local function current_uplink_value()
	if stored_uplink_radio and stored_uplink_bssid then
		return stored_uplink_radio .. '|' .. stored_uplink_bssid
	end

	if stored_uplink_radio and stored_uplink_ssid then
		for _, value in ipairs(scan_order) do
			local entry = scan_entries[value]
			if entry.radio == stored_uplink_radio and entry.ssid == stored_uplink_ssid then
				return value
			end
		end
	end

	return nil
end

local stored_uplink_value = current_uplink_value()

if stored_uplink_value and not scan_entries[stored_uplink_value] and stored_uplink_ssid and stored_uplink_bssid then
	uplink_network:value(stored_uplink_value, string.format('%s: %s (%s, %s)', stored_uplink_radio, stored_uplink_ssid, stored_uplink_bssid, translate('configured; currently not seen')))
	scan_entries[stored_uplink_value] = {
		radio = stored_uplink_radio,
		ssid = stored_uplink_ssid,
		bssid = stored_uplink_bssid,
		encryption = stored_uplink_encryption,
		label = stored_uplink_ssid,
	}
end

if #scan_order == 0 and not stored_uplink_value then
	uplink_network:value('', translate('No supported networks found'))
else
	for _, value in ipairs(scan_order) do
		local entry = scan_entries[value]
		uplink_network:value(value, entry.label)
	end
end

uplink_network.default = stored_uplink_value or ''

local uplink_bssid = us:option(Value, 'uplink_bssid', translate('BSSID'))
uplink_bssid:depends(uplink_enabled, true)
uplink_bssid.default = stored_uplink_bssid or ''
uplink_bssid.optional = true
function uplink_bssid:cfgvalue()
	if stored_uplink_bssid then
		return stored_uplink_bssid
	end

	local selected = scan_entries[uplink_network.data or stored_uplink_value or '']
	return selected and selected.bssid or ''
end
uplink_bssid.description = translate('Pre-filled with the BSSID of the selected upstream network. You may change it manually.')

local uplink_bssid_lock = us:option(Flag, 'uplink_bssid_lock', translate('Use only this BSSID'))
uplink_bssid_lock:depends(uplink_enabled, true)
uplink_bssid_lock.default = stored_uplink_bssid_lock
uplink_bssid_lock.description = translate('When disabled, the uplink may associate with any AP that advertises the selected SSID.')

local uplink_key = us:option(Value, 'uplink_key', translate('Uplink passphrase'))
uplink_key:depends(uplink_enabled, true)
uplink_key.default = uci:get('pump', 'settings', 'uplink_key') or ''
uplink_key.optional = true
uplink_key.password = true
uplink_key.description = translate('Required for encrypted upstream networks; ignored for open networks.')

local uplink_info = us:option(Value, '_uplink_info', translate('Current uplink'))
uplink_info.readonly = true
function uplink_info:cfgvalue()
	if stored_uplink_radio and stored_uplink_ssid then
		local bssid = stored_uplink_bssid or translate('any BSSID')
		return string.format('%s / %s / %s / %s', stored_uplink_radio, stored_uplink_ssid, bssid, stored_uplink_encryption)
	end
	return translate('not configured')
end
function uplink_info:write()
	-- informational only
end

function f:write()
	if not uci:get('pump', 'settings') then
		uci:section('pump', 'settings', 'settings', {})
	end

	local old_uplink_enabled = uci:get_bool('pump', 'settings', 'uplink_enabled')
	local old_uplink_radio = pump.non_empty(uci:get('pump', 'settings', 'uplink_radio'))
	local old_uplink_ssid = pump.non_empty(uci:get('pump', 'settings', 'uplink_ssid'))
	local old_uplink_bssid = pump.non_empty(uci:get('pump', 'settings', 'uplink_bssid'))

	local new_pump_enabled = enabled.data and pump.config_is_valid()
	local new_mode = mode.data == 'sta' and 'sta' or 'ap'
	local new_radio = radio.data or 'all'

	uci:set('pump', 'settings', 'enabled', new_pump_enabled and '1' or '0')
	uci:set('pump', 'settings', 'mode', new_mode)
	uci:set('pump', 'settings', 'radio', new_radio)

	local selected_uplink_value = uplink_network.data or ''
	local selected_uplink = scan_entries[selected_uplink_value]
	local new_uplink_enabled = uplink_enabled.data and selected_uplink ~= nil and pump.non_empty(selected_uplink.ssid) ~= nil and pump.non_empty(selected_uplink.radio) ~= nil
	local new_uplink_bssid = nil

	uci:set('pump', 'settings', 'uplink_enabled', new_uplink_enabled and '1' or '0')
	uci:set('pump', 'settings', 'uplink_key', uplink_key.data or '')

	if new_uplink_enabled then
		local submitted_bssid = pump.non_empty(uplink_bssid.data)
		local network_changed = selected_uplink_value ~= (stored_uplink_value or '')

		-- Keep the BSSID field as a server-side prefill value. When the user
		-- changes the dropdown, the newly selected AP's BSSID wins on this save;
		-- on later saves the editable BSSID field wins. This avoids the old/new
		-- BSSID oscillation caused by comparing against the previously rendered
		-- form value.
		if network_changed then
			new_uplink_bssid = selected_uplink.bssid
		else
			new_uplink_bssid = submitted_bssid or selected_uplink.bssid
		end

		uci:set('pump', 'settings', 'uplink_radio', selected_uplink.radio)
		uci:set('pump', 'settings', 'uplink_ssid', selected_uplink.ssid)
		uci:set('pump', 'settings', 'uplink_bssid', new_uplink_bssid or '')
		uci:set('pump', 'settings', 'uplink_bssid_lock', uplink_bssid_lock.data and '1' or '0')
		uci:set('pump', 'settings', 'uplink_encryption', pump.normalize_encryption(selected_uplink.encryption))
	else
		uci:set('pump', 'settings', 'uplink_enabled', '0')
	end

	local uplink_radio_name = new_uplink_enabled and selected_uplink.radio or nil
	local should_restore_site_wireless = false

	if new_pump_enabled then
		for radio_name, options in pairs(radio_options) do
			write_radio_options(radio_name, options, uplink_radio_name)
		end
	end

	if not new_pump_enabled and not new_uplink_enabled then
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

	local uplink_changed = old_uplink_enabled ~= new_uplink_enabled
		or old_uplink_radio ~= (new_uplink_enabled and selected_uplink.radio or nil)
		or old_uplink_ssid ~= (new_uplink_enabled and selected_uplink.ssid or nil)
		or old_uplink_bssid ~= (new_uplink_enabled and new_uplink_bssid or nil)

	if uplink_changed or new_uplink_enabled then
		-- WiFi uplink is a Gluon uplink interface, not just a wireless VIF.
		-- First materialize gluon.iface_pumpwan, then rebuild /etc/config/network
		-- from /etc/config/gluon. The later direct upgrade call remains a fallback
		-- for builds without gluon-reconfigure and reapplies wireless details after
		-- Gluon regenerated the base configuration.
		os.execute('/lib/gluon/upgrade/335-gluon-pump')
		uci:commit('pump')
		uci:commit('gluon')
		uci:commit('network')
		uci:commit('wireless')
		os.execute('command -v gluon-reconfigure >/dev/null 2>&1 && gluon-reconfigure >/dev/null 2>&1')
	end

	os.execute('/lib/gluon/upgrade/335-gluon-pump')
	uci:commit('pump')
	uci:commit('network')
	uci:commit('gluon')
	uci:commit('wireless')

	if uplink_changed or new_uplink_enabled then
		-- Apply the newly created STA VIF for immediate testing; a normal reboot
		-- after leaving Config Mode would do the same.
		os.execute('/etc/init.d/network reload >/dev/null 2>&1')
		os.execute('wifi reload >/dev/null 2>&1')
	end
end

return f
