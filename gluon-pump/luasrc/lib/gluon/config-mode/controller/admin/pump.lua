local uci = require('simple-uci').cursor()
local wireless = require 'gluon.wireless'

package 'gluon-pump'

if wireless.device_uses_wlan(uci) then
	entry({'admin', 'pump'}, model('admin/pump'), _('PUMP'), 35)
end
