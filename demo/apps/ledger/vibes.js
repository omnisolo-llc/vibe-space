(function () {
  'use strict';

  var subWatchV1 = {
    id: 'subscription-watch',
    name: 'Subscription Watch',
    wish: 'Flag recurring charges above $20/mo, red above 80% of budget',
    version: 1,
    needs: ['transactions.recent', 'accounts.cashflow'],
    refresh: 2000,
    source: (function invoke(input) {
      var AMOUNT_LIMIT = 20;
      var THRESHOLD = 0.8;
      var txRows = (input.data && input.data['transactions.recent']) || [];
      var acctRows = (input.data && input.data['accounts.cashflow']) || [];

      if (txRows.length === 0 && acctRows.length === 0) {
        return {
          state: null,
          view: {
            type: 'column',
            children: [
              { type: 'heading', text: 'Subscription watch' },
              { type: 'badge', text: 'No transactions reporting', tone: 'warn' },
              { type: 'text', text: 'All accounts are currently unlinked.', tone: 'warn' },
            ],
          },
        };
      }

      var budgetByAccount = {};
      var overBudget = 0;
      var acctsSorted = acctRows.slice().sort(function (a, b) {
        return b.budgetUsed - a.budgetUsed;
      });
      for (var i = 0; i < acctsSorted.length; i++) {
        var acct = acctsSorted[i];
        if (acct.account && acct.account.sealed) {
          budgetByAccount[acct.account.sealed] = acct.budgetUsed;
        }
        if (acct.budgetUsed >= THRESHOLD) overBudget++;
      }

      var recurring = [];
      for (var j = 0; j < txRows.length; j++) {
        var tx = txRows[j];
        if (tx.isRecurring && tx.amountUsd >= AMOUNT_LIMIT) {
          recurring.push(tx);
        }
      }
      recurring.sort(function (a, b) {
        return b.amountUsd - a.amountUsd;
      });

      var thresholdPct = Math.round(THRESHOLD * 100);
      var children = [
        { type: 'heading', text: 'Subscription watch' },
        {
          type: 'text',
          text:
            recurring.length +
            ' recurring >= $' +
            AMOUNT_LIMIT +
            '/mo \u00b7 ' +
            overBudget +
            ' of ' +
            acctsSorted.length +
            ' accounts above ' +
            thresholdPct +
            '%',
          tone: overBudget > 0 ? 'danger' : 'ok',
        },
      ];

      for (var k = 0; k < acctsSorted.length; k++) {
        var row = acctsSorted[k];
        var pct = Math.round(row.budgetUsed * 100);
        var acctTone = row.budgetUsed >= THRESHOLD
          ? 'danger'
          : (row.budgetUsed >= 0.6 ? 'warn' : 'ok');
        children.push({
          type: 'bar',
          label: row.account,
          caption: pct + '% budget \u00b7 ' + Math.round(row.recurringShare * 100) + '% recurring',
          value: row.budgetUsed,
          max: 1,
          tone: acctTone,
        });
      }

      if (recurring.length > 0) {
        children.push({ type: 'divider' });
        children.push({
          type: 'text',
          text: 'Recurring charges >= $' + AMOUNT_LIMIT + '/mo',
          strong: true,
        });
        var maxAmt = recurring[0].amountUsd > 0 ? recurring[0].amountUsd : 100;
        for (var m = 0; m < recurring.length; m++) {
          var sub = recurring[m];
          var acctKey = sub.account && sub.account.sealed ? sub.account.sealed : '';
          var acctBudget = budgetByAccount[acctKey] || 0;
          var subTone = acctBudget >= THRESHOLD
            ? 'danger'
            : (sub.amountUsd >= AMOUNT_LIMIT * 3 ? 'warn' : 'ok');
          children.push({
            type: 'bar',
            label: sub.merchant,
            caption: sub.category + ' \u00b7 $' + Number(sub.amountUsd).toFixed(2) + '/mo',
            value: sub.amountUsd,
            max: Math.max(100, maxAmt),
            tone: subTone,
          });
        }
      }

      return {
        state: null,
        view: { type: 'column', children: children },
      };
    }).toString(),
  };

  var subWatchV2 = {
    id: 'subscription-watch',
    name: 'Subscription Watch',
    wish: 'Make it red above 90% and show only the worst three',
    version: 2,
    needs: ['transactions.recent', 'accounts.cashflow'],
    refresh: 2000,
    source: (function invoke(input) {
      var AMOUNT_LIMIT = 20;
      var THRESHOLD = 0.9;
      var TOP_LIMIT = 3;
      var limitLabel = TOP_LIMIT === 3 ? 'three' : String(TOP_LIMIT);
      var txRows = (input.data && input.data['transactions.recent']) || [];
      var acctRows = (input.data && input.data['accounts.cashflow']) || [];

      if (txRows.length === 0 && acctRows.length === 0) {
        return {
          state: null,
          view: {
            type: 'column',
            children: [
              { type: 'heading', text: 'Subscription watch \u00b7 worst ' + limitLabel },
              { type: 'badge', text: 'No transactions reporting', tone: 'warn' },
              { type: 'text', text: 'All accounts are currently unlinked.', tone: 'warn' },
            ],
          },
        };
      }

      var budgetByAccount = {};
      var overBudget = 0;
      var acctsSorted = acctRows.slice().sort(function (a, b) {
        return b.budgetUsed - a.budgetUsed;
      });
      for (var i = 0; i < acctsSorted.length; i++) {
        var acct = acctsSorted[i];
        if (acct.account && acct.account.sealed) {
          budgetByAccount[acct.account.sealed] = acct.budgetUsed;
        }
        if (acct.budgetUsed >= THRESHOLD) overBudget++;
      }

      var recurring = [];
      for (var j = 0; j < txRows.length; j++) {
        var tx = txRows[j];
        if (tx.isRecurring && tx.amountUsd >= AMOUNT_LIMIT) {
          recurring.push(tx);
        }
      }
      recurring.sort(function (a, b) {
        return b.amountUsd - a.amountUsd;
      });

      var worstAccts = acctsSorted.slice(0, TOP_LIMIT);
      var worstSubs = recurring.slice(0, TOP_LIMIT);
      var thresholdPct = Math.round(THRESHOLD * 100);
      var children = [
        { type: 'heading', text: 'Subscription watch \u00b7 worst ' + limitLabel },
        {
          type: 'text',
          text: overBudget + ' of ' + acctsSorted.length + ' accounts above ' + thresholdPct + '%',
          tone: overBudget > 0 ? 'danger' : 'ok',
        },
      ];

      for (var k = 0; k < worstAccts.length; k++) {
        var row = worstAccts[k];
        var pct = Math.round(row.budgetUsed * 100);
        var acctTone = row.budgetUsed >= THRESHOLD
          ? 'danger'
          : (row.budgetUsed >= 0.6 ? 'warn' : 'ok');
        children.push({
          type: 'bar',
          label: row.account,
          caption: pct + '% budget \u00b7 ' + Math.round(row.recurringShare * 100) + '% recurring',
          value: row.budgetUsed,
          max: 1,
          tone: acctTone,
        });
      }

      if (worstSubs.length > 0) {
        children.push({ type: 'divider' });
        children.push({
          type: 'text',
          text: 'Top ' + worstSubs.length + ' recurring >= $' + AMOUNT_LIMIT + '/mo',
          strong: true,
        });
        var maxAmt = worstSubs[0].amountUsd > 0 ? worstSubs[0].amountUsd : 100;
        for (var m = 0; m < worstSubs.length; m++) {
          var sub = worstSubs[m];
          var acctKey = sub.account && sub.account.sealed ? sub.account.sealed : '';
          var acctBudget = budgetByAccount[acctKey] || 0;
          var subTone = acctBudget >= THRESHOLD
            ? 'danger'
            : (sub.amountUsd >= AMOUNT_LIMIT * 3 ? 'warn' : 'ok');
          children.push({
            type: 'bar',
            label: sub.merchant,
            caption: sub.category + ' \u00b7 $' + Number(sub.amountUsd).toFixed(2) + '/mo',
            value: sub.amountUsd,
            max: Math.max(100, maxAmt),
            tone: subTone,
          });
        }
      }

      return {
        state: null,
        view: { type: 'column', children: children },
      };
    }).toString(),
  };

  var accountWatch = {
    id: 'account-watch',
    name: 'Account Cashflow',
    wish: 'Why did Sapphire Card jump this week?',
    version: 1,
    needs: ['accounts.cashflow'],
    refresh: 2000,
    source: (function invoke(input) {
      var WARN_LEVEL = 0.6;
      var DANGER_LEVEL = 0.8;
      var rows = (input.data && input.data['accounts.cashflow']) || [];

      function toneFor(val) {
        if (val >= DANGER_LEVEL) return 'danger';
        if (val >= WARN_LEVEL) return 'warn';
        return 'ok';
      }

      var prev = input.state && typeof input.state === 'object' ? input.state : {};
      var st = {
        showAll: !!prev.showAll,
        lastReading: prev.lastReading || null,
        targetAccount: prev.targetAccount || null,
      };

      if (
        (input.command === 'open' || input.command === 'refresh') &&
        input.args &&
        input.args.account &&
        input.args.account.sealed
      ) {
        if (!st.targetAccount || st.targetAccount.sealed !== input.args.account.sealed) {
          st.lastReading = null;
          st.showAll = false;
        }
        st.targetAccount = input.args.account;
      }

      if (input.command === 'clear-target') {
        st.showAll = true;
      } else if (input.command === 'restore-target') {
        st.showAll = false;
      }

      var targetSealed = st.targetAccount && st.targetAccount.sealed
        ? st.targetAccount.sealed
        : null;
      var match = null;
      if (targetSealed) {
        for (var i = 0; i < rows.length; i++) {
          if (rows[i].account && rows[i].account.sealed === targetSealed) {
            match = rows[i];
            break;
          }
        }
      }

      if (match) {
        st.lastReading = {
          account: match.account,
          budgetUsed: match.budgetUsed,
          recurringShare: match.recurringShare,
          spendHistory: Array.isArray(match.spendHistory) ? match.spendHistory.slice() : [],
          recurringHistory: Array.isArray(match.recurringHistory) ? match.recurringHistory.slice() : [],
        };
      }

      if (targetSealed && !st.showAll) {
        if (match) {
          return {
            state: st,
            view: {
              type: 'column',
              children: [
                { type: 'heading', text: match.account },
                {
                  type: 'row',
                  children: [
                    {
                      type: 'stat',
                      label: 'Budget used',
                      value: Math.round(match.budgetUsed * 100) + '%',
                      tone: toneFor(match.budgetUsed),
                    },
                    {
                      type: 'stat',
                      label: 'Recurring share',
                      value: Math.round(match.recurringShare * 100) + '%',
                      tone: toneFor(match.recurringShare),
                    },
                  ],
                },
                { type: 'text', text: 'Weekly spend pace' },
                {
                  type: 'sparkline',
                  values: st.lastReading.spendHistory,
                  tone: toneFor(match.budgetUsed),
                },
                { type: 'text', text: 'Recurring share trend' },
                {
                  type: 'sparkline',
                  values: st.lastReading.recurringHistory,
                  tone: toneFor(match.recurringShare),
                },
              ],
            },
          };
        }

        var unlinkedChildren = [
          { type: 'heading', text: st.targetAccount },
          { type: 'badge', text: 'Target account unlinked', tone: 'warn' },
        ];
        if (st.lastReading) {
          unlinkedChildren.push({
            type: 'text',
            text: 'Last known reading before account was unlinked',
            tone: 'warn',
          });
          unlinkedChildren.push({
            type: 'row',
            children: [
              {
                type: 'stat',
                label: 'Budget used',
                value: Math.round(st.lastReading.budgetUsed * 100) + '%',
                tone: 'warn',
              },
              {
                type: 'stat',
                label: 'Recurring share',
                value: Math.round(st.lastReading.recurringShare * 100) + '%',
                tone: 'warn',
              },
            ],
          });
          unlinkedChildren.push({ type: 'text', text: 'Weekly spend pace' });
          unlinkedChildren.push({
            type: 'sparkline',
            values: st.lastReading.spendHistory || [],
            tone: 'warn',
          });
          unlinkedChildren.push({ type: 'text', text: 'Recurring share trend' });
          unlinkedChildren.push({
            type: 'sparkline',
            values: st.lastReading.recurringHistory || [],
            tone: 'warn',
          });
        } else {
          unlinkedChildren.push({
            type: 'text',
            text: 'No reading captured yet while target account is unlinked.',
            tone: 'warn',
          });
        }
        unlinkedChildren.push({
          type: 'button',
          text: 'Show all active accounts',
          command: 'clear-target',
          tone: 'default',
        });
        return {
          state: st,
          view: { type: 'column', children: unlinkedChildren },
        };
      }

      var sorted = rows.slice().sort(function (a, b) {
        return b.budgetUsed - a.budgetUsed;
      });
      var list = [{ type: 'heading', text: 'Account Cashflow' }];
      if (sorted.length === 0) {
        list.push({ type: 'badge', text: 'No active accounts reporting', tone: 'warn' });
      } else {
        for (var j = 0; j < sorted.length; j++) {
          var r = sorted[j];
          list.push({
            type: 'bar',
            label: r.account,
            caption:
              Math.round(r.budgetUsed * 100) +
              '% budget \u00b7 ' +
              Math.round(r.recurringShare * 100) +
              '% recurring',
            value: r.budgetUsed,
            max: 1,
            tone: toneFor(r.budgetUsed),
          });
        }
      }
      if (targetSealed) {
        list.push({
          type: 'button',
          text: 'Back to target account',
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

  window.LEDGER_VIBES = {
    subWatchV1: subWatchV1,
    subWatchV2: subWatchV2,
    accountWatch: accountWatch,
  };
})();
