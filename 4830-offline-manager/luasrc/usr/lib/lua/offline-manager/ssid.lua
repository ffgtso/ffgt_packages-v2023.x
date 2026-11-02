local M = {}
function M.valid(s)
	return type(s) == 'string' and #s > 0 and #s <= 32 and not s:find('[%z\r\n]')
end
function M.offline_name(prefix, hostname)
	local s = prefix .. hostname
	if #s <= 32 then return s end
	local space = 32 - #prefix - 3
	local first = math.floor(space / 2)
	return prefix .. hostname:sub(1, first) .. '...' .. hostname:sub(- (space - first))
end
local function hex(s)
	return (s:gsub('.', function(c) return string.format('%02x', c:byte()) end))
end
function M.rewrite(text, mapping)
	local iface
	return (text:gsub('([^\n]*)(\n?)', function(line, newline)
		iface = line:match('^interface=(.*)$') or line:match('^bss=(.*)$') or iface
		local entry = mapping[iface]
		if entry then
			if line:match('^ssid=') or line:match('^ssid2=') then
				line = 'ssid2=' .. hex(entry.ssid)
			elseif line:match('^config_id=') then
				-- OpenWrt uses this ID to invalidate stations on BSS changes.
				line = 'config_id=offline-manager-' .. hex(entry.ssid)
			end
		end
		return line .. newline
	end))
end
return M
