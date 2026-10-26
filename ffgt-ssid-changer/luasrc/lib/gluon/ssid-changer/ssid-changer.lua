#!/usr/bin/lua

local uci = require('simple-uci').cursor()

-- Safety check functions
local function log_debug(...)
	if uci:get('ssid-changer', 'settings', 'debug_log_enabled') == '1' then
		os.execute('logger -t "ffgt-ssid-changer" -p debug "' .. table.concat({...}, ' ') .. '"')
	end
end

local function log(...)
	os.execute('logger -t "ffgt-ssid-changer" "' .. table.concat({...}, ' ') .. '"')
end

local function safety_exit(message)
	log_debug(message .. ", exiting with error code 2")
	os.exit(2)
end

-- Check if the script is enabled
if uci:get('ssid-changer', 'settings', 'enabled') == '0' then
	os.exit(0)  -- Exit silently if the script is disabled
end

-- Check for autoupdater running
local function is_autoupdater_running()
	local handle = io.popen('pgrep -f autoupdater')
	local result = handle:read("*a")
	handle:close()
	return result ~= ''
end

if is_autoupdater_running() then
	safety_exit('autoupdater running')
end

-- Read uptime
local function get_uptime()
	local file = io.open('/proc/uptime', 'r')
	local uptime = file:read("*n")  -- Read only the first number (uptime in seconds)
	file:close()
	return uptime
end

local uptime = get_uptime()
local uptime_minutes = math.floor(uptime / 60)
local monitor_duration = tonumber(uci:get('ssid-changer', 'settings', 'switch_timeframe') or 30)
if not monitor_duration or monitor_duration < 1 or monitor_duration ~= math.floor(monitor_duration) then
	safety_exit('switch_timeframe must be a positive integer')
end
local is_switch_time = uptime_minutes % monitor_duration

if uptime < 60 then
	safety_exit('uptime less than one minute')
end

-- Check for hostapd processes
local function has_hostapd_processes()
	local handle = io.popen('find /var/run -name "hostapd-*.conf" | wc -l')
	local result = handle:read("*a")
	handle:close()
	return tonumber(result) > 0
end

if not has_hostapd_processes() then
	safety_exit('no hostapd-*')
end

-- Generate the offline SSID
local function calculate_offline_ssid()
	local prefix = uci:get('ssid-changer', 'settings', 'prefix') or 'FF_Offline_'
	local settings_suffix = uci:get('ssid-changer', 'settings', 'suffix') or 'nodename'
	local suffix
	if #prefix > 32 then
		safety_exit('offline SSID prefix exceeds 32 bytes')
	end

	if settings_suffix == 'nodename' then
		local handle = io.popen('uname -n')
		suffix = handle:read('*a'):gsub('%s+', '')
		handle:close()
	elseif settings_suffix == 'mac' then
		suffix = (uci:get('network', 'bat0', 'macaddr') or ''):gsub(':', '')
	else
		suffix = ''
	end

	local available = 32 - #prefix
	if #suffix > available then
		if available <= 3 then
			suffix = suffix:sub(1, available)
		else
			local first = math.ceil((available - 3) / 2)
			local last = math.floor((available - 3) / 2)
			suffix = suffix:sub(1, first) .. '...' .. (last > 0 and suffix:sub(-last) or '')
		end
	end
	return prefix .. suffix
end

local offline_ssid = calculate_offline_ssid()
if #offline_ssid < 1 or #offline_ssid > 32 then
	safety_exit('offline SSID must contain 1 to 32 bytes')
end

-- Keep monitoring history separate from the applied wireless state. The old
-- ssid-changer-offline file described an interval, not an SSID transition.
local tmp = '/tmp/ssid-changer-count'
local tmp_state = '/tmp/ssid-changer-offline'
local tmp_applied = '/tmp/ssid-changer-applied'

local function read_number(path)
	local file = io.open(path, 'r')
	if not file then return nil end
	local value = tonumber(file:read('*a'))
	file:close()
	return value
end

local function write_number(path, value)
	local file = io.open(path, 'w')
	if not file then safety_exit('cannot write SSID changer state') end
	local ok = file:write(tostring(value))
	local closed = file:close()
	if not ok or not closed then safety_exit('cannot save SSID changer state') end
end

local off_count = math.max(0, read_number(tmp) or 0)
local is_offline = read_number(tmp_state) or 0
local applied = read_number(tmp_applied)
if applied == nil then
	-- Migration from the previous script: recover an already active offline SSID.
	applied = 0
	for i = 0, 2 do
		if uci:get('wireless', 'client_radio' .. i, 'ssid') == offline_ssid then
			applied = 1
		end
	end
	write_number(tmp_applied, applied)
end

local function reconfigure()
	if os.execute('wifi reconf') ~= 0 then
		safety_exit('wifi reconf failed')
	end
end

local function calculate_tq_limit()
	local tq_limit_max = tonumber(uci:get('ssid-changer', 'settings', 'tq_limit_max') or 45)
	local tq_limit_min = tonumber(uci:get('ssid-changer', 'settings', 'tq_limit_min') or 35)
	if not tq_limit_min or not tq_limit_max or tq_limit_min < 0
		or tq_limit_max > 255 or tq_limit_min > tq_limit_max then
		safety_exit('invalid TQ limits')
	end
	-- Parse in Lua: the old double-quoted awk program expanded $2 in the shell.
	local handle = io.popen('batctl gwl -H 2>/dev/null')
	local output = handle:read('*a')
	handle:close()
	local gateway_tq
	for line in output:gmatch('[^\n]+') do
		local tq = line:match('^%s*%*%s+%S+%s+%(%s*(%d+)%s*%)')
		if tq then gateway_tq = tonumber(tq); break end
	end
	-- A missing selected gateway is an offline observation, not a reason
	-- to stop updating the monitoring history.
	if not gateway_tq then return 'offline' end
	local is_online

	if gateway_tq >= tq_limit_max then
		is_online = true
	elseif gateway_tq < tq_limit_min then
		is_online = false
	else
		-- in the middle part we consider us offline if there was at least one offline incidents
		-- or we were offline before the current monitor interval
		is_online = off_count == 0 and is_offline == 0
	end

	if is_online then
		return 'online'
	else
		return 'offline'
	end
end

local function has_default_gw4()
	local default_gw4 = io.open('/var/gluon/state/has_default_gw4', 'r')
	if default_gw4 then
		default_gw4:close()
		return true
	end
	return false
end

local status
if has_default_gw4() then
	local tq_limit_enabled = tonumber(uci:get('ssid-changer', 'settings', 'tq_limit_enabled') or 0)

	if tq_limit_enabled == 1 then
		status = calculate_tq_limit()
	else
		status = 'online'
	end
else
	status = 'offline'
end

if applied == 2 and status == 'offline' then
	-- Retry an interrupted/failed offline reload on the next invocation.
	reconfigure()
	write_number(tmp_applied, 1)
	applied = 1
end

if status == 'online' then
	log_debug("node is online")
	-- Reconfigure once per actual SSID transition, not once per offline observation.
	if applied > 0 then
		log("reverting offline ssid back to default wireless config")
		-- Leave unrelated pending wireless changes (channel, mesh, WAN) alone.
		for i = 0, 2 do
			uci:revert('wireless', 'client_radio' .. i, 'ssid')
			uci:revert('wireless', 'owe_radio' .. i, 'disabled')
		end
		reconfigure()
		write_number(tmp_applied, 0)
	end
elseif status == 'offline' then
	log_debug("node is considered offline")
	local first = tonumber(uci:get('ssid-changer', 'settings', 'first')) or 5
	-- set SSID offline, only if uptime is less than FIRST or exactly a multiplicative of switch_timeframe
	if uptime_minutes < first or is_switch_time == 0 then

		-- check if off_count is more than half of the monitor duration
		if applied == 0 and off_count >= math.floor(monitor_duration / 2) then
			-- if has been offline for at least half checks in monitor duration
			-- set the SSID to the offline SSID
			-- and disable owe client radios
			local changed = false
			for i = 0, 2 do
				local client_ssid = uci:get('wireless', 'client_radio' .. i, 'ssid')
				if client_ssid then
					uci:set('wireless', 'client_radio' .. i, 'ssid', offline_ssid)
					changed = true
				end

				local owe_ssid = uci:get('wireless', 'owe_radio' .. i, 'ssid')
				if owe_ssid then
					uci:set('wireless', 'owe_radio' .. i, 'disabled', '1')
					changed = true
				end
			end
			if changed then
				-- Mark before reconfiguration so a failed reload can still be undone.
				if not uci:save('wireless') then safety_exit('cannot save wireless changes') end
				write_number(tmp_applied, 2)
				log("reconfiguring wifi to offline ssid")
				reconfigure()
				write_number(tmp_applied, 1)
			end
		end
	end
	off_count = off_count + 1
	write_number(tmp, off_count)
end

if is_switch_time == 0 then
	-- Retain the existing monitoring-window accounting, independently of
	-- whether an SSID transition took place.
	write_number(tmp, status == 'offline' and 1 or 0)
	write_number(tmp_state, status == 'offline' and 1 or 0)
end
