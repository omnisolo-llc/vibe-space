(function () {
  'use strict';

  var isFriend = false;
  try {
    isFriend = new URLSearchParams(window.location.search).get('as') === 'friend';
  } catch (e) {
    isFriend = false;
  }

  var priceFeedOnline = true;
  var PRICE_FEED_OFFLINE_REASON = 'Merchant price feed rate-limited';

  var defaultWishlist = [
    {
      item: 'Studio Monitor Headphones',
      seller: 'SoundCraft Direct',
      category: 'Audio',
      currentUsd: 179,
      typicalUsd: 249,
      discountFraction: 0.28,
      priceHistory: [249, 245, 249, 239, 229, 249, 219, 199, 179],
      inStock: true,
      listed: true,
      art: 'linear-gradient(135deg, #c2410c, #ea580c)'
    },
    {
      item: 'Burr Espresso Grinder',
      seller: 'RoastWorks Supply',
      category: 'Kitchen',
      currentUsd: 210,
      typicalUsd: 299,
      discountFraction: 0.30,
      priceHistory: [299, 299, 289, 275, 279, 259, 240, 225, 210],
      inStock: true,
      listed: true,
      art: 'linear-gradient(135deg, #92400e, #d97706)'
    },
    {
      item: '34" Ultrawide IPS Display',
      seller: 'PixelBench Hardware',
      category: 'Desk',
      currentUsd: 399,
      typicalUsd: 549,
      discountFraction: 0.27,
      priceHistory: [549, 539, 520, 549, 499, 479, 449, 419, 399],
      inStock: true,
      listed: true,
      art: 'linear-gradient(135deg, #0f766e, #0d9488)'
    },
    {
      item: 'Split Mechanical Keyboard',
      seller: 'KeyFoundry Lab',
      category: 'Desk',
      currentUsd: 165,
      typicalUsd: 199,
      discountFraction: 0.17,
      priceHistory: [199, 199, 195, 189, 199, 185, 179, 172, 165],
      inStock: true,
      listed: true,
      art: 'linear-gradient(135deg, #4338ca, #6366f1)'
    },
    {
      item: 'Wool & Cork Desk Mat',
      seller: 'NordicAtelier',
      category: 'Studio',
      currentUsd: 48,
      typicalUsd: 62,
      discountFraction: 0.23,
      priceHistory: [62, 62, 58, 60, 56, 54, 52, 50, 48],
      inStock: false,
      listed: true,
      art: 'linear-gradient(135deg, #78716c, #a8a29e)'
    },
    {
      item: 'Carry-On Hardshell 40L',
      seller: 'Wayfarer Gear',
      category: 'Travel',
      currentUsd: 215,
      typicalUsd: 240,
      discountFraction: 0.10,
      priceHistory: [240, 240, 235, 230, 229, 225, 220, 218, 215],
      inStock: true,
      listed: true,
      art: 'linear-gradient(135deg, #be123c, #e11d48)'
    }
  ];

  var friendWishlist = [
    {
      item: 'Mirrorless Prime 35mm Lens',
      seller: 'OpticHouse Camera',
      category: 'Photo',
      currentUsd: 429,
      typicalUsd: 599,
      discountFraction: 0.28,
      priceHistory: [599, 599, 579, 560, 549, 510, 479, 449, 429],
      inStock: true,
      listed: true,
      art: 'linear-gradient(135deg, #b45309, #f59e0b)'
    },
    {
      item: 'Cast Iron Dutch Oven 5.5qt',
      seller: 'Hearthstone Kitchen',
      category: 'Kitchen',
      currentUsd: 189,
      typicalUsd: 260,
      discountFraction: 0.27,
      priceHistory: [260, 255, 249, 240, 235, 220, 209, 198, 189],
      inStock: true,
      listed: true,
      art: 'linear-gradient(135deg, #9a3412, #c2410c)'
    },
    {
      item: 'Portable E-Ink Notebook',
      seller: 'SlatePaper Tech',
      category: 'Notes',
      currentUsd: 310,
      typicalUsd: 379,
      discountFraction: 0.18,
      priceHistory: [379, 375, 369, 359, 349, 339, 329, 319, 310],
      inStock: true,
      listed: true,
      art: 'linear-gradient(135deg, #334155, #64748b)'
    }
  ];

  var wishlist = isFriend ? friendWishlist : defaultWishlist;

  var deliveries = isFriend
    ? [
        { package: 'Tripod Quick-Release Plate', etaHours: 5, progressFraction: 0.82 },
        { package: 'Linen Camera Strap', etaHours: 22, progressFraction: 0.45 }
      ]
    : [
        { package: 'USB-C Braided Dock Cable', etaHours: 4, progressFraction: 0.86 },
        { package: 'Acoustic Felt Wall Panels (4x)', etaHours: 19, progressFraction: 0.52 }
      ];

  var sampleWishlist = [
    {
      item: 'Sample Noise-Cancelling Cans',
      seller: 'Demo Audio Co',
      currentUsd: 159,
      typicalUsd: 229,
      discountFraction: 0.31,
      priceHistory: [229, 225, 219, 209, 199, 189, 179, 169, 159],
      inStock: true
    },
    {
      item: 'Sample Standing Desk Frame',
      seller: 'Demo Furniture',
      currentUsd: 280,
      typicalUsd: 390,
      discountFraction: 0.28,
      priceHistory: [390, 385, 375, 360, 345, 330, 315, 295, 280],
      inStock: true
    },
    {
      item: 'Sample Espresso Scale',
      seller: 'Demo Roastware',
      currentUsd: 54,
      typicalUsd: 68,
      discountFraction: 0.21,
      priceHistory: [68, 68, 66, 65, 62, 60, 58, 56, 54],
      inStock: true
    },
    {
      item: 'Sample Travel Backpack',
      seller: 'Demo Transit',
      currentUsd: 132,
      typicalUsd: 145,
      discountFraction: 0.09,
      priceHistory: [145, 145, 142, 140, 138, 136, 135, 134, 132],
      inStock: false
    }
  ];

  var host = VibeKit.createHost({
    id: isFriend ? 'shop-demo-friend' : 'shop-demo',
    name: 'CartScout',
    capabilities: [
      {
        name: 'wishlist.deals',
        title: 'Wishlist items and 90-day prices',
        fields: {
          item: 'sealed',
          seller: 'sealed',
          currentUsd: 'public',
          typicalUsd: 'public',
          discountFraction: 'public',
          priceHistory: 'public',
          inStock: 'public'
        },
        sealedNote: 'product and seller names stay sealed',
        sealedCannot: 'See product names, sellers, or your home address',
        status: function () {
          if (!priceFeedOnline) {
            return {
              available: false,
              mode: 'offline',
              reason: PRICE_FEED_OFFLINE_REASON
            };
          }
          return { available: true, mode: 'live' };
        },
        read: function () {
          var out = [];
          for (var i = 0; i < wishlist.length; i++) {
            var w = wishlist[i];
            if (w.listed === false) continue;
            out.push({
              item: w.item,
              seller: w.seller,
              currentUsd: w.currentUsd,
              typicalUsd: w.typicalUsd,
              discountFraction: w.discountFraction,
              priceHistory: w.priceHistory.slice(),
              inStock: w.inStock
            });
          }
          return out;
        },
        sample: sampleWishlist
      },
      {
        name: 'orders.deliveries',
        title: 'Incoming package deliveries',
        fields: {
          package: 'sealed',
          etaHours: 'public',
          progressFraction: 'public'
        },
        sealedNote: 'package names stay sealed',
        sealedCannot: 'See product names, sellers, or your home address',
        status: function () {
          return { available: true, mode: 'live' };
        },
        read: function () {
          return deliveries.slice();
        },
        sample: [
          { package: 'Sample Parcel A', etaHours: 6, progressFraction: 0.78 },
          { package: 'Sample Parcel B', etaHours: 24, progressFraction: 0.34 }
        ]
      }
    ],
    notOffered: [
      'Place orders or change your cart',
      'See saved payment cards or shipping address',
      'Use the internet'
    ]
  });

  function clearEl(el) {
    while (el.firstChild) el.removeChild(el.firstChild);
  }

  function el(tag, className, text) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined && text !== null) node.textContent = String(text);
    return node;
  }

  function renderWishlist() {
    var grid = document.getElementById('wishlist-grid');
    if (grid) {
      clearEl(grid);
      for (var i = 0; i < wishlist.length; i++) {
        var row = wishlist[i];
        var card = el('article', 'item-card' + (row.listed === false ? ' is-delisted' : ''));
        var art = el('div', 'item-art');
        art.style.background = row.art;
        art.appendChild(el('span', null, row.category));
        art.appendChild(el('span', 'item-discount-pill', '-' + Math.round(row.discountFraction * 100) + '% vs 90d'));
        card.appendChild(art);

        var body = el('div', 'item-body');
        body.appendChild(el('h3', 'item-title', row.item));
        body.appendChild(el('div', 'item-seller', row.seller));

        var priceRow = el('div', 'item-price-row');
        priceRow.appendChild(el('span', 'item-price-now', '$' + row.currentUsd));
        priceRow.appendChild(el('span', 'item-price-typ', '$' + row.typicalUsd));
        body.appendChild(priceRow);

        var stockText = row.listed === false ? 'Delisted' : (row.inStock ? 'In stock' : 'Backordered');
        var stockCls = row.listed !== false && row.inStock ? 'is-ok' : 'is-warn';
        body.appendChild(el('span', 'item-stock-badge ' + stockCls, stockText));

        card.appendChild(body);
        grid.appendChild(card);
      }
    }

    var watchList = document.getElementById('watch-toggle-list');
    if (watchList) {
      clearEl(watchList);
      for (var j = 0; j < wishlist.length; j++) {
        (function (entry) {
          var rowEl = el('div', 'watch-row' + (entry.listed === false ? ' is-delisted' : ''));
          rowEl.appendChild(el('span', 'watch-name', entry.item));
          var btn = el('button', 'watch-toggle', entry.listed === false ? 'Relist' : 'Delist');
          btn.type = 'button';
          btn.setAttribute('data-app', 'toggle-item');
          btn.setAttribute('data-item', entry.item);
          btn.addEventListener('click', function () {
            entry.listed = entry.listed === false ? true : false;
            renderWishlist();
            renderSummary();
            host.notifySourceChange();
          });
          rowEl.appendChild(btn);
          watchList.appendChild(rowEl);
        })(wishlist[j]);
      }
    }
  }

  function renderDeliveries() {
    var list = document.getElementById('deliveries-list');
    if (!list) return;
    clearEl(list);
    for (var i = 0; i < deliveries.length; i++) {
      var d = deliveries[i];
      var row = el('div', 'delivery-row');
      row.appendChild(el('span', 'delivery-name', d.package));
      row.appendChild(el('span', 'delivery-eta', 'ETA ' + d.etaHours + 'h · ' + Math.round(d.progressFraction * 100) + '%'));
      list.appendChild(row);
    }
  }

  function renderSummary() {
    var listedCount = 0;
    var dealsCount = 0;
    for (var i = 0; i < wishlist.length; i++) {
      if (wishlist[i].listed === false) continue;
      listedCount += 1;
      if (wishlist[i].discountFraction >= 0.2) dealsCount += 1;
    }
    var itemsEl = document.getElementById('nav-items-count');
    var dealsEl = document.getElementById('nav-deals-count');
    var delivEl = document.getElementById('nav-deliveries-count');
    if (itemsEl) itemsEl.textContent = String(listedCount);
    if (dealsEl) dealsEl.textContent = String(dealsCount);
    if (delivEl) delivEl.textContent = String(deliveries.length);
  }

  function syncPriceFeedUi() {
    var card = document.getElementById('price-feed-card');
    var pill = document.getElementById('price-feed-status');
    var desc = document.getElementById('price-feed-desc');
    var btn = document.getElementById('toggle-price-feed');
    if (!card || !pill || !desc || !btn) return;
    if (priceFeedOnline) {
      card.classList.remove('is-offline');
      pill.classList.remove('is-offline');
      pill.classList.add('is-live');
      pill.textContent = 'Live';
      desc.textContent = 'Product & seller names stay sealed behind opaque handles.';
      btn.textContent = 'Simulate rate limit';
      btn.setAttribute('aria-pressed', 'true');
    } else {
      card.classList.add('is-offline');
      pill.classList.remove('is-live');
      pill.classList.add('is-offline');
      pill.textContent = 'Offline';
      desc.textContent = PRICE_FEED_OFFLINE_REASON;
      btn.textContent = 'Reconnect price feed';
      btn.setAttribute('aria-pressed', 'false');
    }
  }

  function bindControls() {
    if (isFriend) {
      var tag = document.getElementById('persona-tag');
      var subtitle = document.getElementById('feed-subtitle');
      if (tag) tag.textContent = 'friend view';
      if (subtitle) subtitle.textContent = 'Friend shared wishlist (separate CartScout store)';
    }

    var toggleFeedBtn = document.getElementById('toggle-price-feed');
    if (toggleFeedBtn) {
      toggleFeedBtn.addEventListener('click', function () {
        priceFeedOnline = !priceFeedOnline;
        syncPriceFeedUi();
        host.notifySourceChange();
      });
    }

    var agentChip = document.getElementById('ask-deal-assistant');
    var agentReply = document.getElementById('agent-reply');
    var agentReplyText = document.getElementById('agent-reply-text');
    var agentSlot = document.getElementById('agent-embed-slot');
    var activeEmbedHandle = null;

    if (agentChip && agentReply && agentReplyText && agentSlot) {
      agentChip.addEventListener('click', function () {
        var featured = wishlist[0];
        agentReply.hidden = false;
        agentReplyText.textContent =
          'Yes — your top watched item is ' +
          Math.round(featured.discountFraction * 100) +
          '% below its 90-day baseline ($' +
          featured.currentUsd +
          ' vs $' +
          featured.typicalUsd +
          ' typical). Here is a temporary live price watch (seller and product name stay sealed):';
        if (activeEmbedHandle && typeof activeEmbedHandle.stop === 'function') {
          activeEmbedHandle.stop();
        } else if (activeEmbedHandle && typeof activeEmbedHandle.unmount === 'function') {
          activeEmbedHandle.unmount();
        }
        clearEl(agentSlot);
        activeEmbedHandle = VibeSpace.embed(host, agentSlot, window.SHOP_VIBES.itemPriceWatch, {
          args: { item: host.seal(featured.item) },
          defaultTitle: '90-Day Price Watch'
        });
      });
    }

    var workspace = document.getElementById('workspace');
    var tabButtons = document.querySelectorAll('.mobile-tab');
    for (var i = 0; i < tabButtons.length; i++) {
      tabButtons[i].addEventListener('click', function (ev) {
        var target = ev.currentTarget.getAttribute('data-app');
        var nextTab = target === 'tab-vibes' ? 'vibes' : 'feed';
        if (workspace) workspace.setAttribute('data-mobile-tab', nextTab);
        for (var j = 0; j < tabButtons.length; j++) {
          var active = tabButtons[j].getAttribute('data-app') === target;
          tabButtons[j].classList.toggle('is-active', active);
          tabButtons[j].setAttribute('aria-pressed', active ? 'true' : 'false');
        }
      });
    }

    var pill = document.getElementById('protocol-pill');
    if (pill) {
      pill.addEventListener('click', function () {
        VibeSpace.showOffer(host);
      });
    }

    var howBtn = document.getElementById('how-turned-on');
    if (howBtn) {
      howBtn.addEventListener('click', openHowDialog);
    }
  }

  function openHowDialog() {
    var scrim = el('div', 'app-scrim');
    var dialog = el('div', 'app-dialog');
    dialog.setAttribute('role', 'dialog');
    dialog.setAttribute('aria-modal', 'true');
    dialog.setAttribute('aria-labelledby', 'how-dialog-title');

    var head = el('div', 'app-dialog-head');
    var title = el('h2', 'app-dialog-title', 'How CartScout turned on VibeProtocol');
    title.id = 'how-dialog-title';
    var closeBtn = el('button', 'app-dialog-close', 'Close');
    closeBtn.type = 'button';
    head.appendChild(title);
    head.appendChild(closeBtn);
    dialog.appendChild(head);

    dialog.appendChild(
      el(
        'p',
        'app-dialog-lead',
        'CartScout keeps product names, sellers, saved payment cards, and your address out of the sandbox. Vibes receive opaque sealed handles for items while reading numeric price histories.'
      )
    );

    var code = el(
      'pre',
      'app-code-block',
      [
        'var host = VibeKit.createHost({',
        "  id: 'shop-demo',",
        "  name: 'CartScout',",
        '  capabilities: [',
        "    { name: 'wishlist.deals', fields: { item: 'sealed', seller: 'sealed', currentUsd: 'public', discountFraction: 'public' } },",
        "    { name: 'orders.deliveries', fields: { package: 'sealed', etaHours: 'public', progressFraction: 'public' } }",
        '  ],',
        "  notOffered: ['Place orders or change your cart', 'See saved payment cards or shipping address', 'Use the internet']",
        '});'
      ].join('\n')
    );
    dialog.appendChild(code);

    function close() {
      document.removeEventListener('keydown', onKey);
      if (scrim.parentNode) scrim.parentNode.removeChild(scrim);
    }

    function onKey(ev) {
      if (ev.key === 'Escape') close();
    }

    closeBtn.addEventListener('click', close);
    scrim.addEventListener('click', function (ev) {
      if (ev.target === scrim) close();
    });
    document.addEventListener('keydown', onKey);

    scrim.appendChild(dialog);
    document.body.appendChild(scrim);
    closeBtn.focus();
  }

  function syncTopbarHeight() {
    var topbar = document.querySelector('.topbar');
    if (topbar) {
      document.documentElement.style.setProperty('--topbar-h', topbar.offsetHeight + 'px');
    }
  }

  renderWishlist();
  renderDeliveries();
  renderSummary();
  syncPriceFeedUi();
  bindControls();
  syncTopbarHeight();
  window.addEventListener('resize', syncTopbarHeight);

  var panelContainer = document.getElementById('vibe-space');
  if (panelContainer) {
    VibeSpace.mountPanel(host, panelContainer, {
      wishes: window.SHOP_VIBES.wishes,
      gallery: window.VIBE_GALLERY || [],
      shareTargets: [
        {
          label: isFriend ? 'Open your wishlist' : 'Open as a friend',
          url: isFriend ? 'index.html' : 'index.html?as=friend'
        },
        {
          label: 'Open in PocketLedger',
          url: '../ledger/index.html'
        }
      ]
    });
  }
})();
