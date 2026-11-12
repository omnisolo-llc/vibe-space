(function () {
  'use strict';

  var params = new URLSearchParams(window.location.search);
  var isTeammate = params.get('as') === 'teammate';
  var imapOnline = true;
  var activeFolder = 'all';
  var OFFLINE_REASON = 'IMAP mailbox connection paused';

  var ownerThreads = [
    {
      id: 't1',
      sender: 'Elena Vance <elena@northstar-vc.com>',
      shortName: 'Elena Vance',
      initials: 'EV',
      color: '#4338ca',
      subject: 'Q4 diligence deck sign-off before board call',
      snippet: 'Could you confirm the updated enterprise ARR slide by this afternoon?',
      waitHours: 38,
      priority: 'high',
      unreadCount: 3
    },
    {
      id: 't2',
      sender: 'Marcus Chen <mchen@ridgewayhealth.org>',
      shortName: 'Marcus Chen',
      initials: 'MC',
      color: '#0f766e',
      subject: 'BAA redlines on data retention schedule',
      snippet: 'Legal signed off on section 4.2, waiting on your reply to lock Friday.',
      waitHours: 29,
      priority: 'high',
      unreadCount: 2
    },
    {
      id: 't3',
      sender: 'Priya Nair <priya@cobaltcloud.io>',
      shortName: 'Priya Nair',
      initials: 'PN',
      color: '#b45309',
      subject: 'SOC 2 audit evidence upload window',
      snippet: 'Need one contact confirmed for the staging database access review.',
      waitHours: 26,
      priority: 'normal',
      unreadCount: 1
    },
    {
      id: 't4',
      sender: 'Devon Brooks <devon@studioharbor.co>',
      shortName: 'Devon Brooks',
      initials: 'DB',
      color: '#6d28d9',
      subject: 'Revised brand illustrations & mobile iconography',
      snippet: 'Attached the SVG export set — let us know which icon weight you prefer.',
      waitHours: 16,
      priority: 'normal',
      unreadCount: 2
    },
    {
      id: 't5',
      sender: 'Hannah Sato <hsato@pacificlegal.com>',
      shortName: 'Hannah Sato',
      initials: 'HS',
      color: '#be123c',
      subject: 'MSA renewal terms for EU customer tier',
      snippet: 'Two quick questions on SLA credits before we send DocuSign.',
      waitHours: 11,
      priority: 'high',
      unreadCount: 1
    },
    {
      id: 't6',
      sender: 'Samir Patel <samir@finopsweekly.io>',
      shortName: 'Samir Patel',
      initials: 'SP',
      color: '#1d4ed8',
      subject: 'Reserved instance commitments expiring Thursday',
      snippet: 'Should we renew the 12-month compute pool on the same terms?',
      waitHours: 5,
      priority: 'normal',
      unreadCount: 1
    },
    {
      id: 't7',
      sender: 'Claire Dubois <claire@atelier-lyon.fr>',
      shortName: 'Claire Dubois',
      initials: 'CD',
      color: '#0369a1',
      subject: 'Invoice #1048 confirmation & VAT receipt',
      snippet: 'Already processed on our side, sharing the PDF receipt for your books.',
      waitHours: 2,
      priority: 'low',
      unreadCount: 0
    },
    {
      id: 't8',
      sender: 'Noah Bennett <noah@kestrel.build>',
      shortName: 'Noah Bennett',
      initials: 'NB',
      color: '#374151',
      subject: 'Re: Beta feedback call notes from Tuesday',
      snippet: 'Thanks for sending the summary over — everything looks accurate.',
      waitHours: 1,
      priority: 'low',
      unreadCount: 0
    }
  ];

  var teammateThreads = [
    {
      id: 'tm1',
      sender: 'Nadia Kowalski <nadia@kestrel.build>',
      shortName: 'Nadia Kowalski',
      initials: 'NK',
      color: '#4338ca',
      subject: 'Escalation: enterprise SSO callback timeout',
      snippet: 'Customer IT team is standing by for updated SAML metadata.',
      waitHours: 31,
      priority: 'high',
      unreadCount: 4
    },
    {
      id: 'tm2',
      sender: 'Liam Gallagher <liam@meridianops.net>',
      shortName: 'Liam Gallagher',
      initials: 'LG',
      color: '#0f766e',
      subject: 'Incident post-mortem draft review',
      snippet: 'Added timeline notes — need teammate sign-off before sharing externally.',
      waitHours: 19,
      priority: 'high',
      unreadCount: 2
    },
    {
      id: 'tm3',
      sender: 'Tessa Morales <tessa@vervecreative.co>',
      shortName: 'Tessa Morales',
      initials: 'TM',
      color: '#b45309',
      subject: 'Launch webinar dry-run scheduling',
      snippet: 'Can your team make Thursday at 10am PT?',
      waitHours: 9,
      priority: 'normal',
      unreadCount: 1
    },
    {
      id: 'tm4',
      sender: 'Kenji Watanabe <kenji@osaka-systems.jp>',
      shortName: 'Kenji Watanabe',
      initials: 'KW',
      color: '#6d28d9',
      subject: 'API rate limit bump request for batch import',
      snippet: 'Confirming expected peak burst windows for next Monday.',
      waitHours: 4,
      priority: 'normal',
      unreadCount: 1
    }
  ];

  var ownerNewsletters = [
    { sender: 'CloudCost Weekly <digest@cloudcost.news>', label: 'CloudCost Weekly', emails30d: 28, openRate: 0.04 },
    { sender: 'SaaS Deal Radar <alerts@saasradar.co>', label: 'SaaS Deal Radar', emails30d: 24, openRate: 0.08 },
    { sender: 'Founders Dispatch <news@foundersdispatch.io>', label: 'Founders Dispatch', emails30d: 19, openRate: 0.11 },
    { sender: 'DevTools Digest <editor@devtoolsdigest.org>', label: 'DevTools Digest', emails30d: 14, openRate: 0.14 },
    { sender: 'Infra Notes <hello@infranotes.dev>', label: 'Infra Notes', emails30d: 11, openRate: 0.18 },
    { sender: 'Engineering Post <team@engpost.com>', label: 'Engineering Post', emails30d: 8, openRate: 0.62 }
  ];

  var teammateNewsletters = [
    { sender: 'SupportOps Bulletin <ops@supportdigest.com>', label: 'SupportOps Bulletin', emails30d: 22, openRate: 0.09 },
    { sender: 'Vendor Release Feed <updates@vendorfeed.io>', label: 'Vendor Release Feed', emails30d: 18, openRate: 0.12 },
    { sender: 'Security Advisories <sec@cvewatch.org>', label: 'Security Advisories', emails30d: 9, openRate: 0.78 }
  ];

  var sampleThreads = [
    { sender: 'Sample VIP Contact', subject: 'Sample contract review', waitHours: 32, priority: 'high', unreadCount: 2 },
    { sender: 'Sample Partner Lead', subject: 'Sample rollout dates', waitHours: 18, priority: 'normal', unreadCount: 1 },
    { sender: 'Sample Finance Ops', subject: 'Sample invoice confirmation', waitHours: 7, priority: 'normal', unreadCount: 1 }
  ];

  var sampleNewsletters = [
    { sender: 'Sample Weekly Digest', emails30d: 20, openRate: 0.05 },
    { sender: 'Sample Product Alerts', emails30d: 12, openRate: 0.15 }
  ];

  var threads = isTeammate ? teammateThreads : ownerThreads;
  var newsletters = isTeammate ? teammateNewsletters : ownerNewsletters;
  var currentEmbedRun = null;

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

  function syncCounts() {
    var unread = threads.filter(function (t) { return t.unreadCount > 0; });
    var vipCount = unread.filter(function (t) { return t.priority === 'high' || t.waitHours >= 24; }).length;
    var overdue = unread.filter(function (t) { return t.waitHours > 24; }).length;

    var countAllEl = document.getElementById('count-all');
    var countVipEl = document.getElementById('count-vip');
    var countNewsEl = document.getElementById('count-newsletters');
    var summaryUnreadEl = document.getElementById('summary-unread');
    var summaryOverdueEl = document.getElementById('summary-overdue');

    if (countAllEl) countAllEl.textContent = String(threads.length);
    if (countVipEl) countVipEl.textContent = String(vipCount);
    if (countNewsEl) countNewsEl.textContent = String(newsletters.length);
    if (summaryUnreadEl) summaryUnreadEl.textContent = String(unread.length);
    if (summaryOverdueEl) summaryOverdueEl.textContent = String(overdue);
  }

  function renderThreadList() {
    var listEl = document.getElementById('thread-list');
    var titleEl = document.getElementById('pane-title');
    var subEl = document.getElementById('pane-subtitle');
    if (!listEl) return;

    clearNode(listEl);

    if (activeFolder === 'newsletters') {
      if (titleEl) titleEl.textContent = 'Newsletter senders';
      if (subEl) subEl.textContent = '30-day delivery volume and your open rate';

      var sortedNews = newsletters.slice().sort(function (a, b) {
        return b.emails30d - a.emails30d;
      });
      sortedNews.forEach(function (item) {
        var card = el('article', 'newsletter-card');
        var meta = el('div', 'newsletter-meta');
        meta.appendChild(el('div', 'newsletter-name', item.label));
        meta.appendChild(el('div', 'newsletter-addr', item.sender));
        card.appendChild(meta);

        var stats = el('div', 'newsletter-stats');
        stats.appendChild(el('span', null, item.emails30d + ' emails/30d'));
        var openPct = Math.round(item.openRate * 100);
        var pill = el('span', 'open-rate-pill' + (item.openRate >= 0.4 ? ' is-good' : ''), openPct + '% opened');
        stats.appendChild(pill);
        card.appendChild(stats);
        listEl.appendChild(card);
      });
      syncCounts();
      return;
    }

    if (titleEl) titleEl.textContent = activeFolder === 'vip' ? 'VIP / Action Needed' : 'Inbox triage';
    if (subEl) {
      subEl.textContent = activeFolder === 'vip'
        ? 'High-priority or >24h waiting unread threads'
        : 'Unread threads ordered by wait time';
    }

    var visible = threads.filter(function (t) {
      if (activeFolder === 'vip') {
        return t.unreadCount > 0 && (t.priority === 'high' || t.waitHours >= 24);
      }
      return true;
    }).slice().sort(function (a, b) {
      if ((b.unreadCount > 0) !== (a.unreadCount > 0)) {
        return b.unreadCount > 0 ? 1 : -1;
      }
      return b.waitHours - a.waitHours;
    });

    visible.forEach(function (thread) {
      var isUnread = thread.unreadCount > 0;
      var card = el('article', 'thread-card ' + (isUnread ? 'is-unread' : 'is-read'));

      var avatar = el('div', 'sender-avatar', thread.initials);
      avatar.style.background = thread.color;
      avatar.setAttribute('aria-hidden', 'true');
      card.appendChild(avatar);

      var main = el('div', 'thread-main');
      var top = el('div', 'thread-top');
      var senderGrp = el('div', 'thread-sender-group');
      senderGrp.appendChild(el('span', 'thread-sender', thread.shortName));
      senderGrp.appendChild(el('span', 'thread-email', thread.sender));
      top.appendChild(senderGrp);

      var metaRight = el('div', 'thread-meta-right');
      metaRight.appendChild(el('span', 'priority-pill is-' + thread.priority, thread.priority));
      var waitCls = 'wait-badge' + (isUnread && thread.waitHours > 24 ? ' is-overdue' : '');
      metaRight.appendChild(el('span', waitCls, thread.waitHours + 'h waiting'));
      top.appendChild(metaRight);
      main.appendChild(top);

      main.appendChild(el('div', 'thread-subject', thread.subject));
      main.appendChild(el('p', 'thread-snippet', thread.snippet));

      var footer = el('div', 'thread-footer');
      footer.appendChild(
        el(
          'span',
          'thread-unread-tag',
          isUnread ? (thread.unreadCount + ' unread message' + (thread.unreadCount === 1 ? '' : 's')) : 'Read'
        )
      );

      var actionBtn = el('button', 'thread-action-btn', isUnread ? 'Mark read' : 'Mark unread');
      actionBtn.type = 'button';
      actionBtn.addEventListener('click', function () {
        thread.unreadCount = isUnread ? 0 : 1;
        renderThreadList();
      });
      footer.appendChild(actionBtn);
      main.appendChild(footer);

      card.appendChild(main);
      listEl.appendChild(card);
    });

    syncCounts();
  }

  function setupFolders() {
    var btns = document.querySelectorAll('.left-nav [data-folder]');
    btns.forEach(function (btn) {
      btn.addEventListener('click', function () {
        activeFolder = btn.getAttribute('data-folder') || 'all';
        btns.forEach(function (other) {
          var active = other === btn;
          other.classList.toggle('is-active', active);
          other.setAttribute('aria-pressed', active ? 'true' : 'false');
        });
        renderThreadList();
      });
    });
  }

  function setupMobileTabs() {
    var workspace = document.getElementById('workspace');
    var mailBtn = document.querySelector('[data-app="tab-mail"]');
    var vibesBtn = document.querySelector('[data-app="tab-vibes"]');
    if (!workspace || !mailBtn || !vibesBtn) return;

    function selectTab(tab) {
      workspace.setAttribute('data-mobile-tab', tab);
      mailBtn.classList.toggle('is-active', tab === 'mail');
      mailBtn.setAttribute('aria-pressed', tab === 'mail' ? 'true' : 'false');
      vibesBtn.classList.toggle('is-active', tab === 'vibes');
      vibesBtn.setAttribute('aria-pressed', tab === 'vibes' ? 'true' : 'false');
    }

    mailBtn.addEventListener('click', function () { selectTab('mail'); });
    vibesBtn.addEventListener('click', function () { selectTab('vibes'); });
  }

  function setupHowTurnedOnDialog() {
    var trigger = document.getElementById('how-turned-on');
    if (!trigger) return;

    var snippet = [
      "var host = VibeKit.createHost({",
      "  id: '" + (isTeammate ? 'inbox-demo-teammate' : 'inbox-demo') + "',",
      "  name: 'PulseMail',",
      "  capabilities: [",
      "    { name: 'threads.waiting', fields: { sender: 'sealed', subject: 'sealed', waitHours: 'public', priority: 'public', unreadCount: 'public' }, read: ... },",
      "    { name: 'senders.newsletters', fields: { sender: 'sealed', emails30d: 'public', openRate: 'public' }, read: ... }",
      "  ],",
      "  notOffered: ['Read email bodies or attachments', 'Send, archive, or delete emails', 'Use the internet']",
      "});",
      "VibeSpace.mountPanel(host, document.getElementById('vibe-space'), { ... });"
    ].join('\n');

    trigger.addEventListener('click', function () {
      var prevFocus = document.activeElement;
      var scrim = el('div', 'app-scrim');
      var dlg = el('div', 'app-dialog');
      dlg.setAttribute('role', 'dialog');
      dlg.setAttribute('aria-modal', 'true');

      var head = el('div', 'app-dialog-head');
      head.appendChild(el('h2', 'app-dialog-title', 'How PulseMail turned on VibeProtocol'));
      var closeBtn = el('button', 'app-dialog-close', 'Close');
      closeBtn.type = 'button';
      head.appendChild(closeBtn);
      dlg.appendChild(head);

      dlg.appendChild(
        el(
          'p',
          'app-dialog-lead',
          'PulseMail exposes wait hours, unread counts, and newsletter volume while sealing sender addresses and subjects behind host handles.'
        )
      );
      var pre = el('pre', 'app-code-block', snippet);
      dlg.appendChild(pre);
      scrim.appendChild(dlg);
      document.body.appendChild(scrim);

      function closeDialog() {
        document.removeEventListener('keydown', onKey);
        if (scrim.parentNode) scrim.parentNode.removeChild(scrim);
        if (prevFocus && typeof prevFocus.focus === 'function') prevFocus.focus();
      }
      function onKey(e) {
        if (e.key === 'Escape') closeDialog();
      }

      closeBtn.addEventListener('click', closeDialog);
      scrim.addEventListener('click', function (e) {
        if (e.target === scrim) closeDialog();
      });
      document.addEventListener('keydown', onKey);
      closeBtn.focus();
    });
  }

  function setupMailboxSyncToggle(getHost) {
    var btn = document.querySelector('[data-app="toggle-mailbox-sync"]');
    var statusPill = document.getElementById('mailbox-sync-status');
    var descEl = document.getElementById('mailbox-sync-desc');
    var cardEl = document.getElementById('mailbox-sync-card');
    var liveChip = document.getElementById('pane-live-chip');
    var liveText = document.getElementById('pane-live-text');

    function syncUi() {
      if (cardEl) cardEl.classList.toggle('is-offline', !imapOnline);
      if (statusPill) {
        statusPill.textContent = imapOnline ? 'Live' : 'Offline';
        statusPill.classList.toggle('is-live', imapOnline);
        statusPill.classList.toggle('is-offline', !imapOnline);
      }
      if (descEl) {
        descEl.textContent = imapOnline
          ? 'IMAP streaming headers & wait timers'
          : OFFLINE_REASON;
      }
      if (btn) {
        btn.textContent = imapOnline ? 'Pause mailbox sync' : 'Resume mailbox sync';
        btn.setAttribute('aria-pressed', imapOnline ? 'true' : 'false');
      }
      if (liveChip) liveChip.classList.toggle('is-offline', !imapOnline);
      if (liveText) liveText.textContent = imapOnline ? 'IMAP live' : 'IMAP paused';
    }

    if (btn) {
      btn.addEventListener('click', function () {
        imapOnline = !imapOnline;
        syncUi();
        var host = getHost();
        if (host && typeof host.notifySourceChange === 'function') {
          host.notifySourceChange();
        }
      });
    }

    syncUi();
  }

  function setupInboxAssistant(getHost) {
    var chipBtn = document.querySelector('[data-app="agent-chip"]');
    var replyBox = document.getElementById('assistant-reply');
    var replyText = document.getElementById('assistant-reply-text');
    var embedTarget = document.getElementById('assistant-embed');
    if (!chipBtn || !replyBox || !replyText || !embedTarget) return;

    chipBtn.addEventListener('click', function () {
      var host = getHost();
      if (!host || !window.VibeSpace || !window.PULSEMAIL_VIBES) return;

      var unread = threads.filter(function (t) { return t.unreadCount > 0; });
      unread.sort(function (a, b) { return b.waitHours - a.waitHours; });
      var oldest = unread[0];

      replyBox.classList.remove('is-hidden');
      chipBtn.classList.add('is-open');
      replyText.textContent = oldest
        ? 'Oldest unread reply has been waiting ' + oldest.waitHours + 'h (' + unread.length + ' unread threads total). Here is a live VIP Reply Queue — sender addresses stay sealed until rendered by PulseMail:'
        : 'All tracked threads are read right now. Embedding live VIP Reply Queue:';

      if (currentEmbedRun && typeof currentEmbedRun.stop === 'function') {
        currentEmbedRun.stop();
      }
      currentEmbedRun = window.VibeSpace.embed(
        host,
        embedTarget,
        window.PULSEMAIL_VIBES.vipSla,
        {
          defaultTitle: 'VIP Reply Queue',
          caption: 'Live SLA queue embedded from PulseMail'
        }
      );
    });
  }

  function initHostAndPanel() {
    if (!window.VibeKit || !window.VibeSpace || !window.PULSEMAIL_VIBES) {
      return null;
    }

    var personaTag = document.getElementById('persona-tag');
    if (personaTag) {
      personaTag.textContent = isTeammate ? 'teammate inbox' : 'demo host';
    }

    var host = window.VibeKit.createHost({
      id: isTeammate ? 'inbox-demo-teammate' : 'inbox-demo',
      name: 'PulseMail',
      capabilities: [
        {
          name: 'threads.waiting',
          title: 'Unread threads and waiting hours',
          fields: {
            sender: 'sealed',
            subject: 'sealed',
            waitHours: 'public',
            priority: 'public',
            unreadCount: 'public'
          },
          sealedNote: 'sender addresses and subjects stay sealed',
          sealedCannot: 'Read email bodies, addresses, or subject lines',
          status: function () {
            if (imapOnline) {
              return { available: true, mode: 'live' };
            }
            return {
              available: false,
              mode: 'offline',
              reason: OFFLINE_REASON
            };
          },
          read: function () {
            if (!imapOnline) {
              return {
                available: false,
                mode: 'offline',
                reason: OFFLINE_REASON
              };
            }
            return threads.map(function (t) {
              return {
                sender: t.sender,
                subject: t.subject,
                waitHours: t.waitHours,
                priority: t.priority,
                unreadCount: t.unreadCount
              };
            });
          },
          sample: sampleThreads
        },
        {
          name: 'senders.newsletters',
          title: 'Newsletter frequency and open rate',
          fields: {
            sender: 'sealed',
            emails30d: 'public',
            openRate: 'public'
          },
          sealedNote: 'sender addresses stay sealed',
          sealedCannot: 'Read email bodies, addresses, or subject lines',
          status: function () {
            if (imapOnline) {
              return { available: true, mode: 'live' };
            }
            return {
              available: false,
              mode: 'offline',
              reason: OFFLINE_REASON
            };
          },
          read: function () {
            if (!imapOnline) {
              return {
                available: false,
                mode: 'offline',
                reason: OFFLINE_REASON
              };
            }
            return newsletters.map(function (n) {
              return {
                sender: n.sender,
                emails30d: n.emails30d,
                openRate: n.openRate
              };
            });
          },
          sample: sampleNewsletters
        }
      ],
      notOffered: [
        'Read email bodies or attachments',
        'Send, archive, or delete emails',
        'Use the internet'
      ]
    });

    var pill = document.getElementById('protocol-pill');
    if (pill) {
      pill.addEventListener('click', function () {
        window.VibeSpace.showOffer(host);
      });
    }

    var panelTarget = document.getElementById('vibe-space');
    if (panelTarget) {
      var v = window.PULSEMAIL_VIBES;
      window.VibeSpace.mountPanel(host, panelTarget, {
        wishes: [
          { text: v.replyRadar.wish, vibe: v.replyRadar },
          { text: v.replyRadarV2.wish, remixOf: v.replyRadarV2.remixOf, vibe: v.replyRadarV2 },
          { text: v.newsletterCleanup.wish, vibe: v.newsletterCleanup }
        ],
        gallery: window.VIBE_GALLERY || [],
        shareTargets: [
          { label: 'Open as a teammate', url: 'index.html?as=teammate' },
          { label: 'Open in CartScout', url: '../shop/index.html' }
        ]
      });
    }

    return host;
  }

  function startWaitTimers() {
    var tick = 0;
    setInterval(function () {
      if (!imapOnline) return;
      var unread = threads.filter(function (t) { return t.unreadCount > 0; });
      if (unread.length === 0) return;
      var target = unread[tick % unread.length];
      tick += 1;
      if (target && target.waitHours < 72) {
        target.waitHours += 1;
        if (activeFolder !== 'newsletters') {
          renderThreadList();
        } else {
          syncCounts();
        }
      }
    }, 6000);
  }

  function syncTopbarHeight() {
    var topbar = document.querySelector('.topbar');
    if (topbar && document.documentElement && document.documentElement.style) {
      document.documentElement.style.setProperty('--topbar-h', topbar.offsetHeight + 'px');
    }
  }

  var activeHost = null;
  syncTopbarHeight();
  window.addEventListener('resize', syncTopbarHeight);
  renderThreadList();
  setupFolders();
  setupMobileTabs();
  setupHowTurnedOnDialog();
  setupMailboxSyncToggle(function () { return activeHost; });
  setupInboxAssistant(function () { return activeHost; });
  startWaitTimers();
  activeHost = initHostAndPanel();
})();
