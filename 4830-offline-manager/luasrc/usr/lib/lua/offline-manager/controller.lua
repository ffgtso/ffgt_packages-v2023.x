local core = require 'offline-manager.core'
local M = {}
function M.tick(ops)
	local now, boot = ops.uptime(), ops.boot_id()
	if not boot or boot == '' then ops.log('Missing boot identity'); return false end
	local gateways, tq = ops.gateway_status()
	local state = core.observe(ops.load_state(), now, boot, gateways)
	ops.save_state(state)
	if gateways == nil then ops.log('Gateway status unknown; outage interval reset'); return false end
	if not ops.option('enabled') or now < 900 or ops.upgrading() then return true end
	local action_lock = ops.lock('action')
	if not action_lock then return true end
	local ok, err = xpcall(function()
		if ops.autoupdater_busy() then return end
		if ops.option('ssid_enabled') then ops.ssid(core.ssid_online(tq)) end
		local action = core.action(state, now)
		if action == 'none' then return end
		-- Recheck just before a disruptive action; a listed gateway is enough.
		if ops.has_gateways() ~= false or ops.upgrading() or ops.autoupdater_busy() then return end
		if action == 'reboot' then
			if ops.option('reboot_enabled') then ops.reboot() end
		elseif ops.option('autoupdate_enabled') and ops.autoupdate_enabled() then
			state.last_attempt = now
			ops.save_state(state)
			-- The tick lock and cooldown prevent a second launch. The worker
			-- takes the action lock itself; minute observations keep running.
			ops.unlock(action_lock); action_lock = nil
			if not ops.spawn_worker() then ops.log('Unable to start update worker') end
		end
	end, debug.traceback)
	if action_lock then ops.unlock(action_lock) end
	if not ok then ops.log(err) end
	return ok
end
return M
