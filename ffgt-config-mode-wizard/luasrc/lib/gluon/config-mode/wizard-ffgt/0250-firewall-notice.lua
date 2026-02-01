
return function(form, uci)
    local ffgt_i18n = i18n 'ffgt-config-mode-wizard'
    local text = ffgt_i18n.translate('4830-firewall-notice')
    local cmdstr="/lib/gluon/ffgt-geolocate/get_td_portnumbers.sh"
    local pipe = io.popen(cmdstr)
    local ports = pipe:read("*a")
    pipe:close()
    local text2 = ffgt_i18n.translate('4830-firewall-notice-template')
    text2 = string.format(text2, ports)
    text = string.format(text, text2)
    local s = form:section(Section, nil, text)
    return {'gluon', reconfigure}
end
