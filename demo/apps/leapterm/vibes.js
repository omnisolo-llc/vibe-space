(function () {
  'use strict';

  var diskWatchV1 = {
    id: 'disk-watch',
    name: 'Disk Watch',
    wish: 'Show disk usage for my servers, red above 80%',
    version: 1,
    needs: ['telemetry.disk'],
    refresh: 2000,
    source: (function invoke(input) {
      var THRESHOLD = 0.8;
      var rows = (input.data && input.data['telemetry.disk']) || [];
      if (rows.length === 0) {
        return {
          state: null,
          view: {
            type: 'column',
            children: [
              { type: 'heading', text: 'Disk usage' },
              { type: 'badge', text: 'No volumes reporting', tone: 'warn' },
              { type: 'text', text: 'All servers are currently offline.', tone: 'warn' },
            ],
          },
        };
      }
      var sorted = rows.slice().sort(function (a, b) {
        return b.usedFraction - a.usedFraction;
      });
      var overCount = 0;
      for (var i = 0; i < sorted.length; i++) {
        if (sorted[i].usedFraction >= THRESHOLD) overCount++;
      }
      var thresholdPct = Math.round(THRESHOLD * 100);
      var children = [
        { type: 'heading', text: 'Disk usage' },
        {
          type: 'text',
          text: overCount + ' of ' + sorted.length + ' volumes above ' + thresholdPct + '%',
          tone: overCount > 0 ? 'danger' : 'ok',
        },
      ];
      for (var j = 0; j < sorted.length; j++) {
        var row = sorted[j];
        var pct = Math.round(row.usedFraction * 100);
        var tone = row.usedFraction >= THRESHOLD
          ? 'danger'
          : (row.usedFraction >= 0.6 ? 'warn' : 'ok');
        children.push({
          type: 'bar',
          label: row.server,
          caption: row.mount + ' \u00b7 ' + pct + '% of ' + row.sizeGb + ' GB',
          value: row.usedFraction,
          max: 1,
          tone: tone,
        });
      }
      return {
        state: null,
        view: { type: 'column', children: children },
      };
    }).toString(),
  };

  var diskWatchV2 = {
    id: 'disk-watch',
    name: 'Disk Watch',
    wish: 'Make it red above 90% and show only the worst three',
    version: 2,
    needs: ['telemetry.disk'],
    refresh: 2000,
    source: (function invoke(input) {
      var THRESHOLD = 0.9;
      var TOP_LIMIT = 3;
      var limitLabel = TOP_LIMIT === 3 ? 'three' : String(TOP_LIMIT);
      var rows = (input.data && input.data['telemetry.disk']) || [];
      if (rows.length === 0) {
        return {
          state: null,
          view: {
            type: 'column',
            children: [
              { type: 'heading', text: 'Disk usage \u00b7 worst ' + limitLabel },
              { type: 'badge', text: 'No volumes reporting', tone: 'warn' },
              { type: 'text', text: 'All servers are currently offline.', tone: 'warn' },
            ],
          },
        };
      }
      var sorted = rows.slice().sort(function (a, b) {
        return b.usedFraction - a.usedFraction;
      });
      var overCount = 0;
      for (var i = 0; i < sorted.length; i++) {
        if (sorted[i].usedFraction >= THRESHOLD) overCount++;
      }
      var thresholdPct = Math.round(THRESHOLD * 100);
      var worst = sorted.slice(0, TOP_LIMIT);
      var children = [
        { type: 'heading', text: 'Disk usage \u00b7 worst ' + limitLabel },
        {
          type: 'text',
          text: overCount + ' of ' + sorted.length + ' volumes above ' + thresholdPct + '%',
          tone: overCount > 0 ? 'danger' : 'ok',
        },
      ];
      for (var j = 0; j < worst.length; j++) {
        var row = worst[j];
        var pct = Math.round(row.usedFraction * 100);
        var tone = row.usedFraction >= THRESHOLD
          ? 'danger'
          : (row.usedFraction >= 0.6 ? 'warn' : 'ok');
        children.push({
          type: 'bar',
          label: row.server,
          caption: row.mount + ' \u00b7 ' + pct + '% of ' + row.sizeGb + ' GB',
          value: row.usedFraction,
          max: 1,
          tone: tone,
        });
      }
      return {
        state: null,
        view: { type: 'column', children: children },
      };
    }).toString(),
  };

  var serverLoad = {
    id: 'server-load',
    name: 'CPU and memory',
    wish: 'Why is db-1 slow?',
    version: 1,
    needs: ['telemetry.load'],
    refresh: 2000,
    source: (function invoke(input) {
      var WARN_LEVEL = 0.6;
      var DANGER_LEVEL = 0.8;
      var rows = (input.data && input.data['telemetry.load']) || [];

      function toneFor(val) {
        if (val >= DANGER_LEVEL) return 'danger';
        if (val >= WARN_LEVEL) return 'warn';
        return 'ok';
      }

      var prev = input.state && typeof input.state === 'object' ? input.state : {};
      var st = {
        showAll: !!prev.showAll,
        lastReading: prev.lastReading || null,
        targetServer: prev.targetServer || null,
      };

      if (
        (input.command === 'open' || input.command === 'refresh') &&
        input.args &&
        input.args.server &&
        input.args.server.sealed
      ) {
        if (!st.targetServer || st.targetServer.sealed !== input.args.server.sealed) {
          st.lastReading = null;
          st.showAll = false;
        }
        st.targetServer = input.args.server;
      }

      if (input.command === 'clear-target') {
        st.showAll = true;
      } else if (input.command === 'restore-target') {
        st.showAll = false;
      }

      var targetSealed = st.targetServer && st.targetServer.sealed ? st.targetServer.sealed : null;
      var match = null;
      if (targetSealed) {
        for (var i = 0; i < rows.length; i++) {
          if (rows[i].server && rows[i].server.sealed === targetSealed) {
            match = rows[i];
            break;
          }
        }
      }

      if (match) {
        st.lastReading = {
          server: match.server,
          cpu: match.cpu,
          mem: match.mem,
          cpuHistory: Array.isArray(match.cpuHistory) ? match.cpuHistory.slice() : [],
          memHistory: Array.isArray(match.memHistory) ? match.memHistory.slice() : [],
        };
      }

      if (targetSealed && !st.showAll) {
        if (match) {
          return {
            state: st,
            view: {
              type: 'column',
              children: [
                { type: 'heading', text: match.server },
                {
                  type: 'row',
                  children: [
                    {
                      type: 'stat',
                      label: 'CPU',
                      value: Math.round(match.cpu * 100) + '%',
                      tone: toneFor(match.cpu),
                    },
                    {
                      type: 'stat',
                      label: 'Memory',
                      value: Math.round(match.mem * 100) + '%',
                      tone: toneFor(match.mem),
                    },
                  ],
                },
                { type: 'text', text: 'CPU, last minute' },
                {
                  type: 'sparkline',
                  values: st.lastReading.cpuHistory,
                  tone: toneFor(match.cpu),
                },
                { type: 'text', text: 'Memory, last minute' },
                {
                  type: 'sparkline',
                  values: st.lastReading.memHistory,
                  tone: toneFor(match.mem),
                },
              ],
            },
          };
        }

        var offlineChildren = [
          { type: 'heading', text: st.targetServer },
          { type: 'badge', text: 'Target server offline', tone: 'warn' },
        ];
        if (st.lastReading) {
          offlineChildren.push({
            type: 'text',
            text: 'Last known reading before server went offline',
            tone: 'warn',
          });
          offlineChildren.push({
            type: 'row',
            children: [
              {
                type: 'stat',
                label: 'CPU',
                value: Math.round(st.lastReading.cpu * 100) + '%',
                tone: 'warn',
              },
              {
                type: 'stat',
                label: 'Memory',
                value: Math.round(st.lastReading.mem * 100) + '%',
                tone: 'warn',
              },
            ],
          });
          offlineChildren.push({ type: 'text', text: 'CPU, last minute' });
          offlineChildren.push({
            type: 'sparkline',
            values: st.lastReading.cpuHistory || [],
            tone: 'warn',
          });
          offlineChildren.push({ type: 'text', text: 'Memory, last minute' });
          offlineChildren.push({
            type: 'sparkline',
            values: st.lastReading.memHistory || [],
            tone: 'warn',
          });
        } else {
          offlineChildren.push({
            type: 'text',
            text: 'No reading captured yet while target server is offline.',
            tone: 'warn',
          });
        }
        offlineChildren.push({
          type: 'button',
          text: 'Show all online servers',
          command: 'clear-target',
          tone: 'default',
        });
        return {
          state: st,
          view: { type: 'column', children: offlineChildren },
        };
      }

      var sorted = rows.slice().sort(function (a, b) {
        return b.cpu - a.cpu;
      });
      var list = [{ type: 'heading', text: 'CPU and memory' }];
      if (sorted.length === 0) {
        list.push({ type: 'badge', text: 'No online servers reporting', tone: 'warn' });
      } else {
        for (var j = 0; j < sorted.length; j++) {
          var r = sorted[j];
          list.push({
            type: 'bar',
            label: r.server,
            caption: 'CPU ' + Math.round(r.cpu * 100) + '% \u00b7 Mem ' + Math.round(r.mem * 100) + '%',
            value: r.cpu,
            max: 1,
            tone: toneFor(r.cpu),
          });
        }
      }
      if (targetSealed) {
        list.push({
          type: 'button',
          text: 'Back to target server',
          command: 'restore-target',
          tone: 'default',
        });
      }
      return {
        state: st,
        view: { type: 'column', children: list },
      };
    }).toString(),
  };

  window.LEAPTERM_VIBES = {
    diskWatchV1: diskWatchV1,
    diskWatchV2: diskWatchV2,
    serverLoad: serverLoad,
  };
})();
