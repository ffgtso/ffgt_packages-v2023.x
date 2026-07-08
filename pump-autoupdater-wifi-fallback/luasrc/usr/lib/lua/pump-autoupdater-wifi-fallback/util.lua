#!/usr/bin/lua
-- SPDX-License-Identifier: BSD-2-Clause

local uci = require('simple-uci').cursor()
local iwinfo = require 'iwinfo'
local syslog = require 'posix.syslog'

local M = {}

local configname = 'pump-autoupdater-wifi-fallback'

function M.log(dest, msg)
	local prefix = configname .. ': '
	msg = prefix .. msg
	if dest == 'out' then
		io.stdout:write(msg .. '\n')
		syslog.syslog(syslog.LOG_INFO, msg)
	else
		io.stderr:write(msg .. '\n')
		syslog.syslog(syslog.LOG_CRIT, msg)
	end
end

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

function M.shell_quote(value)
	value = tostring(value or '')
	return "'" .. value:gsub("'", "'\\''") .. "'"
end

function M.file_exists(path)
	local f = io.open(path, 'r')
	if f then
		f:close()
		return true
	end
	return false
end

function M.executable_exists(path)
	return os.execute('[ -x ' .. M.shell_quote(path) .. ' ]') == 0
end

function M.pump_installed()
	return M.file_exists('/etc/config/pump')
end

function M.get_ssid_pattern()
	return non_empty(uci:get(configname, 'settings', 'ssid_pattern')) or '.*[Ff][Rr][Ee][Ii][Ff][Uu][Nn][Kk].*'
end

function M.get_available_wifi_networks()
	local radios = {}
	local pattern = M.get_ssid_pattern()

	uci:foreach('wireless', 'wifi-device', function(s)
		local name = s['.name']
		if name and s.disabled ~= '1' and s.disabled ~= true then
			radios[name] = {}
		end
	end)

	for radio, _ in pairs(radios) do
		local wifitype = iwinfo.type(radio)
		local iw = wifitype and iwinfo[wifitype] or nil
		if iw and iw.scanlist then
			local ok, tmplist = pcall(iw.scanlist, radio)
			if ok and type(tmplist) == 'table' then
				for _, net in ipairs(tmplist) do
					if net.ssid and net.bssid and net.ssid:match(pattern) then
						table.insert(radios[radio], net)
					end
				end
			else
				M.log('err', 'scan failed on ' .. radio)
			end
		end
	end

	return radios
end

function M.batman_gateway_available()
	local p = io.popen('batctl gwl 2>/dev/null')
	if not p then
		return false
	end

	for line in p:lines() do
		local stripped = line:gsub('^%s+', '')
		-- The batctl header can contain the local MainIF/MAC address. Only gateway
		-- table rows count as mesh connectivity.
		if not stripped:match('^%[')
		and not stripped:match('^[Nn]o gateways')
		and stripped:match('%x%x:%x%x:%x%x:%x%x:%x%x:%x%x') then
			p:close()
			return true
		end
	end

	p:close()
	return false
end

return M
