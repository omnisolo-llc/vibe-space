(function () {
  'use strict';

  var params = new URLSearchParams(window.location.search);
  var isPartner = params.get('as') === 'partner';

  function clamp(val, min, max) {
    return Math.min(max, Math.max(min, val));
  }

  function round3(val) {
    return Math.round(val * 1000) / 1000;
  }

  function makeHistory(base, spread, min, max) {
    var points = [];
    var cur = base;
    for (var i = 0; i < 24; i++) {
      cur = clamp(cur + (Math.random() - 0.5) * spread, min, max);
      points.push(round3(cur));
    }
    return points;
  }

  function createAccounts(partnerMode) {
    if (partnerMode) {
      return [
        {
          name: 'Amex Gold \u2022\u20226104',
          shortName: 'Amex Gold',
          kind: 'Credit',
          linked: true,
          budgetUsed: 0.93,
          budgetRange: [0.905, 0.96],
          recurringShare: 0.39,
          recurringRange: [0.36, 0.43],
          spendHistory: makeHistory(0.93, 0.04, 0.86, 0.96),
          recurringHistory: makeHistory(0.39, 0.02, 0.36, 0.43),
        },
        {
          name: 'Joint Checking \u2022\u20223310',
          shortName: 'Joint Checking',
          kind: 'Checking',
          linked: true,
          budgetUsed: 0.84,
          budgetRange: [0.81, 0.87],
          recurringShare: 0.72,
          recurringRange: [0.69, 0.75],
          spendHistory: makeHistory(0.84, 0.03, 0.80, 0.88),
          recurringHistory: makeHistory(0.72, 0.02, 0.69, 0.75),
        },
        {
          name: 'Venture Card \u2022\u20228819',
          shortName: 'Venture Card',
          kind: 'Credit',
          linked: true,
          budgetUsed: 0.66,
          budgetRange: [0.62, 0.70],
          recurringShare: 0.28,
          recurringRange: [0.25, 0.31],
          spendHistory: makeHistory(0.66, 0.04, 0.61, 0.71),
          recurringHistory: makeHistory(0.28, 0.02, 0.25, 0.31),
        },
        {
          name: 'Reserve Savings \u2022\u20225508',
          shortName: 'Reserve Savings',
          kind: 'Savings',
          linked: true,
          budgetUsed: 0.32,
          budgetRange: [0.28, 0.36],
          recurringShare: 0.15,
          recurringRange: [0.12, 0.18],
          spendHistory: makeHistory(0.32, 0.03, 0.28, 0.36),
          recurringHistory: makeHistory(0.15, 0.015, 0.12, 0.18),
        },
      ];
    }

    return [
      {
        name: 'Sapphire Card \u2022\u20224821',
        shortName: 'Sapphire Card',
        kind: 'Credit',
        linked: true,
        budgetUsed: 0.92,
        budgetRange: [0.905, 0.955],
        recurringShare: 0.44,
        recurringRange: [0.41, 0.47],
        spendHistory: makeHistory(0.92, 0.04, 0.85, 0.96),
        recurringHistory: makeHistory(0.44, 0.02, 0.41, 0.47),
      },
      {
        name: 'Household Bills \u2022\u20222209',
        shortName: 'Household Bills',
        kind: 'Checking',
        linked: true,
        budgetUsed: 0.83,
        budgetRange: [0.805, 0.865],
        recurringShare: 0.78,
        recurringRange: [0.75, 0.81],
        spendHistory: makeHistory(0.83, 0.03, 0.80, 0.87),
        recurringHistory: makeHistory(0.78, 0.02, 0.75, 0.81),
      },
      {
        name: 'Checking \u2022\u20229014',
        shortName: 'Checking',
        kind: 'Checking',
        linked: true,
        budgetUsed: 0.46,
        budgetRange: [0.42, 0.52],
        recurringShare: 0.36,
        recurringRange: [0.33, 0.39],
        spendHistory: makeHistory(0.46, 0.04, 0.41, 0.53),
        recurringHistory: makeHistory(0.36, 0.02, 0.33, 0.39),
      },
      {
        name: 'Travel Card \u2022\u20227732',
        shortName: 'Travel Card',
        kind: 'Credit',
        linked: true,
        budgetUsed: 0.64,
        budgetRange: [0.60, 0.69],
        recurringShare: 0.24,
        recurringRange: [0.21, 0.27],
        spendHistory: makeHistory(0.64, 0.04, 0.59, 0.70),
        recurringHistory: makeHistory(0.24, 0.02, 0.21, 0.27),
      },
    ];
  }

  function createTransactions(partnerMode, acctList) {
    if (partnerMode) {
      return [
        { merchant: 'Nordic Air', account: acctList[0].name, category: 'Travel', amountUsd: 388.0, isRecurring: false, daysAgo: 1 },
        { merchant: 'HomeShield Fiber', account: acctList[1].name, category: 'Internet', amountUsd: 89.0, isRecurring: true, daysAgo: 2 },
        { merchant: 'Apex Wireless', account: acctList[1].name, category: 'Mobile', amountUsd: 112.0, isRecurring: true, daysAgo: 3 },
        { merchant: 'CloudDocs Suite', account: acctList[0].name, category: 'Software', amountUsd: 36.0, isRecurring: true, daysAgo: 2 },
        { merchant: 'GreenBasket Market', account: acctList[2].name, category: 'Groceries', amountUsd: 94.5, isRecurring: false, daysAgo: 4 },
        { merchant: 'SoundWave HiFi', account: acctList[0].name, category: 'Media', amountUsd: 24.99, isRecurring: true, daysAgo: 5 },
        { merchant: 'Metro Fitness', account: acctList[2].name, category: 'Fitness', amountUsd: 68.0, isRecurring: true, daysAgo: 6 },
        { merchant: 'Nordic Roasters', account: acctList[3].name, category: 'Coffee', amountUsd: 18.25, isRecurring: false, daysAgo: 1 },
      ];
    }

    return [
      { merchant: 'Delta Air Lines', account: acctList[0].name, category: 'Travel', amountUsd: 412.0, isRecurring: false, daysAgo: 1 },
      { merchant: 'City Power & Light', account: acctList[1].name, category: 'Utilities', amountUsd: 164.0, isRecurring: true, daysAgo: 2 },
      { merchant: 'Equinox Club', account: acctList[3].name, category: 'Fitness', amountUsd: 215.0, isRecurring: true, daysAgo: 3 },
      { merchant: 'FiberStream Gigabit', account: acctList[1].name, category: 'Internet', amountUsd: 79.0, isRecurring: true, daysAgo: 4 },
      { merchant: 'CloudHost Pro', account: acctList[0].name, category: 'Software', amountUsd: 48.0, isRecurring: true, daysAgo: 2 },
      { merchant: 'Whole Harvest Market', account: acctList[2].name, category: 'Groceries', amountUsd: 118.5, isRecurring: false, daysAgo: 3 },
      { merchant: 'StreamFlix 4K', account: acctList[0].name, category: 'Media', amountUsd: 22.99, isRecurring: true, daysAgo: 5 },
      { merchant: 'CloudVault Backup', account: acctList[2].name, category: 'Storage', amountUsd: 14.0, isRecurring: true, daysAgo: 6 },
    ];
  }

  var accounts = createAccounts(isPartner);
  var transactions = createTransactions(isPartner, accounts);
  var hotAccount = accounts[0];
  var bankSyncOnline = true;
  var activeHost = null;

  function notifyHostSourceChange() {
    if (activeHost && typeof activeHost.notifySourceChange === 'function') {
      activeHost.notifySourceChange();
    }
  }

  function isAccountLinked(accountName) {
    for (var i = 0; i < accounts.length; i++) {
      if (accounts[i].name === accountName) return accounts[i].linked;
    }
    return false;
  }

  function driftAccounts() {
    if (!bankSyncOnline) return;
    for (var i = 0; i < accounts.length; i++) {
      var acct = accounts[i];
      if (!acct.linked) continue;
      acct.budgetUsed = round3(clamp(
        acct.budgetUsed + (Math.random() - 0.5) * 0.015,
        acct.budgetRange[0],
        acct.budgetRange[1]
      ));
      acct.recurringShare = round3(clamp(
        acct.recurringShare + (Math.random() - 0.5) * 0.012,
        acct.recurringRange[0],
        acct.recurringRange[1]
      ));
      acct.spendHistory.push(acct.budgetUsed);
      if (acct.spendHistory.length > 24) acct.spendHistory.shift();
      acct.recurringHistory.push(acct.recurringShare);
      if (acct.recurringHistory.length > 24) acct.recurringHistory.shift();
    }
  }

  function accountTone(acct) {
    if (!acct.linked) return 'offline';
    if (!bankSyncOnline) return 'warn';
    if (acct.budgetUsed >= 0.9) return 'danger';
    if (acct.budgetUsed >= 0.75) return 'warn';
    return 'ok';
  }

  function renderSyncControl() {
    var card = document.getElementById('pl-sync-card');
    var dot = document.getElementById('pl-sync-dot');
    var stateEl = document.getElementById('pl-sync-state');
    var btn = document.getElementById('pl-sync-toggle');
    if (card) card.classList.toggle('is-offline', !bankSyncOnline);
    if (dot) dot.className = 'pl-status-dot ' + (bankSyncOnline ? 'is-ok' : 'is-danger');
    if (stateEl) stateEl.textContent = bankSyncOnline ? 'Live' : 'Offline';
    if (btn) {
      btn.textContent = bankSyncOnline ? 'Go offline' : 'Reconnect';
      btn.setAttribute('aria-pressed', bankSyncOnline ? 'false' : 'true');
    }
  }

  var accountDomItems = [];

  function renderAccounts() {
    var listEl = document.getElementById('pl-account-list');
    var countEl = document.getElementById('pl-account-count');
    if (!listEl) return;

    if (accountDomItems.length === 0) {
      listEl.textContent = '';
      for (var i = 0; i < accounts.length; i++) {
        (function (acct) {
          var li = document.createElement('li');
          li.className = 'pl-account-item';

          var top = document.createElement('div');
          top.className = 'pl-account-top';

          var dot = document.createElement('span');
          dot.className = 'pl-status-dot';
          dot.setAttribute('aria-hidden', 'true');

          var nameEl = document.createElement('span');
          nameEl.className = 'pl-account-name';
          nameEl.textContent = acct.name;

          top.appendChild(dot);
          top.appendChild(nameEl);

          var bottom = document.createElement('div');
          bottom.className = 'pl-account-bottom';

          var meta = document.createElement('div');
          meta.className = 'pl-account-meta';

          var kindEl = document.createElement('span');
          kindEl.textContent = acct.kind;

          var stateEl = document.createElement('span');
          stateEl.className = 'pl-account-state';

          meta.appendChild(kindEl);
          meta.appendChild(stateEl);

          var toggleBtn = document.createElement('button');
          toggleBtn.type = 'button';
          toggleBtn.className = 'pl-acct-toggle';
          toggleBtn.setAttribute('data-app', 'toggle-account');
          toggleBtn.setAttribute('data-account', acct.name);
          toggleBtn.addEventListener('click', function () {
            acct.linked = !acct.linked;
            renderAccounts();
            renderTransactions();
            notifyHostSourceChange();
          });

          bottom.appendChild(meta);
          bottom.appendChild(toggleBtn);
          li.appendChild(top);
          li.appendChild(bottom);
          listEl.appendChild(li);
          accountDomItems.push({
            li: li,
            dot: dot,
            stateEl: stateEl,
            toggleBtn: toggleBtn,
          });
        })(accounts[i]);
      }
    }

    var linkedCount = 0;
    for (var j = 0; j < accounts.length; j++) {
      var item = accountDomItems[j];
      var a = accounts[j];
      if (a.linked) linkedCount++;
      item.li.classList.toggle('is-unlinked', !a.linked);
      item.dot.className = 'pl-status-dot is-' + accountTone(a);
      if (!a.linked) {
        item.stateEl.textContent = 'Unlinked';
      } else if (!bankSyncOnline) {
        item.stateEl.textContent = 'Sync paused';
      } else {
        item.stateEl.textContent = Math.round(a.budgetUsed * 100) + '% budget';
      }
      item.toggleBtn.textContent = a.linked ? 'Unlink' : 'Relink';
      item.toggleBtn.setAttribute('aria-pressed', a.linked ? 'false' : 'true');
    }

    if (countEl) {
      if (!bankSyncOnline) {
        countEl.textContent = 'Sync paused';
      } else if (linkedCount === accounts.length) {
        countEl.textContent = linkedCount + ' linked';
      } else {
        countEl.textContent = linkedCount + '/' + accounts.length + ' linked';
      }
    }
  }

  function renderTransactions() {
    var listEl = document.getElementById('pl-tx-list');
    var badgeEl = document.getElementById('pl-ledger-badge');
    if (!listEl) return;

    listEl.textContent = '';
    var visible = [];
    for (var i = 0; i < transactions.length; i++) {
      if (isAccountLinked(transactions[i].account)) {
        visible.push(transactions[i]);
      }
    }

    if (badgeEl) {
      badgeEl.textContent = visible.length + ' posted';
    }

    for (var j = 0; j < visible.length; j++) {
      var tx = visible[j];
      var li = document.createElement('li');
      li.className = 'pl-tx-row';

      var main = document.createElement('div');
      main.className = 'pl-tx-main';

      var titleRow = document.createElement('div');
      titleRow.className = 'pl-tx-title-row';

      var merchEl = document.createElement('span');
      merchEl.className = 'pl-tx-merchant';
      merchEl.textContent = tx.merchant;
      titleRow.appendChild(merchEl);

      if (tx.isRecurring) {
        var rec = document.createElement('span');
        rec.className = 'pl-tx-recurring';
        rec.textContent = 'Recurring';
        titleRow.appendChild(rec);
      }

      var sub = document.createElement('div');
      sub.className = 'pl-tx-sub';
      sub.textContent =
        tx.category +
        ' \u00b7 ' +
        tx.account +
        ' \u00b7 ' +
        (tx.daysAgo === 1 ? '1 day ago' : tx.daysAgo + ' days ago');

      main.appendChild(titleRow);
      main.appendChild(sub);

      var amt = document.createElement('span');
      amt.className = 'pl-tx-amount';
      amt.textContent = '$' + tx.amountUsd.toFixed(2);

      li.appendChild(main);
      li.appendChild(amt);
      listEl.appendChild(li);
    }
  }

  function renderChrome() {
    var tagEl = document.getElementById('pl-host-tag');
    var chipEl = document.getElementById('pl-agent-chip');

    if (isPartner) {
      document.title = "PocketLedger — partner's copy";
      if (tagEl) tagEl.textContent = "partner's copy";
    } else {
      document.title = 'PocketLedger — demo host';
      if (tagEl) tagEl.textContent = 'demo host';
    }

    if (chipEl) {
      chipEl.textContent = 'Why did ' + hotAccount.shortName + ' jump this week?';
    }
  }

  function buildSampleHistory(base, spread) {
    return makeHistory(base, spread, Math.max(0.1, base - 0.08), Math.min(0.98, base + 0.08));
  }

  function createLedgerHost() {
    function bankSyncStatus() {
      if (!bankSyncOnline) {
        return {
          available: false,
          mode: 'offline',
          reason: 'Bank Plaid sync disconnected',
        };
      }
      return { available: true, mode: 'live' };
    }

    return window.VibeKit.createHost({
      id: isPartner ? 'ledger-demo-partner' : 'ledger-demo',
      name: 'PocketLedger',
      capabilities: [
        {
          name: 'transactions.recent',
          title: 'Recent transactions and recurring charges',
          fields: {
            merchant: 'sealed',
            account: 'sealed',
            category: 'public',
            amountUsd: 'public',
            isRecurring: 'public',
            daysAgo: 'public',
          },
          sealedNote: 'merchant and account names stay sealed',
          sealedCannot: 'See merchant names or account numbers',
          status: bankSyncStatus,
          read: function () {
            if (!bankSyncOnline) return bankSyncStatus();
            var rows = [];
            for (var i = 0; i < transactions.length; i++) {
              var tx = transactions[i];
              if (!isAccountLinked(tx.account)) continue;
              rows.push({
                merchant: tx.merchant,
                account: tx.account,
                category: tx.category,
                amountUsd: tx.amountUsd,
                isRecurring: tx.isRecurring,
                daysAgo: tx.daysAgo,
              });
            }
            return rows;
          },
          sample: [
            { merchant: 'Sample Cloud', account: 'Sample Card', category: 'Software', amountUsd: 49, isRecurring: true, daysAgo: 1 },
            { merchant: 'Sample Utility', account: 'Sample Bills', category: 'Utilities', amountUsd: 135, isRecurring: true, daysAgo: 3 },
            { merchant: 'Sample Media', account: 'Sample Card', category: 'Media', amountUsd: 24, isRecurring: true, daysAgo: 5 },
            { merchant: 'Sample Market', account: 'Sample Checking', category: 'Groceries', amountUsd: 82, isRecurring: false, daysAgo: 2 },
          ],
        },
        {
          name: 'accounts.cashflow',
          title: 'Budget usage and recurring share by account',
          fields: {
            account: 'sealed',
            budgetUsed: 'public',
            recurringShare: 'public',
            spendHistory: 'public',
            recurringHistory: 'public',
          },
          sealedNote: 'account names stay sealed',
          sealedCannot: 'See merchant names or account numbers',
          status: bankSyncStatus,
          read: function () {
            if (!bankSyncOnline) return bankSyncStatus();
            var rows = [];
            for (var i = 0; i < accounts.length; i++) {
              var acct = accounts[i];
              if (!acct.linked) continue;
              rows.push({
                account: acct.name,
                budgetUsed: acct.budgetUsed,
                recurringShare: acct.recurringShare,
                spendHistory: acct.spendHistory.slice(),
                recurringHistory: acct.recurringHistory.slice(),
              });
            }
            return rows;
          },
          sample: [
            {
              account: 'Sample Card',
              budgetUsed: 0.92,
              recurringShare: 0.44,
              spendHistory: buildSampleHistory(0.92, 0.04),
              recurringHistory: buildSampleHistory(0.44, 0.02),
            },
            {
              account: 'Sample Bills',
              budgetUsed: 0.83,
              recurringShare: 0.76,
              spendHistory: buildSampleHistory(0.83, 0.03),
              recurringHistory: buildSampleHistory(0.76, 0.02),
            },
            {
              account: 'Sample Checking',
              budgetUsed: 0.46,
              recurringShare: 0.35,
              spendHistory: buildSampleHistory(0.46, 0.04),
              recurringHistory: buildSampleHistory(0.35, 0.02),
            },
          ],
        },
      ],
      notOffered: [
        'Move money or pay bills',
        'Read full card or account numbers',
        'Use the internet',
      ],
    });
  }

  function setupTabs() {
    var workspace = document.getElementById('pl-workspace');
    var tabButtons = document.querySelectorAll('.pl-tab-btn');

    function setTab(tab) {
      if (workspace) workspace.setAttribute('data-active-tab', tab);
      for (var i = 0; i < tabButtons.length; i++) {
        var btn = tabButtons[i];
        var attr = btn.getAttribute('data-app');
        var active = attr === 'tab-' + tab;
        btn.classList.toggle('is-active', active);
        btn.setAttribute('aria-pressed', active ? 'true' : 'false');
      }
    }

    for (var i = 0; i < tabButtons.length; i++) {
      (function (btn) {
        btn.addEventListener('click', function () {
          var attr = btn.getAttribute('data-app') || '';
          var tab = attr.replace(/^tab-/, '');
          setTab(tab);
        });
      })(tabButtons[i]);
    }

    if (window.location.hash && window.location.hash.indexOf('#vibe=') === 0) {
      setTab('vibes');
    }
    window.addEventListener('hashchange', function () {
      if (window.location.hash && window.location.hash.indexOf('#vibe=') === 0) {
        setTab('vibes');
      }
    });
  }

  function setupHowDialog() {
    var trigger = document.getElementById('pl-how-link');
    var scrim = document.getElementById('pl-how-scrim');
    var closeBtn = document.getElementById('pl-how-close');
    var codeEl = document.getElementById('pl-how-code');

    if (codeEl) {
      codeEl.textContent = [
        'const host = VibeKit.createHost({',
        "  id: '" + (isPartner ? 'ledger-demo-partner' : 'ledger-demo') + "',",
        "  name: 'PocketLedger',",
        '  capabilities: [',
        '    {',
        "      name: 'transactions.recent',",
        "      title: 'Recent transactions and recurring charges',",
        "      fields: { merchant: 'sealed', account: 'sealed', category: 'public', amountUsd: 'public', isRecurring: 'public', daysAgo: 'public' },",
        "      sealedNote: 'merchant and account names stay sealed',",
        "      sealedCannot: 'See merchant names or account numbers',",
        "      status: () => ({ available: bankSyncOnline, mode: bankSyncOnline ? 'live' : 'offline' }),",
        '      read: () => transactions.filter(/* linked accounts */),',
        '      sample: [ /* synthetic transactions */ ],',
        '    },',
        '    {',
        "      name: 'accounts.cashflow',",
        "      title: 'Budget usage and recurring share by account',",
        "      fields: { account: 'sealed', budgetUsed: 'public', recurringShare: 'public', spendHistory: 'public', recurringHistory: 'public' },",
        "      sealedNote: 'account names stay sealed',",
        "      sealedCannot: 'See merchant names or account numbers',",
        '      status: bankSyncStatus,',
        '      read: () => accounts.filter(a => a.linked),',
        '      sample: [ /* synthetic accounts */ ],',
        '    },',
        '  ],',
        '  notOffered: [',
        "    'Move money or pay bills',",
        "    'Read full card or account numbers',",
        "    'Use the internet',",
        '  ],',
        '});',
      ].join('\n');
    }

    function openDialog() {
      if (!scrim) return;
      scrim.hidden = false;
      if (closeBtn) closeBtn.focus();
    }

    function closeDialog() {
      if (!scrim || scrim.hidden) return;
      scrim.hidden = true;
      if (trigger) trigger.focus();
    }

    if (trigger) trigger.addEventListener('click', openDialog);
    if (closeBtn) closeBtn.addEventListener('click', closeDialog);
    if (scrim) {
      scrim.addEventListener('click', function (ev) {
        if (ev.target === scrim) closeDialog();
      });
    }
    document.addEventListener('keydown', function (ev) {
      if (ev.key === 'Escape') closeDialog();
    });
  }

  function setupAgentChat(host) {
    var chip = document.getElementById('pl-agent-chip');
    var suggestions = document.getElementById('pl-chat-suggestions');
    var messages = document.getElementById('pl-chat-messages');
    var empty = document.getElementById('pl-chat-empty');
    var activeEmbed = null;
    var pending = false;

    if (!chip || !messages) return;

    chip.addEventListener('click', function () {
      if (pending) return;
      pending = true;
      chip.disabled = true;
      if (suggestions) suggestions.hidden = true;
      if (empty) empty.hidden = true;

      var userBubble = document.createElement('div');
      userBubble.className = 'pl-msg pl-msg-user';
      userBubble.textContent = 'Why did ' + hotAccount.shortName + ' jump this week?';
      messages.appendChild(userBubble);

      var typing = document.createElement('div');
      typing.className = 'pl-typing';
      typing.textContent = 'Checking account cashflow';
      var dots = document.createElement('span');
      dots.className = 'pl-typing-dots';
      dots.setAttribute('aria-hidden', 'true');
      dots.appendChild(document.createElement('span'));
      dots.appendChild(document.createElement('span'));
      dots.appendChild(document.createElement('span'));
      typing.appendChild(dots);
      messages.appendChild(typing);
      messages.scrollTop = messages.scrollHeight;

      window.setTimeout(function () {
        if (typing.parentNode) typing.parentNode.removeChild(typing);

        var agentMsg = document.createElement('div');
        agentMsg.className = 'pl-msg pl-msg-agent';
        agentMsg.setAttribute('data-app', 'agent-message');

        var textEl = document.createElement('p');
        textEl.className = 'pl-msg-agent-text';
        textEl.textContent =
          hotAccount.shortName +
          ' crossed 90% of its weekly budget after a large travel charge alongside recurring software and media renewals. Here is a live view.';
        agentMsg.appendChild(textEl);

        var embedBox = document.createElement('div');
        embedBox.className = 'pl-msg-embed';
        agentMsg.appendChild(embedBox);
        messages.appendChild(agentMsg);

        if (activeEmbed && typeof activeEmbed.stop === 'function') {
          activeEmbed.stop();
        }
        if (window.VibeSpace && window.LEDGER_VIBES && window.LEDGER_VIBES.accountWatch) {
          activeEmbed = window.VibeSpace.embed(
            host,
            embedBox,
            window.LEDGER_VIBES.accountWatch,
            {
              args: { account: host.seal(hotAccount.name) },
              defaultTitle: 'Spend Watch \u00b7 ' + hotAccount.shortName,
            }
          );
        }
        messages.scrollTop = messages.scrollHeight;
        pending = false;
      }, 420);
    });
  }

  function init() {
    renderChrome();
    renderSyncControl();
    renderAccounts();
    renderTransactions();
    setupTabs();
    setupHowDialog();

    var syncToggle = document.getElementById('pl-sync-toggle');
    if (syncToggle) {
      syncToggle.addEventListener('click', function () {
        bankSyncOnline = !bankSyncOnline;
        renderSyncControl();
        renderAccounts();
        notifyHostSourceChange();
      });
    }

    window.setInterval(function () {
      driftAccounts();
      renderAccounts();
    }, 2500);

    if (!window.VibeKit || !window.VibeSpace) return;

    var host = createLedgerHost();
    activeHost = host;

    var offerPill = document.getElementById('pl-offer-pill');
    if (offerPill) {
      offerPill.addEventListener('click', function () {
        window.VibeSpace.showOffer(host);
      });
    }

    var panelEl = document.getElementById('vibe-space');
    var vibes = window.LEDGER_VIBES || {};
    var gallery = window.VIBE_GALLERY || [];

    if (panelEl) {
      window.VibeSpace.mountPanel(host, panelEl, {
        wishes: [
          {
            text: vibes.subWatchV1.wish,
            vibe: vibes.subWatchV1,
          },
          {
            text: vibes.subWatchV2.wish,
            vibe: vibes.subWatchV2,
            remixOf: 'subscription-watch',
          },
        ],
        gallery: gallery,
        shareTargets: [
          { label: 'Open as household partner', url: 'index.html?as=partner' },
          { label: 'Open in Moments', url: '../moments/index.html' },
        ],
      });
    }

    setupAgentChat(host);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
