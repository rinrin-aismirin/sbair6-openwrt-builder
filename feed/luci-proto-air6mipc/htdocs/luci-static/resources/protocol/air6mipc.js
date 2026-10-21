'use strict';
'require form';
'require network';

network.registerPatternVirtual(/^air6mipc-.+$/);
network.registerErrorCode('NO_APN', _('No APN configured'));
network.registerErrorCode('INVALID_AUTH', _('Invalid authentication type'));
network.registerErrorCode('INVALID_PDPTYPE', _('Invalid PDP type'));
network.registerErrorCode('MODEM_NOT_READY', _('Modem not ready (is the air6-modem service enabled?)'));
network.registerErrorCode('SIM_NOT_INSERTED', _('No SIM card'));
network.registerErrorCode('SIM_SLOT_FAILED', _('Could not switch the SIM slot'));
network.registerErrorCode('SIM_LOCKED', _('SIM PIN or PUK required'));
network.registerErrorCode('SIM_NOT_READY', _('SIM not ready'));
network.registerErrorCode('NOT_REGISTERED', _('Not registered to a network'));
network.registerErrorCode('CALL_FAILED', _('Call failed'));

return network.registerProtocol('air6mipc', {
	getI18n: function() {
		return _('SoftBank Air 6 modem');
	},

	getIfname: function() {
		return this._ubus('l3_device') || 'air6mipc-%s'.format(this.sid);
	},

	getPackageName: function() {
		return 'air6-modem';
	},

	isFloating: function() {
		return true;
	},

	isVirtual: function() {
		return true;
	},

	getDevices: function() {
		return null;
	},

	containsDevice: function(ifname) {
		return (network.getIfnameOf(ifname) == this.getIfname());
	},

	renderFormOptions: function(s) {
		var o;

		o = s.taboption('general', form.Value, 'apn', _('APN'));
		o.rmempty = false;
		o.validate = function(section_id, value) {
			if (value == null || value == '')
				return _('An APN is required');
			if (!/^[a-zA-Z0-9\-.]*[a-zA-Z0-9]$/.test(value))
				return _('Invalid APN provided');
			return true;
		};

		o = s.taboption('general', form.ListValue, 'auth', _('Authentication Type'));
		o.value('none', 'NONE');
		o.value('pap', 'PAP');
		o.value('chap', 'CHAP');
		o.value('both', 'PAP/CHAP');
		o.default = 'none';

		o = s.taboption('general', form.Value, 'username', _('PAP/CHAP username'));
		o.depends('auth', 'pap');
		o.depends('auth', 'chap');
		o.depends('auth', 'both');

		o = s.taboption('general', form.Value, 'password', _('PAP/CHAP password'));
		o.depends('auth', 'pap');
		o.depends('auth', 'chap');
		o.depends('auth', 'both');
		o.password = true;

		o = s.taboption('advanced', form.ListValue, 'pdptype', _('PDP Type'));
		o.value('ipv4v6', 'IPv4/IPv6');
		o.value('ipv4', 'IPv4');
		o.value('ipv6', 'IPv6');
		o.default = 'ipv4v6';

		o = s.taboption('advanced', form.Flag, 'roaming', _('Allow roaming'));
		o.default = o.disabled;

		o = s.taboption('advanced', form.Value, 'delay', _('Modem init timeout'),
			_('Maximum amount of seconds to wait for each step: modem ready, SIM ready, network registration'));
		o.placeholder = '30';
		o.datatype = 'min(1)';

		o = s.taboption('advanced', form.Value, 'mtu', _('Override MTU'));
		o.placeholder = '1500';
		o.datatype = 'max(9200)';
	}
});
