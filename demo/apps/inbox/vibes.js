(function () {
  'use strict';

  var replyRadarSource = (function invoke(input) {
    var SLA_HOURS = 24;
    var TOP_LIMIT = 5;
    var rows = (input.data && input.data['threads.waiting']) || [];

    var unread = [];
    for (var i = 0; i < rows.length; i++) {
      var r = rows[i];
      if (r && (r.unreadCount || 0) > 0) {
        unread.push(r);
      }
    }

    unread.sort(function (a, b) {
      return (b.waitHours || 0) - (a.waitHours || 0);
    });

    var shown = unread.slice(0, TOP_LIMIT);
    var maxHours = Math.max(SLA_HOURS, 1);
    for (var j = 0; j < shown.length; j++) {
      var wh = Number(shown[j].waitHours || 0);
      if (wh > maxHours) maxHours = wh;
    }

    var breachedCount = 0;
    for (var k = 0; k < unread.length; k++) {
      if ((unread[k].waitHours || 0) > SLA_HOURS) {
        breachedCount += 1;
      }
    }

    var headingText = SLA_HOURS === 24 && TOP_LIMIT === 5
      ? 'Reply SLA radar (>24h)'
      : 'Worst ' + TOP_LIMIT + ' waiting (SLA ' + SLA_HOURS + 'h)';

    var children = [
      { type: 'heading', text: headingText },
      {
        type: 'row',
        children: [
          {
            type: 'stat',
            label: 'Overdue',
            value: String(breachedCount),
            tone: breachedCount > 0 ? 'danger' : 'ok'
          },
          {
            type: 'badge',
            text: breachedCount > 0 ? 'Red above ' + SLA_HOURS + 'h' : 'Within SLA',
            tone: breachedCount > 0 ? 'danger' : 'ok'
          }
        ]
      }
    ];

    if (rows.length === 0) {
      children.push({ type: 'badge', text: 'No threads waiting', tone: 'ok' });
      children.push({ type: 'text', text: 'Your unread queue is currently empty.' });
    } else if (shown.length === 0) {
      children.push({ type: 'badge', text: 'All caught up', tone: 'ok' });
      children.push({ type: 'text', text: 'Every tracked thread has already been read.' });
    } else {
      for (var m = 0; m < shown.length; m++) {
        var row = shown[m];
        var wait = Number(row.waitHours || 0);
        var prio = String(row.priority || 'normal');
        var unreadCnt = Number(row.unreadCount || 1);
        var tone = wait > SLA_HOURS
          ? 'danger'
          : (wait >= SLA_HOURS * 0.75 ? 'warn' : 'ok');
        children.push({
          type: 'bar',
          label: row.sender,
          caption: wait + 'h waiting \u00b7 ' + unreadCnt + ' unread \u00b7 ' + prio,
          value: wait,
          max: maxHours,
          tone: tone
        });
      }
    }

    return {
      state: input.state || null,
      view: {
        type: 'column',
        children: children
      }
    };
  }).toString();

  var replyRadarV2Source = (function invoke(input) {
    var SLA_HOURS = 12;
    var TOP_LIMIT = 3;
    var rows = (input.data && input.data['threads.waiting']) || [];

    var unread = [];
    for (var i = 0; i < rows.length; i++) {
      var r = rows[i];
      if (r && (r.unreadCount || 0) > 0) {
        unread.push(r);
      }
    }

    unread.sort(function (a, b) {
      return (b.waitHours || 0) - (a.waitHours || 0);
    });

    var shown = unread.slice(0, TOP_LIMIT);
    var maxHours = Math.max(SLA_HOURS, 1);
    for (var j = 0; j < shown.length; j++) {
      var wh = Number(shown[j].waitHours || 0);
      if (wh > maxHours) maxHours = wh;
    }

    var breachedCount = 0;
    for (var k = 0; k < unread.length; k++) {
      if ((unread[k].waitHours || 0) > SLA_HOURS) {
        breachedCount += 1;
      }
    }

    var children = [
      { type: 'heading', text: 'Worst ' + TOP_LIMIT + ' waiting (>' + SLA_HOURS + 'h)' },
      {
        type: 'row',
        children: [
          {
            type: 'stat',
            label: 'Over ' + SLA_HOURS + 'h',
            value: String(breachedCount),
            tone: breachedCount > 0 ? 'danger' : 'ok'
          },
          {
            type: 'badge',
            text: breachedCount > 0 ? 'Action needed' : 'Within ' + SLA_HOURS + 'h SLA',
            tone: breachedCount > 0 ? 'danger' : 'ok'
          }
        ]
      }
    ];

    if (shown.length === 0) {
      children.push({ type: 'badge', text: 'No unread backlog', tone: 'ok' });
    } else {
      for (var m = 0; m < shown.length; m++) {
        var row = shown[m];
        var wait = Number(row.waitHours || 0);
        var tone = wait > SLA_HOURS ? 'danger' : (wait >= SLA_HOURS * 0.75 ? 'warn' : 'ok');
        children.push({
          type: 'bar',
          label: row.sender,
          caption: wait + 'h waiting \u00b7 ' + String(row.priority || 'normal'),
          value: wait,
          max: maxHours,
          tone: tone
        });
      }
    }

    return {
      state: input.state || null,
      view: {
        type: 'column',
        children: children
      }
    };
  }).toString();

  var newsletterCleanupSource = (function invoke(input) {
    var THRESHOLD = 0.2;
    var TOP_LIMIT = 5;
    var rows = (input.data && input.data['senders.newsletters']) || [];

    var lowOpen = [];
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i];
      if (!row) continue;
      if (Number(row.openRate || 0) <= THRESHOLD) {
        lowOpen.push(row);
      }
    }

    var list = lowOpen.length > 0 ? lowOpen.slice() : rows.slice();
    list.sort(function (a, b) {
      return (b.emails30d || 0) - (a.emails30d || 0);
    });
    var top = list.slice(0, TOP_LIMIT);

    var maxEmails = 1;
    for (var j = 0; j < top.length; j++) {
      var count = Number(top[j].emails30d || 0);
      if (count > maxEmails) maxEmails = count;
    }

    var pctCut = Math.round(THRESHOLD * 100);
    var headingText = 'Low-open newsletters (<' + pctCut + '% open)';

    var children = [
      { type: 'heading', text: headingText },
      {
        type: 'text',
        text: lowOpen.length > 0
          ? lowOpen.length + ' noisy sender' + (lowOpen.length === 1 ? '' : 's') + ' opened under ' + pctCut + '% of the time'
          : 'Showing highest-volume senders in the last 30 days'
      }
    ];

    if (rows.length === 0) {
      children.push({ type: 'badge', text: 'No newsletter data', tone: 'warn' });
    } else {
      for (var k = 0; k < top.length; k++) {
        var sender = top[k];
        var emails = Number(sender.emails30d || 0);
        var openPct = Math.round(Number(sender.openRate || 0) * 100);
        var tone = Number(sender.openRate || 0) <= THRESHOLD
          ? (emails >= 20 ? 'danger' : 'warn')
          : 'ok';
        children.push({
          type: 'bar',
          label: sender.sender,
          caption: emails + ' emails/30d \u00b7 ' + openPct + '% opened',
          value: emails,
          max: maxEmails,
          tone: tone
        });
      }
    }

    return {
      state: input.state || null,
      view: {
        type: 'column',
        children: children
      }
    };
  }).toString();

  var vipSlaSource = (function invoke(input) {
    var TOP_LIMIT = 4;
    var rows = (input.data && input.data['threads.waiting']) || [];
    var unread = [];
    var highCount = 0;
    for (var i = 0; i < rows.length; i++) {
      var r = rows[i];
      if (r && (r.unreadCount || 0) > 0) {
        unread.push(r);
        if (r.priority === 'high') {
          highCount += 1;
        }
      }
    }

    unread.sort(function (a, b) {
      return (b.waitHours || 0) - (a.waitHours || 0);
    });

    var top = unread.slice(0, TOP_LIMIT);
    var maxHours = top.length > 0 ? Math.max(24, Number(top[0].waitHours || 1)) : 24;
    var oldestHours = top.length > 0 ? Number(top[0].waitHours || 0) : 0;

    var children = [
      { type: 'heading', text: 'Longest-waiting replies' },
      {
        type: 'row',
        children: [
          {
            type: 'stat',
            label: 'Oldest wait',
            value: oldestHours + 'h',
            tone: oldestHours >= 24 ? 'danger' : (oldestHours >= 12 ? 'warn' : 'ok')
          },
          {
            type: 'stat',
            label: 'High priority',
            value: String(highCount),
            tone: highCount > 0 ? 'warn' : 'ok'
          }
        ]
      }
    ];

    if (top.length === 0) {
      children.push({ type: 'badge', text: 'Inbox clear', tone: 'ok' });
    } else {
      for (var j = 0; j < top.length; j++) {
        var item = top[j];
        var wh = Number(item.waitHours || 0);
        var tone = wh >= 24 ? 'danger' : (wh >= 12 ? 'warn' : 'ok');
        children.push({
          type: 'bar',
          label: item.sender,
          caption: wh + 'h ago \u00b7 ' + String(item.priority || 'normal') + ' priority',
          value: wh,
          max: maxHours,
          tone: tone
        });
      }
    }

    return {
      state: input.state || null,
      view: {
        type: 'column',
        children: children
      }
    };
  }).toString();

  window.PULSEMAIL_VIBES = {
    replyRadar: {
      id: 'reply-radar',
      name: 'Reply SLA Radar',
      wish: 'Show unread threads waiting over 24 hours',
      version: 1,
      needs: ['threads.waiting'],
      refresh: 3000,
      source: replyRadarSource
    },
    replyRadarV2: {
      id: 'reply-radar',
      name: 'Reply SLA Radar',
      wish: 'Flag threads over 12 hours and show only the worst 3',
      version: 2,
      remixOf: 'reply-radar',
      needs: ['threads.waiting'],
      refresh: 3000,
      source: replyRadarV2Source
    },
    newsletterCleanup: {
      id: 'newsletter-cleanup',
      name: 'Newsletter Clutter',
      wish: 'Show high-volume senders I open less than 20% of the time',
      version: 1,
      needs: ['senders.newsletters'],
      refresh: 3000,
      source: newsletterCleanupSource
    },
    vipSla: {
      id: 'vip-sla-queue',
      name: 'VIP Reply Queue',
      wish: 'Who is waiting on my reply the longest?',
      version: 1,
      needs: ['threads.waiting'],
      refresh: 3000,
      source: vipSlaSource
    }
  };
})();
