local iwinfo = require 'iwinfo'
local wireless = require 'gluon.wireless'
local pump = require 'gluon.pump'

local M = {}

local preferred_htmodes = {
	'HE160', 'HE80', 'HE40', 'HE20',
	'VHT160', 'VHT80', 'VHT40', 'VHT20',
	'HT40', 'HT20',
}

local valid_encryptions = {
	none = true,
	psk = true,
	psk2 = true,
	sae = true,
	['sae-mixed'] = true,
}

local commit_configs = {
	'pump', 'gluon', 'network', 'wireless', 'firewall', 'tunneldigger',
}

local function bool(value)
	return value == true or value == 1 or value == '1' or value == 'true' or value == 'yes' or value == 'on'
end

local function shell_ok(command)
	local status = os.execute(command)
	return status == true or status == 0
end

local function get_cursor(options)
	if options and options.uci then
		return options.uci
	end
	return require('simple-uci').cursor()
end

local function ensure_settings(uci)
	if uci:get('pump', 'settings') then
		return
	end

	uci:section('pump', 'settings', 'settings', {
		enabled = false,
		mode = 'ap',
		radio = 'all',
		mesh_no_rebroadcast = false,
		preserve_channels = false,
		uplink_enabled = false,
		uplink_bssid_lock = true,
		uplink_encryption = 'auto',
		uplink_htmode = 'auto',
		uplink_powersave = false,
		firewall_wan_zone = false,
	})
end

local function radio_map(uci)
	local radios = {}
	wireless.foreach_radio(uci, function(radio, index)
		local name = radio['.name']
		if name then
			radios[name] = {
				config = radio,
				index = index,
				phy = wireless.find_phy(radio),
			}
		end
	end)
	return radios
end

local function supported_channels(radio)
	local channels = {auto = true}
	if not radio.phy then
		return channels
	end

	for _, entry in ipairs(iwinfo.nl80211.freqlist(radio.phy) or {}) do
		channels[tostring(entry.channel)] = true
	end
	return channels
end

local function supported_htmodes(radio)
	local modes = {auto = true}
	if not radio.phy then
		return modes
	end

	for mode, available in pairs(iwinfo.nl80211.htmodelist(radio.phy) or {}) do
		if available then
			modes[mode] = true
		end
	end
	return modes
end

local function validate_radio_setting(radios, radio_name, key, value)
	local radio = radios[radio_name]
	if not radio then
		return nil, 'unknown radio: ' .. tostring(radio_name)
	end

	value = tostring(value or '')
	if key == 'channel' then
		if not supported_channels(radio)[value] then
			return nil, string.format('channel %s is not supported by %s', value, radio_name)
		end
	elseif key == 'htmode' then
		if not supported_htmodes(radio)[value] then
			return nil, string.format('HT mode %s is not supported by %s', value, radio_name)
		end
	else
		return nil, 'unknown radio setting: ' .. tostring(key)
	end

	return true
end

local function final_value(uci, changes, key, default)
	if changes[key] ~= nil then
		return changes[key]
	end
	local value = uci:get('pump', 'settings', key)
	if value == nil then
		return default
	end
	return value
end

local function validate(uci, changes)
	local radios = radio_map(uci)
	local enabled = bool(final_value(uci, changes, 'enabled', false))
	local mode = tostring(final_value(uci, changes, 'mode', 'ap'))
	local selected_radio = tostring(final_value(uci, changes, 'radio', 'all'))

	if mode ~= 'ap' and mode ~= 'sta' then
		return nil, 'mode must be ap or sta'
	end
	if enabled and selected_radio ~= 'all' and not radios[selected_radio] then
		return nil, 'unknown PUMP radio: ' .. selected_radio
	end
	if enabled and not pump.config_is_valid() then
		return nil, 'derived PUMP SSID or passphrase is invalid; check gluon.core.domain and site prefix6'
	end

	for key, value in pairs(changes) do
		local radio_name, setting = key:match('^(radio%d+)_(channel)$')
		if not radio_name then
			radio_name, setting = key:match('^(radio%d+)_(htmode)$')
		end
		if radio_name then
			local ok, err = validate_radio_setting(radios, radio_name, setting, value)
			if not ok then
				return nil, err
			end
		end
	end

	if enabled then
		for radio_name, _ in pairs(radios) do
			if pump.radio_selected(selected_radio, radio_name) then
				local htmode = final_value(uci, changes, radio_name .. '_htmode', 'auto')
				local ok, err = validate_radio_setting(radios, radio_name, 'htmode', htmode)
				if not ok then return nil, err end
				if mode == 'ap' then
					local channel = final_value(uci, changes, radio_name .. '_channel',
						radios[radio_name].config.channel or 'auto')
					ok, err = validate_radio_setting(radios, radio_name, 'channel', channel)
					if not ok then return nil, err end
				end
			end
		end
	end

	local uplink_enabled = bool(final_value(uci, changes, 'uplink_enabled', false))
	if uplink_enabled then
		local uplink_radio = pump.non_empty(final_value(uci, changes, 'uplink_radio'))
		local ssid = pump.non_empty(final_value(uci, changes, 'uplink_ssid'))
		local encryption = pump.normalize_encryption(final_value(uci, changes, 'uplink_encryption', 'psk2'))
		local key = final_value(uci, changes, 'uplink_key', '')
		local lock = bool(final_value(uci, changes, 'uplink_bssid_lock', true))
		local bssid = final_value(uci, changes, 'uplink_bssid', '')
		local htmode = tostring(final_value(uci, changes, 'uplink_htmode', 'auto'))

		if not uplink_radio or not radios[uplink_radio] then
			return nil, 'a valid WiFi uplink radio is required'
		end
		if not ssid or #ssid > 32 then
			return nil, 'WiFi uplink SSID must contain 1-32 bytes'
		end
		if not valid_encryptions[encryption] then
			return nil, 'unsupported WiFi uplink encryption: ' .. tostring(encryption)
		end
		if pump.encryption_uses_key(encryption) and not pump.wpa_key_is_valid(key) then
			return nil, 'WiFi uplink passphrase must contain 8-63 printable ASCII characters'
		end
		if lock and not pump.uplink_bssid_is_valid(bssid) then
			return nil, 'a valid BSSID is required while BSSID locking is enabled'
		end
		local ok, err = validate_radio_setting(radios, uplink_radio, 'htmode', htmode)
		if not ok then
			return nil, err
		end
	end

	return true
end

local function commit_materialized()
	for _, config in ipairs(commit_configs) do
		shell_ok('uci -q commit ' .. config .. ' >/dev/null 2>&1')
	end
end

function M.configure(changes, options)
	changes = changes or {}
	local uci = get_cursor(options)
	ensure_settings(uci)

	local ok, err = validate(uci, changes)
	if not ok then
		return nil, err
	end

	for key, value in pairs(changes) do
		if value == M.DELETE then
			uci:delete('pump', 'settings', key)
		elseif type(value) == 'boolean' then
			uci:set('pump', 'settings', key, value and '1' or '0')
		else
			uci:set('pump', 'settings', key, tostring(value))
		end
	end

	uci:commit('pump')

	if not shell_ok('/lib/gluon/upgrade/335-gluon-pump') then
		return nil, '335-gluon-pump failed; PUMP settings were saved but derived UCI state was not committed'
	end
	commit_materialized()

	if options and options.runtime then
		return M.runtime_apply()
	end

	return true
end

M.DELETE = {}

function M.validate(options)
	local uci = get_cursor(options)
	ensure_settings(uci)
	return validate(uci, {})
end

function M.radios(options)
	local uci = get_cursor(options)
	local result = {}
	for name, entry in pairs(radio_map(uci)) do
		local config = entry.config
		result[#result + 1] = {
			name = name,
			phy = entry.phy,
			band = config.band,
			channel = config.channel,
			htmode = config.htmode,
		}
	end
	table.sort(result, function(a, b) return a.name < b.name end)
	return result
end

local function table_to_string(value)
	if type(value) ~= 'table' then
		return tostring(value or '')
	end
	local parts = {}
	for _, item in pairs(value) do
		parts[#parts + 1] = tostring(item)
	end
	return table.concat(parts, ' ')
end

local function scan_encryption(entry)
	local enc = entry.encryption
	if not enc or not enc.enabled then
		return 'none', 'open'
	end

	local auth = table_to_string(enc.auth_suites or enc.authentication):upper()
	if auth:match('802%.1X') or auth:match('EAP') then
		return nil
	elseif auth:match('SAE') and auth:match('PSK') then
		return 'sae-mixed', 'WPA2/WPA3 PSK/SAE'
	elseif auth:match('SAE') then
		return 'sae', 'WPA3 SAE'
	elseif tonumber(enc.wpa) and tonumber(enc.wpa) >= 2 then
		return 'psk2', 'WPA2 PSK'
	elseif tonumber(enc.wpa) and tonumber(enc.wpa) == 1 then
		return 'psk', 'WPA PSK'
	end
	return 'psk2', enc.description or 'encrypted'
end

function M.scan(options)
	local uci = get_cursor(options)
	local only_radio = options and options.radio or nil
	local result = {}

	for name, radio in pairs(radio_map(uci)) do
		if not only_radio or only_radio == name then
			local ok, entries = pcall(iwinfo.nl80211.scanlist, radio.phy)
			if ok and entries then
				for _, entry in ipairs(entries) do
					local ssid = pump.non_empty(entry.ssid)
					local bssid = pump.non_empty(entry.bssid)
					local encryption, description = scan_encryption(entry)
					if ssid and bssid and encryption then
						result[#result + 1] = {
							radio = name,
							ssid = ssid,
							bssid = bssid,
							encryption = encryption,
							description = description,
							channel = entry.channel,
							signal = entry.signal,
						}
					end
				end
			end
		end
	end

	table.sort(result, function(a, b)
		if a.radio ~= b.radio then return a.radio < b.radio end
		if a.ssid ~= b.ssid then return a.ssid < b.ssid end
		return a.bssid < b.bssid
	end)
	return result
end

function M.status(options)
	local uci = get_cursor(options)
	ensure_settings(uci)
	local settings = uci:get_all('pump', 'settings') or {}
	local valid, validation_error = validate(uci, {})
	return {
		settings = settings,
		ssid = pump.ssid(),
		key_valid = pump.key_is_valid(),
		config_valid = valid and true or false,
		validation_error = validation_error,
	}
end

function M.runtime_apply()
	io.stderr:write('Applying PUMP runtime state; wireless connectivity may be interrupted.\n')
	io.stderr:flush()

	local commands = {
		'/etc/init.d/network reload',
		'/etc/init.d/firewall reload',
		'wifi reload',
	}
	for _, command in ipairs(commands) do
		if not shell_ok(command) then
			return nil, 'runtime command failed: ' .. command
		end
	end

	shell_ok('/lib/gluon/wan-dnsmasq/update.lua >/dev/null 2>&1')
	if bool(require('simple-uci').cursor():get('pump', 'settings', 'uplink_enabled')) then
		shell_ok('/usr/lib/gluon/pump/tunneldigger-bind restart >/dev/null 2>&1')
	elseif shell_ok('[ -x /etc/init.d/tunneldigger ]') then
		shell_ok('/etc/init.d/tunneldigger restart >/dev/null 2>&1')
	end

	return true
end

function M.preferred_htmodes()
	return preferred_htmodes
end

return M
