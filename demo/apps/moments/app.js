(function () {
  'use strict';

  var DAY_MS = 86400000;
  var loadedAt = Date.now();
  var followerAccessEnabled = true;
  var REVOKED_FOLLOWER_REASON = 'Follower like counts turned off in Moments privacy settings';

  var posts = [
    {
      id: 'p1',
      caption: 'Golden hour from the ferry deck',
      postedAt: loadedAt - 2 * DAY_MS,
      likes: 418,
      swatch: '#e07a5f'
    },
    {
      id: 'p2',
      caption: 'Matcha latte by the rain-streaked window panes',
      postedAt: loadedAt - 5 * DAY_MS,
      likes: 612,
      swatch: '#5b8a72'
    },
    {
      id: 'p3',
      caption: 'Late afternoon shadows across the studio wall',
      postedAt: loadedAt - 8 * DAY_MS,
      likes: 289,
      swatch: '#e9a84c'
    },
    {
      id: 'p4',
      caption: 'Coastal fog clearing over the headland',
      postedAt: loadedAt - 12 * DAY_MS,
      likes: 745,
      swatch: '#3d8b99'
    },
    {
      id: 'p5',
      caption: 'Fresh figs and warm sourdough on Sunday',
      postedAt: loadedAt - 16 * DAY_MS,
      likes: 534,
      swatch: '#9d4e7c'
    },
    {
      id: 'p6',
      caption: 'Dusk purple reflection in the puddles',
      postedAt: loadedAt - 21 * DAY_MS,
      likes: 194,
      swatch: '#7c5cbf'
    },
    {
      id: 'p7',
      caption: 'Desert clay walls in the afternoon sun',
      postedAt: loadedAt - 25 * DAY_MS,
      likes: 361,
      swatch: '#c85a3b'
    },
    {
      id: 'p8',
      caption: 'Quiet cedar trail after the storm passed',
      postedAt: loadedAt - 29 * DAY_MS,
      likes: 126,
      swatch: '#3e6b4e'
    },
    {
      id: 'p9',
      caption: 'First light over the glassy harbor bay',
      postedAt: loadedAt - 34 * DAY_MS,
      likes: 862,
      swatch: '#4a6fa5'
    },
    {
      id: 'p10',
      caption: 'Sunlit terracotta pots on the balcony',
      postedAt: loadedAt - 41 * DAY_MS,
      likes: 490,
      swatch: '#d49a35'
    },
    {
      id: 'p11',
      caption: 'Wild lavender along the hillside path',
      postedAt: loadedAt - 48 * DAY_MS,
      likes: 238,
      swatch: '#9a7bd6'
    },
    {
      id: 'p12',
      caption: 'Rose sky right after sunset downtown',
      postedAt: loadedAt - 56 * DAY_MS,
      likes: 64,
      swatch: '#d9778b'
    }
  ];

  var followers = [
    { follower: 'maya.r', count: 84 },
    { follower: 'tom\u00e1s_k', count: 71 },
    { follower: 'jun.park', count: 63 },
    { follower: 'elena_v', count: 55 },
    { follower: 'samir.patel', count: 48 },
    { follower: 'chloe.m', count: 39 },
    { follower: 'noah_b', count: 34 },
    { follower: 'priya.n', count: 29 },
    { follower: 'lucas.g', count: 25 },
    { follower: 'hana_w', count: 21 },
    { follower: 'owen.t', count: 18 },
    { follower: 'zara_ali', count: 15 },
    { follower: 'leo.s', count: 13 },
    { follower: 'nadia.c', count: 11 },
    { follower: 'kai_m', count: 9 }
  ];

  var samplePosts = [
    {
      caption: 'Sample sunrise over quiet hills',
      postedAt: loadedAt - 3 * DAY_MS,
      likes: 184,
      swatch: '#e07a5f'
    },
    {
      caption: 'Sample coastal walk at dusk',
      postedAt: loadedAt - 9 * DAY_MS,
      likes: 242,
      swatch: '#3d8b99'
    },
    {
      caption: 'Sample studio skylight study',
      postedAt: loadedAt - 18 * DAY_MS,
      likes: 118,
      swatch: '#7c5cbf'
    },
    {
      caption: 'Sample espresso and notebook',
      postedAt: loadedAt - 24 * DAY_MS,
      likes: 96,
      swatch: '#5b8a72'
    },
    {
      caption: 'Sample autumn leaves on brick',
      postedAt: loadedAt - 38 * DAY_MS,
      likes: 310,
      swatch: '#d49a35'
    }
  ];

  var sampleFollowers = [
    { follower: 'sample-fan-1', count: 46 },
    { follower: 'sample-fan-2', count: 38 },
    { follower: 'sample-fan-3', count: 29 },
    { follower: 'sample-fan-4', count: 21 },
    { follower: 'sample-fan-5', count: 14 },
    { follower: 'sample-fan-6', count: 8 }
  ];

  function hexToRgb(hex) {
    var clean = String(hex || '#7c3aed').replace('#', '');
    if (clean.length !== 6) {
      return { r: 124, g: 58, b: 237 };
    }
    return {
      r: parseInt(clean.slice(0, 2), 16),
      g: parseInt(clean.slice(2, 4), 16),
      b: parseInt(clean.slice(4, 6), 16)
    };
  }

  function mixRgb(a, b, ratio) {
    var t = Math.max(0, Math.min(1, ratio));
    return {
      r: Math.round(a.r + (b.r - a.r) * t),
      g: Math.round(a.g + (b.g - a.g) * t),
      b: Math.round(a.b + (b.b - a.b) * t)
    };
  }

  function rgbCss(c, alpha) {
    if (typeof alpha === 'number') {
      return 'rgba(' + c.r + ', ' + c.g + ', ' + c.b + ', ' + alpha + ')';
    }
    return 'rgb(' + c.r + ', ' + c.g + ', ' + c.b + ')';
  }

  function buildPhotoGradient(swatch, index) {
    var base = hexToRgb(swatch);
    var warmLight = mixRgb(base, { r: 255, g: 244, b: 226 }, 0.56);
    var softMid = mixRgb(base, { r: 248, g: 236, b: 230 }, 0.24);
    var deepShade = mixRgb(base, { r: 28, g: 22, b: 36 }, 0.42);
    var glowX = 20 + ((index * 23) % 62);
    var glowY = 18 + ((index * 19) % 44);
    var angle = 128 + ((index * 25) % 48);

    return [
      'radial-gradient(circle at ' + glowX + '% ' + glowY + '%, ' + rgbCss(warmLight, 0.9) + ' 0%, ' + rgbCss(warmLight, 0) + ' 54%)',
      'radial-gradient(ellipse at ' + (100 - glowX) + '% 88%, ' + rgbCss(deepShade, 0.55) + ' 0%, ' + rgbCss(deepShade, 0) + ' 62%)',
      'linear-gradient(' + angle + 'deg, ' + rgbCss(softMid) + ' 0%, ' + rgbCss(base) + ' 52%, ' + rgbCss(deepShade) + ' 100%)'
    ].join(', ');
  }

  function formatDaysAgo(postedAt) {
    var days = Math.max(0, Math.floor((Date.now() - postedAt) / DAY_MS));
    return days + ' days ago';
  }

  function createHeartSvg() {
    var svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('width', '18');
    svg.setAttribute('height', '18');
    svg.setAttribute('fill', 'currentColor');
    svg.setAttribute('aria-hidden', 'true');
    svg.classList.add('post-heart');

    var path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    path.setAttribute(
      'd',
      'M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z'
    );
    svg.appendChild(path);
    return svg;
  }

  var feedListEl = document.getElementById('feed-list');
  var likeCountNodes = Object.create(null);
  var likeButtonNodes = Object.create(null);

  function bumpPostLike(post) {
    post.likes += 1;
    var countEl = likeCountNodes[post.id];
    var btnEl = likeButtonNodes[post.id];
    if (countEl) {
      countEl.textContent = String(post.likes);
    }
    if (btnEl) {
      btnEl.setAttribute('aria-label', post.likes + ' likes');
      btnEl.classList.remove('is-pulsing');
      void btnEl.offsetWidth;
      btnEl.classList.add('is-pulsing');
      setTimeout(function () {
        btnEl.classList.remove('is-pulsing');
      }, 220);
    }
  }

  function renderFeed() {
    if (!feedListEl) return;
    feedListEl.textContent = '';

    var visiblePosts = posts.slice(0, 8);
    visiblePosts.forEach(function (post, idx) {
      var card = document.createElement('article');
      card.className = 'post-card';
      card.style.setProperty('--post-swatch', post.swatch);

      var head = document.createElement('div');
      head.className = 'post-head';

      var authorWrap = document.createElement('div');
      authorWrap.className = 'post-author-wrap';

      var avatar = document.createElement('span');
      avatar.className = 'post-avatar';
      avatar.setAttribute('aria-hidden', 'true');
      avatar.textContent = 'Y';

      var author = document.createElement('span');
      author.className = 'post-author';
      author.textContent = 'you';

      authorWrap.appendChild(avatar);
      authorWrap.appendChild(author);

      var age = document.createElement('span');
      age.className = 'post-age';
      age.textContent = formatDaysAgo(post.postedAt);

      head.appendChild(authorWrap);
      head.appendChild(age);

      var photo = document.createElement('div');
      photo.className = 'post-photo';
      photo.setAttribute('role', 'img');
      photo.setAttribute('aria-label', post.caption);
      photo.style.background = buildPhotoGradient(post.swatch, idx);

      var footer = document.createElement('div');
      footer.className = 'post-footer';

      var metaRow = document.createElement('div');
      metaRow.className = 'post-meta-row';

      var likesBtn = document.createElement('button');
      likesBtn.type = 'button';
      likesBtn.className = 'post-likes-btn';
      likesBtn.setAttribute('aria-label', post.likes + ' likes');

      var likesCount = document.createElement('span');
      likesCount.className = 'post-likes-count';
      likesCount.textContent = String(post.likes);

      var likesWord = document.createElement('span');
      likesWord.textContent = 'likes';

      likesBtn.appendChild(createHeartSvg());
      likesBtn.appendChild(likesCount);
      likesBtn.appendChild(likesWord);

      likesBtn.addEventListener('click', function () {
        bumpPostLike(post);
      });

      likeCountNodes[post.id] = likesCount;
      likeButtonNodes[post.id] = likesBtn;

      metaRow.appendChild(likesBtn);

      var caption = document.createElement('p');
      caption.className = 'post-caption';
      caption.textContent = post.caption;

      footer.appendChild(metaRow);
      footer.appendChild(caption);

      card.appendChild(head);
      card.appendChild(photo);
      card.appendChild(footer);
      feedListEl.appendChild(card);
    });
  }

  function setupMobileTabs() {
    var workspace = document.getElementById('workspace');
    var feedBtn = document.querySelector('[data-app="tab-feed"]');
    var vibesBtn = document.querySelector('[data-app="tab-vibes"]');
    if (!workspace || !feedBtn || !vibesBtn) return;

    function setTab(tab) {
      workspace.setAttribute('data-mobile-tab', tab);
      var isFeed = tab === 'feed';
      feedBtn.classList.toggle('is-active', isFeed);
      feedBtn.setAttribute('aria-pressed', isFeed ? 'true' : 'false');
      vibesBtn.classList.toggle('is-active', !isFeed);
      vibesBtn.setAttribute('aria-pressed', !isFeed ? 'true' : 'false');
    }

    feedBtn.addEventListener('click', function () {
      setTab('feed');
    });

    vibesBtn.addEventListener('click', function () {
      setTab('vibes');
    });

    function syncTabFromHash() {
      if (window.location.hash && window.location.hash.indexOf('#vibe=') === 0) {
        setTab('vibes');
      }
    }

    window.addEventListener('hashchange', syncTabFromHash);

    if (window.location.hash && window.location.hash.indexOf('#vibe=') === 0) {
      setTab('vibes');
    } else {
      setTab('feed');
    }
  }

  function setupHowTurnedOnDialog() {
    var trigger = document.getElementById('how-turned-on');
    if (!trigger) return;

    var snippet = [
      "const host = VibeKit.createHost({",
      "  id: 'moments-demo',",
      "  name: 'Moments',",
      "  capabilities: [",
      "    {",
      "      name: 'posts.mine',",
      "      title: 'Your posts and their like counts',",
      "      fields: { caption: 'public', postedAt: 'public', likes: 'public', swatch: 'public' },",
      "      read: () => posts.map(/* live posts */),",
      "      sample: samplePosts",
      "    },",
      "    {",
      "      name: 'likes.byFollower',",
      "      title: 'How many likes each follower gave you',",
      "      fields: { follower: 'sealed', count: 'public' },",
      "      sealedNote: 'follower names stay sealed',",
      "      sealedCannot: 'See who your followers are',",
      "      status: () => (followerAccessEnabled ? { available: true, mode: 'live' } : { available: false, mode: 'revoked', reason: REVOKED_FOLLOWER_REASON }),",
      "      read: () => followers.map(/* live counts */),",
      "      sample: sampleFollowers",
      "    }",
      "  ],",
      "  notOffered: [",
      "    'Read your direct messages',",
      "    'See follower contact details',",
      "    'Post, like or follow for you',",
      "    'Use the internet'",
      "  ]",
      "});"
    ].join('\n');

    trigger.addEventListener('click', function () {
      var prevFocus = document.activeElement;
      var scrim = document.createElement('div');
      scrim.className = 'app-scrim';

      var dialog = document.createElement('div');
      dialog.className = 'app-dialog';
      dialog.setAttribute('role', 'dialog');
      dialog.setAttribute('aria-modal', 'true');
      dialog.setAttribute('aria-labelledby', 'how-dialog-title');

      var head = document.createElement('div');
      head.className = 'app-dialog-head';

      var title = document.createElement('h2');
      title.className = 'app-dialog-title';
      title.id = 'how-dialog-title';
      title.textContent = 'How Moments turned VibeProtocol on';

      var closeBtn = document.createElement('button');
      closeBtn.type = 'button';
      closeBtn.className = 'app-dialog-close';
      closeBtn.textContent = 'Close';

      head.appendChild(title);
      head.appendChild(closeBtn);

      var lead = document.createElement('p');
      lead.className = 'app-dialog-lead';
      lead.textContent = 'Moments declares what it offers. A vibe can use nothing else.';

      var pre = document.createElement('pre');
      pre.className = 'app-code-block';
      var code = document.createElement('code');
      code.textContent = snippet;
      pre.appendChild(code);

      dialog.appendChild(head);
      dialog.appendChild(lead);
      dialog.appendChild(pre);
      scrim.appendChild(dialog);
      document.body.appendChild(scrim);

      function closeDialog() {
        document.removeEventListener('keydown', onKeyDown);
        if (scrim.parentNode) {
          scrim.parentNode.removeChild(scrim);
        }
        if (prevFocus && typeof prevFocus.focus === 'function') {
          prevFocus.focus();
        }
      }

      function onKeyDown(e) {
        if (e.key === 'Escape') {
          closeDialog();
        }
      }

      closeBtn.addEventListener('click', closeDialog);
      scrim.addEventListener('click', function (e) {
        if (e.target === scrim) {
          closeDialog();
        }
      });
      document.addEventListener('keydown', onKeyDown);
      closeBtn.focus();
    });
  }

  function startLiveUpdates() {
    var postTick = 0;
    var fanTick = 0;

    setInterval(function () {
      var post = posts[postTick % 8];
      postTick += 1;
      if (post && post.likes < 900) {
        bumpPostLike(post);
      }

      var fanIndex = fanTick % 2 === 0 ? (fanTick / 2) % 6 : fanTick % followers.length;
      var fan = followers[fanIndex];
      fanTick += 1;
      if (fan) {
        fan.count += 1;
      }
    }, 2500);
  }

  function setupFollowerSourceToggle(getHost) {
    var toggleBtn = document.querySelector('[data-app="toggle-follower-source"]');
    var statusBadge = document.getElementById('follower-source-status');
    var descEl = document.getElementById('follower-source-desc');
    var cardEl = document.getElementById('follower-access-card');

    function syncToggleUi() {
      if (cardEl) {
        cardEl.classList.toggle('is-revoked', !followerAccessEnabled);
      }
      if (statusBadge) {
        statusBadge.textContent = followerAccessEnabled ? 'Live' : 'Off';
        statusBadge.classList.toggle('is-live', followerAccessEnabled);
        statusBadge.classList.toggle('is-revoked', !followerAccessEnabled);
      }
      if (descEl) {
        descEl.textContent = followerAccessEnabled
          ? 'Shared as sealed handles with Vibes'
          : REVOKED_FOLLOWER_REASON;
      }
      if (toggleBtn) {
        toggleBtn.textContent = followerAccessEnabled ? 'Turn off access' : 'Turn on access';
        toggleBtn.setAttribute('aria-pressed', followerAccessEnabled ? 'true' : 'false');
      }
    }

    if (toggleBtn) {
      toggleBtn.addEventListener('click', function () {
        followerAccessEnabled = !followerAccessEnabled;
        syncToggleUi();
        var activeHost = typeof getHost === 'function' ? getHost() : null;
        if (activeHost && typeof activeHost.notifySourceChange === 'function') {
          activeHost.notifySourceChange();
        }
      });
    }

    syncToggleUi();
  }

  function initHostAndPanel() {
    if (!window.VibeKit || !window.VibeSpace || !window.MOMENTS_VIBES) {
      return null;
    }

    var host = window.VibeKit.createHost({
      id: 'moments-demo',
      name: 'Moments',
      capabilities: [
        {
          name: 'posts.mine',
          title: 'Your posts and their like counts',
          fields: {
            caption: 'public',
            postedAt: 'public',
            likes: 'public',
            swatch: 'public'
          },
          status: function () {
            return { available: true, mode: 'live' };
          },
          read: function () {
            return posts.map(function (p) {
              return {
                caption: p.caption,
                postedAt: p.postedAt,
                likes: p.likes,
                swatch: p.swatch
              };
            });
          },
          sample: samplePosts
        },
        {
          name: 'likes.byFollower',
          title: 'How many likes each follower gave you',
          fields: {
            follower: 'sealed',
            count: 'public'
          },
          sealedNote: 'follower names stay sealed',
          sealedCannot: 'See who your followers are',
          status: function () {
            if (followerAccessEnabled) {
              return { available: true, mode: 'live' };
            }
            return {
              available: false,
              mode: 'revoked',
              reason: REVOKED_FOLLOWER_REASON
            };
          },
          read: function () {
            if (!followerAccessEnabled) {
              return {
                available: false,
                mode: 'revoked',
                reason: REVOKED_FOLLOWER_REASON
              };
            }
            return followers.map(function (f) {
              return {
                follower: f.follower,
                count: f.count
              };
            });
          },
          sample: sampleFollowers
        }
      ],
      notOffered: [
        'Read your direct messages',
        'See follower contact details',
        'Post, like or follow for you',
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
      var topPosts = window.MOMENTS_VIBES.topPosts;
      var topFans = window.MOMENTS_VIBES.topFans;
      window.VibeSpace.mountPanel(host, panelTarget, {
        wishes: [
          { text: topPosts.wish, vibe: topPosts },
          { text: topFans.wish, vibe: topFans }
        ],
        gallery: window.VIBE_GALLERY || [],
        shareTargets: [
          { label: 'Open in LeapTerm', url: '../leapterm/index.html' }
        ]
      });
    }

    return host;
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
  renderFeed();
  setupMobileTabs();
  setupHowTurnedOnDialog();
  setupFollowerSourceToggle(function () {
    return activeHost;
  });
  startLiveUpdates();
  activeHost = initHostAndPanel();
})();
