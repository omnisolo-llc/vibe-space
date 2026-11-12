import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { DEMO_ROOT, launchChromium, loadPlaywright, startDemoServer } from './server.mjs';

const SHOTS_DIR = '/home/kevin/leapterm/target/vibeprotocol-demo/shots';

function assert(cond, msg) {
  if (!cond) {
    throw new Error(msg);
  }
}

function trackErrors(page, label, errorLog) {
  page.on('console', (msg) => {
    if (msg.type() === 'error') {
      errorLog.push(`[${label}] console.error: ${msg.text()}`);
    }
  });
  page.on('pageerror', (err) => {
    errorLog.push(`[${label}] pageerror: ${err.message}`);
  });
}

async function waitForAuthoringToFinish(page) {
  await page.locator('[data-vs="label"]').waitFor({ state: 'visible', timeout: 10000 });
  await page.locator('[data-vs="preview"]').waitFor({ state: 'visible', timeout: 10000 });
}

async function assertNoVkErrors(page, stepLabel) {
  const errCount = await page.locator('.vk-error').count();
  if (errCount > 0) {
    const texts = await page.locator('.vk-error').allTextContents();
    throw new Error(`[${stepLabel}] Unexpected .vk-error rendered: ${JSON.stringify(texts)}`);
  }
}

async function clickCardMenuAction(card, actionVs) {
  const menu = card.locator('[data-vs="vibe-menu"]');
  if (!(await menu.isVisible().catch(() => false))) {
    const moreBtn = card.locator('[data-vs="vibe-more"]');
    await moreBtn.scrollIntoViewIfNeeded();
    await moreBtn.click();
    await menu.waitFor({ state: 'visible', timeout: 5000 });
  }
  await menu.locator(`[data-vs="${actionVs}"]`).click();
}

async function checkMobileTabTargets(page, label) {
  const sizes = await page.evaluate(() => {
    const btns = Array.from(document.querySelectorAll('.mobile-tabs button, .pl-mobile-tabs button, [data-app^="tab-"]'));
    return btns.filter((b) => b.offsetParent !== null).map((b) => {
      const r = b.getBoundingClientRect();
      return { text: b.textContent.trim(), width: r.width, height: r.height };
    });
  });
  assert(sizes.length >= 2, `[${label}] Expected visible mobile bottom tab buttons, found ${sizes.length}`);
  for (const s of sizes) {
    assert(s.width >= 44 && s.height >= 44, `[${label}] Mobile tab "${s.text}" smaller than 44x44: ${JSON.stringify(s)}`);
  }
}

async function checkIndependentPanelScroll(page, contentSelector, label) {
  await page.evaluate(() => window.scrollTo(0, 0));
  const res = await page.evaluate((sel) => {
    const panel = document.getElementById('vibe-space');
    const contentEl = document.querySelector(sel);
    let scrollEl = null;
    let cur = panel;
    while (cur && cur !== document.body && cur !== document.documentElement) {
      const cs = getComputedStyle(cur);
      if ((cs.overflowY === 'auto' || cs.overflowY === 'scroll') && cur.scrollHeight > cur.clientHeight + 5) {
        scrollEl = cur;
        break;
      }
      cur = cur.parentElement;
    }
    const beforeTop = contentEl ? contentEl.getBoundingClientRect().top : null;
    const beforeWinY = window.scrollY;
    let delta = 0;
    if (scrollEl) {
      const prev = scrollEl.scrollTop;
      scrollEl.scrollTop = prev > 40 ? prev - 40 : 120;
      delta = Math.abs(scrollEl.scrollTop - prev);
    }
    const afterTop = contentEl ? contentEl.getBoundingClientRect().top : null;
    const afterWinY = window.scrollY;
    return { hasScroller: !!scrollEl, delta, beforeTop, afterTop, beforeWinY, afterWinY };
  }, contentSelector);
  assert(res.hasScroller && res.delta > 0, `[${label}] Vibe Space panel did not scroll independently (${JSON.stringify(res)})`);
  assert(res.beforeTop === res.afterTop && res.afterWinY === res.beforeWinY, `[${label}] Scrolling panel moved host content (${JSON.stringify(res)})`);
}

async function verifyStartPage(context, baseUrl, viewport, errorLog, snap, checkNoHorizontalOverflow) {
  const width = viewport.width;
  const homePage = await context.newPage();
  trackErrors(homePage, `home-${width}`, errorLog);
  await homePage.goto(`${baseUrl}/index.html`, { waitUntil: 'networkidle' });
  await homePage.waitForSelector('h1, main, .hosts-grid');
  const homeText = await homePage.evaluate(() => document.body.innerText);
  assert(homeText.includes('VibeProtocol demo'), 'Home page missing title "VibeProtocol demo"');
  assert(!/leapterm/i.test(homeText), 'Home page still mentions LeapTerm');
  assert(homeText.includes('PocketLedger'), 'Home page missing PocketLedger');
  assert(homeText.includes('PulseMail'), 'Home page missing PulseMail');
  assert(homeText.includes('CartScout'), 'Home page missing CartScout');
  assert(homeText.includes('Moments'), 'Home page missing Moments');
  assert((await homePage.locator('.host-card').count()) === 4, 'Home page should list 4 host demo cards');
  assert((await homePage.locator('.tour-list li').count()) === 9, 'Home page tour missing 9 steps');
  assert((await homePage.locator('a[href="README.md"]').count()) >= 1, 'Home page missing README.md link');
  await checkNoHorizontalOverflow(homePage, 'home');
  await snap('00', 'home', 'landing', homePage);
  await homePage.close();
}

async function verifyMoments(context, baseUrl, isMobile, errorLog, snap, ledgerShareUrl, width) {
  const momentsPage = await context.newPage();
  trackErrors(momentsPage, `moments-${width}`, errorLog);

  // Story 6: Cross-host share refusal using PocketLedger share URL opened in Moments
  const shareHash = ledgerShareUrl.slice(ledgerShareUrl.indexOf('#'));
  await momentsPage.goto(`${baseUrl}/apps/moments/index.html${shareHash}`, { waitUntil: 'networkidle' });
  if (isMobile) {
    await checkMobileTabTargets(momentsPage, 'moments');
    await momentsPage.locator('[data-app="tab-vibes"]').click();
  }
  await momentsPage.locator('[data-vs="from-link"]').waitFor({ state: 'visible', timeout: 5000 });
  const mBlockText = await momentsPage.locator('[data-vs="from-link"]').textContent();
  assert(
    /cannot run here/i.test(mBlockText) || /does not have/i.test(mBlockText) || /blocked/i.test(mBlockText),
    `Cross-app share in Moments did not explain refusal: "${mBlockText}"`
  );
  assert(mBlockText.includes('transactions.recent'), 'Blocked card missing missing-capability id transactions.recent');
  await snap('13', 'moments', 'ledger-blocked', momentsPage);

  // Clean reload on Moments without blocked hash
  await momentsPage.goto(`${baseUrl}/apps/moments/index.html`, { waitUntil: 'networkidle' });
  await momentsPage.waitForSelector('#vibe-space [data-vs="wish-input"]', { state: 'attached' });
  const fanNames = ['maya.r', 'tomás_k', 'jun.park', 'elena_v', 'samir.patel', 'chloe.m'];

  if (isMobile) {
    await momentsPage.locator('[data-app="tab-vibes"]').click();
  }
  await momentsPage.locator('[data-vs="wish-chip"]', { hasText: 'Who are my top fans?' }).click();
  await waitForAuthoringToFinish(momentsPage);
  await momentsPage.locator('[data-vs="label-allow"]').click();

  const topFansCard = momentsPage.locator('[data-vs="vibe-card"][data-vibe-id="top-fans"]');
  await topFansCard.waitFor({ state: 'visible', timeout: 5000 });
  await momentsPage.waitForFunction(() => {
    const card = document.querySelector('[data-vs="vibe-card"][data-vibe-id="top-fans"]');
    return card && card.querySelectorAll('.vk-sealed').length >= 1;
  }, null, { timeout: 6000 });

  await clickCardMenuAction(topFansCard, 'vibe-inspect');
  const fansInspect = topFansCard.locator('[data-vs="inspect-pane"]');
  await fansInspect.waitFor({ state: 'visible', timeout: 5000 });
  const fansInspectText = await fansInspect.innerText();
  assert(fansInspectText.includes('"sealed"'), 'Top fans inspect pane missing "sealed"');
  for (const fan of fanNames) {
    assert(!fansInspectText.includes(fan), `Top fans inspect pane leaked follower name "${fan}"`);
  }
  const mSealedHandles = await fansInspect.locator('.vs-inspect-sealed').allTextContents();
  assert(mSealedHandles.length >= 1, 'Expected .vs-inspect-sealed handles in Moments inspect pane');
  for (const h of mSealedHandles) {
    assert(!/[\r\n]/.test(h), `Moments inspect sealed handle wraps: ${JSON.stringify(h)}`);
  }
  const mLegend = await momentsPage.locator('.vs-installed-legend').textContent();
  assert(mLegend.includes('Values with a lock are sealed. Moments draws them. The vibe never sees them.'), 'Missing sealed legend in Moments');
  await fansInspect.scrollIntoViewIfNeeded();
  if (!isMobile) {
    assert((await momentsPage.evaluate(() => window.scrollY)) === 0, 'Moments window scrolled on inspect');
  }
  await snap('14', 'moments', 'topfans-inspect', momentsPage);

  // Check "How this app turned it on" + "Show my top 5 posts this month"
  await momentsPage.locator('button, a', { hasText: 'How this app turned it on' }).first().click();
  await momentsPage.locator('[role="dialog"]').waitFor({ state: 'visible', timeout: 5000 });
  assert((await momentsPage.locator('[role="dialog"]').textContent()).includes('Moments declares what it offers'));
  await momentsPage.keyboard.press('Escape');
  await momentsPage.locator('[role="dialog"]').waitFor({ state: 'hidden', timeout: 5000 });

  await momentsPage.locator('[data-vs="wish-chip"]', { hasText: 'Show my top 5 posts this month' }).click();
  await waitForAuthoringToFinish(momentsPage);
  await momentsPage.locator('[data-vs="label-allow"]').click();
  await momentsPage.waitForFunction(() => {
    const card = document.querySelector('[data-vs="vibe-card"][data-vibe-id="top-posts"]');
    return card && card.querySelectorAll('.vk-bar-swatch').length === 5;
  }, null, { timeout: 6000 });

  // Focus timer in Moments
  const mFocusAdd = momentsPage.locator('[data-vs="gallery-add"][data-vibe-id="focus-timer"]');
  await mFocusAdd.scrollIntoViewIfNeeded();
  await mFocusAdd.click();
  await momentsPage.locator('[data-vs="label"]').waitFor({ state: 'visible', timeout: 5000 });
  await momentsPage.locator('[data-vs="label-allow"]').click();
  const mFocusCard = momentsPage.locator('[data-vs="vibe-card"][data-vibe-id="focus-timer"]');
  await mFocusCard.waitFor({ state: 'visible', timeout: 5000 });
  const mTimeBefore = await mFocusCard.locator('.vk-stat-value').first().innerText();
  await mFocusCard.locator('.vk-button', { hasText: /^Start$/i }).click();
  await momentsPage.waitForFunction(
    (prev) => {
      const el = document.querySelector('[data-vs="vibe-card"][data-vibe-id="focus-timer"] .vk-stat-value');
      return el && el.textContent.trim() !== prev.trim();
    },
    mTimeBefore,
    { timeout: 5000 }
  );
  if (!isMobile) {
    await checkIndependentPanelScroll(momentsPage, '.post-card, .feed-card, article', 'moments');
  }
  await mFocusCard.scrollIntoViewIfNeeded();
  await snap('15', 'moments', 'focustimer', momentsPage);
  if (isMobile) {
    await momentsPage.locator('[data-app="tab-feed"]').click();
    await momentsPage.waitForTimeout(200);
  } else {
    await momentsPage.evaluate(() => window.scrollTo(0, 0));
  }
  await snap('16', 'moments', 'feed', momentsPage);

  // Revoke follower access -> source banner + sample fallback -> auto recovery
  const followerToggle = momentsPage.locator('[data-app="toggle-follower-source"]');
  await followerToggle.click();
  if (isMobile) {
    await momentsPage.locator('[data-app="tab-vibes"]').click();
  }
  const mSourceBanner = topFansCard.locator('[data-vs="source-banner"]');
  await mSourceBanner.waitFor({ state: 'visible', timeout: 6000 });
  assert((await mFocusCard.locator('[data-vs="source-banner"]').count()) === 0, 'Focus timer showed source banner in Moments');
  await topFansCard.scrollIntoViewIfNeeded();
  await momentsPage.waitForTimeout(200);
  await snap('17', 'moments', 'source-revoked', momentsPage);

  await topFansCard.locator('[data-vs="source-use-sample"]').click();
  await topFansCard.locator('[data-vs="source-use-live"]').waitFor({ state: 'visible', timeout: 6000 });
  await snap('18', 'moments', 'sample-fallback', momentsPage);

  await followerToggle.click();
  await topFansCard.locator('[data-vs="source-use-live"]').click();
  await mSourceBanner.waitFor({ state: 'hidden', timeout: 6000 });
  await momentsPage.close();
}

async function verifyInbox(context, baseUrl, isMobile, errorLog, snap, checkNoHorizontalOverflow, width) {
  const inboxPage = await context.newPage();
  trackErrors(inboxPage, `inbox-${width}`, errorLog);
  await inboxPage.goto(`${baseUrl}/apps/inbox/index.html`, { waitUntil: 'networkidle' });
  await inboxPage.waitForSelector('#vibe-space [data-vs="wish-input"]', { state: 'attached' });
  await checkNoHorizontalOverflow(inboxPage, 'inbox-initial');

  if (isMobile) {
    await checkMobileTabTargets(inboxPage, 'inbox');
    await inboxPage.locator('[data-app="tab-vibes"]').click();
  }

  // Install Reply SLA Radar (v1), check sealed senders/subjects, inspect privacy
  await inboxPage.locator('[data-vs="wish-chip"]', { hasText: 'Show unread threads waiting over 24 hours' }).click();
  await waitForAuthoringToFinish(inboxPage);
  await inboxPage.locator('[data-vs="label-allow"]').click();
  const replyCard = inboxPage.locator('[data-vs="vibe-card"][data-vibe-id="reply-radar"]');
  await replyCard.waitFor({ state: 'visible', timeout: 5000 });
  await inboxPage.waitForFunction(() => {
    const card = document.querySelector('[data-vs="vibe-card"][data-vibe-id="reply-radar"]');
    return card && card.querySelectorAll('.vk-bar').length >= 1 && card.querySelectorAll('.vk-sealed').length >= 1;
  }, null, { timeout: 6000 });

  await clickCardMenuAction(replyCard, 'vibe-inspect');
  const inspectText = await replyCard.locator('[data-vs="inspect-pane"]').innerText();
  assert(inspectText.includes('"sealed"'), 'PulseMail inspect missing sealed');
  assert(!inspectText.includes('Elena Vance') && !inspectText.includes('Q4 diligence'), 'PulseMail leaked sealed sender/subject');
  await replyCard.locator('.vs-inspect-hide-btn').click();

  // Remix to v2 using hours SLA remix
  await clickCardMenuAction(replyCard, 'vibe-edit');
  await inboxPage.locator('[data-vs="edit-wish-input"]').fill('Flag threads over 12 hours and show only the worst 3');
  await inboxPage.locator('[data-vs="edit-wish-run"]').click();
  const permNote = await inboxPage.locator('.vs-edit-perm-note').textContent();
  assert(/no new permissions/i.test(permNote), `PulseMail hours remix unexpected perm note: "${permNote}"`);
  await inboxPage.locator('[data-vs="edit-save"]').click();
  await inboxPage.waitForFunction(() => {
    const card = document.querySelector('[data-vs="vibe-card"][data-vibe-id="reply-radar"]');
    return card && card.textContent.includes('v2') && card.querySelectorAll('.vk-bar').length <= 3;
  }, null, { timeout: 6000 });

  // Inbox Assistant embed + Pin
  if (isMobile) {
    await inboxPage.locator('[data-app="tab-mail"]').click();
  }
  await inboxPage.locator('[data-app="agent-chip"]').click();
  const embedBox = inboxPage.locator('[data-vs="embed"]');
  await embedBox.waitFor({ state: 'visible', timeout: 5000 });
  assert((await embedBox.textContent()).includes('Temporary'), 'Inbox embed missing Temporary badge');
  await embedBox.locator('[data-vs="embed-pin"]').click();
  await inboxPage.locator('[data-vs="label-allow"]').click();
  if (isMobile) {
    await inboxPage.locator('[data-app="tab-vibes"]').click();
  }
  await inboxPage.locator('[data-vs="vibe-card"][data-vibe-id="vip-sla-queue"]').waitFor({ state: 'visible', timeout: 5000 });
  if (!isMobile) {
    await checkIndependentPanelScroll(inboxPage, '.thread-card', 'inbox');
  }
  await assertNoVkErrors(inboxPage, `inbox-live-${width}`);
  await snap('25', 'inbox', 'live', inboxPage);

  // Mailbox sync offline toggle -> source banner -> restore
  if (isMobile) {
    await inboxPage.locator('[data-app="tab-mail"]').click();
  }
  await inboxPage.locator('[data-app="toggle-mailbox-sync"]').click();
  if (isMobile) {
    await inboxPage.locator('[data-app="tab-vibes"]').click();
  }
  await replyCard.locator('[data-vs="source-banner"]').waitFor({ state: 'visible', timeout: 6000 });
  assert((await replyCard.locator('[data-vs="source-banner"]').textContent()).includes('IMAP mailbox connection paused'));
  await snap('26', 'inbox', 'offline', inboxPage);
  if (isMobile) {
    await inboxPage.locator('[data-app="tab-mail"]').click();
  }
  await inboxPage.locator('[data-app="toggle-mailbox-sync"]').click();
  if (isMobile) {
    await inboxPage.locator('[data-app="tab-vibes"]').click();
  }
  await replyCard.locator('[data-vs="source-banner"]').waitFor({ state: 'hidden', timeout: 6000 });

  // Verify ?as=teammate uses distinct teammate data
  await inboxPage.goto(`${baseUrl}/apps/inbox/index.html?as=teammate`, { waitUntil: 'networkidle' });
  const tmBody = await inboxPage.evaluate(() => document.body.innerText);
  assert(tmBody.includes('Nadia Kowalski'), 'PulseMail ?as=teammate missing teammate dataset');
  await inboxPage.close();
}

async function verifyShop(context, baseUrl, isMobile, errorLog, snap, checkNoHorizontalOverflow, width) {
  const shopPage = await context.newPage();
  trackErrors(shopPage, `shop-${width}`, errorLog);
  await shopPage.goto(`${baseUrl}/apps/shop/index.html`, { waitUntil: 'networkidle' });
  await shopPage.waitForSelector('#vibe-space [data-vs="wish-input"]', { state: 'attached' });
  await checkNoHorizontalOverflow(shopPage, 'shop-initial');

  if (isMobile) {
    await checkMobileTabTargets(shopPage, 'shop');
    await shopPage.locator('[data-app="tab-vibes"]').click();
  }

  // Install True Deal Radar (v1) + Inspect sealed product/seller
  await shopPage.locator('[data-vs="wish-chip"]', { hasText: 'Highlight wishlist items at least 20% below typical price' }).click();
  await waitForAuthoringToFinish(shopPage);
  await shopPage.locator('[data-vs="label-allow"]').click();
  const dealCard = shopPage.locator('[data-vs="vibe-card"][data-vibe-id="deal-radar"]');
  await dealCard.waitFor({ state: 'visible', timeout: 5000 });
  await shopPage.waitForFunction(() => {
    const card = document.querySelector('[data-vs="vibe-card"][data-vibe-id="deal-radar"]');
    return card && card.querySelectorAll('.vk-bar').length >= 1 && card.querySelectorAll('.vk-sealed').length >= 1;
  }, null, { timeout: 6000 });

  await clickCardMenuAction(dealCard, 'vibe-inspect');
  const inspectText = await dealCard.locator('[data-vs="inspect-pane"]').innerText();
  assert(inspectText.includes('"sealed"'), 'CartScout inspect missing sealed');
  assert(!inspectText.includes('Studio Monitor Headphones') && !inspectText.includes('SoundCraft Direct'), 'CartScout leaked sealed item/seller');
  await dealCard.locator('.vs-inspect-hide-btn').click();

  // Remix to v2 using % MIN_DISCOUNT remix extension
  await clickCardMenuAction(dealCard, 'vibe-edit');
  await shopPage.locator('[data-vs="edit-wish-input"]').fill('Show only the top 3 deals at 25% off or better');
  await shopPage.locator('[data-vs="edit-wish-run"]').click();
  const permNote = await shopPage.locator('.vs-edit-perm-note').textContent();
  assert(/no new permissions/i.test(permNote), `CartScout discount remix unexpected perm note: "${permNote}"`);
  await shopPage.locator('[data-vs="edit-save"]').click();
  await shopPage.waitForFunction(() => {
    const card = document.querySelector('[data-vs="vibe-card"][data-vibe-id="deal-radar"]');
    return card && card.textContent.includes('v2') && card.querySelectorAll('.vk-bar').length <= 3;
  }, null, { timeout: 6000 });

  // Deal Assistant embed + Pin
  if (isMobile) {
    await shopPage.locator('[data-app="tab-feed"]').click();
  }
  await shopPage.locator('[data-app="agent-chip"]').click();
  const embedBox = shopPage.locator('[data-vs="embed"]');
  await embedBox.waitFor({ state: 'visible', timeout: 5000 });
  assert((await embedBox.textContent()).includes('Temporary'), 'CartScout embed missing Temporary badge');
  await embedBox.locator('[data-vs="embed-pin"]').click();
  await shopPage.locator('[data-vs="label-allow"]').click();
  if (isMobile) {
    await shopPage.locator('[data-app="tab-vibes"]').click();
  }
  await shopPage.locator('[data-vs="vibe-card"][data-vibe-id="item-price-watch"]').waitFor({ state: 'visible', timeout: 5000 });
  if (!isMobile) {
    await checkIndependentPanelScroll(shopPage, '.wishlist-card, .deal-card, article', 'shop');
  }
  await assertNoVkErrors(shopPage, `shop-live-${width}`);
  await snap('27', 'shop', 'live', shopPage);

  // Price feed offline -> source-banner -> restore
  if (isMobile) {
    await shopPage.locator('[data-app="tab-feed"]').click();
  }
  await shopPage.locator('[data-app="toggle-price-feed"]').click();
  if (isMobile) {
    await shopPage.locator('[data-app="tab-vibes"]').click();
  }
  await dealCard.locator('[data-vs="source-banner"]').waitFor({ state: 'visible', timeout: 6000 });
  assert((await dealCard.locator('[data-vs="source-banner"]').textContent()).includes('Merchant price feed rate-limited'));
  await snap('28', 'shop', 'offline', shopPage);
  if (isMobile) {
    await shopPage.locator('[data-app="tab-feed"]').click();
  }
  await shopPage.locator('[data-app="toggle-price-feed"]').click();
  if (isMobile) {
    await shopPage.locator('[data-app="tab-vibes"]').click();
  }
  await dealCard.locator('[data-vs="source-banner"]').waitFor({ state: 'hidden', timeout: 6000 });

  // Verify ?as=friend uses distinct friend wishlist
  await shopPage.goto(`${baseUrl}/apps/shop/index.html?as=friend`, { waitUntil: 'networkidle' });
  const friendBody = await shopPage.evaluate(() => document.body.innerText);
  assert(friendBody.includes('Mirrorless Prime 35mm Lens'), 'CartScout ?as=friend missing friend dataset');
  await shopPage.close();
}

async function runStoryForViewport(browser, baseUrl, viewport, errorLog, shots) {
  const width = viewport.width;
  const isMobile = width < 720;
  const context = await browser.newContext({ viewport });

  async function snap(nn, app, beat, page) {
    const filename = `${nn}-${app}-${beat}-${width}.png`;
    const fullPath = path.join(SHOTS_DIR, filename);
    await page.screenshot({ path: fullPath, fullPage: false });
    shots.push(fullPath);
    return fullPath;
  }

  async function checkNoHorizontalOverflow(page, label) {
    const dims = await page.evaluate(() => ({
      scrollW: document.documentElement.scrollWidth,
      innerW: window.innerWidth,
    }));
    assert(
      dims.scrollW <= dims.innerW + 2,
      `[${label} @ ${width}] Horizontal overflow detected: scrollWidth=${dims.scrollW} > innerWidth=${dims.innerW}`
    );
  }

  try {
    // 00. Landing page
    await verifyStartPage(context, baseUrl, viewport, errorLog, snap, checkNoHorizontalOverflow);

    // 01–12. PocketLedger full deep walkthrough
    const ledgerPage = await context.newPage();
    trackErrors(ledgerPage, `ledger-${width}`, errorLog);
    await ledgerPage.goto(`${baseUrl}/apps/ledger/index.html`, { waitUntil: 'networkidle' });
    await ledgerPage.waitForSelector('#vibe-space [data-vs="wish-input"]', { state: 'attached' });
    await checkNoHorizontalOverflow(ledgerPage, 'ledger-initial');

    if (isMobile) {
      await checkMobileTabTargets(ledgerPage, 'ledger');
      await ledgerPage.locator('[data-app="tab-accounts"]').click();
      await ledgerPage.waitForTimeout(200);
      await snap('01', 'ledger', 'accounts', ledgerPage);
      await ledgerPage.locator('[data-app="tab-vibes"]').click();
      await ledgerPage.waitForTimeout(200);
    } else {
      await snap('01', 'ledger', 'initial', ledgerPage);
    }

    // Offer dialog
    await ledgerPage.locator('[data-vs="offer-open"]').click();
    await ledgerPage.locator('[data-vs="offer-dialog"]').waitFor({ state: 'visible', timeout: 5000 });
    const offerText = await ledgerPage.locator('[data-vs="offer-dialog"]').textContent();
    assert(offerText.includes('transactions.recent') && offerText.includes('accounts.cashflow'), 'Offer dialog missing capabilities');
    assert(offerText.includes('sealed') && offerText.includes('public'), 'Offer dialog missing public/sealed chips');
    await snap('02', 'ledger', 'offer', ledgerPage);
    await ledgerPage.keyboard.press('Escape');
    await ledgerPage.locator('[data-vs="offer-dialog"]').waitFor({ state: 'hidden', timeout: 5000 });

    // "How this app turned it on" dialog
    await ledgerPage.locator('button, a', { hasText: 'How this app turned it on' }).first().click();
    await ledgerPage.locator('[role="dialog"]').waitFor({ state: 'visible', timeout: 5000 });
    assert((await ledgerPage.locator('[role="dialog"]').textContent()).includes('PocketLedger declares what it offers'));
    await ledgerPage.keyboard.press('Escape');
    await ledgerPage.locator('[role="dialog"]').waitFor({ state: 'hidden', timeout: 5000 });

    // Unmatched typed wish highlights scripted note
    await ledgerPage.locator('[data-vs="wish-input"]').fill('Make me coffee');
    await ledgerPage.locator('[data-vs="wish-send"]').click();
    assert((await ledgerPage.locator('.vs-wish-note-prominent').count()) === 1, 'Unmatched wish did not emphasize note');

    // Story 1 & 2: Subscription Watch v1
    const wish1Chip = ledgerPage.locator('[data-vs="wish-chip"]', { hasText: 'Flag recurring charges above $20/mo' });
    await wish1Chip.waitFor({ state: 'visible' });
    assert((await ledgerPage.locator('[data-vs="wish-chip"]', { hasText: 'red above 90%' }).count()) === 0, 'Remix chip shown prematurely');
    await wish1Chip.click();
    await waitForAuthoringToFinish(ledgerPage);
    await ledgerPage.waitForFunction(() => {
      const p = document.querySelector('[data-vs="preview"]');
      return p && p.querySelectorAll('.vk-bar').length >= 1;
    }, null, { timeout: 6000 });
    assert((await ledgerPage.locator('[data-vs="vibe-card"]').count()) === 0, 'Card installed before Allow');

    const labelText = await ledgerPage.locator('[data-vs="label"]').textContent();
    for (const expected of ['Reads', 'Shows', 'Cannot', 'merchant and account names stay sealed', 'Only inside its own box', 'See merchant names or account numbers', 'Change anything in PocketLedger']) {
      assert(labelText.includes(expected), `Label missing "${expected}"`);
    }
    assert(!(await ledgerPage.locator('.vs-installed-legend').isVisible().catch(() => false)), 'Sealed legend visible before install');

    await ledgerPage.locator('[data-vs="show-code"]').click();
    assert(await ledgerPage.evaluate(() => document.body.innerText.includes('function invoke')));
    await ledgerPage.locator('[data-vs="show-code"]').click();
    await ledgerPage.locator('[data-vs="label-allow"]').scrollIntoViewIfNeeded();
    await assertNoVkErrors(ledgerPage, `wish1-label-${width}`);
    await snap('03', 'ledger', 'wish1-label', ledgerPage);

    // Allow & add -> Subscription Watch live
    await ledgerPage.locator('[data-vs="label-allow"]').click();
    const subWatchCard = ledgerPage.locator('[data-vs="vibe-card"][data-vibe-id="subscription-watch"]');
    await subWatchCard.waitFor({ state: 'visible', timeout: 5000 });
    await ledgerPage.waitForFunction(() => {
      const card = document.querySelector('[data-vs="vibe-card"][data-vibe-id="subscription-watch"]');
      return card && card.querySelectorAll('.vk-tone-danger').length >= 1 && card.querySelectorAll('span.vk-sealed').length >= 1;
    }, null, { timeout: 6000 });
    await assertNoVkErrors(ledgerPage, `subwatch-live-${width}`);
    await snap('04', 'ledger', 'subwatch-live', ledgerPage);

    // Inspect -> sealed handles only, no real merchant/account names
    await clickCardMenuAction(subWatchCard, 'vibe-inspect');
    const inspectPane = subWatchCard.locator('[data-vs="inspect-pane"]');
    await inspectPane.waitFor({ state: 'visible', timeout: 5000 });
    const inspectText = await inspectPane.innerText();
    assert(inspectText.includes('"sealed"'), 'Inspect pane missing "sealed"');
    for (const secret of ['Sapphire Card', 'Checking', 'CloudBox', 'StreamFlix']) {
      assert(!inspectText.includes(secret), `Inspect pane leaked "${secret}"`);
    }
    const sealedHandles = await inspectPane.locator('.vs-inspect-sealed').allTextContents();
    assert(sealedHandles.length >= 1, 'Expected highlighted sealed handles in Inspect pane');
    for (const h of sealedHandles) {
      assert(!/[\r\n]/.test(h), `Sealed handle wraps across lines: ${JSON.stringify(h)}`);
    }
    const legendText = await ledgerPage.locator('.vs-installed-legend').textContent();
    assert(legendText.includes('Values with a lock are sealed. PocketLedger draws them. The vibe never sees them.'), 'Missing sealed legend');
    await inspectPane.scrollIntoViewIfNeeded();
    if (!isMobile) {
      assert((await ledgerPage.evaluate(() => window.scrollY)) === 0, 'Window scrolled on Inspect at 1440x900');
    }
    await snap('05', 'ledger', 'subwatch-inspect', ledgerPage);
    await subWatchCard.locator('.vs-inspect-hide-btn').click();

    // Story 3: Second wish (v2 with "No new permissions")
    await ledgerPage.locator('[data-vs="wish-chip"]', { hasText: 'red above 90%' }).click();
    await waitForAuthoringToFinish(ledgerPage);
    const label2Text = await ledgerPage.locator('[data-vs="label"]').textContent();
    assert(/no new permissions/i.test(label2Text) && /version 2/i.test(label2Text), `Second wish missing v2 / No new permissions: "${label2Text}"`);
    await snap('06', 'ledger', 'wish2-label', ledgerPage);
    await ledgerPage.locator('[data-vs="label-allow"]').click();
    await ledgerPage.waitForFunction(() => {
      const card = document.querySelector('[data-vs="vibe-card"][data-vibe-id="subscription-watch"]');
      return card && card.textContent.includes('v2') && card.querySelectorAll('.vk-bar').length <= 3;
    }, null, { timeout: 6000 });
    await snap('07', 'ledger', 'subwatch-v2', ledgerPage);

    // Story 4: Finance Assistant inline embed + Pin with custom title/note
    if (isMobile) {
      await ledgerPage.locator('[data-app="tab-ledger"]').click();
      await ledgerPage.waitForTimeout(200);
    }
    await ledgerPage.locator('[data-app="agent-chip"]').click();
    await ledgerPage.locator('[data-app="agent-message"]').waitFor({ state: 'visible', timeout: 5000 });
    const embed = ledgerPage.locator('[data-vs="embed"]');
    await embed.waitFor({ state: 'visible', timeout: 5000 });
    assert((await embed.textContent()).includes('Temporary'), 'Agent embed missing Temporary badge');
    await ledgerPage.waitForFunction(() => {
      const e = document.querySelector('[data-vs="embed"]');
      return e && e.querySelectorAll('.vk-stat, .vk-sparkline').length >= 1;
    }, null, { timeout: 6000 });
    await embed.scrollIntoViewIfNeeded();
    await snap('08', 'ledger', 'agent-embed', ledgerPage);

    await embed.locator('[data-vs="embed-pin"]').click();
    await ledgerPage.locator('[data-vs="label"]').waitFor({ state: 'visible', timeout: 5000 });
    await ledgerPage.locator('[data-vs="label-title-input"]').fill('Card Watch · Sapphire');
    await ledgerPage.locator('[data-vs="label-note-input"]').fill('Pinned from Finance Assistant');
    await ledgerPage.locator('[data-vs="label-allow"]').click();
    await ledgerPage.waitForFunction(() => {
      const e = document.querySelector('[data-vs="embed"]');
      return e && e.textContent.includes('Pinned');
    }, null, { timeout: 5000 });
    if (isMobile) {
      await ledgerPage.locator('[data-app="tab-vibes"]').click();
      await ledgerPage.waitForTimeout(200);
    }
    const pinnedCard = ledgerPage.locator('[data-vs="vibe-card"][data-vibe-id="account-watch"]');
    await pinnedCard.waitFor({ state: 'visible', timeout: 5000 });
    assert((await pinnedCard.locator('[data-vs="vibe-title"]').textContent()).trim() === 'Card Watch · Sapphire');
    assert((await pinnedCard.locator('[data-vs="vibe-note"]').textContent()).trim() === 'Pinned from Finance Assistant');
    if (!isMobile) {
      assert((await ledgerPage.evaluate(() => window.scrollY)) === 0, 'PocketLedger scrolled after Pin at 1440x900');
    }
    await snap('09', 'ledger', 'embed-pinned', ledgerPage);

    // Story 5: Share dialog + partner dataset
    await clickCardMenuAction(subWatchCard, 'vibe-share');
    await ledgerPage.locator('[data-vs="share-link"]').waitFor({ state: 'visible', timeout: 5000 });
    const shareUrl = await ledgerPage.locator('[data-vs="share-link"]').inputValue();
    assert(shareUrl.includes('#vibe='), 'Share link missing #vibe= token');
    await snap('10', 'ledger', 'share-dialog', ledgerPage);

    const partnerBtn = ledgerPage.locator('[data-vs="share-target"]', { hasText: 'Open as household partner' });
    const [partnerPage] = await Promise.all([
      context.waitForEvent('page'),
      partnerBtn.click(),
    ]);
    trackErrors(partnerPage, `partner-${width}`, errorLog);
    await partnerPage.waitForLoadState('networkidle');
    if (isMobile) {
      await partnerPage.locator('[data-app="tab-vibes"]').click();
    }
    await partnerPage.locator('[data-vs="label"]').waitFor({ state: 'visible', timeout: 5000 });
    assert((await partnerPage.locator('[data-vs="vibe-card"]').count()) === 0, 'Partner page auto-installed before Allow');
    await snap('11', 'ledger', 'partner-label', partnerPage);
    await partnerPage.locator('[data-vs="label-allow"]').click();
    await partnerPage.waitForFunction(() => {
      const card = document.querySelector('[data-vs="vibe-card"][data-vibe-id="subscription-watch"]');
      return card && card.querySelectorAll('.vk-bar').length >= 1;
    }, null, { timeout: 6000 });
    const partnerCardText = await partnerPage.locator('[data-vs="vibe-card"][data-vibe-id="subscription-watch"]').innerText();
    assert(!partnerCardText.includes('Sapphire Card'), 'Partner page rendered owner account instead of partner dataset');
    assert(partnerCardText.includes('Amex Gold') || partnerCardText.includes('Joint Checking') || partnerCardText.includes('DesignSuite'), 'Partner card missing partner dataset values');
    await snap('12', 'ledger', 'partner-live', partnerPage);
    await partnerPage.close();

    // Cross-host check + Moments complete walkthrough (Beats 13-18)
    await verifyMoments(context, baseUrl, isMobile, errorLog, snap, shareUrl, width);

    // Back in PocketLedger: Close share dialog, Focus Timer, Edit/History/Manage, Account & Bank Sync Outages (Beats 19-24)
    await ledgerPage.keyboard.press('Escape');
    await ledgerPage.locator('[data-vs="share-link"]').waitFor({ state: 'hidden', timeout: 5000 });

    const focusAdd = ledgerPage.locator('[data-vs="gallery-add"][data-vibe-id="focus-timer"]');
    await focusAdd.scrollIntoViewIfNeeded();
    await focusAdd.click();
    await ledgerPage.locator('[data-vs="label"]').waitFor({ state: 'visible', timeout: 5000 });
    await ledgerPage.locator('[data-vs="label-allow"]').click();
    const ltFocusCard = ledgerPage.locator('[data-vs="vibe-card"][data-vibe-id="focus-timer"]');
    await ltFocusCard.waitFor({ state: 'visible', timeout: 5000 });
    const ltTimeBefore = await ltFocusCard.locator('.vk-stat-value').first().innerText();
    await ltFocusCard.locator('.vk-button', { hasText: /^Start$/i }).click();
    await ledgerPage.waitForFunction(
      (prev) => {
        const el = document.querySelector('[data-vs="vibe-card"][data-vibe-id="focus-timer"] .vk-stat-value');
        return el && el.textContent.trim() !== prev.trim();
      },
      ltTimeBefore,
      { timeout: 5000 }
    );
    if (!isMobile) {
      await checkIndependentPanelScroll(ledgerPage, '.pl-tx-row, .pl-assistant-card', 'ledger');
    }
    await ltFocusCard.scrollIntoViewIfNeeded();
    await snap('19', 'ledger', 'focustimer', ledgerPage);

    // Edit by wish (uses AMOUNT_LIMIT / THRESHOLD remix!) + Edit code + Version restore
    await clickCardMenuAction(subWatchCard, 'vibe-edit');
    await ledgerPage.locator('[data-vs="edit-dialog"]').waitFor({ state: 'visible', timeout: 5000 });
    await ledgerPage.locator('[data-vs="edit-wish-input"]').fill('Make it red above 85% and show only the worst 3');
    await ledgerPage.locator('[data-vs="edit-wish-run"]').click();
    const permMsg = await ledgerPage.locator('.vs-edit-perm-note').textContent();
    assert(/no new permissions/i.test(permMsg) && permMsg.includes('Version 3'), `Expected Version 3 No new permissions, got "${permMsg}"`);
    await ledgerPage.locator('[data-vs="edit-save"]').click();
    await ledgerPage.locator('[data-vs="edit-dialog"]').waitFor({ state: 'hidden', timeout: 5000 });

    await clickCardMenuAction(subWatchCard, 'vibe-edit');
    await ledgerPage.locator('[data-vs="edit-tab-code"]').click();
    await ledgerPage.locator('[data-vs="edit-source-input"]').waitFor({ state: 'visible', timeout: 5000 });
    const curSrc = await ledgerPage.locator('[data-vs="edit-source-input"]').inputValue();
    await ledgerPage.locator('[data-vs="edit-source-input"]').fill(`${curSrc}\n// customized in story check`);
    await ledgerPage.locator('[data-vs="edit-test-btn"]').click();
    await ledgerPage.waitForFunction(() => {
      const p = document.querySelector('[data-vs="edit-preview"]');
      return p && p.querySelectorAll('.vk-bar').length >= 1;
    }, null, { timeout: 6000 });
    await snap('20', 'ledger', 'edit-code', ledgerPage);
    await ledgerPage.locator('[data-vs="edit-save"]').click();
    await ledgerPage.locator('[data-vs="edit-dialog"]').waitFor({ state: 'hidden', timeout: 5000 });

    // Version history Restore back to v1
    await clickCardMenuAction(subWatchCard, 'vibe-edit');
    await ledgerPage.locator('.vs-edit-history-list').waitFor({ state: 'visible', timeout: 5000 });
    assert((await ledgerPage.locator('[data-vs="edit-restore-version"]').count()) >= 3, 'Expected >= 3 history revisions');
    await ledgerPage.locator('.vs-edit-history-item', { hasText: 'v1 \u2014' }).first().locator('[data-vs="edit-restore-version"]').click();
    await ledgerPage.locator('[data-vs="edit-dialog"]').waitFor({ state: 'hidden', timeout: 5000 });
    await ledgerPage.waitForFunction(() => {
      const badge = document.querySelector('[data-vs="vibe-card"][data-vibe-id="subscription-watch"] .vs-version-badge');
      return badge && /^v1\b/.test(badge.textContent.trim());
    }, null, { timeout: 6000 });

    // Rename + Pin + Pause + Filter + Three-dots menu check
    await clickCardMenuAction(subWatchCard, 'vibe-rename');
    await subWatchCard.locator('[data-vs="vibe-title-input"]').fill('Household Spend Radar');
    await subWatchCard.locator('[data-vs="vibe-title-input"]').press('Enter');
    assert((await subWatchCard.locator('[data-vs="vibe-title"]').textContent()).trim() === 'Household Spend Radar');
    await clickCardMenuAction(subWatchCard, 'vibe-pin-top');
    await clickCardMenuAction(ltFocusCard, 'vibe-pause');
    await ltFocusCard.locator('[data-vs="vibe-resume"]').waitFor({ state: 'visible', timeout: 5000 });

    const filterBox = ledgerPage.locator('[data-vs="vibe-filter"]');
    await filterBox.fill('Radar');
    await ledgerPage.waitForFunction(() => {
      return Array.from(document.querySelectorAll('[data-vs="vibe-card"]')).filter((c) => c.offsetParent !== null && !c.hidden).length === 1;
    }, null, { timeout: 5000 });

    await subWatchCard.locator('[data-vs="vibe-more"]').scrollIntoViewIfNeeded();
    await subWatchCard.locator('[data-vs="vibe-more"]').click();
    await subWatchCard.locator('[data-vs="vibe-menu"]').waitFor({ state: 'visible', timeout: 5000 });
    const menuCheck = await ledgerPage.evaluate((mobile) => {
      const menu = document.querySelector('[data-vs="vibe-card"][data-vibe-id="subscription-watch"] [data-vs="vibe-menu"]');
      const delBtn = menu.querySelector('[data-vs="vibe-remove"]');
      const mr = menu.getBoundingClientRect();
      const dr = delBtn.getBoundingClientRect();
      const tabs = document.querySelector('.pl-mobile-tabs, .mobile-tabs');
      const maxBottom = mobile && tabs ? tabs.getBoundingClientRect().top : window.innerHeight;
      return { ok: dr.bottom <= maxBottom + 1 && mr.bottom <= maxBottom + 1, drBottom: dr.bottom, maxBottom };
    }, isMobile);
    assert(menuCheck.ok, `Three-dots menu clipped or behind bottom bar: ${JSON.stringify(menuCheck)}`);
    await snap('21', 'ledger', 'manage-cards', ledgerPage);
    await subWatchCard.locator('[data-vs="vibe-more"]').click();
    await subWatchCard.locator('[data-vs="vibe-menu"]').waitFor({ state: 'hidden', timeout: 5000 });

    await filterBox.fill('');
    await ledgerPage.waitForFunction(() => {
      return Array.from(document.querySelectorAll('[data-vs="vibe-card"]')).filter((c) => c.offsetParent !== null && !c.hidden).length === 3;
    }, null, { timeout: 5000 });
    await ltFocusCard.locator('[data-vs="vibe-resume"]').click();

    // Delete + Undo
    await clickCardMenuAction(subWatchCard, 'vibe-remove');
    await ledgerPage.locator('[data-vs="undo-banner"]').waitFor({ state: 'visible', timeout: 5000 });
    await ledgerPage.locator('[data-vs="undo-delete"]').click();
    await subWatchCard.waitFor({ state: 'visible', timeout: 5000 });
    assert((await subWatchCard.locator('[data-vs="vibe-title"]').textContent()).trim() === 'Household Spend Radar');

    // Beat 22: Single account unlinked -> Target account unlinked -> relink
    if (isMobile) {
      await ledgerPage.locator('[data-app="tab-accounts"]').click();
    }
    const sapphireToggle = ledgerPage.locator('[data-app="toggle-account"][data-account*="Sapphire Card"]');
    await sapphireToggle.click();
    if (isMobile) {
      await ledgerPage.locator('[data-app="tab-vibes"]').click();
    }
    await ledgerPage.waitForFunction(() => {
      const card = document.querySelector('[data-vs="vibe-card"][data-vibe-id="account-watch"]');
      return card && card.textContent.includes('Target account unlinked') && card.querySelectorAll('.vk-stat').length >= 2;
    }, null, { timeout: 6000 });
    await pinnedCard.scrollIntoViewIfNeeded();
    await snap('22', 'ledger', 'account-offline', ledgerPage);

    if (isMobile) {
      await ledgerPage.locator('[data-app="tab-accounts"]').click();
    }
    await sapphireToggle.click();
    if (isMobile) {
      await ledgerPage.locator('[data-app="tab-vibes"]').click();
    }
    await ledgerPage.waitForFunction(() => {
      const card = document.querySelector('[data-vs="vibe-card"][data-vibe-id="account-watch"]');
      return card && !card.textContent.includes('Target account unlinked');
    }, null, { timeout: 6000 });

    // Beats 23 & 24: Bank sync offline -> stale banner (Focus timer unaffected) -> reconnect recovery
    if (isMobile) {
      await ledgerPage.locator('[data-app="tab-accounts"]').click();
    }
    await ledgerPage.locator('[data-app="toggle-telemetry"]').click();
    if (isMobile) {
      await ledgerPage.locator('[data-app="tab-vibes"]').click();
    }
    await subWatchCard.locator('[data-vs="source-banner"]').waitFor({ state: 'visible', timeout: 6000 });
    await ledgerPage.waitForFunction(() => {
      const sw = document.querySelector('[data-vs="vibe-card"][data-vibe-id="subscription-watch"]');
      const ft = document.querySelector('[data-vs="vibe-card"][data-vibe-id="focus-timer"]');
      return sw && !!sw.querySelector('.vk-view-stale') && sw.querySelectorAll('.vk-bar').length >= 1 &&
        ft && !ft.querySelector('[data-vs="source-banner"]') && !ft.querySelector('.vk-view-stale');
    }, null, { timeout: 6000 });
    await subWatchCard.scrollIntoViewIfNeeded();
    await ledgerPage.waitForTimeout(200);
    await snap('23', 'ledger', 'sync-offline', ledgerPage);

    if (isMobile) {
      await ledgerPage.locator('[data-app="tab-accounts"]').click();
    }
    await ledgerPage.locator('[data-app="toggle-telemetry"]').click();
    if (isMobile) {
      await ledgerPage.locator('[data-app="tab-vibes"]').click();
    }
    await subWatchCard.locator('[data-vs="source-banner"]').waitFor({ state: 'hidden', timeout: 6000 });
    await ledgerPage.waitForTimeout(200);
    await snap('24', 'ledger', 'sync-recovered', ledgerPage);
    await ledgerPage.close();

    // Beats 25-26: PulseMail end-to-end
    await verifyInbox(context, baseUrl, isMobile, errorLog, snap, checkNoHorizontalOverflow, width);

    // Beats 27-28: CartScout end-to-end
    await verifyShop(context, baseUrl, isMobile, errorLog, snap, checkNoHorizontalOverflow, width);
  } finally {
    await context.close();
  }
}

async function checkFileUrls(browser, errorLog) {
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  try {
    const pages = [
      { label: 'file-home', file: path.join(DEMO_ROOT, 'index.html'), check: async (p) => (await p.innerText('body')).includes('PocketLedger') },
      { label: 'file-ledger', file: path.join(DEMO_ROOT, 'apps/ledger/index.html'), check: async (p) => (await p.locator('#vibe-space [data-vs="wish-input"]').count()) === 1 },
      { label: 'file-inbox', file: path.join(DEMO_ROOT, 'apps/inbox/index.html'), check: async (p) => (await p.locator('#vibe-space [data-vs="wish-input"]').count()) === 1 },
      { label: 'file-shop', file: path.join(DEMO_ROOT, 'apps/shop/index.html'), check: async (p) => (await p.locator('#vibe-space [data-vs="wish-input"]').count()) === 1 },
      { label: 'file-moments', file: path.join(DEMO_ROOT, 'apps/moments/index.html'), check: async (p) => (await p.locator('#vibe-space [data-vs="wish-input"]').count()) === 1 },
    ];
    for (const item of pages) {
      const page = await context.newPage();
      trackErrors(page, item.label, errorLog);
      await page.goto(pathToFileURL(item.file).href, { waitUntil: 'load' });
      await page.waitForTimeout(400);
      assert(await item.check(page), `${item.label} did not render expected content under file://`);
      if (item.label === 'file-ledger') {
        await page.locator('[data-vs="gallery-add"][data-vibe-id="focus-timer"]').click();
        await page.locator('[data-vs="label-allow"]').click();
        await page.waitForFunction(() => {
          const el = document.querySelector('[data-vs="vibe-card"][data-vibe-id="focus-timer"] .vk-stat-value');
          return el && el.textContent.includes('25:00');
        }, null, { timeout: 6000 });
        await assertNoVkErrors(page, 'file-ledger-mount');
      }
      await page.close();
    }
  } finally {
    await context.close();
  }
}

async function main() {
  fs.mkdirSync(SHOTS_DIR, { recursive: true });
  for (const name of fs.readdirSync(SHOTS_DIR)) {
    if (name.endsWith('.png')) {
      fs.unlinkSync(path.join(SHOTS_DIR, name));
    }
  }

  const { chromium } = await loadPlaywright();
  const server = await startDemoServer();
  const browser = await launchChromium(chromium);
  const errorLog = [];
  const shots = [];

  try {
    console.log('Running 4-demo story walkthrough at 1440x900...');
    await runStoryForViewport(browser, server.baseUrl, { width: 1440, height: 900 }, errorLog, shots);
    console.log('1440x900 walkthrough passed.');

    console.log('Running 4-demo story walkthrough at 390x844...');
    await runStoryForViewport(browser, server.baseUrl, { width: 390, height: 844 }, errorLog, shots);
    console.log('390x844 walkthrough passed.');

    console.log('Checking file:// rendering across index.html + all 4 demo apps...');
    await checkFileUrls(browser, errorLog);
    console.log('file:// checks passed.');

    if (errorLog.length > 0) {
      throw new Error(`Console/page errors detected:\n${errorLog.join('\n')}`);
    }

    console.log(`\nALL STORY CHECKS PASSED. Screenshots (${shots.length}):`);
    for (const s of shots) {
      console.log(`  ${s}`);
    }
  } finally {
    await browser.close();
    await server.close();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
