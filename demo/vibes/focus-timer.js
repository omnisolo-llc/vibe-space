(function (global) {
  'use strict';

  var focusTimer = {
    id: 'focus-timer',
    name: 'Focus timer',
    wish: 'Give me a 25-minute focus timer',
    version: 1,
    needs: [],
    refresh: 1000,
    source: (function invoke(input) {
      var DURATION_MIN = 25;
      var DURATION = DURATION_MIN * 60 * 1000;
      var st = input.state;
      if (!st || typeof st !== 'object') {
        st = { running: false, remainingMs: DURATION, endAt: null };
      }

      var now = typeof input.now === 'number' ? input.now : Date.now();
      var cmd = input.command;

      if (cmd === 'start') {
        if (!st.running) {
          var base = typeof st.remainingMs === 'number' && st.remainingMs > 0 ? st.remainingMs : DURATION;
          st = { running: true, remainingMs: base, endAt: now + base };
        }
      } else if (cmd === 'pause') {
        if (st.running && typeof st.endAt === 'number') {
          var leftOnPause = Math.max(0, st.endAt - now);
          st = { running: false, remainingMs: leftOnPause, endAt: null };
        }
      } else if (cmd === 'reset') {
        st = { running: false, remainingMs: DURATION, endAt: null };
      } else if (st.running && typeof st.endAt === 'number') {
        var leftOnTick = Math.max(0, st.endAt - now);
        if (leftOnTick === 0) {
          st = { running: false, remainingMs: 0, endAt: null };
        } else {
          st = { running: true, remainingMs: leftOnTick, endAt: st.endAt };
        }
      }

      var rem = typeof st.remainingMs === 'number' ? st.remainingMs : DURATION;
      var totalSeconds = rem <= 0 ? 0 : (rem < 1000 ? 1 : Math.floor(rem / 1000));
      var mins = Math.floor(totalSeconds / 60);
      var secs = totalSeconds % 60;
      var timeText = (mins < 10 ? '0' + mins : String(mins)) + ':' + (secs < 10 ? '0' + secs : String(secs));

      var elapsed = Math.max(0, Math.min(DURATION, DURATION - rem));
      var barCaption = rem === 0
        ? 'Done'
        : (mins >= 1 ? mins + ' min left' : totalSeconds + ' sec left');

      var statusText = st.running ? 'Running' : (rem === 0 ? 'Done' : (rem < DURATION ? 'Paused' : 'Ready'));
      var tone = rem === 0 ? 'ok' : (st.running ? (rem <= 5 * 60 * 1000 ? 'warn' : 'ok') : 'default');

      var buttons;
      if (rem === 0) {
        buttons = [
          { type: 'button', text: 'Reset', command: 'reset', tone: 'ok' }
        ];
      } else if (st.running) {
        buttons = [
          { type: 'button', text: 'Pause', command: 'pause', tone: 'warn' },
          { type: 'button', text: 'Reset', command: 'reset', tone: 'default' }
        ];
      } else if (rem < DURATION) {
        buttons = [
          { type: 'button', text: 'Resume', command: 'start', tone: 'ok' },
          { type: 'button', text: 'Reset', command: 'reset', tone: 'default' }
        ];
      } else {
        buttons = [
          { type: 'button', text: 'Start', command: 'start', tone: 'ok' },
          { type: 'button', text: 'Reset', command: 'reset', tone: 'default' }
        ];
      }

      return {
        state: st,
        view: {
          type: 'column',
          children: [
            {
              type: 'row',
              children: [
                {
                  type: 'stat',
                  label: 'Time left',
                  value: timeText,
                  tone: tone
                },
                {
                  type: 'badge',
                  text: statusText,
                  tone: tone
                }
              ]
            },
            {
              type: 'bar',
              label: DURATION_MIN + '-minute session',
              value: elapsed,
              max: DURATION,
              caption: barCaption,
              tone: tone
            },
            {
              type: 'row',
              children: buttons
            }
          ]
        }
      };
    }).toString()
  };

  global.VIBE_GALLERY = [focusTimer];
})(typeof window !== 'undefined' ? window : globalThis);
