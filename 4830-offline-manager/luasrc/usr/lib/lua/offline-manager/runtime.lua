local uci = require('simple-uci').cursor()
local util = require 'gluon.util'
local wireless = require 'gluon.wireless'
local iwinfo = require 'iwinfo'
local json = require 'jsonc'
local unistd = require 'posix.unistd'
local wait = require 'posix.sys.wait'
local signal = require 'posix.signal'
local fcntl = require 'posix.fcntl'
local bit = require 'bit'
local syslog = require 'posix.syslog'
local core = require 'offline-manager.core'
local M = { uci = uci }
local iface, network = 'offlinewifi', 'offline_wifi6'
local network4 = 'offline_wifi4'
local output = '/tmp/4830-offline-manager.output.' .. unistd.getpid()
local interrupted, restoring = false, false
local deadline

function M.log(message)
	syslog.syslog(syslog.LOG_NOTICE, '4830-offline-manager: ' .. message)
	io.stderr:write(message .. '\n')
end

function M.upgrading()
	return util.readfile('/tmp/4830-offline-manager.upgrading') ~= nil
end

function M.cancelled()
	if restoring then return false end
	if interrupted or (deadline and M.uptime() >= deadline) then return true end
	if deadline then
		local s = M.load_state()
		return not core.outage_valid(s, M.uptime(), M.boot_id())
	end
	return false
end
function M.set_deadline(value) deadline = value end
function M.install_signals()
	for _, sig in ipairs({signal.SIGTERM, signal.SIGINT, signal.SIGHUP}) do
		signal.signal(sig, function() interrupted = true end)
	end
end

-- Direct argv execution: received SSIDs are never parsed by a shell.
-- Only capture small status responses; updater output is not buffered in RAM.
function M.command(argv, seconds, capture)
	local fd
	if capture then
		fd = assert(fcntl.open(output, bit.bor(fcntl.O_WRONLY, fcntl.O_CREAT, fcntl.O_TRUNC), 384))
	end
	local pid = unistd.fork()
	if not pid then
		if fd then unistd.close(fd); os.remove(output) end
		return 127, ''
	end
	if pid == 0 then
		if fd then unistd.dup2(fd, 1); unistd.close(fd) end
		local args = {}
		for i = 2, #argv do args[#args + 1] = tostring(argv[i]) end
		unistd.execp(argv[1], args)
		unistd._exit(127)
	end
	if fd then unistd.close(fd) end
	local elapsed, rc = 0, 127
	while true do
		local child, reason, status = wait.wait(pid, seconds and wait.WNOHANG or 0)
		if child == pid then
			rc = reason == 'exited' and status or 128 + (status or 0)
			break
		elseif child == nil then
			-- Interrupted waits are retried; an already reaped child is an error.
			if status ~= 4 then break end
		elseif seconds and (elapsed >= seconds or (M.cancelled() and not restoring)) then
			signal.kill(pid, signal.SIGKILL)
			wait.wait(pid, 0)
			rc = 124
			break
		else
			unistd.sleep(1)
			elapsed = elapsed + 1
		end
	end
	local text = capture and (util.readfile(output) or '') or ''
	if capture then os.remove(output) end
	return rc, text
end

function M.pause() unistd.sleep(1) end
function M.uptime()
	return tonumber((util.readfile('/proc/uptime') or ''):match('^[%d.]+')) or 0
end

function M.lock(name)
	local fd = fcntl.open('/var/lock/4830-offline-manager-' .. name .. '.lock', bit.bor(fcntl.O_WRONLY, fcntl.O_CREAT), 384)
	if not fd then return nil end
	local ok = fcntl.fcntl(fd, fcntl.F_SETLK, {
		l_start = 0, l_len = 0, l_type = fcntl.F_WRLCK, l_whence = unistd.SEEK_SET,
	})
	if not ok then unistd.close(fd); return nil end
	fcntl.fcntl(fd, fcntl.F_SETFD, fcntl.FD_CLOEXEC)
	return fd
end
function M.unlock(fd) unistd.close(fd) end

-- Unknown gateway state must not trigger a recovery update.
function M.gateway_status()
	local rc, text = M.command({'batctl', 'gwl', '-H'}, 5, true)
	if rc ~= 0 then return nil end
	return core.gateway_status(text)
end

function M.has_gateways()
	local present = M.gateway_status()
	return present
end

-- Distinguish absent hardware from administratively disabled WLAN.
function M.wifi_state()
	-- iw cannot initialize without nl80211 (common on Ethernet-only nodes).
	-- Inspect sysfs first so these nodes still reach the WAN fallback.
	if #util.glob('/sys/class/ieee80211/*') == 0 then return 'absent' end
	local rc, text = M.command({'iw', 'dev'}, 5, true)
	if rc ~= 0 then return nil end
	local phy, active = nil, {}
	for line in text:gmatch('[^\n]+') do
		local id = line:match('^phy#(%d+)')
		if id then phy = 'phy' .. id end
		local name = line:match('Interface%s+(%S+)')
		if phy and name then
			local flags = tonumber(util.readfile('/sys/class/net/' .. name .. '/flags') or '')
			if flags and flags % 2 == 1 then active[phy] = true end
		end
	end
	return next(active) and 'active' or 'inactive', active
end

function M.wan_routes()
	if not util.readfile('/sys/class/net/br-wan/ifindex') then return {} end
	-- /proc includes IPv6 policy tables, including Gluon's WAN table 1.
	return core.wan_routes(util.readfile('/proc/net/route') or '',
		util.readfile('/proc/net/ipv6_route') or '')
end

function M.branch_exists(branch)
	return uci:get('autoupdater', branch) ~= nil
end

function M.update_wan(branch)
	-- WAN IPv6 routes use mark 1 (network.wan6_lookup). Keep the environment local
	-- to this child. gluon-wan additionally selects the process group whose
	-- DNS requests are redirected to the WAN resolver on port 54.
	return M.command({'env', 'LD_PRELOAD=libpacketmark.so', 'LIBPACKETMARK_MARK=1',
		'/usr/bin/gluon-wan', '/usr/sbin/autoupdater', '-f', '-b', branch}, nil)
end

function M.scan(active_phys)
	local result, seen = {}, {}
	uci:foreach('wireless', 'wifi-device', function(radio)
		if M.cancelled() then return end
		local phy = wireless.find_phy(radio)
		if not phy or (active_phys and not active_phys[phy]) then return end
		local kind = iwinfo.type(radio['.name'])
		local backend = kind and iwinfo[kind]
		if not backend then return end
		local ok, list = pcall(backend.scanlist, radio['.name'])
		if not ok or type(list) ~= 'table' then return end
		for _, net in ipairs(list) do
			if core.eligible(net) then
				local key = phy .. '/' .. net.bssid:lower()
				if not seen[key] then
					seen[key] = true
					result[#result + 1] = {phy = phy, ssid = net.ssid,
						bssid = net.bssid:lower(), signal = tonumber(net.signal) or -999}
				end
			end
		end
	end)
	table.sort(result, function(a, b)
		if a.signal ~= b.signal then return a.signal > b.signal end
		return a.phy .. a.bssid < b.phy .. b.bssid
	end)
	return result
end

local function status(name)
	local rc, text = M.command({'ubus', 'call', 'network.interface.' .. (name or network), 'status'}, 5, true)
	if rc ~= 0 then return nil end
	local ok, value = pcall(json.parse, text)
	return ok and type(value) == 'table' and value or nil
end

function M.default_branch() return uci:get('autoupdater', 'settings', 'branch') end

function M.pump_uplink_enabled()
	return uci:get_bool('pump', 'settings', 'uplink_enabled')
end

function M.pump_routes()
	if not M.pump_uplink_enabled() then return {} end
	local device = uci:get('wireless', 'pump_uplink', 'ifname') or 'pumpwan'
	if type(device) ~= 'string' or not device:match('^[%w_%.%-]+$') or not util.readfile('/sys/class/net/' .. device .. '/ifindex') then return {} end
	local routes = core.wan_routes(util.readfile('/proc/net/route') or '',
		util.readfile('/proc/net/ipv6_route') or '', device)
	for _, family in ipairs({4, 6}) do
		local s = status(family == 4 and 'pump_wan' or 'pump_wan6')
		if not s or not s.up or (s.l3_device or s.device) ~= device then routes[family] = nil end
	end
	return routes
end

function M.down()
	if M.command({'wifi', 'down'}, 30) ~= 0 then return false end
	for _ = 1, 30 do
		local rc, text = M.command({'iw', 'dev'}, 5, true)
		if rc == 0 and not text:match('Interface%s') then return true end
		if M.cancelled() then return false end
		M.pause()
	end
	return false
end

function M.stop()
	-- Finish cleanup even after SIGTERM; never apply this to autoupdater.
	local previous = restoring
	restoring = true
	local stopped = true
	for _, name in ipairs({network4, network}) do
		stopped = M.command({'ifdown', name}, 15) == 0 and stopped
	end
	local down = false
	for _ = 1, 15 do
		local s, s4 = status(), status(network4)
		if s and s4 and not s.up and not s.pending and not s4.up and not s4.pending then down = true; break end
		M.pause()
	end
	local f = io.open('/sys/class/net/' .. iface .. '/ifindex')
	if f then
		f:close()
		M.command({'iw', 'dev', iface, 'disconnect'}, 5)
		stopped = M.command({'iw', 'dev', iface, 'del'}, 5) == 0 and stopped
	end
	restoring = previous
	return stopped and down
end

function M.up()
	restoring = true
	local ok = M.command({'wifi', 'up'}, 30) == 0
	restoring = false
	return ok
end

function M.connect(net)
	if M.command({'iw', 'phy', net.phy, 'interface', 'add', iface, 'type', 'managed'}, 5) ~= 0 then return false end
	if M.command({'ip', 'link', 'set', 'dev', iface, 'up'}, 5) ~= 0 then return false end
	-- Do not use -w: iw 4.14's event wait has no built-in timeout.
	if M.command({'iw', 'dev', iface, 'connect', net.ssid, net.bssid}, 5) ~= 0 then return false end
	for _ = 1, 30 do
		local rc, text = M.command({'iw', 'dev', iface, 'link'}, 5, true)
		local bssid = text:match('Connected to (%x%x:%x%x:%x%x:%x%x:%x%x:%x%x)')
		if rc == 0 and bssid and bssid:lower() == net.bssid then
			-- Manually created WLAN devices must be registered as external
			-- with netifd; carrier alone does not make them available.
			for _, name in ipairs({network, network4}) do
				local object = 'network.interface.' .. name
				if M.command({'ubus', 'call', object, 'add_device',
					'{"name":"' .. iface .. '","link-ext":true}'}, 5) ~= 0 then
					M.log('Cannot register fallback device with netifd')
					return false
				end
				-- Avoid ifup's global network reload after creating the station.
				if M.command({'ubus', 'call', object, 'up'}, 5) ~= 0 then return false end
			end
			return true
		end
		if M.cancelled() then return false end
		M.pause()
	end
	return false
end

function M.ready()
	for _ = 1, 60 do
		if core.ipv6_ready(status()) then return {[6] = true} end
		if core.ipv4_ready(status(network4)) then return {[4] = true} end
		if M.cancelled() then return false end
		M.pause()
	end
	M.log('No IPv4/IPv6 address/default route/DNS on fallback interfaces')
	return false
end

function M.update(branch, families)
	if type(families) == 'table' and families[4] and not families[6] and M.branch_exists('offline4') then
		branch = 'offline4'
	end
	return M.command({'/usr/sbin/autoupdater', '-f', '-b', branch}, nil)
end

local statefile = '/tmp/4830-offline-manager.state'
function M.boot_id() return (util.readfile('/proc/sys/kernel/random/boot_id') or ''):match('%S+') end
function M.load_state()
	local ok, s = pcall(json.parse, util.readfile(statefile) or '')
	return ok and type(s) == 'table' and s or nil
end
function M.save_state(s)
	local f = assert(io.open(statefile .. '.tmp', 'w'))
	assert(f:write(json.stringify(s))); assert(f:close())
	assert(os.rename(statefile .. '.tmp', statefile))
end
function M.option(key)
	return uci:get_bool('4830-offline-manager', 'settings', key)
end
function M.autoupdate_enabled()
	return uci:get_bool('autoupdater', 'settings', 'enabled')
end
function M.autoupdater_busy()
	local rc = M.command({'pgrep', '-x', 'autoupdater'}, 5, true)
	-- An unavailable process check must not authorize a reboot.
	return rc ~= 1
end
function M.spawn_worker()
	return M.command({'start-stop-daemon', '-S', '-b', '-x',
		'/usr/lib/4830-offline-manager/worker'}, 5) == 0
end
function M.reboot()
	M.log('Offline for more than 95 minutes; rebooting')
	M.command({'sync'}, 10)
	return M.command({'reboot'}, 5) == 0
end
function M.ssid(online)
	local ssid = require 'offline-manager.ssid'
	local mapping = {}
	local hostname = (util.readfile('/proc/sys/kernel/hostname') or ''):gsub('%s+$', '')
	uci:foreach('wireless', 'wifi-iface', function(s)
		if online == nil then return end
		local kind, radio = s['.name']:match('^(client)_(radio%d+)$')
		if not kind then kind, radio = s['.name']:match('^(owe)_(radio%d+)$') end
		if not kind or not s.ifname or not ssid.valid(s.ssid) then return end
		local prefix = kind == 'owe' and 'FF_OFF_OWE_' or 'FF_OFFLINE_'
		local entry = {ssid = online and s.ssid or ssid.offline_name(prefix, hostname)}
		mapping[s.ifname] = entry
	end)
	local pending = '/tmp/4830-offline-manager.ssid-reload'
	for _, path in ipairs(util.glob('/var/run/hostapd-phy*.conf')) do
		local old = util.readfile(path)
		if old then
			local new = ssid.rewrite(old, mapping)
			if new ~= old then
				-- cp -p preserves private-BSS file permissions; replace atomically.
				local tmp = path .. '.offline-manager'
				assert(M.command({'cp', '-p', path, tmp}, 5) == 0)
				local f = assert(io.open(tmp, 'w')); assert(f:write(new)); assert(f:close())
				local p = assert(io.open(pending, 'w')); p:close()
				assert(os.rename(tmp, path))
			end
		end
	end
	if util.readfile(pending) ~= nil and M.command({'killall', '-HUP', 'hostapd'}, 5) == 0 then
		os.remove(pending)
	end
end

return M
