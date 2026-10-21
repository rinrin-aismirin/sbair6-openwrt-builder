'use strict';
'require view';
'require form';
'require rpc';
'require poll';
'require uci';
'require ui';
'require request';
'require dom';

var callStatus = rpc.declare({
	object: 'air6-modem',
	method: 'status',
	params: [ 'ids' ],
	expect: { '': {} }
});

var callNvJob = rpc.declare({
	object: 'air6-modem',
	method: 'nv_job',
	params: [ 'op', 'source', 'sha256' ]
});

var callNvJobStatus = rpc.declare({
	object: 'air6-modem',
	method: 'nv_job_status',
	params: [ 'job' ]
});

var callNvBackupDone = rpc.declare({
	object: 'air6-modem',
	method: 'nv_backup_done',
	params: [ 'job', 'sha256' ]
});

var callReboot = rpc.declare({
	object: 'system',
	method: 'reboot'
});

/*
 * Run an NV job on the router and wait for that job; resolves with its status (st.job is its ID), rejects with its
 * log on failure (error.job: its status, error.notStarted: the router refused to start it). When the job's status
 * cannot be read (lost connection, job no longer known), the error has neither: the outcome is unknown.
 */
function runNvJob(op, source, sha256) {
	return callNvJob(op, source || '', sha256 || '').then(function(res) {
		if (!res || res.error || !res.job) {
			var e = new Error((res && res.error) || _('The router did not start the job'));
			e.notStarted = true;
			throw e;
		}

		return new Promise(function(resolve, reject) {
			var poll = function() {
				callNvJobStatus(res.job).then(function(st) {
					if (!st || st.error || !st.state) {
						reject(new Error(_('The result of the job cannot be read: %s').format((st && st.error) || _('no answer'))));
					}
					else if (st.state == 'running') {
						window.setTimeout(poll, 2000);
					}
					else if (st.state == 'done') {
						resolve(st);
					}
					else {
						var e = new Error(st.log || _('Failed'));
						e.job = st;
						reject(e);
					}
				}, reject);
			};
			window.setTimeout(poll, 2000);
		});
	});
}

/* SHA-256 of an ArrayBuffer as hex. WebCrypto is only available in secure contexts (LuCI is often plain HTTP). */
function sha256hex(buf) {
	if (window.crypto && window.crypto.subtle && window.isSecureContext)
		return window.crypto.subtle.digest('SHA-256', buf).then(hex);

	return Promise.resolve(hex(sha256js(new Uint8Array(buf))));

	function hex(b) {
		return Array.prototype.map.call(new Uint8Array(b), function(x) { return ('0' + x.toString(16)).slice(-2); }).join('');
	}
}

function sha256js(data) {
	var K = [], H = [], i, j, n = 0, x = 2;
	/* First 32 bits of the fractional parts of the square and cube roots of the first 64 primes. */
	while (n < 64) {
		for (j = 2; j * j <= x && x % j; j++);
		if (j * j > x) {
			if (n < 8)
				H[n] = (Math.pow(x, 1 / 2) % 1) * 4294967296 | 0;
			K[n++] = (Math.pow(x, 1 / 3) % 1) * 4294967296 | 0;
		}
		x++;
	}

	var len = data.length, words = new Int32Array(((len + 9 + 63) >> 6) << 4), w = new Int32Array(64);
	for (i = 0; i < len; i++)
		words[i >> 2] |= data[i] << (24 - (i & 3) * 8);
	words[len >> 2] |= 0x80 << (24 - (len & 3) * 8);
	words[words.length - 1] = len * 8;
	words[words.length - 2] = Math.floor(len / 536870912);

	for (i = 0; i < words.length; i += 16) {
		var a = H[0], b = H[1], c = H[2], d = H[3], e = H[4], f = H[5], g = H[6], h = H[7];
		for (j = 0; j < 64; j++) {
			if (j < 16) {
				w[j] = words[i + j];
			}
			else {
				var w15 = w[j - 15], w2 = w[j - 2];
				w[j] = (((w15 >>> 7) | (w15 << 25)) ^ ((w15 >>> 18) | (w15 << 14)) ^ (w15 >>> 3)) + w[j - 7] +
					(((w2 >>> 17) | (w2 << 15)) ^ ((w2 >>> 19) | (w2 << 13)) ^ (w2 >>> 10)) + w[j - 16] | 0;
			}
			var t1 = h + (((e >>> 6) | (e << 26)) ^ ((e >>> 11) | (e << 21)) ^ ((e >>> 25) | (e << 7))) +
				((e & f) ^ (~e & g)) + K[j] + w[j] | 0;
			var t2 = (((a >>> 2) | (a << 30)) ^ ((a >>> 13) | (a << 19)) ^ ((a >>> 22) | (a << 10))) +
				((a & b) ^ (a & c) ^ (b & c)) | 0;
			h = g; g = f; f = e; e = d + t1 | 0; d = c; c = b; b = a; a = t1 + t2 | 0;
		}
		H[0] = H[0] + a | 0; H[1] = H[1] + b | 0; H[2] = H[2] + c | 0; H[3] = H[3] + d | 0;
		H[4] = H[4] + e | 0; H[5] = H[5] + f | 0; H[6] = H[6] + g | 0; H[7] = H[7] + h | 0;
	}

	var out = new Uint8Array(32);
	for (i = 0; i < 32; i++)
		out[i] = (H[i >> 2] >>> (24 - (i & 3) * 8)) & 255;
	return out.buffer;
}

/* Fetch a file from the router; resolves with its Blob. */
function fetchFile(path, filename) {
	return request.post(L.env.cgi_base + '/cgi-download',
		'sessionid=%s&path=%s&filename=%s'.format(encodeURIComponent(rpc.getSessionID()),
			encodeURIComponent(path), encodeURIComponent(filename)),
		{ headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, responseType: 'blob' })
	.then(function(res) {
		if (!res.ok)
			throw new Error(_('Download failed (HTTP %d)').format(res.status));

		return res.blob();
	});
}

function save(blob, filename) {
	var a = E('a', { 'href': URL.createObjectURL(blob), 'download': filename, 'style': 'display:none' });
	document.body.appendChild(a);
	a.click();
	window.setTimeout(function() { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
}

function download(path, filename) {
	return fetchFile(path, filename).then(function(blob) { save(blob, filename); });
}

function busy(title, text) {
	ui.showModal(title, [ E('p', { 'class': 'spinning' }, text) ]);
}

var labels = {
	service: { running: _('Running'), stopped: _('Stopped'), disabled: _('Disabled'), error: _('Error') },
	reason: { 'reboot-required': _('an earlier stop of the modem was not confirmed; reboot to use it'),
		'modem-start-failed': _('the modem did not start, also after two automatic restarts; restart the service') },
	md_state: { ready: _('Ready'), booting: _('Starting'), exception: _('Exception'), off: _('Off') },
	sim: { ready: _('Ready'), absent: _('No SIM'), pin: _('PIN required'), puk: _('PUK required'),
		'network-locked': _('Locked to another network (SIM lock)'), busy: _('Not read yet (radio off)'),
		unknown: _('Unknown') },
	reg: { home: _('Registered (home)'), roaming: _('Registered (roaming)'), searching: _('Searching'),
		denied: _('Registration denied'), none: _('Not registered') },
	rat: { lte: 'LTE', nr: '5G NR', umts: 'UMTS', gsm: 'GSM' }
};

function label(group, value) {
	return (value != null && labels[group][value]) ? labels[group][value] : (value || '-');
}

function renderStatus(st) {
	var sim = st.sim || {}, reg = st.registration || {}, sig = st.signal || {}, data = st.data || {};
	var rows = [
		[ _('Service'), st.reason ? '%s: %s'.format(label('service', st.service), label('reason', st.reason)) : label('service', st.service) ],
		[ _('Modem'), label('md_state', st.md_state) ],
		[ _('SIM'), sim.state ? '%s (%s)'.format(label('sim', sim.state),
			sim.slot == 'embedded' ? _('built-in eSIM') : _('SIM slot')) : '-' ],
		[ _('Network'), reg.state ? '%s%s'.format(label('reg', reg.state),
			reg.plmn ? ', %s %s'.format(reg.plmn, label('rat', reg.rat)) : '') : '-' ],
		[ _('Signal'), sig.csq != null ? '%d / 3 (CSQ %d)'.format(sig.level, sig.csq) : '-' ],
		[ _('Data'), data.interface ? '%s: %s%s'.format(data.interface, data.up ? _('up') : _('down'),
			data.device ? ' (%s)'.format(data.device) : '') : E('span', [
				_('No interface uses the "SoftBank Air 6 modem" protocol. Add one under '),
				E('a', { 'href': L.url('admin/network/network') }, _('Interfaces')), '.' ]) ]
	];

	return E('table', { 'class': 'table' }, rows.map(function(r) {
		return E('tr', { 'class': 'tr' }, [
			E('td', { 'class': 'td left', 'width': '33%' }, r[0]),
			E('td', { 'class': 'td left' }, r[1])
		]);
	}));
}

return view.extend({
	load: function() {
		return Promise.all([ callStatus(false), uci.load('air6-modem') ]).then(function(r) { return r[0]; });
	},

	handleBackup: function(ev) {
		busy(_('NV backup'), _('Reading the NV partitions. This takes about a minute.'));
		return runNvJob('backup').then(function(st) {
			var name = 'air6-nv-%s.tar.gz'.format(new Date().toISOString().replace(/[-:]/g, '').substring(0, 15));
			return fetchFile('/tmp/air6-nv/jobs/%s/backup.tar.gz'.format(st.job), name).then(function(blob) {
				return blob.arrayBuffer().then(sha256hex).then(function(sha) {
					/*
					 * Only the user can tell whether the browser saved the file; the router keeps its copy and
					 * the backup counts as done once the user confirms, and only for these bytes.
					 */
					save(blob, name);
					return new Promise(function(resolve, reject) {
						ui.showModal(_('NV backup'), [
							E('p', _('Your browser should have saved %s. Check that the file is in your downloads, then confirm.').format(name)),
							E('div', { 'class': 'right' }, [
								E('button', { 'class': 'btn', 'click': function() { save(blob, name); } }, _('Download again')), ' ',
								E('button', { 'class': 'btn', 'click': function() { reject(new Error(_('not confirmed'))); } }, _('Cancel')), ' ',
								E('button', { 'class': 'btn cbi-button-action important', 'click': function() {
									resolve(callNvBackupDone(st.job, sha));
								} }, _('The file is saved'))
							])
						]);
					});
				});
			}).then(function(res) {
				if (res && res.error)
					throw new Error(res.error);
				ui.hideModal();
				ui.addNotification(null, E('p', _('NV backup saved as %s. Keep this file.').format(name)), 'info');
				window.setTimeout(function() { location.reload(); }, 1500);
			});
		}).catch(function(e) {
			ui.hideModal();
			ui.addNotification(null, E('p', _('NV backup failed: %s').format(e.message)), 'error');
		});
	},

	handleRestore: function(ev) {
		return ui.uploadFile('/tmp/air6-nv-restore.tar.gz', ev.target).then(function() {
			busy(_('NV restore'), _('Checking the archive. This takes about a minute.'));
			return runNvJob('check');
		}).then(function(st) {
			var confirmBtn, confirmInput = E('input', { 'type': 'text', 'class': 'cbi-input-text', 'autocomplete': 'off',
				'input': function() { confirmBtn.disabled = (this.value != 'restore'); } });
			ui.showModal(_('Restore NV partitions?'), [
				E('p', _('The archive is from this unit and intact. Restoring overwrites the NV partitions; ' +
					'the current ones are kept on the router until the next reboot.')),
				E('pre', {}, st.log.split('\n').filter(function(l) { return /^(created|image)=/.test(l); }).join('\n')),
				E('p', _('Type %s to confirm.').format('<code>restore</code>')), confirmInput,
				E('div', { 'class': 'right' }, [
					E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Cancel')), ' ',
					confirmBtn = E('button', { 'class': 'btn cbi-button-negative important', 'disabled': true, 'click': function() {
						if (confirmInput.value != 'restore')
							return;
						busy(_('NV restore'), _('Writing the NV partitions. Do not power off.'));
						return runNvJob('restore', st.job, st.sha256).then(function() {
							ui.showModal(_('NV partitions restored'), [
								E('p', _('Reboot to use them.')),
								E('div', { 'class': 'right' }, [
									E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Later')), ' ',
									E('button', { 'class': 'btn cbi-button-action important', 'click': function() {
										callReboot();
										ui.showModal(_('Rebooting…'), [ E('p', { 'class': 'spinning' }, _('Waiting for the router…')) ]);
										ui.awaitReconnect();
									} }, _('Reboot'))
								])
							]);
						}).catch(function(e) {
							/* The pre-restore copy is offered only when this restore job made it. */
							var before = e.job && e.job.before;
							var known = e.notStarted || (e.job && !/ended without a result/.test(e.job.log || ''));
							ui.showModal(_('NV restore failed'), [
								E('pre', {}, e.message),
								before ? E('p', _('The partitions as they were before this restore are kept on the router until the next reboot.'))
									: E('p', known ? _('Nothing was written.') : _('Whether anything was written is unknown; see the system log.')),
								E('div', { 'class': 'right' }, [
									before ? E('button', { 'class': 'btn', 'click': function() {
										download('/tmp/air6-nv/jobs/%s/before-restore.tar.gz'.format(e.job.job), 'air6-nv-before-restore.tar.gz');
									} }, _('Download them')) : '', ' ',
									E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Close'))
								])
							]);
						});
					} }, _('Restore'))
				])
			]);
		}).catch(function(e) {
			ui.hideModal();
			if (e && e.message)
				ui.addNotification(null, E('p', _('NV restore: %s').format(e.message)), 'error');
		});
	},

	render: function(st) {
		var m, s, o, box = E('div', {}, renderStatus(st));

		poll.add(function() {
			return callStatus(false).then(function(st) {
				box.replaceChildren(renderStatus(st));
			});
		}, 15);

		m = new form.Map('air6-modem', _('Air 6 modem'),
			_('Status and settings of the built-in 5G/LTE modem of the SoftBank Air 6.'));

		s = m.section(form.NamedSection, 'main', 'modem', _('Status'));
		s.render = function() {
			return E('div', { 'class': 'cbi-section' }, [ E('h3', {}, _('Status')), box ]);
		};

		s = m.section(form.NamedSection, 'main', 'modem', _('NV backup'),
			_('The modem writes to NV partitions shared with the stock firmware (calibration, IMEI area). ' +
			  'A backup is required before enabling the modem; keep the file.'));

		o = s.option(form.HiddenValue, 'nv_backup_done');

		o = s.option(form.DummyValue, '_nv_backup', _('Backup'));
		o.cfgvalue = function(section_id) {
			var t = uci.get('air6-modem', section_id, 'nv_backup_time');
			return t ? _('Backed up on %s').format(t) : _('Not backed up yet');
		};

		o = s.option(form.Button, '_nv_backup_btn', ' ');
		o.inputtitle = function(section_id) {
			return uci.get('air6-modem', section_id, 'nv_backup_done') == '1' ? _('Back up again') : _('Back up NV partitions');
		};
		o.inputstyle = 'action';
		o.readonly = (uci.get('air6-modem', 'main', 'enabled') == '1');
		o.description = o.readonly ? _('To back up again, disable the modem and save first.') : null;
		o.onclick = ui.createHandlerFn(this, 'handleBackup');

		o = s.option(form.Button, '_nv_restore_btn', ' ');
		o.inputtitle = _('Restore...');
		o.inputstyle = 'reset';
		o.depends('nv_backup_done', '1');
		o.readonly = (uci.get('air6-modem', 'main', 'enabled') == '1');
		o.description = o.readonly ? _('To restore, disable the modem and save first.') : null;
		o.onclick = ui.createHandlerFn(this, 'handleRestore');

		s = m.section(form.NamedSection, 'main', 'modem', _('Settings'));

		o = s.option(form.Flag, 'enabled', _('Enabled'));
		o.rmempty = false;
		o.readonly = (uci.get('air6-modem', 'main', 'nv_backup_done') != '1');
		o.description = o.readonly ? _('Back up the NV partitions first.') : null;

		o = s.option(form.ListValue, 'sim_slot', _('SIM'),
			_('Applied when the mobile data interface starts.'));
		o.value('auto', _('Automatic (SIM slot if a card is inserted, otherwise built-in eSIM)'));
		o.value('physical', _('SIM slot'));
		o.value('embedded', _('Built-in eSIM'));
		o.default = 'auto';

		o = s.option(form.Flag, 'allow_version_mismatch', _('Allow version mismatch'),
			_('Start even if the stock modem programs do not match the modem firmware of this slot.'));

		return m.render();
	}
});
