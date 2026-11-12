(function () {
  'use strict';

  var params = new URLSearchParams(window.location.search);
  var isTeammate = params.get('as') === 'teammate';

  function clamp(val, min, max) {
    return Math.min(max, Math.max(min, val));
  }

  function round3(val) {
    return Math.round(val * 1000) / 1000;
  }

  function makeHistory(base, spread, min, max) {
    var points = [];
    var cur = base;
    for (var i = 0; i < 30; i++) {
      cur = clamp(cur + (Math.random() - 0.5) * spread, min, max);
      points.push(round3(cur));
    }
    return points;
  }

  function createServers(teammateMode) {
    if (teammateMode) {
      return [
        {
          name: 'api-east-1.corp.example',
          shortName: 'api-east-1',
          address: '172.18.10.4',
          cpu: 0.91,
          cpuRange: [0.85, 0.97],
          cpuStep: 0.03,
          mem: 0.59,
          memRange: [0.57, 0.61],
          memStep: 0.01,
          cpuHistory: makeHistory(0.91, 0.04, 0.85, 0.97),
          memHistory: makeHistory(0.59, 0.015, 0.57, 0.61),
          volumes: [
            { mount: '/', usedFraction: 0.84, min: 0.81, max: 0.87, sizeGb: 500 },
            { mount: '/var/data', usedFraction: 0.72, min: 0.69, max: 0.75, sizeGb: 1500 },
          ],
        },
        {
          name: 'api-east-2.corp.example',
          shortName: 'api-east-2',
          address: '172.18.10.5',
          cpu: 0.41,
          cpuRange: [0.30, 0.54],
          cpuStep: 0.05,
          mem: 0.51,
          memRange: [0.46, 0.56],
          memStep: 0.02,
          cpuHistory: makeHistory(0.41, 0.06, 0.30, 0.54),
          memHistory: makeHistory(0.51, 0.02, 0.46, 0.56),
          volumes: [
            { mount: '/', usedFraction: 0.46, min: 0.42, max: 0.50, sizeGb: 500 },
          ],
        },
        {
          name: 'worker-1.corp.example',
          shortName: 'worker-1',
          address: '172.18.20.14',
          cpu: 0.58,
          cpuRange: [0.46, 0.70],
          cpuStep: 0.05,
          mem: 0.55,
          memRange: [0.50, 0.60],
          memStep: 0.02,
          cpuHistory: makeHistory(0.58, 0.05, 0.46, 0.70),
          memHistory: makeHistory(0.55, 0.02, 0.50, 0.60),
          volumes: [
            { mount: '/', usedFraction: 0.92, min: 0.905, max: 0.945, sizeGb: 250 },
            { mount: '/tmp', usedFraction: 0.57, min: 0.53, max: 0.61, sizeGb: 400 },
          ],
        },
        {
          name: 'worker-2.corp.example',
          shortName: 'worker-2',
          address: '172.18.20.15',
          cpu: 0.35,
          cpuRange: [0.24, 0.48],
          cpuStep: 0.05,
          mem: 0.49,
          memRange: [0.44, 0.54],
          memStep: 0.02,
          cpuHistory: makeHistory(0.35, 0.05, 0.24, 0.48),
          memHistory: makeHistory(0.49, 0.02, 0.44, 0.54),
          volumes: [
            { mount: '/', usedFraction: 0.64, min: 0.60, max: 0.68, sizeGb: 250 },
          ],
        },
        {
          name: 'redis-1.corp.example',
          shortName: 'redis-1',
          address: '172.18.30.8',
          cpu: 0.22,
          cpuRange: [0.15, 0.32],
          cpuStep: 0.04,
          mem: 0.78,
          memRange: [0.74, 0.82],
          memStep: 0.02,
          cpuHistory: makeHistory(0.22, 0.04, 0.15, 0.32),
          memHistory: makeHistory(0.78, 0.02, 0.74, 0.82),
          volumes: [
            { mount: '/', usedFraction: 0.34, min: 0.30, max: 0.38, sizeGb: 120 },
          ],
        },
      ];
    }

    return [
      {
        name: 'db-1.prod.internal',
        shortName: 'db-1',
        address: '10.0.4.11',
        cpu: 0.92,
        cpuRange: [0.85, 0.97],
        cpuStep: 0.03,
        mem: 0.62,
        memRange: [0.60, 0.64],
        memStep: 0.01,
        cpuHistory: makeHistory(0.92, 0.04, 0.85, 0.97),
        memHistory: makeHistory(0.62, 0.015, 0.60, 0.64),
        volumes: [
          { mount: '/', usedFraction: 0.83, min: 0.81, max: 0.86, sizeGb: 500 },
          { mount: '/var/lib/pg', usedFraction: 0.74, min: 0.71, max: 0.77, sizeGb: 2000 },
        ],
      },
      {
        name: 'db-2.prod.internal',
        shortName: 'db-2',
        address: '10.0.4.12',
        cpu: 0.38,
        cpuRange: [0.28, 0.48],
        cpuStep: 0.04,
        mem: 0.58,
        memRange: [0.53, 0.63],
        memStep: 0.02,
        cpuHistory: makeHistory(0.38, 0.05, 0.28, 0.48),
        memHistory: makeHistory(0.58, 0.02, 0.53, 0.63),
        volumes: [
          { mount: '/', usedFraction: 0.44, min: 0.40, max: 0.48, sizeGb: 500 },
          { mount: '/var/lib/pg', usedFraction: 0.67, min: 0.63, max: 0.71, sizeGb: 2000 },
        ],
      },
      {
        name: 'web-1.prod.internal',
        shortName: 'web-1',
        address: '10.0.2.21',
        cpu: 0.54,
        cpuRange: [0.42, 0.66],
        cpuStep: 0.05,
        mem: 0.48,
        memRange: [0.43, 0.54],
        memStep: 0.02,
        cpuHistory: makeHistory(0.54, 0.05, 0.42, 0.66),
        memHistory: makeHistory(0.48, 0.02, 0.43, 0.54),
        volumes: [
          { mount: '/', usedFraction: 0.91, min: 0.905, max: 0.94, sizeGb: 160 },
          { mount: '/var/log', usedFraction: 0.54, min: 0.50, max: 0.58, sizeGb: 320 },
        ],
      },
      {
        name: 'web-2.prod.internal',
        shortName: 'web-2',
        address: '10.0.2.22',
        cpu: 0.44,
        cpuRange: [0.32, 0.56],
        cpuStep: 0.05,
        mem: 0.46,
        memRange: [0.41, 0.52],
        memStep: 0.02,
        cpuHistory: makeHistory(0.44, 0.05, 0.32, 0.56),
        memHistory: makeHistory(0.46, 0.02, 0.41, 0.52),
        volumes: [
          { mount: '/', usedFraction: 0.49, min: 0.45, max: 0.53, sizeGb: 160 },
        ],
      },
      {
        name: 'cache-1.prod.internal',
        shortName: 'cache-1',
        address: '10.0.6.5',
        cpu: 0.24,
        cpuRange: [0.16, 0.34],
        cpuStep: 0.04,
        mem: 0.76,
        memRange: [0.72, 0.80],
        memStep: 0.02,
        cpuHistory: makeHistory(0.24, 0.04, 0.16, 0.34),
        memHistory: makeHistory(0.76, 0.02, 0.72, 0.80),
        volumes: [
          { mount: '/', usedFraction: 0.31, min: 0.27, max: 0.35, sizeGb: 120 },
        ],
      },
    ];
  }

  var servers = createServers(isTeammate);
  for (var si = 0; si < servers.length; si++) {
    servers[si].online = true;
  }
  var hotServer = servers[0];
  var telemetryOnline = true;
  var activeHost = null;

  function notifyHostSourceChange() {
    if (activeHost && typeof activeHost.notifySourceChange === 'function') {
      activeHost.notifySourceChange();
    }
  }

  function driftServers() {
    if (!telemetryOnline) return;
    for (var i = 0; i < servers.length; i++) {
      var srv = servers[i];
      if (!srv.online) continue;
      srv.cpu = round3(clamp(
        srv.cpu + (Math.random() - 0.5) * srv.cpuStep,
        srv.cpuRange[0],
        srv.cpuRange[1]
      ));
      srv.mem = round3(clamp(
        srv.mem + (Math.random() - 0.5) * srv.memStep,
        srv.memRange[0],
        srv.memRange[1]
      ));
      srv.cpuHistory.push(srv.cpu);
      if (srv.cpuHistory.length > 30) srv.cpuHistory.shift();
      srv.memHistory.push(srv.mem);
      if (srv.memHistory.length > 30) srv.memHistory.shift();

      for (var j = 0; j < srv.volumes.length; j++) {
        var vol = srv.volumes[j];
        vol.usedFraction = round3(clamp(
          vol.usedFraction + (Math.random() - 0.5) * 0.012,
          vol.min,
          vol.max
        ));
      }
    }
  }

  function serverTone(srv) {
    if (!srv.online) return 'offline';
    if (!telemetryOnline) return 'warn';
    var maxDisk = 0;
    for (var i = 0; i < srv.volumes.length; i++) {
      if (srv.volumes[i].usedFraction > maxDisk) {
        maxDisk = srv.volumes[i].usedFraction;
      }
    }
    if (srv.cpu >= 0.85 || maxDisk >= 0.9) return 'danger';
    if (srv.cpu >= 0.6 || maxDisk >= 0.8) return 'warn';
    return 'ok';
  }

  function renderTelemetryControl() {
    var card = document.getElementById('lt-telemetry-card');
    var dot = document.getElementById('lt-telemetry-dot');
    var stateEl = document.getElementById('lt-telemetry-state');
    var btn = document.getElementById('lt-telemetry-toggle');
    if (card) card.classList.toggle('is-offline', !telemetryOnline);
    if (dot) dot.className = 'lt-status-dot ' + (telemetryOnline ? 'is-ok' : 'is-danger');
    if (stateEl) stateEl.textContent = telemetryOnline ? 'Live' : 'Offline';
    if (btn) {
      btn.textContent = telemetryOnline ? 'Go offline' : 'Reconnect';
      btn.setAttribute('aria-pressed', telemetryOnline ? 'false' : 'true');
    }
  }

  var serverDomItems = [];

  function renderServerList() {
    var listEl = document.getElementById('lt-server-list');
    var countEl = document.getElementById('lt-server-count');
    if (!listEl) return;

    if (serverDomItems.length === 0) {
      listEl.textContent = '';
      for (var i = 0; i < servers.length; i++) {
        (function (srv) {
          var li = document.createElement('li');
          li.className = 'lt-server-item';

          var top = document.createElement('div');
          top.className = 'lt-server-top';

          var dot = document.createElement('span');
          dot.className = 'lt-status-dot';
          dot.setAttribute('aria-hidden', 'true');

          var nameEl = document.createElement('span');
          nameEl.className = 'lt-server-name';
          nameEl.textContent = srv.name;

          top.appendChild(dot);
          top.appendChild(nameEl);

          var bottom = document.createElement('div');
          bottom.className = 'lt-server-bottom';

          var meta = document.createElement('div');
          meta.className = 'lt-server-meta';

          var addrEl = document.createElement('span');
          addrEl.textContent = srv.address;

          var metricsEl = document.createElement('span');
          metricsEl.className = 'lt-server-metrics';

          meta.appendChild(addrEl);
          meta.appendChild(metricsEl);

          var toggleBtn = document.createElement('button');
          toggleBtn.type = 'button';
          toggleBtn.className = 'lt-srv-toggle';
          toggleBtn.setAttribute('data-app', 'toggle-server');
          toggleBtn.setAttribute('data-server', srv.name);
          toggleBtn.addEventListener('click', function () {
            srv.online = !srv.online;
            renderServerList();
            notifyHostSourceChange();
          });

          bottom.appendChild(meta);
          bottom.appendChild(toggleBtn);
          li.appendChild(top);
          li.appendChild(bottom);
          listEl.appendChild(li);
          serverDomItems.push({
            li: li,
            dot: dot,
            metricsEl: metricsEl,
            toggleBtn: toggleBtn,
          });
        })(servers[i]);
      }
    }

    var onlineCount = 0;
    for (var j = 0; j < servers.length; j++) {
      var item = serverDomItems[j];
      var s = servers[j];
      if (s.online) onlineCount++;
      item.li.classList.toggle('is-offline', !s.online);
      item.dot.className = 'lt-status-dot is-' + serverTone(s);
      if (!s.online) {
        item.metricsEl.textContent = 'Offline';
      } else if (!telemetryOnline) {
        item.metricsEl.textContent = 'Feed off';
      } else {
        item.metricsEl.textContent = 'CPU ' + Math.round(s.cpu * 100) + '%';
      }
      item.toggleBtn.textContent = s.online ? 'Go offline' : 'Go online';
      item.toggleBtn.setAttribute('aria-pressed', s.online ? 'false' : 'true');
    }

    if (countEl) {
      if (!telemetryOnline) {
        countEl.textContent = 'Feed offline';
      } else if (onlineCount === servers.length) {
        countEl.textContent = onlineCount + ' online';
      } else {
        countEl.textContent = onlineCount + '/' + servers.length + ' online';
      }
    }
  }

  function renderChrome() {
    var tagEl = document.getElementById('lt-host-tag');
    var termTitleEl = document.getElementById('lt-term-title');
    var termBodyEl = document.getElementById('lt-term-body');
    var chipEl = document.getElementById('lt-agent-chip');

    if (isTeammate) {
      document.title = "LeapTerm — teammate's copy";
      if (tagEl) tagEl.textContent = "teammate's copy";
    } else {
      document.title = 'LeapTerm — demo host';
      if (tagEl) tagEl.textContent = 'demo host';
    }

    if (termTitleEl) {
      termTitleEl.textContent = 'ops@' + hotServer.name + ' \u2014 bash';
    }

    if (termBodyEl) {
      var primaryVol = hotServer.volumes[0];
      var secondaryVol = hotServer.volumes[1];
      var lines = [
        '$ ssh ops@' + hotServer.name,
        'Connected to ' + hotServer.address + ' (Ubuntu 24.04 LTS)',
        'ops@' + hotServer.shortName + ':~$ uptime',
        ' 06:00:14 up 48 days, 14:12,  1 user,  load average: 7.84, 7.62, 7.19',
        'ops@' + hotServer.shortName + ':~$ df -h ' + primaryVol.mount +
          (secondaryVol ? ' ' + secondaryVol.mount : ''),
        'Filesystem      Size  Used Avail Use% Mounted on',
        '/dev/nvme0n1p1  ' + primaryVol.sizeGb + 'G  ' +
          Math.round(primaryVol.sizeGb * primaryVol.usedFraction) + 'G   ' +
          Math.round(primaryVol.sizeGb * (1 - primaryVol.usedFraction)) + 'G  ' +
          Math.round(primaryVol.usedFraction * 100) + '% ' + primaryVol.mount,
      ];
      if (secondaryVol) {
        lines.push(
          '/dev/nvme1n1   ' + secondaryVol.sizeGb + 'G ' +
          Math.round(secondaryVol.sizeGb * secondaryVol.usedFraction) + 'G  ' +
          Math.round(secondaryVol.sizeGb * (1 - secondaryVol.usedFraction)) + 'G  ' +
          Math.round(secondaryVol.usedFraction * 100) + '% ' + secondaryVol.mount
        );
      }
      lines.push('ops@' + hotServer.shortName + ':~$ _');
      termBodyEl.textContent = lines.join('\n');
    }

    if (chipEl) {
      chipEl.textContent = 'Why is ' + hotServer.shortName + ' slow?';
    }
  }

  function buildSampleLoad(baseCpu, baseMem) {
    return {
      cpu: baseCpu,
      mem: baseMem,
      cpuHistory: makeHistory(baseCpu, 0.04, Math.max(0.1, baseCpu - 0.08), Math.min(0.98, baseCpu + 0.08)),
      memHistory: makeHistory(baseMem, 0.02, Math.max(0.1, baseMem - 0.05), Math.min(0.95, baseMem + 0.05)),
    };
  }

  function createLeapTermHost() {
    var sA = buildSampleLoad(0.91, 0.62);
    var sB = buildSampleLoad(0.48, 0.54);
    var sC = buildSampleLoad(0.27, 0.71);

    function telemetryStatus() {
      if (!telemetryOnline) {
        return {
          available: false,
          mode: 'offline',
          reason: 'SSH telemetry feed disconnected',
        };
      }
      return { available: true, mode: 'live' };
    }

    return window.VibeKit.createHost({
      id: isTeammate ? 'leapterm-demo-teammate' : 'leapterm-demo',
      name: 'LeapTerm',
      capabilities: [
        {
          name: 'telemetry.disk',
          title: 'Disk usage of your servers',
          fields: {
            server: 'sealed',
            mount: 'public',
            usedFraction: 'public',
            sizeGb: 'public',
          },
          sealedNote: 'server names stay sealed',
          sealedCannot: 'See server names or addresses',
          status: telemetryStatus,
          read: function () {
            if (!telemetryOnline) return telemetryStatus();
            var rows = [];
            for (var i = 0; i < servers.length; i++) {
              var srv = servers[i];
              if (!srv.online) continue;
              for (var j = 0; j < srv.volumes.length; j++) {
                var vol = srv.volumes[j];
                rows.push({
                  server: srv.name,
                  mount: vol.mount,
                  usedFraction: vol.usedFraction,
                  sizeGb: vol.sizeGb,
                });
              }
            }
            return rows;
          },
          sample: [
            { server: 'sample-a', mount: '/', usedFraction: 0.92, sizeGb: 256 },
            { server: 'sample-a', mount: '/var/log', usedFraction: 0.64, sizeGb: 512 },
            { server: 'sample-b', mount: '/', usedFraction: 0.83, sizeGb: 500 },
            { server: 'sample-c', mount: '/', usedFraction: 0.41, sizeGb: 200 },
          ],
        },
        {
          name: 'telemetry.load',
          title: 'CPU and memory of your servers',
          fields: {
            server: 'sealed',
            cpu: 'public',
            mem: 'public',
            cpuHistory: 'public',
            memHistory: 'public',
          },
          sealedNote: 'server names stay sealed',
          sealedCannot: 'See server names or addresses',
          status: telemetryStatus,
          read: function () {
            if (!telemetryOnline) return telemetryStatus();
            var rows = [];
            for (var i = 0; i < servers.length; i++) {
              var srv = servers[i];
              if (!srv.online) continue;
              rows.push({
                server: srv.name,
                cpu: srv.cpu,
                mem: srv.mem,
                cpuHistory: srv.cpuHistory.slice(),
                memHistory: srv.memHistory.slice(),
              });
            }
            return rows;
          },
          sample: [
            {
              server: 'sample-a',
              cpu: sA.cpu,
              mem: sA.mem,
              cpuHistory: sA.cpuHistory,
              memHistory: sA.memHistory,
            },
            {
              server: 'sample-b',
              cpu: sB.cpu,
              mem: sB.mem,
              cpuHistory: sB.cpuHistory,
              memHistory: sB.memHistory,
            },
            {
              server: 'sample-c',
              cpu: sC.cpu,
              mem: sC.mem,
              cpuHistory: sC.cpuHistory,
              memHistory: sC.memHistory,
            },
          ],
        },
      ],
      notOffered: [
        'Run commands',
        'Read files, keys or passwords',
        'Use the internet',
      ],
    });
  }

  function setupTabs() {
    var workspace = document.getElementById('lt-workspace');
    var tabButtons = document.querySelectorAll('.lt-tab-btn');

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
    var trigger = document.getElementById('lt-how-link');
    var scrim = document.getElementById('lt-how-scrim');
    var closeBtn = document.getElementById('lt-how-close');
    var codeEl = document.getElementById('lt-how-code');

    if (codeEl) {
      codeEl.textContent = [
        "const host = VibeKit.createHost({",
        "  id: '" + (isTeammate ? 'leapterm-demo-teammate' : 'leapterm-demo') + "',",
        "  name: 'LeapTerm',",
        "  capabilities: [",
        "    {",
        "      name: 'telemetry.disk',",
        "      title: 'Disk usage of your servers',",
        "      fields: {",
        "        server: 'sealed',",
        "        mount: 'public',",
        "        usedFraction: 'public',",
        "        sizeGb: 'public',",
        "      },",
        "      sealedNote: 'server names stay sealed',",
        "      sealedCannot: 'See server names or addresses',",
        "      status: () => ({ available: telemetryOnline, mode: telemetryOnline ? 'live' : 'offline' }),",
        "      read: () => servers.filter(s => s.online).flatMap(/* live volumes */),",
        "      sample: [ /* 3 synthetic servers */ ],",
        "    },",
        "    {",
        "      name: 'telemetry.load',",
        "      title: 'CPU and memory of your servers',",
        "      fields: {",
        "        server: 'sealed',",
        "        cpu: 'public',",
        "        mem: 'public',",
        "        cpuHistory: 'public',",
        "        memHistory: 'public',",
        "      },",
        "      sealedNote: 'server names stay sealed',",
        "      sealedCannot: 'See server names or addresses',",
        "      status: () => ({ available: telemetryOnline, mode: telemetryOnline ? 'live' : 'offline' }),",
        "      read: () => servers.filter(s => s.online).map(/* live cpu, mem & 30-pt history */),",
        "      sample: [ /* 3 synthetic servers */ ],",
        "    },",
        "  ],",
        "  notOffered: [",
        "    'Run commands',",
        "    'Read files, keys or passwords',",
        "    'Use the internet',",
        "  ],",
        "});",
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
    var chip = document.getElementById('lt-agent-chip');
    var suggestions = document.getElementById('lt-chat-suggestions');
    var messages = document.getElementById('lt-chat-messages');
    var empty = document.getElementById('lt-chat-empty');
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
      userBubble.className = 'lt-msg lt-msg-user';
      userBubble.textContent = 'Why is ' + hotServer.shortName + ' slow?';
      messages.appendChild(userBubble);

      var typing = document.createElement('div');
      typing.className = 'lt-typing';
      typing.textContent = 'Checking telemetry';
      var dots = document.createElement('span');
      dots.className = 'lt-typing-dots';
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
        agentMsg.className = 'lt-msg lt-msg-agent';
        agentMsg.setAttribute('data-app', 'agent-message');

        var textEl = document.createElement('p');
        textEl.className = 'lt-msg-agent-text';
        textEl.textContent =
          hotServer.shortName +
          ' has been close to full CPU for the last few minutes, while memory is steady. Here is a live view.';
        agentMsg.appendChild(textEl);

        var embedBox = document.createElement('div');
        embedBox.className = 'lt-msg-embed';
        agentMsg.appendChild(embedBox);
        messages.appendChild(agentMsg);

        if (activeEmbed && typeof activeEmbed.stop === 'function') {
          activeEmbed.stop();
        }
        if (window.VibeSpace && window.LEAPTERM_VIBES && window.LEAPTERM_VIBES.serverLoad) {
          activeEmbed = window.VibeSpace.embed(
            host,
            embedBox,
            window.LEAPTERM_VIBES.serverLoad,
            {
              args: { server: host.seal(hotServer.name) },
              defaultTitle: 'CPU and memory \u00b7 ' + hotServer.shortName,
            }
          );
        }
        messages.scrollTop = messages.scrollHeight;
        pending = false;
      }, 450);
    });
  }

  function init() {
    renderChrome();
    renderTelemetryControl();
    renderServerList();
    setupTabs();
    setupHowDialog();

    var telemetryToggle = document.getElementById('lt-telemetry-toggle');
    if (telemetryToggle) {
      telemetryToggle.addEventListener('click', function () {
        telemetryOnline = !telemetryOnline;
        renderTelemetryControl();
        renderServerList();
        notifyHostSourceChange();
      });
    }

    window.setInterval(function () {
      driftServers();
      renderServerList();
    }, 2000);

    if (!window.VibeKit || !window.VibeSpace) return;

    var host = createLeapTermHost();
    activeHost = host;

    var offerPill = document.getElementById('lt-offer-pill');
    if (offerPill) {
      offerPill.addEventListener('click', function () {
        window.VibeSpace.showOffer(host);
      });
    }

    var panelEl = document.getElementById('vibe-space');
    var vibes = window.LEAPTERM_VIBES || {};
    var gallery = window.VIBE_GALLERY || [];

    if (panelEl) {
      window.VibeSpace.mountPanel(host, panelEl, {
        wishes: [
          {
            text: vibes.diskWatchV1.wish,
            vibe: vibes.diskWatchV1,
          },
          {
            text: vibes.diskWatchV2.wish,
            vibe: vibes.diskWatchV2,
            remixOf: 'disk-watch',
          },
        ],
        gallery: gallery,
        shareTargets: [
          { label: 'Open as a teammate', url: 'index.html?as=teammate' },
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
