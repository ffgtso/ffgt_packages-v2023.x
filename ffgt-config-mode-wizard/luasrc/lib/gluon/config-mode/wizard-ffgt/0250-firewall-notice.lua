
return function(form, uci)
    local ffgt_i18n = i18n 'ffgt-config-mode-wizard'
    local text = ffgt_i18n.translate('4830-firewall-notice')
    local s = form:section(Section, nil, text)
    return {'gluon', reconfigure}
end
