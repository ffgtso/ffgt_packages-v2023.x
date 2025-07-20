
return function(form, uci)
	local admin_i18n = i18n 'gluon-web-admin'
	local ffgt_i18n = i18n 'ffgt-config-mode-wizard'
	local json = require 'jsonc'
	local site = require 'gluon.site'
	local util = require 'gluon.util'

	local text=""
	local text2=admin_i18n.translate("Remote access")
	local cmdstr='(wc -l /etc/dropbear/authorized_keys 2>/dev/null || echo 0)| cut -d " " -f 1'
	rc=util.trim(util.exec(cmdstr))
	if rc=="0" then
		text = ffgt_i18n.translate("WARNING: You have not configured any SSH keys, you will not have SSH access to the running node!")
		text = "<strong>" .. text .. "</strong>"
	else
		text = ffgt_i18n.translate('There are SSH keys (%s) configured, fine!')
		text = string.format(text, rc)
	end
	text = text .. "<br> </br>"
	text = text .. ffgt_i18n.translate('To change it, go to %s.')
	text = string.format(text, '<a href="/cgi-bin/config/admin/remote">%s</a>')
	text = string.format(text, text2)
	local s = form:section(Section, nil, text)
	return {'gluon-node-info'}
end
