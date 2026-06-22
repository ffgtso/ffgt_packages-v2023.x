local site = require 'gluon.site'

local M = {}

local function first_domain_name(domain_names)
	if type(domain_names) ~= 'table' then
		return nil
	end

	local keys = {}
	for key in pairs(domain_names) do
		table.insert(keys, key)
	end
	table.sort(keys)

	if #keys == 0 then
		return nil
	end

	return domain_names[keys[1]]
end

function M.domain_name()
	return first_domain_name(site.domain_names({}))
		or site.site_name(site.site_code('gluon'))
		or 'gluon'
end

function M.ssid()
	return 'PUMP-' .. tostring(M.domain_name())
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
