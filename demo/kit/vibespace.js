(function (global) {
  'use strict';

  var ORIGIN_CARD_BADGE = {
    yours: 'Yours',
    shared: 'Shared',
    gallery: 'Gallery',
    agent: 'From the agent'
  };

  var ORIGIN_LABEL_SOURCE = {
    yours: 'Made from your wish.',
    shared: 'Shared with you by link.',
    gallery: 'From the gallery.',
    agent: 'Made by the agent.'
  };

  var activeDialogCleanup = null;
  var dialogIdCounter = 0;

  function el(tag, className, text) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined && text !== null) node.textContent = String(text);
    return node;
  }

  function clearNode(node) {
    while (node.firstChild) {
      node.removeChild(node.firstChild);
    }
  }

  function getKit() {
    if (!global.VibeKit) {
      throw new Error('VibeKit is not loaded');
    }
    return global.VibeKit;
  }

  function resolveSpaceStrings(host, opts) {
    var locale = (opts && opts.locale) || (host && host.locale) || 'en';
    var overrides = (opts && opts.strings) || (host && host.strings) || undefined;
    var kit = global.VibeKit;
    if (kit && kit.adapters && typeof kit.adapters.getVibeStrings === 'function') {
      return kit.adapters.getVibeStrings(locale, overrides);
    }
    return {
      locale: locale,
      rtl: false,
      panelTitle: 'Vibe Space',
      whatOffers: 'What {host} offers',
      wishPlaceholder: 'I wish {host} would\u2026',
      send: 'Send',
      wishNote: 'The AI is scripted in this demo. Pick a wish.',
      installed: 'Installed',
      filterPlaceholder: 'Filter installed vibes\u2026',
      emptyInstalled: 'Nothing here yet. Make a wish.',
      sealedLegend: 'Values with a lock are sealed. {host} draws them. The vibe never sees them.',
      portableVibes: 'Portable vibes',
      portableSub: 'These need nothing from the app, so they run anywhere.',
      reads: 'Reads',
      shows: 'Shows',
      cannot: 'Cannot',
      allowAndAdd: 'Allow and add',
      update: 'Update',
      cancel: 'Cancel',
      noNewPermissions: 'Version {version}. No new permissions.',
      inspect: 'Inspect',
      hideInspect: 'Hide inspect',
      share: 'Share',
      edit: 'Edit',
      rename: 'Rename',
      pause: 'Pause',
      resume: 'Resume',
      pinToTop: 'Pin to top',
      unpin: 'Unpin',
      moveUp: 'Move up',
      moveDown: 'Move down',
      revert: 'Revert',
      deleteLabel: 'Delete',
      undo: 'Undo',
      temporary: 'Temporary',
      pinned: 'Pinned',
      pinToVibeSpace: 'Pin to Vibe Space',
      pinnedToVibeSpace: 'Pinned to Vibe Space',
      madeByAgent: 'Made by the agent for this answer'
    };
  }

  function formatStr(template, vars) {
    var out = String(template || '');
    if (!vars) return out;
    var keys = Object.keys(vars);
    for (var i = 0; i < keys.length; i++) {
      out = out.split('{' + keys[i] + '}').join(String(vars[keys[i]]));
    }
    return out;
  }

  function sameNeeds(a, b) {
    var listA = Array.isArray(a) ? a.slice().sort() : [];
    var listB = Array.isArray(b) ? b.slice().sort() : [];
    if (listA.length !== listB.length) return false;
    for (var i = 0; i < listA.length; i++) {
      if (listA[i] !== listB[i]) return false;
    }
    return true;
  }

  function findExistingRecord(host, vibeId, args) {
    var list = host.installed() || [];
    var targetArgs = JSON.stringify(args === undefined ? null : args);
    for (var i = 0; i < list.length; i++) {
      var r = list[i];
      if (!r || !r.vibe || r.vibe.id !== vibeId) continue;
      if (JSON.stringify(r.args === undefined ? null : r.args) === targetArgs) {
        return r;
      }
    }
    return null;
  }

  function clearHashFromAddressBar() {
    if (!global.location || !global.location.hash) return;
    var cleanUrl = global.location.pathname + global.location.search;
    try {
      if (global.history && typeof global.history.replaceState === 'function') {
        global.history.replaceState(null, '', cleanUrl);
        return;
      }
    } catch (_) {
      // Fallback below if history.replaceState is restricted.
    }
    try {
      global.location.hash = '';
    } catch (_) {
      // Ignore if immutable.
    }
  }

  function closeActiveDialog() {
    if (typeof activeDialogCleanup === 'function') {
      var fn = activeDialogCleanup;
      activeDialogCleanup = null;
      fn();
    }
  }

  function openDialog(opts) {
    closeActiveDialog();

    var previousFocus = document.activeElement;
    var titleId = 'vs-dialog-title-' + (++dialogIdCounter);

    var backdrop = el('div', 'vs-dialog-backdrop');
    var dialog = el('div', 'vs-dialog');
    dialog.setAttribute('role', 'dialog');
    dialog.setAttribute('aria-modal', 'true');
    dialog.setAttribute('aria-labelledby', titleId);
    dialog.tabIndex = -1;
    if (opts.dataVs) {
      dialog.setAttribute('data-vs', opts.dataVs);
    }
    if (opts.dir) {
      dialog.setAttribute('dir', opts.dir);
    }

    var header = el('div', 'vs-dialog-header');
    var titleEl = el('h2', 'vs-dialog-title', opts.title || '');
    titleEl.id = titleId;

    var closeBtn = el('button', 'vs-btn vs-btn-ghost vs-dialog-close', '\u00d7');
    closeBtn.type = 'button';
    closeBtn.setAttribute('aria-label', 'Close dialog');

    header.appendChild(titleEl);
    header.appendChild(closeBtn);

    var body = el('div', 'vs-dialog-body');
    if (opts.body) {
      body.appendChild(opts.body);
    }

    dialog.appendChild(header);
    dialog.appendChild(body);
    backdrop.appendChild(dialog);
    document.body.appendChild(backdrop);

    var closed = false;
    function cleanup() {
      if (closed) return;
      closed = true;
      document.removeEventListener('keydown', onKeyDown, true);
      if (backdrop.parentNode) {
        backdrop.parentNode.removeChild(backdrop);
      }
      if (activeDialogCleanup === cleanup) {
        activeDialogCleanup = null;
      }
      if (typeof opts.onClose === 'function') {
        opts.onClose();
      }
      if (previousFocus && typeof previousFocus.focus === 'function' && document.contains(previousFocus)) {
        try {
          previousFocus.focus();
        } catch (_) {
          // Ignore focus errors.
        }
      }
    }

    function onKeyDown(e) {
      if (e.key === 'Escape') {
        e.preventDefault();
        e.stopPropagation();
        cleanup();
      }
    }

    closeBtn.addEventListener('click', cleanup);
    backdrop.addEventListener('click', function (e) {
      if (e.target === backdrop) {
        cleanup();
      }
    });
    document.addEventListener('keydown', onKeyDown, true);

    activeDialogCleanup = cleanup;

    try {
      dialog.focus();
    } catch (_) {
      // Ignore focus errors.
    }

    return { close: cleanup, dialog: dialog, body: body };
  }

  function renderHighlightedJson(preEl, dataObj) {
    clearNode(preEl);

    function appendFormatted(val, depth) {
      if (val === null || typeof val !== 'object') {
        var prim = JSON.stringify(val);
        preEl.appendChild(document.createTextNode(prim === undefined ? 'null' : prim));
        return;
      }
      if (Array.isArray(val)) {
        if (val.length === 0) {
          preEl.appendChild(document.createTextNode('[]'));
          return;
        }
        var childIndent = '  '.repeat(depth + 1);
        var closeIndent = '  '.repeat(depth);
        preEl.appendChild(document.createTextNode('[\n'));
        for (var i = 0; i < val.length; i++) {
          preEl.appendChild(document.createTextNode(childIndent));
          appendFormatted(val[i], depth + 1);
          preEl.appendChild(document.createTextNode(i < val.length - 1 ? ',\n' : '\n'));
        }
        preEl.appendChild(document.createTextNode(closeIndent + ']'));
        return;
      }

      var keys = Object.keys(val).filter(function (k) {
        return val[k] !== undefined;
      });
      if (keys.length === 1 && keys[0] === 'sealed' && typeof val.sealed === 'string') {
        preEl.appendChild(
          el('span', 'vs-inspect-sealed', '{ "sealed": ' + JSON.stringify(val.sealed) + ' }')
        );
        return;
      }
      if (keys.length === 0) {
        preEl.appendChild(document.createTextNode('{}'));
        return;
      }

      var propIndent = '  '.repeat(depth + 1);
      var objCloseIndent = '  '.repeat(depth);
      preEl.appendChild(document.createTextNode('{\n'));
      for (var k = 0; k < keys.length; k++) {
        var key = keys[k];
        preEl.appendChild(document.createTextNode(propIndent + JSON.stringify(key) + ': '));
        appendFormatted(val[key], depth + 1);
        preEl.appendChild(document.createTextNode(k < keys.length - 1 ? ',\n' : '\n'));
      }
      preEl.appendChild(document.createTextNode(objCloseIndent + '}'));
    }

    appendFormatted(dataObj === undefined ? {} : dataObj, 0);
  }

  function createInspectPane(host, getVibe, getRun, onClose) {
    var pane = el('div', 'vs-inspect-pane');
    pane.setAttribute('data-vs', 'inspect-pane');

    var recvSection = el('div', 'vs-inspect-section');
    if (typeof onClose === 'function') {
      var recvHead = el('div', 'vs-inspect-head');
      recvHead.appendChild(el('div', 'vs-inspect-heading', 'What the vibe received'));
      var hideBtn = el('button', 'vs-btn vs-btn-ghost vs-inspect-hide-btn', 'Hide');
      hideBtn.type = 'button';
      hideBtn.addEventListener('click', onClose);
      recvHead.appendChild(hideBtn);
      recvSection.appendChild(recvHead);
    } else {
      recvSection.appendChild(el('div', 'vs-inspect-heading', 'What the vibe received'));
    }
    var jsonPre = el('pre', 'vs-inspect-json');
    recvSection.appendChild(jsonPre);

    var didSection = el('div', 'vs-inspect-section');
    didSection.appendChild(el('div', 'vs-inspect-heading', 'What it did'));
    var ledgerList = el('ul', 'vs-inspect-ledger');
    didSection.appendChild(ledgerList);

    var sealedFootnote = el(
      'p',
      'vs-inspect-note',
      'Values marked sealed are handles. ' + host.name + ' draws the real value. The vibe never sees it.'
    );

    pane.appendChild(recvSection);
    pane.appendChild(didSection);
    pane.appendChild(sealedFootnote);

    function getCapTitles() {
      var map = {};
      try {
        var manifest = host.manifest();
        var caps = (manifest && manifest.capabilities) || [];
        for (var i = 0; i < caps.length; i++) {
          map[caps[i].name] = caps[i].title || caps[i].name;
        }
      } catch (_) {
        // Ignore manifest lookup failures.
      }
      return map;
    }

    function update() {
      var run = typeof getRun === 'function' ? getRun() : null;
      if (!run) {
        jsonPre.textContent = 'Paused — resume to inspect live runs.';
        clearNode(ledgerList);
        return;
      }

      var insp = null;
      var led = null;
      try {
        insp = run.inspect();
      } catch (_) {
        insp = null;
      }
      try {
        led = run.ledger();
      } catch (_) {
        led = null;
      }

      var inputData = insp && insp.input ? insp.input.data : {};
      renderHighlightedJson(jsonPre, inputData);

      clearNode(ledgerList);
      var currentVibe = typeof getVibe === 'function' ? getVibe() : getVibe;
      var capTitles = getCapTitles();
      var reads = (led && led.reads) || {};
      var needs = currentVibe && Array.isArray(currentVibe.needs) ? currentVibe.needs : [];
      var seen = {};
      var capNames = [];
      for (var i = 0; i < needs.length; i++) {
        if (!seen[needs[i]]) {
          seen[needs[i]] = true;
          capNames.push(needs[i]);
        }
      }
      var readKeys = Object.keys(reads);
      for (var j = 0; j < readKeys.length; j++) {
        if (!seen[readKeys[j]]) {
          seen[readKeys[j]] = true;
          capNames.push(readKeys[j]);
        }
      }

      if (capNames.length === 0) {
        ledgerList.appendChild(el('li', 'vs-ledger-item', 'Read nothing from ' + host.name));
      } else {
        for (var k = 0; k < capNames.length; k++) {
          var name = capNames[k];
          var title = capTitles[name] || name;
          var count = typeof reads[name] === 'number' ? reads[name] : 0;
          var line = 'Read ' + title + ' ' + count + (count === 1 ? ' time' : ' times');
          ledgerList.appendChild(el('li', 'vs-ledger-item', line));
        }
      }

      var sentCount = led && typeof led.sent === 'number' ? led.sent : 0;
      var changedCount = led && typeof led.changed === 'number' ? led.changed : 0;
      ledgerList.appendChild(
        el(
          'li',
          'vs-ledger-item',
          sentCount === 0
            ? 'Sent nothing'
            : 'Sent ' + sentCount + (sentCount === 1 ? ' time' : ' times')
        )
      );
      ledgerList.appendChild(
        el(
          'li',
          'vs-ledger-item',
          changedCount === 0
            ? 'Changed nothing'
            : 'Changed ' + changedCount + (changedCount === 1 ? ' time' : ' times')
        )
      );

      if (led && led.lastError) {
        ledgerList.appendChild(el('li', 'vs-ledger-item vs-ledger-error', 'Error: ' + led.lastError));
      }
    }

    update();
    return { element: pane, update: update };
  }

  function appendLabelRows(rowsContainer, lbl) {
    clearNode(rowsContainer);
    function addRow(rowTitle, items, rowKind) {
      var row = el('div', 'vs-label-row vs-label-row-' + rowKind);
      var key = el('div', 'vs-label-key', rowTitle);
      var val = el('div', 'vs-label-val');
      var list = Array.isArray(items) ? items : [];
      if (list.length === 1) {
        val.appendChild(el('div', 'vs-label-item', list[0]));
      } else {
        var ul = el('ul', 'vs-label-list');
        for (var i = 0; i < list.length; i++) {
          ul.appendChild(el('li', 'vs-label-item', list[i]));
        }
        val.appendChild(ul);
      }
      row.appendChild(key);
      row.appendChild(val);
      rowsContainer.appendChild(row);
    }

    addRow('Reads', lbl.reads, 'reads');
    addRow('Shows', lbl.shows, 'shows');
    addRow('Cannot', lbl.cannot, 'cannot');
  }

  function buildLabelCard(host, vibe, opts) {
    var origin = (opts && opts.origin) || 'yours';
    var existing = findExistingRecord(host, vibe.id, opts && opts.args);
    var isSamePermissionUpdate = Boolean(existing && sameNeeds(existing.vibe.needs, vibe.needs));

    var card = el('div', 'vs-label-card');
    card.setAttribute('data-vs', 'label');

    var top = el('div', 'vs-label-top');
    top.appendChild(el('h3', 'vs-label-title', vibe.name));
    var originText = ORIGIN_LABEL_SOURCE[origin] || 'Made from your wish.';
    top.appendChild(el('p', 'vs-label-origin', originText));

    if (isSamePermissionUpdate) {
      top.appendChild(
        el('p', 'vs-label-update-note', 'Version ' + vibe.version + '. No new permissions.')
      );
    }

    card.appendChild(top);

    var lbl = host.label(vibe);
    var rows = el('div', 'vs-label-rows');
    appendLabelRows(rows, lbl);
    card.appendChild(rows);

    var metaFields = el('div', 'vs-label-meta-fields');

    var titleWrap = el('label', 'vs-field');
    titleWrap.appendChild(el('span', 'vs-field-label', 'Title'));
    var titleInput = el('input', 'vs-input');
    titleInput.type = 'text';
    titleInput.maxLength = 120;
    titleInput.setAttribute('data-vs', 'label-title-input');
    titleInput.value =
      (opts && opts.defaultTitle) ||
      (existing && existing.title) ||
      vibe.name;
    titleWrap.appendChild(titleInput);

    var noteWrap = el('label', 'vs-field');
    noteWrap.appendChild(el('span', 'vs-field-label', 'Note'));
    var noteInput = el('input', 'vs-input');
    noteInput.type = 'text';
    noteInput.maxLength = 280;
    noteInput.placeholder = 'Optional note (e.g. why you pinned this)';
    noteInput.setAttribute('data-vs', 'label-note-input');
    noteInput.value =
      opts && opts.defaultNote !== undefined
        ? opts.defaultNote
        : ((existing && existing.note) || '');
    noteWrap.appendChild(noteInput);

    metaFields.appendChild(titleWrap);
    metaFields.appendChild(noteWrap);
    card.appendChild(metaFields);

    var actions = el('div', 'vs-label-actions');
    var allowBtn = el(
      'button',
      'vs-btn vs-btn-primary',
      isSamePermissionUpdate ? 'Update' : 'Allow and add'
    );
    allowBtn.type = 'button';
    allowBtn.setAttribute('data-vs', 'label-allow');

    var cancelBtn = el('button', 'vs-btn vs-btn-secondary', 'Cancel');
    cancelBtn.type = 'button';
    cancelBtn.setAttribute('data-vs', 'label-cancel');

    allowBtn.addEventListener('click', function () {
      if (opts && typeof opts.onAllow === 'function') {
        var cleanTitle = titleInput.value.trim() || vibe.name;
        var cleanNote = noteInput.value.trim();
        opts.onAllow(vibe, { title: cleanTitle, note: cleanNote });
      }
    });
    cancelBtn.addEventListener('click', function () {
      if (opts && typeof opts.onCancel === 'function') {
        opts.onCancel();
      }
    });

    actions.appendChild(allowBtn);
    actions.appendChild(cancelBtn);
    card.appendChild(actions);

    return card;
  }

  function openShareDialog(host, vibe, shareTargets) {
    var kit = getKit();
    var encoded = kit.share.encode(vibe);
    var hash = '#vibe=' + encoded;
    var baseUrl = (global.location && global.location.href ? global.location.href : '').split('#')[0];
    var fullLink = baseUrl + hash;

    var body = el('div', 'vs-share-body');

    var linkWrap = el('div', 'vs-share-link-row');
    var linkInput = el('input', 'vs-input vs-share-input');
    linkInput.type = 'text';
    linkInput.readOnly = true;
    linkInput.value = fullLink;
    linkInput.setAttribute('aria-label', 'Share link');
    linkInput.setAttribute('data-vs', 'share-link');

    var copyBtn = el('button', 'vs-btn vs-btn-primary', 'Copy link');
    copyBtn.type = 'button';
    copyBtn.setAttribute('data-vs', 'share-copy');

    var copyTimer = null;
    copyBtn.addEventListener('click', function () {
      var markCopied = function () {
        copyBtn.textContent = 'Copied';
        if (copyTimer) clearTimeout(copyTimer);
        copyTimer = setTimeout(function () {
          copyBtn.textContent = 'Copy link';
        }, 1800);
      };

      if (navigator.clipboard && typeof navigator.clipboard.writeText === 'function') {
        navigator.clipboard.writeText(fullLink).then(markCopied, function () {
          fallbackCopy();
          markCopied();
        });
      } else {
        fallbackCopy();
        markCopied();
      }

      function fallbackCopy() {
        try {
          linkInput.focus();
          linkInput.select();
          document.execCommand('copy');
        } catch (_) {
          // Ignore copy fallback failure.
        }
      }
    });

    linkWrap.appendChild(linkInput);
    linkWrap.appendChild(copyBtn);
    body.appendChild(linkWrap);

    body.appendChild(
      el('p', 'vs-share-note', 'Grants do not travel. Whoever opens the link sees the label and decides.')
    );

    var targets = Array.isArray(shareTargets) ? shareTargets : [];
    if (targets.length > 0) {
      var targetRow = el('div', 'vs-share-targets');
      for (var i = 0; i < targets.length; i++) {
        (function (target) {
          var targetBtn = el('button', 'vs-btn vs-btn-secondary', target.label);
          targetBtn.type = 'button';
          targetBtn.setAttribute('data-vs', 'share-target');
          targetBtn.addEventListener('click', function () {
            var targetBase = String(target.url || '').split('#')[0];
            global.open(targetBase + hash, '_blank');
          });
          targetRow.appendChild(targetBtn);
        })(targets[i]);
      }
      body.appendChild(targetRow);
    }

    openDialog({
      title: 'Share ' + vibe.name,
      body: body,
      onClose: function () {
        if (copyTimer) clearTimeout(copyTimer);
      }
    });
  }

  function showOffer(host, options) {
    var strings = resolveSpaceStrings(host, options);
    var manifest = host.manifest();
    var body = el('div', 'vs-offer-body');

    var offeredSection = el('section', 'vs-offer-section');
    offeredSection.appendChild(el('h3', 'vs-offer-heading', 'Offered'));

    var caps = (manifest && manifest.capabilities) || [];
    for (var i = 0; i < caps.length; i++) {
      var cap = caps[i];
      var capCard = el('div', 'vs-offer-cap');

      var capHead = el('div', 'vs-offer-cap-head');
      capHead.appendChild(el('span', 'vs-offer-cap-title', cap.title || cap.name));
      capHead.appendChild(el('code', 'vs-mono vs-offer-cap-name', cap.name));
      capCard.appendChild(capHead);

      var fieldsWrap = el('div', 'vs-offer-fields');
      var fields = cap.fields || {};
      var fieldNames = Object.keys(fields);
      for (var j = 0; j < fieldNames.length; j++) {
        var fName = fieldNames[j];
        var fMode = fields[fName] === 'sealed' ? 'sealed' : 'public';
        var fieldRow = el('span', 'vs-offer-field');
        fieldRow.appendChild(el('code', 'vs-mono vs-offer-field-name', fName));
        fieldRow.appendChild(el('span', 'vs-chip vs-chip-' + fMode, fMode));
        fieldsWrap.appendChild(fieldRow);
      }
      capCard.appendChild(fieldsWrap);
      offeredSection.appendChild(capCard);
    }
    body.appendChild(offeredSection);

    var notOfferedSection = el('section', 'vs-offer-section');
    notOfferedSection.appendChild(el('h3', 'vs-offer-heading', 'Not offered'));
    var notList = el('ul', 'vs-offer-not-list');
    var notOffered = (manifest && manifest.notOffered) || [];
    for (var k = 0; k < notOffered.length; k++) {
      notList.appendChild(el('li', 'vs-offer-not-item', notOffered[k]));
    }
    notOfferedSection.appendChild(notList);
    body.appendChild(notOfferedSection);

    var details = el('details', 'vs-offer-manifest');
    details.appendChild(el('summary', 'vs-offer-manifest-summary', 'Manifest (what an AI reads)'));
    var pre = el('pre', 'vs-code-block');
    pre.appendChild(el('code', 'vs-mono', JSON.stringify(manifest, null, 2)));
    details.appendChild(pre);
    body.appendChild(details);

    openDialog({
      title: formatStr(strings.whatOffers, { host: host.name }),
      dataVs: 'offer-dialog',
      dir: strings.rtl ? 'rtl' : null,
      body: body
    });
  }

  function parseCountWord(str) {
    var map = {
      one: 1,
      two: 2,
      three: 3,
      four: 4,
      five: 5,
      six: 6,
      seven: 7,
      eight: 8,
      nine: 9,
      ten: 10
    };
    var lower = String(str || '').toLowerCase();
    if (map[lower] !== undefined) return map[lower];
    var num = parseInt(lower, 10);
    return Number.isFinite(num) ? num : null;
  }

  function buildRemixSuggestions(vibe, hostWishes) {
    var suggestions = [];
    var seen = {};
    function pushUnique(text, scriptedVibe) {
      var key = String(text || '').trim().toLowerCase();
      if (!key || seen[key]) return;
      seen[key] = true;
      suggestions.push({ text: text, scriptedVibe: scriptedVibe || null });
    }

    var list = Array.isArray(hostWishes) ? hostWishes : [];
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].remixOf === vibe.id && list[i].vibe) {
        pushUnique(list[i].text, list[i].vibe);
      }
    }

    var src = vibe.source || '';
    if (vibe.id === 'disk-watch' || src.indexOf('usedFraction') !== -1) {
      pushUnique('Make it red above 70% and show only the worst 3');
      pushUnique('Show top 4 volumes, red above 85%');
    } else if (vibe.id === 'server-load' || src.indexOf('telemetry.load') !== -1) {
      pushUnique('Make CPU red above 75%');
      pushUnique('Make CPU red above 90%');
    } else if (vibe.id === 'top-posts' || src.indexOf('posts.mine') !== -1) {
      pushUnique('Show my top 3 posts from the last 14 days');
      pushUnique('Show my top 5 posts from the last 60 days');
    } else if (vibe.id === 'top-fans' || src.indexOf('likes.byFollower') !== -1) {
      pushUnique('Show my top 3 fans');
      pushUnique('Show my top 8 fans');
    } else if (vibe.id === 'focus-timer' || src.indexOf('DURATION_MIN') !== -1) {
      pushUnique('Make it a 10-minute timer');
      pushUnique('Make it a 45-minute timer');
    } else if (vibe.id === 'subscription-watch' || src.indexOf('transactions.recent') !== -1) {
      pushUnique('Flag recurring charges above $15/mo');
      pushUnique('Make it red above 90% and show only the worst 3');
    } else if (vibe.id === 'account-watch' || src.indexOf('accounts.cashflow') !== -1) {
      pushUnique('Warn when budget passes 75%');
      pushUnique('Warn when budget passes 90%');
    } else if (vibe.id === 'vip-sla' || src.indexOf('threads.waiting') !== -1) {
      pushUnique('Flag VIP threads waiting more than 4 hours');
      pushUnique('Show top 3 waiting VIP threads over 2 hours');
    } else if (vibe.id === 'newsletter-cleanup' || src.indexOf('senders.newsletters') !== -1) {
      pushUnique('Show senders opened less than 15% of the time');
      pushUnique('Show only the top 3 clutter senders');
    } else if (vibe.id === 'deal-radar' || src.indexOf('wishlist.deals') !== -1) {
      pushUnique('Show only the top 3 deals at 25% off or better');
      pushUnique('Highlight wishlist items at least 30% below typical price');
    } else if (vibe.id === 'item-price-watch' || src.indexOf('orders.deliveries') !== -1) {
      pushUnique('Flag deals at least 20% below typical price');
    }

    return suggestions;
  }

  function applyWishRemix(baseVibe, promptText, hostWishes) {
    var trimmed = String(promptText || '').trim();
    if (!trimmed) {
      return { ok: false, message: 'Enter a remix request or pick a suggestion chip.' };
    }

    var lower = trimmed.toLowerCase();
    var list = Array.isArray(hostWishes) ? hostWishes : [];
    for (var i = 0; i < list.length; i++) {
      var w = list[i];
      if (w && w.remixOf === baseVibe.id && w.vibe && w.text.trim().toLowerCase() === lower) {
        return {
          ok: true,
          vibe: {
            id: baseVibe.id,
            name: w.vibe.name || baseVibe.name,
            wish: trimmed,
            version: (baseVibe.version || 1) + 1,
            needs: (w.vibe.needs || baseVibe.needs || []).slice(),
            refresh: w.vibe.refresh !== undefined ? w.vibe.refresh : baseVibe.refresh,
            source: w.vibe.source
          }
        };
      }
    }

    var nextSource = String(baseVibe.source || '');
    var changed = false;

    // 1. Threshold percentage (e.g. "70%", "red above 85%")
    var pctMatch = trimmed.match(/\b(\d{1,2})\s*%/);
    if (!pctMatch) {
      pctMatch = trimmed.match(/(?:above|over|at)\s*(\d{1,2})\b/i);
    }
    if (pctMatch) {
      var pct = parseInt(pctMatch[1], 10);
      if (pct >= 1 && pct <= 99) {
        var fracStr = String(pct / 100);
        var updated = nextSource;
        if (/var\s+(?:THRESHOLD|DANGER_LEVEL|MIN_DISCOUNT)\s*=\s*0\.\d+\s*;/.test(updated)) {
          updated = updated.replace(/var\s+THRESHOLD\s*=\s*0\.\d+\s*;/g, 'var THRESHOLD = ' + fracStr + ';');
          updated = updated.replace(/var\s+DANGER_LEVEL\s*=\s*0\.\d+\s*;/g, 'var DANGER_LEVEL = ' + fracStr + ';');
          updated = updated.replace(/var\s+MIN_DISCOUNT\s*=\s*0\.\d+\s*;/g, 'var MIN_DISCOUNT = ' + fracStr + ';');
          updated = updated.replace(/\b(?:below|above|over|under|at)\s+\d+%/gi, function (m) {
            return m.replace(/\d+%/, pct + '%');
          });
        } else {
          updated = updated.replace(/(if\s*\([^)]*usedFraction\s*>=\s*)0\.\d+/g, '$1' + fracStr);
          updated = updated.replace(/(usedFraction\s*>=\s*)0\.\d+(\s*\?\s*'danger')/g, '$1' + fracStr + '$2');
          updated = updated.replace(/volumes above \d+%/g, 'volumes above ' + pct + '%');
          updated = updated.replace(
            /if\s*\(\s*val\s*>=\s*0\.\d+\s*\)\s*return\s*'danger'/g,
            "if (val >= " + fracStr + ") return 'danger'"
          );
        }
        if (updated !== nextSource) {
          nextSource = updated;
          changed = true;
        }
      }
    }

    // 2. Count / top-N / worst-N limit
    var countMatch = trimmed.match(
      /(?:top|worst|only(?:\s+the\s+worst)?|show(?:\s+only)?)\s+(\d+|one|two|three|four|five|six|seven|eight|nine|ten)\b/i
    );
    if (countMatch) {
      var limit = parseCountWord(countMatch[1]);
      if (limit !== null && limit >= 1 && limit <= 50) {
        var beforeCount = nextSource;
        if (/var\s+TOP_LIMIT\s*=\s*\d+\s*;/.test(nextSource)) {
          nextSource = nextSource.replace(/var\s+TOP_LIMIT\s*=\s*\d+\s*;/g, 'var TOP_LIMIT = ' + limit + ';');
        } else if (/\.slice\(\s*0\s*,\s*\d+\s*\)/.test(nextSource)) {
          nextSource = nextSource.replace(/\.slice\(\s*0\s*,\s*\d+\s*\)/g, '.slice(0, ' + limit + ')');
        } else if (nextSource.indexOf('var sorted = rows.slice()') !== -1 && /sorted\.length\s*;\s*j\+\+/.test(nextSource)) {
          nextSource = nextSource.replace(
            /for\s*\(\s*var\s+j\s*=\s*0\s*;\s*j\s*<\s*sorted\.length\s*;\s*j\+\+\s*\)\s*\{/,
            'var worst = sorted.slice(0, ' + limit + ');\n      for (var j = 0; j < worst.length; j++) {'
          );
          nextSource = nextSource.replace(/var\s+row\s*=\s*sorted\[j\]\s*;/, 'var row = worst[j];');
        }
        nextSource = nextSource.replace(/Disk usage(?: \\u00b7| ·)? worst (?:three|\d+)/g, 'Disk usage · worst ' + limit);
        if (nextSource.indexOf("heading', text: 'Disk usage'") !== -1) {
          nextSource = nextSource.replace("heading', text: 'Disk usage'", "heading', text: 'Disk usage · worst " + limit + "'");
        }
        if (nextSource !== beforeCount) {
          changed = true;
        }
      }
    }

    // 3. Focus timer duration (e.g. "10-minute", "45 min")
    var minMatch = trimmed.match(/\b(\d{1,3})\s*(?:-|\s)?(?:minutes?|mins?|m)\b/i);
    if (minMatch) {
      var mins = parseInt(minMatch[1], 10);
      if (mins >= 1 && mins <= 180) {
        var beforeMin = nextSource;
        nextSource = nextSource.replace(/var\s+DURATION_MIN\s*=\s*\d+\s*;/g, 'var DURATION_MIN = ' + mins + ';');
        nextSource = nextSource.replace(/var\s+DURATION\s*=\s*\d+\s*\*\s*60\s*\*\s*1000\s*;/g, 'var DURATION = ' + mins + ' * 60 * 1000;');
        if (nextSource !== beforeMin) {
          changed = true;
        }
      }
    }

    // 4. Time window in days (e.g. "14 days", "60 days")
    var dayMatch = trimmed.match(/\b(\d{1,3})\s*days?\b/i);
    if (dayMatch) {
      var days = parseInt(dayMatch[1], 10);
      if (days >= 1 && days <= 365) {
        var beforeDays = nextSource;
        nextSource = nextSource.replace(/var\s+WINDOW_DAYS\s*=\s*\d+\s*;/g, 'var WINDOW_DAYS = ' + days + ';');
        nextSource = nextSource.replace(/now\s*-\s*\d+\s*\*\s*dayMs/g, 'now - ' + days + ' * dayMs');
        nextSource = nextSource.replace(/last \d+ days/g, 'last ' + days + ' days');
        if (nextSource !== beforeDays) {
          changed = true;
        }
      }
    }

    // 5. Dollar threshold (e.g. "$15", "$25/mo", "above $30")
    var usdMatch = trimmed.match(/\$\s*(\d+(?:\.\d+)?)/);
    if (usdMatch) {
      var usdVal = parseFloat(usdMatch[1]);
      if (Number.isFinite(usdVal) && usdVal > 0 && usdVal <= 100000) {
        var beforeUsd = nextSource;
        if (/var\s+AMOUNT_LIMIT\s*=\s*\d+(?:\.\d+)?\s*;/.test(nextSource)) {
          nextSource = nextSource.replace(
            /var\s+AMOUNT_LIMIT\s*=\s*\d+(?:\.\d+)?\s*;/g,
            'var AMOUNT_LIMIT = ' + usdVal + ';'
          );
        }
        nextSource = nextSource.replace(/\$\d+(?:\.\d+)?\/mo/g, '$' + usdVal + '/mo');
        if (nextSource !== beforeUsd) {
          changed = true;
        }
      }
    }

    // 6. SLA hours (e.g. "4 hours", "2 hrs", "6h")
    var hourMatch = trimmed.match(/\b(\d{1,3})\s*(?:-|\s)?(?:hours?|hrs?|h)\b/i);
    if (hourMatch) {
      var hrs = parseInt(hourMatch[1], 10);
      if (hrs >= 1 && hrs <= 720) {
        var beforeHrs = nextSource;
        if (/var\s+SLA_HOURS\s*=\s*\d+\s*;/.test(nextSource)) {
          nextSource = nextSource.replace(/var\s+SLA_HOURS\s*=\s*\d+\s*;/g, 'var SLA_HOURS = ' + hrs + ';');
        }
        nextSource = nextSource.replace(/\b\d+\s*h(?:\+|ours?)\b/gi, hrs + 'h');
        if (nextSource !== beforeHrs) {
          changed = true;
        }
      }
    }

    if (!changed) {
      return {
        ok: false,
        message: 'Try specifying a threshold (e.g. 75%, $15), count (e.g. top 3), hours (e.g. 4 hours), days (e.g. 14 days), or minutes (e.g. 10 min) — or use Edit code.'
      };
    }

    return {
      ok: true,
      vibe: {
        id: baseVibe.id,
        name: baseVibe.name,
        wish: trimmed,
        version: (baseVibe.version || 1) + 1,
        needs: (baseVibe.needs || []).slice(),
        refresh: baseVibe.refresh,
        source: nextSource
      }
    };
  }

  function openEditDialog(host, record, hostWishes, focusTarget) {
    var kit = getKit();
    var baseVibe = record.vibe;
    var instanceId = record.instanceId || baseVibe.id;

    var draftVibe = {
      id: baseVibe.id,
      name: baseVibe.name,
      wish: baseVibe.wish || '',
      version: baseVibe.version || 1,
      needs: Array.isArray(baseVibe.needs) ? baseVibe.needs.slice() : [],
      refresh: baseVibe.refresh,
      source: baseVibe.source || ''
    };
    var hasCodeOrSpecChanges = false;
    var activeTestRun = null;

    function stopTestRun() {
      if (activeTestRun) {
        try {
          activeTestRun.stop();
        } catch (_) {
          // Ignore stop errors.
        }
        activeTestRun = null;
      }
    }

    var body = el('div', 'vs-edit-body');

    // Title & Note
    var metaGrid = el('div', 'vs-edit-meta-grid');
    var titleField = el('label', 'vs-field');
    titleField.appendChild(el('span', 'vs-field-label', 'Title'));
    var titleInput = el('input', 'vs-input');
    titleInput.type = 'text';
    titleInput.maxLength = 120;
    titleInput.setAttribute('data-vs', 'edit-title-input');
    titleInput.value = record.title || baseVibe.name;
    titleField.appendChild(titleInput);

    var noteField = el('label', 'vs-field');
    noteField.appendChild(el('span', 'vs-field-label', 'Note'));
    var noteInput = el('input', 'vs-input');
    noteInput.type = 'text';
    noteInput.maxLength = 280;
    noteInput.placeholder = 'Optional note';
    noteInput.setAttribute('data-vs', 'edit-note-input');
    noteInput.value = record.note || '';
    noteField.appendChild(noteInput);

    metaGrid.appendChild(titleField);
    metaGrid.appendChild(noteField);
    body.appendChild(metaGrid);

    // Tabs
    var tabBar = el('div', 'vs-edit-tabs');
    tabBar.setAttribute('role', 'tablist');

    var wishTabBtn = el('button', 'vs-btn vs-edit-tab is-active', 'Remix by wish');
    wishTabBtn.type = 'button';
    wishTabBtn.setAttribute('role', 'tab');
    wishTabBtn.setAttribute('aria-selected', 'true');
    wishTabBtn.setAttribute('data-vs', 'edit-tab-wish');

    var codeTabBtn = el('button', 'vs-btn vs-edit-tab', 'Edit code');
    codeTabBtn.type = 'button';
    codeTabBtn.setAttribute('role', 'tab');
    codeTabBtn.setAttribute('aria-selected', 'false');
    codeTabBtn.setAttribute('data-vs', 'edit-tab-code');

    tabBar.appendChild(wishTabBtn);
    tabBar.appendChild(codeTabBtn);
    body.appendChild(tabBar);

    // Tab 1: Remix by wish
    var wishPane = el('div', 'vs-edit-pane');
    if (baseVibe.wish) {
      wishPane.appendChild(el('p', 'vs-edit-current-wish', 'Current wish: \u201c' + baseVibe.wish + '\u201d'));
    }

    var wishRow = el('div', 'vs-edit-wish-row');
    var wishInput = el('input', 'vs-input');
    wishInput.type = 'text';
    wishInput.placeholder = 'Describe how to adjust this vibe\u2026';
    wishInput.setAttribute('data-vs', 'edit-wish-input');

    var wishRunBtn = el('button', 'vs-btn vs-btn-secondary', 'Preview change');
    wishRunBtn.type = 'button';
    wishRunBtn.setAttribute('data-vs', 'edit-wish-run');

    wishRow.appendChild(wishInput);
    wishRow.appendChild(wishRunBtn);
    wishPane.appendChild(wishRow);

    var wishChipsWrap = el('div', 'vs-wish-chips');
    var suggestions = buildRemixSuggestions(baseVibe, hostWishes);
    for (var s = 0; s < suggestions.length; s++) {
      (function (sug) {
        var chip = el('button', 'vs-chip-btn', sug.text);
        chip.type = 'button';
        chip.addEventListener('click', function () {
          wishInput.value = sug.text;
          runWishRemix(sug.text);
        });
        wishChipsWrap.appendChild(chip);
      })(suggestions[s]);
    }
    wishPane.appendChild(wishChipsWrap);

    var wishStatus = el('p', 'vs-edit-status');
    wishStatus.hidden = true;
    wishPane.appendChild(wishStatus);
    body.appendChild(wishPane);

    // Tab 2: Edit code
    var codePane = el('div', 'vs-edit-pane');
    codePane.hidden = true;

    var needsField = el('div', 'vs-field');
    needsField.appendChild(el('span', 'vs-field-label', 'Capabilities needed'));
    var needsWrap = el('div', 'vs-edit-needs-list');
    var manifestCaps = [];
    try {
      var m = host.manifest();
      manifestCaps = (m && m.capabilities) || [];
    } catch (_) {
      manifestCaps = [];
    }

    var capCheckboxes = [];
    var capSeen = {};
    function addNeedCheckbox(capName, titleText, isMissing) {
      if (capSeen[capName]) return;
      capSeen[capName] = true;
      var lbl = el('label', 'vs-checkbox-label');
      var cb = document.createElement('input');
      cb.type = 'checkbox';
      cb.value = capName;
      cb.checked = draftVibe.needs.indexOf(capName) !== -1;
      cb.setAttribute('data-vs', 'edit-needs-checkbox');
      lbl.appendChild(cb);
      lbl.appendChild(el('code', 'vs-mono', capName));
      if (titleText) {
        lbl.appendChild(el('span', 'vs-checkbox-desc', isMissing ? ' (not offered)' : ' \u2014 ' + titleText));
      }
      cb.addEventListener('change', syncFromCodeInputs);
      needsWrap.appendChild(lbl);
      capCheckboxes.push(cb);
    }

    for (var c = 0; c < manifestCaps.length; c++) {
      addNeedCheckbox(manifestCaps[c].name, manifestCaps[c].title, false);
    }
    for (var n = 0; n < draftVibe.needs.length; n++) {
      addNeedCheckbox(draftVibe.needs[n], '', true);
    }
    if (capCheckboxes.length === 0) {
      needsWrap.appendChild(el('span', 'vs-muted-inline', 'No capabilities offered by this host.'));
    }
    needsField.appendChild(needsWrap);
    codePane.appendChild(needsField);

    var refreshField = el('label', 'vs-field');
    refreshField.appendChild(el('span', 'vs-field-label', 'Refresh interval (ms, min 500 or blank)'));
    var refreshInput = el('input', 'vs-input');
    refreshInput.type = 'number';
    refreshInput.min = '500';
    refreshInput.step = '100';
    refreshInput.placeholder = 'Optional (e.g. 2000)';
    refreshInput.setAttribute('data-vs', 'edit-refresh-input');
    refreshInput.value = draftVibe.refresh ? String(draftVibe.refresh) : '';
    refreshInput.addEventListener('input', syncFromCodeInputs);
    refreshField.appendChild(refreshInput);
    codePane.appendChild(refreshField);

    var sourceField = el('label', 'vs-field');
    sourceField.appendChild(el('span', 'vs-field-label', 'Source (runs in Worker sandbox)'));
    var sourceInput = el('textarea', 'vs-textarea vs-mono');
    sourceInput.rows = 8;
    sourceInput.spellcheck = false;
    sourceInput.setAttribute('data-vs', 'edit-source-input');
    sourceInput.value = draftVibe.source;
    sourceInput.addEventListener('input', syncFromCodeInputs);
    sourceField.appendChild(sourceInput);
    codePane.appendChild(sourceField);

    var testRow = el('div', 'vs-edit-test-row');
    var testBtn = el('button', 'vs-btn vs-btn-secondary', 'Test in sandbox');
    testBtn.type = 'button';
    testBtn.setAttribute('data-vs', 'edit-test-btn');
    testRow.appendChild(testBtn);
    codePane.appendChild(testRow);

    body.appendChild(codePane);

    // Live sandbox preview
    var previewSection = el('div', 'vs-edit-preview-wrap');
    previewSection.appendChild(el('div', 'vs-preview-title', 'Sandbox preview'));
    var previewBox = el('div', 'vs-edit-preview');
    previewBox.setAttribute('data-vs', 'edit-preview');
    previewSection.appendChild(previewBox);
    body.appendChild(previewSection);

    // Permission status + diff + save
    var permNote = el('p', 'vs-edit-perm-note');
    body.appendChild(permNote);

    var labelDiff = el('div', 'vs-label-card vs-edit-label-diff');
    labelDiff.setAttribute('data-vs', 'edit-label-diff');
    labelDiff.hidden = true;
    var labelDiffRows = el('div', 'vs-label-rows');
    labelDiff.appendChild(labelDiffRows);
    body.appendChild(labelDiff);

    var editError = el('div', 'vs-inline-error');
    editError.hidden = true;
    body.appendChild(editError);

    var footerActions = el('div', 'vs-label-actions');
    var saveBtn = el('button', 'vs-btn vs-btn-primary', 'Save changes');
    saveBtn.type = 'button';
    saveBtn.setAttribute('data-vs', 'edit-save');

    var cancelBtn = el('button', 'vs-btn vs-btn-secondary', 'Cancel');
    cancelBtn.type = 'button';

    footerActions.appendChild(saveBtn);
    footerActions.appendChild(cancelBtn);
    body.appendChild(footerActions);

    function computeCodeChanged(candidate) {
      return (
        candidate.source !== baseVibe.source ||
        !sameNeeds(candidate.needs, baseVibe.needs) ||
        (candidate.refresh || null) !== (baseVibe.refresh || null) ||
        (candidate.wish || '') !== (baseVibe.wish || '')
      );
    }

    function computeAddedNeeds(candidateNeeds) {
      var orig = Array.isArray(baseVibe.needs) ? baseVibe.needs : [];
      var added = [];
      for (var i = 0; i < candidateNeeds.length; i++) {
        if (orig.indexOf(candidateNeeds[i]) === -1) {
          added.push(candidateNeeds[i]);
        }
      }
      return added;
    }

    function updatePermissionSummary(candidate) {
      var codeChanged = computeCodeChanged(candidate);
      hasCodeOrSpecChanges = codeChanged;
      var added = computeAddedNeeds(candidate.needs);
      var nextVer = codeChanged ? (baseVibe.version || 1) + 1 : (baseVibe.version || 1);

      if (added.length > 0) {
        permNote.textContent =
          'Version ' + nextVer + ' adds capability access: ' + added.join(', ') + '.';
        permNote.classList.add('is-warning');
        try {
          appendLabelRows(labelDiffRows, host.label(candidate));
          labelDiff.hidden = false;
        } catch (_) {
          labelDiff.hidden = true;
        }
        saveBtn.textContent = 'Allow & save';
      } else {
        permNote.classList.remove('is-warning');
        labelDiff.hidden = true;
        if (codeChanged) {
          permNote.textContent = 'Version ' + nextVer + '. No new permissions.';
        } else {
          permNote.textContent = 'No permission changes.';
        }
        saveBtn.textContent = 'Save changes';
      }
    }

    function pushDraftToCodeInputs(candidate) {
      draftVibe = {
        id: candidate.id,
        name: candidate.name,
        wish: candidate.wish || '',
        version: candidate.version,
        needs: (candidate.needs || []).slice(),
        refresh: candidate.refresh,
        source: candidate.source
      };
      for (var i = 0; i < capCheckboxes.length; i++) {
        capCheckboxes[i].checked = draftVibe.needs.indexOf(capCheckboxes[i].value) !== -1;
      }
      refreshInput.value = draftVibe.refresh ? String(draftVibe.refresh) : '';
      sourceInput.value = draftVibe.source;
      updatePermissionSummary(draftVibe);
    }

    function readCandidateFromCodeInputs() {
      var selectedNeeds = [];
      for (var i = 0; i < capCheckboxes.length; i++) {
        if (capCheckboxes[i].checked) {
          selectedNeeds.push(capCheckboxes[i].value);
        }
      }
      var rawRefresh = refreshInput.value.trim();
      var nextRefresh;
      if (rawRefresh !== '') {
        nextRefresh = Number(rawRefresh);
      }
      var candidate = {
        id: baseVibe.id,
        name: baseVibe.name,
        wish: draftVibe.wish,
        version: baseVibe.version || 1,
        needs: selectedNeeds,
        source: sourceInput.value
      };
      if (nextRefresh !== undefined) {
        candidate.refresh = nextRefresh;
      }
      if (computeCodeChanged(candidate)) {
        candidate.version = (baseVibe.version || 1) + 1;
      }
      return candidate;
    }

    function syncFromCodeInputs() {
      editError.hidden = true;
      var candidate = readCandidateFromCodeInputs();
      draftVibe = candidate;
      updatePermissionSummary(candidate);
    }

    function runSandboxPreview(candidate) {
      stopTestRun();
      clearNode(previewBox);
      editError.hidden = true;
      try {
        kit.validate(candidate);
      } catch (err) {
        previewBox.appendChild(
          el('div', 'vk-error', err && err.message ? err.message : 'Invalid vibe')
        );
        return false;
      }
      var chk = host.check(candidate);
      if (!chk || !chk.ok) {
        previewBox.appendChild(
          el(
            'div',
            'vk-error',
            'Missing capabilities: ' + ((chk && chk.missing) || []).join(', ')
          )
        );
        return false;
      }
      var mode = 'sample';
      if (typeof host.sourceStatus === 'function') {
        try {
          if (host.sourceStatus(candidate).state === 'ok') {
            mode = 'live';
          }
        } catch (_) {
          mode = 'sample';
        }
      }
      try {
        activeTestRun = host.mount(candidate, previewBox, {
          data: mode,
          args: record.args
        });
        return true;
      } catch (err) {
        previewBox.appendChild(
          el('div', 'vk-error', err && err.message ? err.message : 'Preview failed')
        );
        return false;
      }
    }

    function runWishRemix(promptText) {
      wishStatus.hidden = true;
      editError.hidden = true;
      var res = applyWishRemix(draftVibe, promptText, hostWishes);
      if (!res.ok) {
        wishStatus.textContent = res.message;
        wishStatus.hidden = false;
        return;
      }
      pushDraftToCodeInputs(res.vibe);
      runSandboxPreview(res.vibe);
    }

    wishTabBtn.addEventListener('click', function () {
      wishTabBtn.classList.add('is-active');
      wishTabBtn.setAttribute('aria-selected', 'true');
      codeTabBtn.classList.remove('is-active');
      codeTabBtn.setAttribute('aria-selected', 'false');
      wishPane.hidden = false;
      codePane.hidden = true;
    });

    codeTabBtn.addEventListener('click', function () {
      codeTabBtn.classList.add('is-active');
      codeTabBtn.setAttribute('aria-selected', 'true');
      wishTabBtn.classList.remove('is-active');
      wishTabBtn.setAttribute('aria-selected', 'false');
      codePane.hidden = false;
      wishPane.hidden = true;
    });

    wishRunBtn.addEventListener('click', function () {
      runWishRemix(wishInput.value);
    });

    wishInput.addEventListener('keydown', function (e) {
      if (e.key === 'Enter') {
        e.preventDefault();
        runWishRemix(wishInput.value);
      }
    });

    testBtn.addEventListener('click', function () {
      var candidate = readCandidateFromCodeInputs();
      draftVibe = candidate;
      updatePermissionSummary(candidate);
      runSandboxPreview(candidate);
    });

    // Version history section
    var history = Array.isArray(record.history) ? record.history : [];
    var dlg = null;

    if (history.length > 0) {
      var histSection = el('div', 'vs-edit-history');
      histSection.appendChild(el('h3', 'vs-offer-heading', 'Version history'));
      var histList = el('ul', 'vs-edit-history-list');
      for (var h = 0; h < history.length; h++) {
        (function (entry, idx) {
          var item = el('li', 'vs-edit-history-item');
          var info = el('div', 'vs-edit-history-info');
          var ver = entry && entry.vibe ? entry.vibe.version : '?';
          var labelText = 'v' + ver + ' \u2014 ' + (entry.title || (entry.vibe && entry.vibe.name) || baseVibe.name);
          info.appendChild(el('div', 'vs-edit-history-title', labelText));
          if (entry && entry.vibe && entry.vibe.wish) {
            info.appendChild(el('div', 'vs-edit-history-wish', '\u201c' + entry.vibe.wish + '\u201d'));
          }
          var restoreBtn = el('button', 'vs-btn vs-btn-secondary vs-edit-restore-btn', 'Restore');
          restoreBtn.type = 'button';
          restoreBtn.setAttribute('data-vs', 'edit-restore-version');
          restoreBtn.addEventListener('click', function () {
            if (typeof host.revertRecord === 'function') {
              host.revertRecord(instanceId, idx);
            }
            if (dlg) dlg.close();
          });
          item.appendChild(info);
          item.appendChild(restoreBtn);
          histList.appendChild(item);
        })(history[h], h);
      }
      histSection.appendChild(histList);
      body.appendChild(histSection);
    }

    saveBtn.addEventListener('click', function () {
      editError.hidden = true;
      var cleanTitle = titleInput.value.trim() || baseVibe.name;
      var cleanNote = noteInput.value.trim();

      var candidate = readCandidateFromCodeInputs();
      var codeChanged = computeCodeChanged(candidate);

      if (!codeChanged) {
        if (typeof host.updateRecord === 'function') {
          host.updateRecord(instanceId, { title: cleanTitle, note: cleanNote });
        }
        if (dlg) dlg.close();
        return;
      }

      try {
        kit.validate(candidate);
        var chk = host.check(candidate);
        if (!chk || !chk.ok) {
          throw new Error('Missing capabilities: ' + ((chk && chk.missing) || []).join(', '));
        }
        if (typeof host.updateRecord === 'function') {
          host.updateRecord(instanceId, {
            title: cleanTitle,
            note: cleanNote,
            vibe: candidate
          });
        }
        if (dlg) dlg.close();
      } catch (err) {
        editError.textContent = err && err.message ? err.message : 'Unable to save vibe';
        editError.hidden = false;
      }
    });

    cancelBtn.addEventListener('click', function () {
      if (dlg) dlg.close();
    });

    updatePermissionSummary(draftVibe);
    runSandboxPreview(draftVibe);

    dlg = openDialog({
      title: 'Edit ' + (record.title || baseVibe.name),
      dataVs: 'edit-dialog',
      body: body,
      onClose: stopTestRun
    });

    if (focusTarget === 'title') {
      try {
        titleInput.focus();
        titleInput.select();
      } catch (_) {
        // Ignore focus errors.
      }
    }
  }

  function mountPanel(host, element, options) {
    if (!element) {
      throw new Error('mountPanel requires a target element');
    }

    var opts = options || {};
    var strings = resolveSpaceStrings(host, opts);
    var wishes = Array.isArray(opts.wishes) ? opts.wishes : [];
    var gallery = Array.isArray(opts.gallery) ? opts.gallery : [];
    var shareTargets = Array.isArray(opts.shareTargets) ? opts.shareTargets : [];

    clearNode(element);

    var panel = el('div', 'vs-panel');
    if (strings.rtl) {
      panel.setAttribute('dir', 'rtl');
    }

    // Header
    var header = el('div', 'vs-panel-header');
    header.appendChild(el('h2', 'vs-panel-title', strings.panelTitle));
    var offerBtn = el('button', 'vs-link-btn', formatStr(strings.whatOffers, { host: host.name }));
    offerBtn.type = 'button';
    offerBtn.setAttribute('data-vs', 'offer-open');
    offerBtn.addEventListener('click', function () {
      showOffer(host, opts);
    });
    header.appendChild(offerBtn);
    panel.appendChild(header);

    // Wish box
    var wishSection = el('section', 'vs-section vs-wish-section');
    var wishForm = el('form', 'vs-wish-form');
    var wishInput = el('input', 'vs-input vs-wish-input');
    wishInput.type = 'text';
    wishInput.setAttribute('dir', 'auto');
    wishInput.placeholder = formatStr(strings.wishPlaceholder, { host: host.name });
    wishInput.setAttribute('aria-label', 'Wish for ' + host.name);
    wishInput.setAttribute('data-vs', 'wish-input');

    var wishSendBtn = el('button', 'vs-btn vs-btn-primary vs-wish-send', strings.send);
    wishSendBtn.type = 'submit';
    wishSendBtn.setAttribute('data-vs', 'wish-send');

    wishForm.appendChild(wishInput);
    wishForm.appendChild(wishSendBtn);
    wishSection.appendChild(wishForm);

    var chipsWrap = el('div', 'vs-wish-chips');
    wishSection.appendChild(chipsWrap);

    var wishNote = el('p', 'vs-wish-note', strings.wishNote);
    wishNote.setAttribute('aria-live', 'polite');
    wishSection.appendChild(wishNote);

    panel.appendChild(wishSection);

    // Draft / incoming slot
    var draftSlot = el('div', 'vs-draft-slot');
    panel.appendChild(draftSlot);

    // Installed vibes section
    var installedSection = el('section', 'vs-section vs-installed-section');
    var installedHead = el('div', 'vs-installed-head');
    var installedTitle = el('h3', 'vs-section-title', strings.installed + ' \u00b7 0');
    installedHead.appendChild(installedTitle);
    installedSection.appendChild(installedHead);

    var filterWrap = el('div', 'vs-filter-wrap');
    filterWrap.hidden = true;
    var filterInput = el('input', 'vs-input vs-vibe-filter');
    filterInput.type = 'search';
    filterInput.setAttribute('dir', 'auto');
    filterInput.placeholder = strings.filterPlaceholder;
    filterInput.setAttribute('aria-label', 'Filter installed vibes');
    filterInput.setAttribute('data-vs', 'vibe-filter');
    filterWrap.appendChild(filterInput);
    installedSection.appendChild(filterWrap);

    var sealedLegend = el(
      'p',
      'vs-installed-legend',
      formatStr(strings.sealedLegend, { host: host.name })
    );
    sealedLegend.hidden = true;
    installedSection.appendChild(sealedLegend);

    var undoSlot = el('div', 'vs-undo-slot');
    installedSection.appendChild(undoSlot);

    var installedList = el('div', 'vs-installed-list');
    installedSection.appendChild(installedList);
    panel.appendChild(installedSection);

    // Gallery section
    var gallerySection = el('section', 'vs-section vs-gallery-section');
    gallerySection.appendChild(el('h3', 'vs-section-title', strings.portableVibes));
    gallerySection.appendChild(
      el('p', 'vs-section-sub', strings.portableSub)
    );
    var galleryList = el('div', 'vs-gallery-list');
    gallerySection.appendChild(galleryList);
    var galleryLabelSlot = el('div', 'vs-gallery-label-slot');
    gallerySection.appendChild(galleryLabelSlot);
    panel.appendChild(gallerySection);

    element.appendChild(panel);

    var activeAuthorTimers = [];
    var activePreviewRun = null;
    var mountedCards = {};
    var undoTimer = null;
    var filterQuery = '';
    var openMoreCleanup = null;
    var destroyed = false;

    function closeOpenMore() {
      if (typeof openMoreCleanup === 'function') {
        var fn = openMoreCleanup;
        openMoreCleanup = null;
        fn();
      }
    }

    function clearUndoBanner() {
      if (undoTimer) {
        clearTimeout(undoTimer);
        undoTimer = null;
      }
      clearNode(undoSlot);
    }

    function showUndoBanner(removedRecord, prevIndex) {
      clearUndoBanner();
      if (!removedRecord) return;

      var banner = el('div', 'vs-undo-banner');
      banner.setAttribute('data-vs', 'undo-banner');

      var displayTitle = removedRecord.title || (removedRecord.vibe && removedRecord.vibe.name) || 'vibe';
      banner.appendChild(el('span', 'vs-undo-text', 'Deleted \u201c' + displayTitle + '\u201d'));

      var undoBtn = el('button', 'vs-btn vs-btn-secondary vs-undo-btn', 'Undo');
      undoBtn.type = 'button';
      undoBtn.setAttribute('data-vs', 'undo-delete');
      undoBtn.addEventListener('click', function () {
        clearUndoBanner();
        if (typeof host.restoreRecord === 'function') {
          host.restoreRecord(removedRecord, prevIndex);
        } else {
          host.install(removedRecord.vibe, {
            origin: removedRecord.origin,
            args: removedRecord.args,
            title: removedRecord.title,
            note: removedRecord.note
          });
        }
      });
      banner.appendChild(undoBtn);
      undoSlot.appendChild(banner);

      undoTimer = setTimeout(function () {
        clearUndoBanner();
      }, 7000);
    }

    function cancelDraft() {
      for (var i = 0; i < activeAuthorTimers.length; i++) {
        clearTimeout(activeAuthorTimers[i]);
      }
      activeAuthorTimers = [];
      if (activePreviewRun) {
        try {
          activePreviewRun.stop();
        } catch (_) {
          // Ignore stop errors.
        }
        activePreviewRun = null;
      }
      clearNode(draftSlot);
      clearNode(galleryLabelSlot);
    }

    function setWishNoteProminent(prominent) {
      if (prominent) {
        wishNote.classList.add('vs-wish-note-prominent');
      } else {
        wishNote.classList.remove('vs-wish-note-prominent');
      }
    }

    function getAvailableWishes() {
      var installed = host.installed() || [];
      var installedVersionById = {};
      for (var i = 0; i < installed.length; i++) {
        if (installed[i] && installed[i].vibe) {
          installedVersionById[installed[i].vibe.id] =
            typeof installed[i].vibe.version === 'number' ? installed[i].vibe.version : 1;
        }
      }
      var available = [];
      for (var j = 0; j < wishes.length; j++) {
        var w = wishes[j];
        if (!w.remixOf) {
          available.push(w);
        } else {
          var currentVer = installedVersionById[w.remixOf];
          var targetVer = w.vibe && typeof w.vibe.version === 'number' ? w.vibe.version : 1;
          if (currentVer !== undefined && currentVer < targetVer) {
            available.push(w);
          }
        }
      }
      return available;
    }

    function renderWishChips() {
      clearNode(chipsWrap);
      var available = getAvailableWishes();
      for (var i = 0; i < available.length; i++) {
        (function (wishObj) {
          var chip = el('button', 'vs-chip-btn', wishObj.text);
          chip.type = 'button';
          chip.setAttribute('data-vs', 'wish-chip');
          chip.addEventListener('click', function () {
            wishInput.value = wishObj.text;
            setWishNoteProminent(false);
            startAuthoring(wishObj);
          });
          chipsWrap.appendChild(chip);
        })(available[i]);
      }
    }

    function startAuthoring(wishObj) {
      if (destroyed) return;
      cancelDraft();

      var vibe = wishObj.vibe;
      var wishText = wishObj.text || vibe.wish || '';
      var capCount = 0;
      try {
        var m = host.manifest();
        capCount = (m && m.capabilities ? m.capabilities.length : 0);
      } catch (_) {
        capCount = 0;
      }

      var container = el('div', 'vs-author-card');

      var stepsBox = el('div', 'vs-author-steps');
      stepsBox.setAttribute('data-vs', 'author-steps');

      function makeStep(labelText, subText) {
        var step = el('div', 'vs-step vs-step-pending');
        var icon = el('span', 'vs-step-icon');
        icon.setAttribute('aria-hidden', 'true');
        var textCol = el('div', 'vs-step-content');
        var headRow = el('div', 'vs-step-head');
        var label = el('span', 'vs-step-label', labelText);
        var detail = el('span', 'vs-step-detail');
        headRow.appendChild(label);
        headRow.appendChild(detail);
        textCol.appendChild(headRow);
        if (subText) {
          textCol.appendChild(el('div', 'vs-step-sub', subText));
        }
        step.appendChild(icon);
        step.appendChild(textCol);
        return { el: step, icon: icon, detail: detail };
      }

      var step1 = makeStep('Reading what ' + host.name + ' offers');
      var step2 = makeStep(
        'Writing the vibe against sample data',
        'Your real data is not sent to the AI.'
      );
      var step3 = makeStep('Checking it in the sandbox');

      stepsBox.appendChild(step1.el);
      stepsBox.appendChild(step2.el);
      stepsBox.appendChild(step3.el);
      container.appendChild(stepsBox);

      var stageBody = el('div', 'vs-author-result');
      container.appendChild(stageBody);
      draftSlot.appendChild(container);

      function setStepState(step, state, detailText) {
        step.el.classList.remove('vs-step-pending', 'vs-step-running', 'vs-step-done');
        step.el.classList.add('vs-step-' + state);
        if (state === 'done') {
          step.icon.textContent = '\u2713';
        } else {
          step.icon.textContent = '';
        }
        if (detailText !== undefined) {
          step.detail.textContent = detailText;
        }
      }

      setStepState(step1, 'running');

      var STEP_MS = 700;

      activeAuthorTimers.push(
        setTimeout(function () {
          if (destroyed) return;
          setStepState(
            step1,
            'done',
            capCount + (capCount === 1 ? ' capability' : ' capabilities')
          );
          setStepState(step2, 'running');
        }, STEP_MS)
      );

      activeAuthorTimers.push(
        setTimeout(function () {
          if (destroyed) return;
          setStepState(step2, 'done');
          setStepState(step3, 'running');
        }, STEP_MS * 2)
      );

      activeAuthorTimers.push(
        setTimeout(function () {
          if (destroyed) return;
          setStepState(step3, 'done');
          showDraftResult(stageBody, vibe, wishText);
        }, STEP_MS * 3)
      );
    }

    function showDraftResult(stageBody, vibe, wishText) {
      clearNode(stageBody);

      var previewBox = el('div', 'vs-preview-box');
      previewBox.setAttribute('data-vs', 'preview');
      previewBox.appendChild(el('div', 'vs-preview-title', 'Preview on sample data'));
      var previewMount = el('div', 'vs-preview-mount');
      previewBox.appendChild(previewMount);
      stageBody.appendChild(previewBox);

      var checkRes = host.check(vibe);
      if (checkRes && checkRes.ok) {
        try {
          activePreviewRun = host.mount(vibe, previewMount, { data: 'sample' });
        } catch (err) {
          previewMount.appendChild(
            el('div', 'vs-inline-error', err && err.message ? err.message : 'Preview failed')
          );
        }
      } else {
        previewMount.appendChild(
          el(
            'div',
            'vs-inline-error',
            'Missing capabilities: ' + ((checkRes && checkRes.missing) || []).join(', ')
          )
        );
      }

      var codeWrap = el('div', 'vs-code-section');
      var codeOpen = false;
      var codeBtn = el('button', 'vs-btn vs-btn-ghost vs-show-code-btn', 'Show code');
      codeBtn.type = 'button';
      codeBtn.setAttribute('data-vs', 'show-code');
      codeBtn.setAttribute('aria-expanded', 'false');

      var codePanel = el('div', 'vs-code-panel');
      codePanel.hidden = true;
      codePanel.appendChild(el('p', 'vs-code-wish', 'Your wish: \u201c' + wishText + '\u201d'));
      var codePre = el('pre', 'vs-code-block');
      codePre.appendChild(el('code', 'vs-mono', vibe.source || ''));
      codePanel.appendChild(codePre);

      codeBtn.addEventListener('click', function () {
        codeOpen = !codeOpen;
        codeBtn.textContent = codeOpen ? 'Hide code' : 'Show code';
        codeBtn.setAttribute('aria-expanded', codeOpen ? 'true' : 'false');
        codePanel.hidden = !codeOpen;
      });

      codeWrap.appendChild(codeBtn);
      codeWrap.appendChild(codePanel);
      stageBody.appendChild(codeWrap);

      var labelCard = buildLabelCard(host, vibe, {
        origin: 'yours',
        onAllow: function (_v, meta) {
          host.install(vibe, {
            origin: 'yours',
            title: meta && meta.title,
            note: meta && meta.note
          });
          cancelDraft();
          wishInput.value = '';
        },
        onCancel: function () {
          cancelDraft();
        }
      });
      stageBody.appendChild(labelCard);
    }

    wishForm.addEventListener('submit', function (e) {
      e.preventDefault();
      var text = wishInput.value.trim();
      if (!text) {
        setWishNoteProminent(true);
        return;
      }
      var available = getAvailableWishes();
      var matched = null;
      var lower = text.toLowerCase();
      for (var i = 0; i < available.length; i++) {
        if (available[i].text.trim().toLowerCase() === lower) {
          matched = available[i];
          break;
        }
      }
      if (!matched) {
        setWishNoteProminent(true);
        return;
      }
      setWishNoteProminent(false);
      startAuthoring(matched);
    });

    wishInput.addEventListener('input', function () {
      setWishNoteProminent(false);
    });

    filterInput.addEventListener('input', function () {
      filterQuery = filterInput.value;
      renderInstalled();
    });

    function createInstalledCard(record) {
      var instanceId = record.instanceId || record.vibe.id;
      var card = el('article', 'vs-vibe-card');
      card.setAttribute('data-vs', 'vibe-card');
      card.setAttribute('data-vibe-id', record.vibe.id);
      card.setAttribute('data-instance-id', instanceId);

      var head = el('div', 'vs-vibe-card-head');

      var titleRow = el('div', 'vs-vibe-card-title-row');
      var collapseBtn = el('button', 'vs-btn vs-btn-ghost vs-collapse-btn', '\u25be');
      collapseBtn.type = 'button';
      collapseBtn.setAttribute('data-vs', 'vibe-collapse');
      collapseBtn.setAttribute('aria-label', 'Collapse card');
      collapseBtn.setAttribute('aria-expanded', 'true');

      var titleWrap = el('div', 'vs-vibe-title-wrap');
      var titleEl = el('h4', 'vs-vibe-card-name', record.title || record.vibe.name);
      titleEl.setAttribute('data-vs', 'vibe-title');
      titleEl.setAttribute('dir', 'auto');
      titleWrap.appendChild(titleEl);

      var moreWrap = el('div', 'vs-more-wrap');
      var moreBtn = el('button', 'vs-btn vs-btn-ghost vs-more-trigger');
      moreBtn.type = 'button';
      moreBtn.setAttribute('data-vs', 'vibe-more');
      moreBtn.setAttribute('aria-label', 'Manage vibe');
      moreBtn.setAttribute('aria-haspopup', 'menu');
      moreBtn.setAttribute('aria-expanded', 'false');
      moreBtn.title = 'Manage vibe';

      var SVG_NS = 'http://www.w3.org/2000/svg';
      var dotsSvg = document.createElementNS(SVG_NS, 'svg');
      dotsSvg.setAttribute('viewBox', '0 0 16 16');
      dotsSvg.setAttribute('width', '16');
      dotsSvg.setAttribute('height', '16');
      dotsSvg.setAttribute('aria-hidden', 'true');
      dotsSvg.setAttribute('fill', 'currentColor');
      var dotXs = [3, 8, 13];
      for (var d = 0; d < dotXs.length; d++) {
        var dotCircle = document.createElementNS(SVG_NS, 'circle');
        dotCircle.setAttribute('cx', String(dotXs[d]));
        dotCircle.setAttribute('cy', '8');
        dotCircle.setAttribute('r', '1.4');
        dotsSvg.appendChild(dotCircle);
      }
      moreBtn.appendChild(dotsSvg);

      var moreMenu = el('div', 'vs-more-menu');
      moreMenu.setAttribute('role', 'menu');
      moreMenu.setAttribute('data-vs', 'vibe-menu');
      moreMenu.hidden = true;

      var editBtn = el('button', 'vs-more-item', 'Edit\u2026');
      editBtn.type = 'button';
      editBtn.setAttribute('role', 'menuitem');
      editBtn.setAttribute('data-vs', 'vibe-edit');

      var renameBtn = el('button', 'vs-more-item', 'Rename');
      renameBtn.type = 'button';
      renameBtn.setAttribute('role', 'menuitem');
      renameBtn.setAttribute('data-vs', 'vibe-rename');

      var inspectBtn = el('button', 'vs-more-item', 'Inspect');
      inspectBtn.type = 'button';
      inspectBtn.setAttribute('role', 'menuitem');
      inspectBtn.setAttribute('data-vs', 'vibe-inspect');
      inspectBtn.setAttribute('aria-expanded', 'false');

      var shareBtn = el('button', 'vs-more-item', 'Share\u2026');
      shareBtn.type = 'button';
      shareBtn.setAttribute('role', 'menuitem');
      shareBtn.setAttribute('data-vs', 'vibe-share');

      var sep1 = el('div', 'vs-more-sep');
      sep1.setAttribute('role', 'separator');

      var menuPause = el('button', 'vs-more-item', 'Pause');
      menuPause.type = 'button';
      menuPause.setAttribute('role', 'menuitem');
      menuPause.setAttribute('data-vs', 'vibe-pause');

      var menuPinTop = el('button', 'vs-more-item', 'Pin to top');
      menuPinTop.type = 'button';
      menuPinTop.setAttribute('role', 'menuitem');
      menuPinTop.setAttribute('data-vs', 'vibe-pin-top');

      var menuMoveUp = el('button', 'vs-more-item', 'Move up');
      menuMoveUp.type = 'button';
      menuMoveUp.setAttribute('role', 'menuitem');
      menuMoveUp.setAttribute('data-vs', 'vibe-move-up');

      var menuMoveDown = el('button', 'vs-more-item', 'Move down');
      menuMoveDown.type = 'button';
      menuMoveDown.setAttribute('role', 'menuitem');
      menuMoveDown.setAttribute('data-vs', 'vibe-move-down');

      var menuRevert = el('button', 'vs-more-item', 'Revert');
      menuRevert.type = 'button';
      menuRevert.setAttribute('role', 'menuitem');
      menuRevert.setAttribute('data-vs', 'vibe-revert');
      menuRevert.hidden = true;

      var sep2 = el('div', 'vs-more-sep');
      sep2.setAttribute('role', 'separator');

      var removeBtn = el('button', 'vs-more-item vs-more-item-danger', 'Delete');
      removeBtn.type = 'button';
      removeBtn.setAttribute('role', 'menuitem');
      removeBtn.setAttribute('data-vs', 'vibe-remove');

      moreMenu.appendChild(editBtn);
      moreMenu.appendChild(renameBtn);
      moreMenu.appendChild(inspectBtn);
      moreMenu.appendChild(shareBtn);
      moreMenu.appendChild(sep1);
      moreMenu.appendChild(menuPause);
      moreMenu.appendChild(menuPinTop);
      moreMenu.appendChild(menuMoveUp);
      moreMenu.appendChild(menuMoveDown);
      moreMenu.appendChild(menuRevert);
      moreMenu.appendChild(sep2);
      moreMenu.appendChild(removeBtn);

      moreWrap.appendChild(moreBtn);
      moreWrap.appendChild(moreMenu);

      titleRow.appendChild(collapseBtn);
      titleRow.appendChild(titleWrap);
      titleRow.appendChild(moreWrap);

      var noteEl = el('p', 'vs-vibe-card-note', record.note || '');
      noteEl.setAttribute('data-vs', 'vibe-note');
      noteEl.setAttribute('dir', 'auto');
      noteEl.hidden = !record.note;

      var metaGroup = el('div', 'vs-vibe-card-meta');
      var pinnedBadge = el('span', 'vs-origin-badge vs-pinned-badge', 'Pinned');
      pinnedBadge.hidden = !record.pinned;

      var originBadge = el(
        'span',
        'vs-origin-badge vs-origin-' + (record.origin || 'yours'),
        ORIGIN_CARD_BADGE[record.origin] || 'Yours'
      );
      var versionBadge = el('span', 'vs-version-badge', 'v' + record.vibe.version);
      var stateBadge = el('span', 'vs-state-badge');
      stateBadge.hidden = true;

      metaGroup.appendChild(pinnedBadge);
      metaGroup.appendChild(originBadge);
      metaGroup.appendChild(versionBadge);
      metaGroup.appendChild(stateBadge);

      head.appendChild(titleRow);
      head.appendChild(noteEl);
      head.appendChild(metaGroup);
      card.appendChild(head);

      var cardCollapsible = el('div', 'vs-vibe-card-collapsible');
      var sourceBannerSlot = el('div', 'vs-source-banner-slot');
      sourceBannerSlot.hidden = true;
      var liveBody = el('div', 'vs-vibe-card-body');
      var inspectWrap = el('div', 'vs-vibe-inspect-wrap');

      cardCollapsible.appendChild(sourceBannerSlot);
      cardCollapsible.appendChild(liveBody);
      cardCollapsible.appendChild(inspectWrap);
      card.appendChild(cardCollapsible);

      var entry = {
        instanceId: instanceId,
        record: record,
        card: card,
        titleWrap: titleWrap,
        titleEl: titleEl,
        renameBtn: renameBtn,
        noteEl: noteEl,
        collapseBtn: collapseBtn,
        cardCollapsible: cardCollapsible,
        pinnedBadge: pinnedBadge,
        originBadge: originBadge,
        versionBadge: versionBadge,
        stateBadge: stateBadge,
        menuPause: menuPause,
        menuPinTop: menuPinTop,
        menuMoveUp: menuMoveUp,
        menuMoveDown: menuMoveDown,
        menuRevert: menuRevert,
        sourceBannerSlot: sourceBannerSlot,
        liveBody: liveBody,
        inspectWrap: inspectWrap,
        run: null,
        inspectOpen: false,
        inspectPane: null,
        renaming: false
      };

      function refreshInspectIfOpen() {
        if (entry.inspectOpen && entry.inspectPane) {
          entry.inspectPane.update();
        }
      }

      function updateStateBadge(health) {
        if (entry.record.paused) {
          stateBadge.textContent = 'Paused';
          stateBadge.className = 'vs-state-badge vs-state-paused';
          stateBadge.hidden = false;
          return;
        }
        if (!health || health.state === 'live') {
          stateBadge.hidden = true;
          return;
        }
        if (health.state === 'sample' || health.usingSampleFallback) {
          stateBadge.textContent = 'Sample data';
          stateBadge.className = 'vs-state-badge vs-state-sample';
          stateBadge.hidden = false;
        } else if (health.state === 'offline') {
          stateBadge.textContent = 'Source offline';
          stateBadge.className = 'vs-state-badge vs-state-offline';
          stateBadge.hidden = false;
        } else {
          stateBadge.textContent = 'Source unavailable';
          stateBadge.className = 'vs-state-badge vs-state-unavailable';
          stateBadge.hidden = false;
        }
      }

      function updateSourceBanner(run) {
        clearNode(sourceBannerSlot);
        if (entry.record.paused || !run || typeof run.health !== 'function') {
          sourceBannerSlot.hidden = true;
          updateStateBadge(null);
          return;
        }
        var health = run.health();
        updateStateBadge(health);

        if (!health || (health.state === 'live' && !health.usingSampleFallback)) {
          sourceBannerSlot.hidden = true;
          return;
        }

        sourceBannerSlot.hidden = false;
        var banner = el('div', 'vs-source-banner vs-source-banner-' + health.state);
        banner.setAttribute('data-vs', 'source-banner');

        if (health.usingSampleFallback || health.state === 'sample') {
          banner.appendChild(
            el('div', 'vs-source-banner-title', 'Previewing sample data instead of live data.')
          );
          var sampleActions = el('div', 'vs-source-banner-actions');
          var liveBtn = el('button', 'vs-btn vs-btn-secondary', 'Return to live');
          liveBtn.type = 'button';
          liveBtn.setAttribute('data-vs', 'source-use-live');
          liveBtn.addEventListener('click', function () {
            if (typeof run.setDataMode === 'function') run.setDataMode('live');
          });
          sampleActions.appendChild(liveBtn);
          banner.appendChild(sampleActions);
          sourceBannerSlot.appendChild(banner);
          return;
        }

        var headline =
          health.state === 'offline'
            ? 'Source offline'
            : (health.state === 'revoked' ? 'Source access turned off' : 'Source unavailable');
        if (health.lastGoodAt !== null && health.lastGoodAt !== undefined) {
          headline += ' \u00b7 Showing last reading';
        }
        banner.appendChild(el('div', 'vs-source-banner-title', headline));

        var issues = Array.isArray(health.issues) ? health.issues : [];
        var hasSample = false;
        for (var i = 0; i < issues.length; i++) {
          var iss = issues[i];
          if (iss.hasSample) hasSample = true;
          var detail = (iss.title || iss.capability || 'Source') + (iss.reason ? ': ' + iss.reason : '');
          banner.appendChild(el('div', 'vs-source-banner-reason', detail));
        }

        var btnRow = el('div', 'vs-source-banner-actions');
        var retryBtn = el('button', 'vs-btn vs-btn-secondary', 'Retry');
        retryBtn.type = 'button';
        retryBtn.setAttribute('data-vs', 'source-retry');
        retryBtn.addEventListener('click', function () {
          if (typeof run.retry === 'function') run.retry();
        });
        btnRow.appendChild(retryBtn);

        if (hasSample) {
          var useSampleBtn = el('button', 'vs-btn vs-btn-secondary', 'Preview sample');
          useSampleBtn.type = 'button';
          useSampleBtn.setAttribute('data-vs', 'source-use-sample');
          useSampleBtn.addEventListener('click', function () {
            if (typeof run.setDataMode === 'function') run.setDataMode('sample');
          });
          btnRow.appendChild(useSampleBtn);
        }

        if (health.state === 'revoked' || health.state === 'missing') {
          var editSourceBtn = el('button', 'vs-btn vs-btn-secondary', 'Edit');
          editSourceBtn.type = 'button';
          editSourceBtn.addEventListener('click', function () {
            openEditDialog(host, entry.record, wishes);
          });
          btnRow.appendChild(editSourceBtn);
        }

        banner.appendChild(btnRow);
        sourceBannerSlot.appendChild(banner);
      }

      function mountOrPauseBody() {
        if (entry.run) {
          try {
            entry.run.stop();
          } catch (_) {
            // Ignore stop errors.
          }
          entry.run = null;
        }
        clearNode(liveBody);
        liveBody.classList.remove('vk-view-stale');
        clearNode(sourceBannerSlot);
        sourceBannerSlot.hidden = true;

        if (entry.record.paused) {
          updateStateBadge(null);
          var pausedBox = el('div', 'vs-paused-box');
          pausedBox.appendChild(el('span', 'vs-paused-text', 'Paused \u2014 live updates stopped.'));
          var resumeBtn = el('button', 'vs-btn vs-btn-primary', 'Resume');
          resumeBtn.type = 'button';
          resumeBtn.setAttribute('data-vs', 'vibe-resume');
          resumeBtn.addEventListener('click', function () {
            if (typeof host.updateRecord === 'function') {
              host.updateRecord(instanceId, { paused: false });
            }
          });
          pausedBox.appendChild(resumeBtn);
          liveBody.appendChild(pausedBox);
          refreshInspectIfOpen();
          return;
        }

        try {
          entry.run = host.mount(entry.record.vibe, liveBody, {
            data: 'live',
            args: entry.record.args,
            onUpdate: function (r) {
              updateSourceBanner(r);
              refreshInspectIfOpen();
            }
          });
          updateSourceBanner(entry.run);
        } catch (err) {
          liveBody.appendChild(
            el('div', 'vk-error', err && err.message ? err.message : 'Unable to run vibe')
          );
        }
      }

      function syncHeader(nextRecord, moveGroupInfo) {
        entry.record = nextRecord;
        var currentTitle = nextRecord.title || nextRecord.vibe.name;
        if (!entry.renaming) {
          titleEl.textContent = currentTitle;
        }
        noteEl.textContent = nextRecord.note || '';
        noteEl.hidden = !nextRecord.note;

        var isCollapsed = Boolean(nextRecord.collapsed);
        cardCollapsible.hidden = isCollapsed;
        collapseBtn.textContent = isCollapsed ? '\u25b8' : '\u25be';
        collapseBtn.setAttribute('aria-expanded', isCollapsed ? 'false' : 'true');
        collapseBtn.setAttribute('aria-label', isCollapsed ? 'Expand card' : 'Collapse card');

        pinnedBadge.hidden = !nextRecord.pinned;
        originBadge.textContent = ORIGIN_CARD_BADGE[nextRecord.origin] || 'Yours';
        originBadge.className = 'vs-origin-badge vs-origin-' + (nextRecord.origin || 'yours');

        var hist = Array.isArray(nextRecord.history) ? nextRecord.history : [];
        versionBadge.textContent =
          hist.length > 0
            ? 'v' + nextRecord.vibe.version + ' \u00b7 ' + hist.length + ' prev'
            : 'v' + nextRecord.vibe.version;

        menuPause.textContent = nextRecord.paused ? 'Resume' : 'Pause';
        menuPinTop.textContent = nextRecord.pinned ? 'Unpin' : 'Pin to top';

        if (moveGroupInfo) {
          menuMoveUp.disabled = !moveGroupInfo.canUp;
          menuMoveDown.disabled = !moveGroupInfo.canDown;
        }

        if (hist.length > 0) {
          var prevVer = hist[0] && hist[0].vibe ? hist[0].vibe.version : '?';
          menuRevert.textContent = 'Revert to v' + prevVer;
          menuRevert.hidden = false;
        } else {
          menuRevert.hidden = true;
        }

        if (nextRecord.paused) {
          updateStateBadge(null);
        } else if (entry.run && typeof entry.run.health === 'function') {
          updateStateBadge(entry.run.health());
        }
      }

      function startInlineRename() {
        if (entry.renaming) return;
        entry.renaming = true;
        titleEl.hidden = true;

        var input = el('input', 'vs-input vs-vibe-title-input');
        input.type = 'text';
        input.maxLength = 120;
        input.setAttribute('data-vs', 'vibe-title-input');
        input.value = entry.record.title || entry.record.vibe.name;
        titleWrap.appendChild(input);

        var finished = false;
        function finish(save) {
          if (finished) return;
          finished = true;
          entry.renaming = false;
          var nextTitle = input.value.trim();
          if (input.parentNode) input.parentNode.removeChild(input);
          titleEl.hidden = false;
          if (save && nextTitle && typeof host.updateRecord === 'function') {
            host.updateRecord(instanceId, { title: nextTitle });
          }
        }

        input.addEventListener('keydown', function (e) {
          if (e.key === 'Enter') {
            e.preventDefault();
            finish(true);
          } else if (e.key === 'Escape') {
            e.preventDefault();
            e.stopPropagation();
            finish(false);
          }
        });
        input.addEventListener('blur', function () {
          finish(true);
        });

        try {
          input.focus();
          input.select();
        } catch (_) {
          // Ignore focus errors.
        }
      }

      function setInspectOpen(nextOpen) {
        entry.inspectOpen = Boolean(nextOpen);
        inspectBtn.setAttribute('aria-expanded', entry.inspectOpen ? 'true' : 'false');
        inspectBtn.textContent = entry.inspectOpen ? 'Hide inspect' : 'Inspect';
        clearNode(inspectWrap);
        if (entry.inspectOpen) {
          entry.inspectPane = createInspectPane(
            host,
            function () { return entry.record.vibe; },
            function () { return entry.run; },
            function () { setInspectOpen(false); }
          );
          inspectWrap.appendChild(entry.inspectPane.element);
        } else {
          entry.inspectPane = null;
        }
      }

      collapseBtn.addEventListener('click', function () {
        if (typeof host.updateRecord === 'function') {
          host.updateRecord(instanceId, { collapsed: !entry.record.collapsed });
        }
      });

      renameBtn.addEventListener('click', function () {
        closeOpenMore();
        startInlineRename();
      });
      titleEl.addEventListener('click', startInlineRename);

      editBtn.addEventListener('click', function () {
        closeOpenMore();
        openEditDialog(host, entry.record, wishes);
      });

      inspectBtn.addEventListener('click', function () {
        closeOpenMore();
        setInspectOpen(!entry.inspectOpen);
      });

      shareBtn.addEventListener('click', function () {
        closeOpenMore();
        openShareDialog(host, entry.record.vibe, shareTargets);
      });

      removeBtn.addEventListener('click', function () {
        closeOpenMore();
        var allBefore = host.installed() || [];
        var prevIndex = -1;
        for (var i = 0; i < allBefore.length; i++) {
          if ((allBefore[i].instanceId || allBefore[i].vibe.id) === instanceId) {
            prevIndex = i;
            break;
          }
        }
        var removed = host.uninstall(instanceId);
        if (removed) {
          showUndoBanner(removed, prevIndex >= 0 ? prevIndex : 0);
        }
      });

      moreBtn.addEventListener('click', function (e) {
        e.stopPropagation();
        var wasOpen = !moreMenu.hidden;
        closeOpenMore();
        if (wasOpen) return;

        card.classList.add('has-open-menu');
        moreMenu.classList.remove('vs-more-menu-up');
        moreMenu.style.maxHeight = '';
        moreMenu.hidden = false;
        moreBtn.setAttribute('aria-expanded', 'true');

        if (typeof moreBtn.getBoundingClientRect === 'function' && typeof global.innerHeight === 'number') {
          var rect = moreBtn.getBoundingClientRect();
          var menuH =
            (typeof moreMenu.getBoundingClientRect === 'function'
              ? moreMenu.getBoundingClientRect().height
              : 0) ||
            moreMenu.offsetHeight ||
            390;
          var bottomReserve = typeof global.innerWidth === 'number' && global.innerWidth < 720 ? 72 : 16;
          var topReserve = 16;
          var spaceBelow = global.innerHeight - rect.bottom - bottomReserve;
          var spaceAbove = rect.top - topReserve;
          if (spaceBelow < menuH && spaceAbove > spaceBelow) {
            moreMenu.classList.add('vs-more-menu-up');
            if (spaceAbove < menuH && spaceAbove > 160) {
              moreMenu.style.maxHeight = Math.floor(spaceAbove) + 'px';
            }
          } else if (spaceBelow < menuH && spaceBelow > 160) {
            moreMenu.style.maxHeight = Math.floor(spaceBelow) + 'px';
          }
        }

        function closeThisMenu() {
          moreMenu.hidden = true;
          moreMenu.classList.remove('vs-more-menu-up');
          moreMenu.style.maxHeight = '';
          card.classList.remove('has-open-menu');
          moreBtn.setAttribute('aria-expanded', 'false');
          document.removeEventListener('click', onDocClick);
          document.removeEventListener('keydown', onEsc, true);
        }
        function onDocClick(ev) {
          if (!moreWrap.contains(ev.target)) {
            if (openMoreCleanup === closeThisMenu) openMoreCleanup = null;
            closeThisMenu();
          }
        }
        function onEsc(ev) {
          if (ev.key === 'Escape') {
            ev.stopPropagation();
            if (openMoreCleanup === closeThisMenu) openMoreCleanup = null;
            closeThisMenu();
          }
        }

        openMoreCleanup = closeThisMenu;
        document.addEventListener('click', onDocClick);
        document.addEventListener('keydown', onEsc, true);
      });

      menuPause.addEventListener('click', function () {
        closeOpenMore();
        if (typeof host.updateRecord === 'function') {
          host.updateRecord(instanceId, { paused: !entry.record.paused });
        }
      });

      menuPinTop.addEventListener('click', function () {
        closeOpenMore();
        if (typeof host.updateRecord === 'function') {
          host.updateRecord(instanceId, { pinned: !entry.record.pinned });
        }
      });

      function moveWithinGroup(delta) {
        closeOpenMore();
        if (typeof host.reorder !== 'function') return;
        var all = (host.installed() || []).slice();
        var groupRecords = all.filter(function (r) {
          return Boolean(r.pinned) === Boolean(entry.record.pinned);
        });
        var groupIds = groupRecords.map(function (r) {
          return r.instanceId || r.vibe.id;
        });
        var pos = groupIds.indexOf(instanceId);
        var swapPos = pos + delta;
        if (pos < 0 || swapPos < 0 || swapPos >= groupIds.length) return;
        var tmp = groupIds[pos];
        groupIds[pos] = groupIds[swapPos];
        groupIds[swapPos] = tmp;

        var pinnedIds = entry.record.pinned
          ? groupIds
          : all.filter(function (r) { return Boolean(r.pinned); }).map(function (r) { return r.instanceId || r.vibe.id; });
        var unpinnedIds = !entry.record.pinned
          ? groupIds
          : all.filter(function (r) { return !r.pinned; }).map(function (r) { return r.instanceId || r.vibe.id; });
        host.reorder(pinnedIds.concat(unpinnedIds));
      }

      menuMoveUp.addEventListener('click', function () {
        moveWithinGroup(-1);
      });

      menuMoveDown.addEventListener('click', function () {
        moveWithinGroup(1);
      });

      menuRevert.addEventListener('click', function () {
        closeOpenMore();
        if (typeof host.revertRecord === 'function') {
          host.revertRecord(instanceId, 0);
        }
      });

      entry.syncHeader = syncHeader;
      entry.mountOrPauseBody = mountOrPauseBody;

      syncHeader(record);
      mountOrPauseBody();

      return entry;
    }

    function matchesFilter(rec, q) {
      if (!q) return true;
      var needle = q.trim().toLowerCase();
      if (!needle) return true;
      var hay = [
        rec.title || '',
        rec.note || '',
        rec.vibe ? rec.vibe.name : '',
        rec.vibe ? rec.vibe.id : '',
        rec.vibe ? rec.vibe.wish : ''
      ].join(' ').toLowerCase();
      return hay.indexOf(needle) !== -1;
    }

    function renderInstalled() {
      if (destroyed) return;
      closeOpenMore();

      var records = (host.installed() || []).slice();
      // Keep host order (pinned first, then user order) if instanceId exists; fallback newest first
      if (records.length > 0 && !records[0].instanceId) {
        records.sort(function (a, b) {
          return (b.installedAt || 0) - (a.installedAt || 0);
        });
      }

      installedTitle.textContent = strings.installed + ' \u00b7 ' + records.length;
      if (records.length < 2 && filterQuery) {
        filterQuery = '';
        filterInput.value = '';
      }
      filterWrap.hidden = records.length < 2;
      sealedLegend.hidden = records.length === 0;

      var nextByInstance = {};
      for (var i = 0; i < records.length; i++) {
        var r = records[i];
        nextByInstance[r.instanceId || r.vibe.id] = r;
      }

      var existingKeys = Object.keys(mountedCards);
      for (var j = 0; j < existingKeys.length; j++) {
        var key = existingKeys[j];
        if (!nextByInstance[key]) {
          var dead = mountedCards[key];
          if (dead.run) {
            try {
              dead.run.stop();
            } catch (_) {
              // Ignore stop errors.
            }
          }
          if (dead.card.parentNode) {
            dead.card.parentNode.removeChild(dead.card);
          }
          delete mountedCards[key];
        }
      }

      clearNode(installedList);

      if (records.length === 0) {
        installedList.appendChild(el('div', 'vs-empty-state', strings.emptyInstalled));
        return;
      }

      var pinnedList = records.filter(function (x) { return Boolean(x.pinned); });
      var unpinnedList = records.filter(function (x) { return !x.pinned; });

      var filtered = records.filter(function (x) {
        return matchesFilter(x, filterQuery);
      });

      if (filtered.length === 0) {
        installedList.appendChild(el('div', 'vs-empty-state', 'No matching vibes.'));
        return;
      }

      for (var k = 0; k < filtered.length; k++) {
        var rec = filtered[k];
        var instKey = rec.instanceId || rec.vibe.id;
        var grp = rec.pinned ? pinnedList : unpinnedList;
        var grpIndex = grp.indexOf(rec);
        var moveInfo = {
          canUp: grpIndex > 0,
          canDown: grpIndex >= 0 && grpIndex < grp.length - 1
        };

        var cardEntry = mountedCards[instKey];
        if (!cardEntry) {
          cardEntry = createInstalledCard(rec);
          mountedCards[instKey] = cardEntry;
          cardEntry.syncHeader(rec, moveInfo);
        } else {
          var prevRec = cardEntry.record;
          var runNeedsRemount =
            prevRec.vibe.source !== rec.vibe.source ||
            prevRec.vibe.version !== rec.vibe.version ||
            !sameNeeds(prevRec.vibe.needs, rec.vibe.needs) ||
            (prevRec.vibe.refresh || null) !== (rec.vibe.refresh || null) ||
            JSON.stringify(prevRec.args || null) !== JSON.stringify(rec.args || null) ||
            Boolean(prevRec.paused) !== Boolean(rec.paused);

          cardEntry.syncHeader(rec, moveInfo);
          if (runNeedsRemount) {
            cardEntry.mountOrPauseBody();
          }
        }
        installedList.appendChild(cardEntry.card);
      }
    }

    function renderGallery() {
      clearNode(galleryList);
      for (var i = 0; i < gallery.length; i++) {
        (function (vibe) {
          var item = el('div', 'vs-gallery-item');
          var info = el('div', 'vs-gallery-info');
          info.appendChild(el('div', 'vs-gallery-name', vibe.name));
          if (vibe.wish) {
            info.appendChild(el('div', 'vs-gallery-desc', vibe.wish));
          }
          var addBtn = el('button', 'vs-btn vs-btn-secondary vs-gallery-add', 'Add');
          addBtn.type = 'button';
          addBtn.setAttribute('data-vs', 'gallery-add');
          addBtn.setAttribute('data-vibe-id', vibe.id);
          addBtn.addEventListener('click', function () {
            cancelDraft();
            var labelCard = buildLabelCard(host, vibe, {
              origin: 'gallery',
              onAllow: function (_v, meta) {
                host.install(vibe, {
                  origin: 'gallery',
                  title: meta && meta.title,
                  note: meta && meta.note
                });
                cancelDraft();
              },
              onCancel: function () {
                cancelDraft();
              }
            });
            galleryLabelSlot.appendChild(labelCard);
          });

          item.appendChild(info);
          item.appendChild(addBtn);
          galleryList.appendChild(item);
        })(gallery[i]);
      }
    }

    function handleHashIfPresent() {
      if (destroyed || !global.location || !global.location.hash) return;
      var hash = global.location.hash;
      if (hash.indexOf('#vibe=') !== 0) return;

      var encoded = hash.slice('#vibe='.length);
      if (!encoded) return;

      cancelDraft();

      var vibe;
      try {
        vibe = getKit().share.decode(encoded);
      } catch (err) {
        var badCard = el('div', 'vs-from-link-card vs-from-link-error');
        badCard.setAttribute('data-vs', 'from-link');
        badCard.appendChild(el('h3', 'vs-from-link-title', 'Shared vibe link'));
        badCard.appendChild(
          el(
            'p',
            'vs-from-link-msg',
            'This link could not be decoded (' + (err && err.message ? err.message : 'invalid payload') + ').'
          )
        );
        var dismissBadBtn = el('button', 'vs-btn vs-btn-secondary', 'Dismiss');
        dismissBadBtn.type = 'button';
        dismissBadBtn.addEventListener('click', function () {
          clearNode(draftSlot);
          clearHashFromAddressBar();
        });
        badCard.appendChild(dismissBadBtn);
        draftSlot.appendChild(badCard);
        return;
      }

      var checkRes = host.check(vibe);
      if (!checkRes || !checkRes.ok) {
        var card = el('div', 'vs-from-link-card');
        card.setAttribute('data-vs', 'from-link');
        card.appendChild(el('h3', 'vs-from-link-title', 'Shared vibe: ' + vibe.name));

        var msg = el('p', 'vs-from-link-msg');
        msg.appendChild(document.createTextNode('It needs '));
        var missing = (checkRes && checkRes.missing) || vibe.needs || [];
        for (var i = 0; i < missing.length; i++) {
          if (i > 0) msg.appendChild(document.createTextNode(', '));
          msg.appendChild(el('code', 'vs-mono', missing[i]));
        }
        msg.appendChild(
          document.createTextNode(', which ' + host.name + ' does not offer. It cannot run here.')
        );
        card.appendChild(msg);

        var dismissBtn = el('button', 'vs-btn vs-btn-secondary', 'Dismiss');
        dismissBtn.type = 'button';
        dismissBtn.addEventListener('click', function () {
          clearNode(draftSlot);
          clearHashFromAddressBar();
        });
        card.appendChild(dismissBtn);
        draftSlot.appendChild(card);
        return;
      }

      var sharedLabel = buildLabelCard(host, vibe, {
        origin: 'shared',
        onAllow: function (_v, meta) {
          host.install(vibe, {
            origin: 'shared',
            title: meta && meta.title,
            note: meta && meta.note
          });
          clearNode(draftSlot);
          clearHashFromAddressBar();
        },
        onCancel: function () {
          clearNode(draftSlot);
          clearHashFromAddressBar();
        }
      });
      draftSlot.appendChild(sharedLabel);
    }

    var unsubscribe = host.onChange(function () {
      renderWishChips();
      renderInstalled();
    });

    function onHashChange() {
      handleHashIfPresent();
    }
    global.addEventListener('hashchange', onHashChange);

    renderWishChips();
    renderInstalled();
    renderGallery();
    handleHashIfPresent();

    return {
      stop: function () {
        if (destroyed) return;
        destroyed = true;
        cancelDraft();
        clearUndoBanner();
        closeOpenMore();
        if (typeof unsubscribe === 'function') unsubscribe();
        global.removeEventListener('hashchange', onHashChange);
        var ids = Object.keys(mountedCards);
        for (var i = 0; i < ids.length; i++) {
          var e = mountedCards[ids[i]];
          if (e && e.run) {
            try {
              e.run.stop();
            } catch (_) {
              // Ignore stop errors.
            }
          }
        }
        mountedCards = {};
      }
    };
  }

  function embed(host, element, vibe, options) {
    if (!element) {
      throw new Error('embed requires a target element');
    }

    var opts = options || {};
    var strings = resolveSpaceStrings(host, opts);
    clearNode(element);

    var box = el('div', 'vs-embed');
    box.setAttribute('data-vs', 'embed');
    if (strings.rtl) {
      box.setAttribute('dir', 'rtl');
    }

    var header = el('div', 'vs-embed-header');
    var titleGroup = el('div', 'vs-embed-title-group');
    titleGroup.appendChild(el('span', 'vs-embed-title', strings.madeByAgent));
    if (opts.caption) {
      var capEl = el('span', 'vs-embed-caption', opts.caption);
      capEl.setAttribute('dir', 'auto');
      titleGroup.appendChild(capEl);
    }
    var tempBadge = el('span', 'vs-embed-badge', strings.temporary);
    header.appendChild(titleGroup);
    header.appendChild(tempBadge);
    box.appendChild(header);

    var body = el('div', 'vs-embed-body');
    box.appendChild(body);

    var footer = el('div', 'vs-embed-footer');
    var lbl = host.label(vibe);
    var readsLine = el('div', 'vs-embed-reads', strings.reads + ': ' + (lbl && lbl.reads ? lbl.reads.join(', ') : ''));
    var footerActions = el('div', 'vs-embed-actions');

    var inspectBtn = el('button', 'vs-btn vs-btn-ghost', strings.inspect);
    inspectBtn.type = 'button';
    inspectBtn.setAttribute('aria-expanded', 'false');

    var pinBtn = el('button', 'vs-btn vs-btn-primary', strings.pinToVibeSpace);
    pinBtn.type = 'button';
    pinBtn.setAttribute('data-vs', 'embed-pin');

    footerActions.appendChild(inspectBtn);
    footerActions.appendChild(pinBtn);
    footer.appendChild(readsLine);
    footer.appendChild(footerActions);
    box.appendChild(footer);

    var inspectWrap = el('div', 'vs-embed-inspect-wrap');
    box.appendChild(inspectWrap);

    element.appendChild(box);

    var run = null;
    var inspectOpen = false;
    var inspectPane = null;
    var pinned = false;

    function refreshInspect() {
      if (inspectOpen && inspectPane) {
        inspectPane.update();
      }
    }

    try {
      run = host.mount(vibe, body, {
        data: 'live',
        args: opts.args,
        onUpdate: refreshInspect
      });
    } catch (err) {
      body.appendChild(
        el('div', 'vk-error', err && err.message ? err.message : 'Unable to run vibe')
      );
    }

    inspectBtn.addEventListener('click', function () {
      inspectOpen = !inspectOpen;
      inspectBtn.setAttribute('aria-expanded', inspectOpen ? 'true' : 'false');
      clearNode(inspectWrap);
      if (inspectOpen) {
        inspectPane = createInspectPane(host, vibe, function () {
          return run;
        });
        inspectWrap.appendChild(inspectPane.element);
      } else {
        inspectPane = null;
      }
    });

    pinBtn.addEventListener('click', function () {
      if (pinned) return;
      var dlg = null;
      var card = buildLabelCard(host, vibe, {
        origin: 'agent',
        args: opts.args,
        defaultTitle: opts.defaultTitle || vibe.name,
        onAllow: function (_v, meta) {
          host.install(vibe, {
            origin: 'agent',
            args: opts.args,
            title: meta && meta.title,
            note: meta && meta.note
          });
          pinned = true;
          tempBadge.textContent = 'Pinned';
          tempBadge.classList.add('vs-embed-badge-pinned');
          if (pinBtn.parentNode) {
            pinBtn.parentNode.replaceChild(
              el('span', 'vs-embed-pinned-status', 'Pinned to Vibe Space'),
              pinBtn
            );
          }
          if (dlg) dlg.close();
        },
        onCancel: function () {
          if (dlg) dlg.close();
        }
      });

      dlg = openDialog({
        title: 'Pin to Vibe Space',
        body: card
      });
    });

    return {
      stop: function () {
        if (run) {
          try {
            run.stop();
          } catch (_) {
            // Ignore stop errors.
          }
          run = null;
        }
      }
    };
  }

  global.VibeSpace = {
    mountPanel: mountPanel,
    embed: embed,
    showOffer: showOffer
  };
})(typeof window !== 'undefined' ? window : globalThis);
