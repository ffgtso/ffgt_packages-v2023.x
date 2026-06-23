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

function M.key_is_valid()
	local key = M.key()
	return key ~= nil and #key >= 8 and #key <= 63 and key:match('^[ -~]+$') ~= nil
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

return M
