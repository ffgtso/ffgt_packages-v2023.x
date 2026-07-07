local site = require 'gluon.site'
local uci = require('simple-uci').cursor()

local M = {}

local function non_empty(value)
	if value == nil then
		return nil
	end

	value = tostring(value)
	if value == '' then
		return nil
	end

	return value
end

function M.non_empty(value)
	return non_empty(value)
end

function M.domain_code()
	return non_empty(uci:get('gluon', 'core', 'domain')) or 'nix'
end

function M.ssid()
	return 'PUMP-' .. M.domain_code()
end

function M.key()
	return tostring(site.prefix6(''))
end

function M.ssid_is_valid()
	local ssid = M.ssid()
	return ssid ~= nil and #ssid >= 1 and #ssid <= 32
end

function M.wpa_key_is_valid(key)
	key = non_empty(key)
	return key ~= nil and #key >= 8 and #key <= 63 and key:match('^[ -~]+$') ~= nil
end

function M.key_is_valid()
	return M.wpa_key_is_valid(M.key())
end

function M.config_is_valid()
	return M.ssid_is_valid() and M.key_is_valid()
end

function M.iface_name(radio_name)
	return 'pump_' .. radio_name
end

function M.ifname(radio_name)
	local suffix = radio_name:match('^radio(%d+)$')
	return suffix and ('pump' .. suffix) or nil
end

function M.uplink_iface_name()
	return 'pump_uplink'
end

function M.uplink_ifname()
	return 'pumpwan'
end

function M.uplink_gluon_iface_section()
	return 'iface_' .. M.uplink_ifname():gsub('[^%w_]', '_')
end

function M.uplink_network_name()
	return 'pump_wan'
end

function M.uplink_network6_name()
	return 'pump_wan6'
end

function M.radio_selected(selected, radio_name)
	selected = non_empty(selected) or 'all'
	return selected == 'all' or selected == radio_name
end

function M.normalize_encryption(encryption)
	encryption = non_empty(encryption) or 'psk2'
	if encryption == 'auto' then
		return 'psk2'
	end
	if encryption == 'psk3-mixed' then
		return 'sae-mixed'
	end
	return encryption
end

function M.encryption_uses_key(encryption)
	encryption = M.normalize_encryption(encryption)
	return encryption ~= 'none'
end

function M.uplink_bssid_is_valid(bssid)
	bssid = non_empty(bssid)
	return bssid ~= nil and bssid:match('^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$') ~= nil
end

function M.uplink_bssid_locked()
	local locked = uci:get('pump', 'settings', 'uplink_bssid_lock')
	if locked == nil then
		-- Existing fix5 configurations always pinned the selected BSSID. Preserve
		-- that behaviour until the user explicitly changes the new option.
		return non_empty(uci:get('pump', 'settings', 'uplink_bssid')) ~= nil
	end

	return uci:get_bool('pump', 'settings', 'uplink_bssid_lock')
end

function M.uplink_config_is_valid()
	local ssid = non_empty(uci:get('pump', 'settings', 'uplink_ssid'))
	local radio = non_empty(uci:get('pump', 'settings', 'uplink_radio'))
	local encryption = M.normalize_encryption(uci:get('pump', 'settings', 'uplink_encryption'))

	if not ssid or not radio then
		return false
	end

	if M.uplink_bssid_locked() and not M.uplink_bssid_is_valid(uci:get('pump', 'settings', 'uplink_bssid')) then
		return false
	end

	if M.encryption_uses_key(encryption) then
		return M.wpa_key_is_valid(uci:get('pump', 'settings', 'uplink_key'))
	end

	return true
end

return M
