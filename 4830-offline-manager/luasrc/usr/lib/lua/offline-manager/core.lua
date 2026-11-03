-- Copyright (c) 2026. Distributed under the accompanying BSD-2-Clause LICENSE.
local M = {}

-- Presence and selected-gateway quality are separate signals.
function M.gateway_status(text)
	local present, selected, tq = false, 0, nil
	for line in text:gmatch('[^\n]+') do
		local clean = line:match('^%s*(.-)%s*$')
		local marker = clean:match('^(=>)') or clean:match('^(%*)')
		local row = marker and clean:sub(#marker + 1):match('^%s*(.*)') or clean
		local mac = row:match('^(%x%x:%x%x:%x%x:%x%x:%x%x:%x%x)%s')
			or row:match('^(%x%x:%x%x:%x%x:%x%x:%x%x:%x%x)$')
		if mac then
			present = true
			if marker then
				selected = selected + 1
				tq = tonumber(row:match('%(%s*(%d+)%s*%)'))
				if tq and tq > 255 then tq = nil end
			end
		elseif clean ~= '' and not clean:match('^No gateways in range') then
			return nil, nil
		end
	end
	if selected == 0 then tq = 0 elseif selected > 1 then tq = nil end
	return present, tq
end
function M.ssid_online(tq)
	if type(tq) ~= 'number' or tq < 0 or tq > 255 then return nil end
	if tq <= 15 then return false end
	if tq >= 30 then return true end
	return nil -- Hysteresis: do not rewrite the SSIDs.
end

function M.eligible(net)
	return type(net.ssid) == 'string' and #net.ssid > 0 and #net.ssid <= 32
		and not net.ssid:find('%z') and net.ssid:lower():find('freifunk', 1, true)
		and type(net.bssid) == 'string'
		and net.bssid:match('^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$')
		and net.mode == 'Master' and type(net.encryption) == 'table'
		and net.encryption.enabled == false
end

function M.ipv6_ready(status)
	if type(status) ~= 'table' or not status.up then return false end
	local address, route = false, false
	for _, entry in ipairs(status['ipv6-address'] or {}) do
		local a = (entry.address or ''):lower()
		-- Global unicast or ULA; link-local alone cannot reach the mirrors.
		if a:match('^[23]') or a:match('^f[cd]') then address = true end
	end
	for _, entry in ipairs(status.route or {}) do
		if entry.target == '::' and tonumber(entry.mask) == 0 then route = true end
	end
	return address and route and #(status['dns-server'] or {}) > 0
end

-- DHCPv4-only recovery networks are useful on PUMP installations too.
function M.ipv4_ready(status)
	if type(status) ~= 'table' or not status.up then return false end
	local address, route = false, false
	for _, entry in ipairs(status['ipv4-address'] or {}) do
		local a, b, c, d = (entry.address or ''):match('^(%d+)%.(%d+)%.(%d+)%.(%d+)$')
		a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
		if a and a > 0 and a < 224 and a ~= 127 and b <= 255 and c <= 255 and d <= 255
			and not (a == 169 and b == 254) then address = true end
	end
	for _, entry in ipairs(status.route or {}) do
		if entry.target == '0.0.0.0' and tonumber(entry.mask) == 0 then route = true end
	end
	return address and route and #(status['dns-server'] or {}) > 0
end

-- Accept only UP unicast default routes on the specified device (default: br-wan).
function M.wan_routes(ipv4, ipv6, device)
	device = device or 'br-wan'
	local found = {}
	local function usable(flags)
		local n = tonumber(flags, 16)
		return n and n % 2 == 1 and math.floor(n / 512) % 2 == 0
	end
	for line in ipv4:gmatch('[^\n]+') do
		local f = {}; for value in line:gmatch('%S+') do f[#f + 1] = value end
		if f[1] == device and f[2] == '00000000' and f[8] == '00000000'
			and usable(f[4]) then found[4] = true end
	end
	for line in ipv6:gmatch('[^\n]+') do
		local f = {}; for value in line:gmatch('%S+') do f[#f + 1] = value end
		if f[1] == string.rep('0', 32) and f[2] == '00' and f[10] == device
			and usable(f[9]) then found[6] = true end
	end
	return found
end

function M.wan_round(ops, pump)
	local routes = pump and ops.pump_routes or ops.wan_routes
	local label = pump and 'PUMP uplink' or 'br-wan'
	for _, family in ipairs({4, 6}) do
		if ops.upgrading() or ops.cancelled() then return true end
		-- Recheck before every attempt, including after offline4 returns.
		local gateways = ops.has_gateways()
		if gateways ~= false then return gateways == true end
		local branch = 'offline' .. family
		if routes()[family] then
			if pump and not ops.branch_exists(branch) then branch = ops.default_branch() end
			if branch and ops.branch_exists(branch) then
				ops.log('Trying uplink branch ' .. branch .. ' on ' .. label)
				if ops.cancelled() then return true end
				local rc = ops.update_wan(branch)
				ops.log('WAN autoupdater returned ' .. tostring(rc))
			else
				ops.log('Missing autoupdater branch ' .. tostring(branch))
			end
		end
	end
	return true
end

-- ops is also used by the deterministic regression tests.
function M.round(ops, candidates, branch)
	if #candidates == 0 or ops.upgrading() then return true end
	local ok, err = xpcall(function()
		assert(ops.down(), 'WiFi teardown failed')
		for _, net in ipairs(candidates) do
			if ops.upgrading() then return end
			if ops.cancelled() then break end
			assert(ops.stop(), 'Cannot stop previous fallback interface')
			ops.log('Trying ' .. net.phy .. ' ' .. net.bssid .. ' ' .. string.format('%q', net.ssid))
			local families = ops.connect(net) and ops.ready()
			if families and not ops.cancelled() and ops.has_gateways() == false then
				-- No outer timeout: never kill autoupdater during sysupgrade.
				local rc = ops.update(branch, families)
				ops.log('Autoupdater returned ' .. tostring(rc) .. '; trying next AP')
				-- Exit 0 can mean "no newer firmware". A completed flash reboots.
			end
		end
	end, debug.traceback)
	-- sysupgrade may hand off to procd and return before the reboot.
	if ops.upgrading() then
		ops.log('Upgrade started; leaving network untouched until reboot')
		return true
	end
	-- Always try both cleanup operations, even if one raises an error.
	local stop_ok, stop_result = pcall(ops.stop)
	local up_ok, up_result = pcall(ops.up)
	if not ok then ops.log(err) end
	if not stop_ok or not stop_result or not up_ok or not up_result then
		ops.log('Cleanup incomplete; check WiFi/network state')
		return false
	end
	return ok
end

function M.outage_valid(s, now, boot)
	return type(s) == 'table' and type(boot) == 'string' and boot ~= '' and s.boot == boot
		and type(s.checked) == 'number' and type(s.since) == 'number'
		and s.since >= 0 and s.since <= s.checked and s.checked <= now
		and now - s.checked <= 150
end
function M.observe(old, now, boot, gateways)
	local s = {boot = boot, checked = now}
	if gateways == false then
		if M.outage_valid(old, now, boot) then
			s.since = old.since
			if type(old.last_attempt) == 'number' and old.last_attempt <= now then
				s.last_attempt = old.last_attempt
			end
		else s.since = now end
	end
	return s
end
function M.action(s, now)
	if now < 900 or type(s.since) ~= 'number' then return 'none' end
	local age = now - s.since
	if age > 5700 then return 'reboot' end
	if age > 3600 and (not s.last_attempt or now - s.last_attempt >= 600) then return 'update' end
	return 'none'
end

return M
