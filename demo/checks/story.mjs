import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { DEMO_ROOT, startDemoServer } from './server.mjs';

const PLAYWRIGHT_PATH = '/home/kevin/leapterm/cloud/web/node_modules/playwright/index.mjs';
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
  // Wait for authoring playback (~2.1s) to yield the preview and label card
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
    // 00. Start page
    const homePage = await context.newPage();
    trackErrors(homePage, `home-${width}`, errorLog);
    await homePage.goto(`${baseUrl}/index.html`, { waitUntil: 'networkidle' });
    await homePage.waitForSelector('h1, main, a[href*="leapterm"]');
    const homeText = await homePage.evaluate(() => document.body.innerText);
    assert(homeText.includes('VibeProtocol demo'), 'Home page missing title "VibeProtocol demo"');
    assert(homeText.includes('LeapTerm'), 'Home page missing LeapTerm link');
    assert(homeText.includes('Moments'), 'Home page missing Moments link');
    assert(homeText.includes('What is real here'), 'Home page missing "What is real here" box');
    assert((await homePage.locator('.tour-list li').count()) === 9, 'Home page tour missing 9 steps');
    assert(homeText.includes('Manage, edit, and title your vibes'), 'Home page tour missing Round 2 step 8');
    assert(homeText.includes('Graceful when data sources go offline'), 'Home page tour missing Round 2 step 9');
    assert((await homePage.locator('a[href="README.md"]').count()) >= 1, 'Home page missing README.md link');
    await checkNoHorizontalOverflow(homePage, 'home');
    await snap('00', 'home', 'landing', homePage);
    await homePage.close();

    // Open LeapTerm
    const ltPage = await context.newPage();
    trackErrors(ltPage, `leapterm-${width}`, errorLog);
    await ltPage.goto(`${baseUrl}/apps/leapterm/index.html`, { waitUntil: 'networkidle' });
    await ltPage.waitForSelector('#vibe-space [data-vs="wish-input"]', { state: 'attached' });
    await checkNoHorizontalOverflow(ltPage, 'leapterm-initial');

    if (isMobile) {
      // Capture initial servers view on phone first, then switch to Vibe Space tab
      await ltPage.locator('[data-app="tab-servers"]').click();
      await ltPage.waitForTimeout(200);
      await snap('01', 'leapterm', 'servers', ltPage);
      await ltPage.locator('[data-app="tab-vibes"]').click();
      await ltPage.waitForTimeout(200);
    } else {
      await snap('01', 'leapterm', 'initial', ltPage);
    }

    // Check offer dialog
    await ltPage.locator('[data-vs="offer-open"]').click();
    await ltPage.locator('[data-vs="offer-dialog"]').waitFor({ state: 'visible', timeout: 5000 });
    const offerText = await ltPage.locator('[data-vs="offer-dialog"]').textContent();
    assert(offerText.includes('telemetry.disk') && offerText.includes('telemetry.load'), 'Offer dialog missing capabilities');
    assert(offerText.includes('sealed') && offerText.includes('public'), 'Offer dialog missing public/sealed field chips');
    await snap('02', 'leapterm', 'offer', ltPage);
    await ltPage.keyboard.press('Escape');
    await ltPage.locator('[data-vs="offer-dialog"]').waitFor({ state: 'hidden', timeout: 5000 });

    // Check "How this app turned it on" dialog in LeapTerm
    await ltPage.locator('button, a', { hasText: 'How this app turned it on' }).first().click();
    await ltPage.locator('[role="dialog"]').waitFor({ state: 'visible', timeout: 5000 });
    const ltHowText = await ltPage.locator('[role="dialog"]').textContent();
    assert(ltHowText.includes('LeapTerm declares what it offers'), 'LeapTerm "How this app turned it on" dialog missing expected wording');
    await ltPage.keyboard.press('Escape');
    await ltPage.locator('[role="dialog"]').waitFor({ state: 'hidden', timeout: 5000 });

    // Check unmatched typed wish highlights scripted note without error
    await ltPage.locator('[data-vs="wish-input"]').fill('Make me coffee');
    await ltPage.locator('[data-vs="wish-send"]').click();
    const noteProminent = await ltPage.locator('.vs-wish-note-prominent').count();
    assert(noteProminent === 1, 'Unmatched wish did not emphasize scripted demo note');

    // Story 1 & 2: Pick Disk Watch wish
    const wish1Chip = ltPage.locator('[data-vs="wish-chip"]', { hasText: 'Show disk usage for my servers' });
    await wish1Chip.waitFor({ state: 'visible' });
    // Also verify remix wish is NOT shown before disk-watch is installed
    const remixBefore = await ltPage.locator('[data-vs="wish-chip"]', { hasText: 'red above 90%' }).count();
    assert(remixBefore === 0, 'Remix wish chip should not appear before disk-watch is installed');

    await wish1Chip.click();
    await waitForAuthoringToFinish(ltPage);

    // Wait for preview render inside sandbox
    await ltPage.waitForFunction(() => {
      const p = document.querySelector('[data-vs="preview"]');
      return p && p.querySelectorAll('.vk-bar').length >= 1;
    }, null, { timeout: 6000 });

    // Verify no card is installed yet, and label has Reads, Shows, Cannot
    const installedBeforeAllow = await ltPage.locator('[data-vs="vibe-card"]').count();
    assert(installedBeforeAllow === 0, `Expected 0 installed vibes before Allow, found ${installedBeforeAllow}`);

    const labelText = await ltPage.locator('[data-vs="label"]').textContent();
    assert(labelText.includes('Reads'), 'Label missing Reads row');
    assert(labelText.includes('Shows'), 'Label missing Shows row');
    assert(labelText.includes('Cannot'), 'Label missing Cannot row');
    assert(labelText.includes('Disk usage of your servers'), 'Label Reads missing capability title');
    assert(labelText.includes('server names stay sealed'), 'Label Reads missing sealedNote');
    assert(labelText.includes('Only inside its own box'), 'Label Shows missing expected wording');
    assert(labelText.includes('See server names or addresses'), 'Label Cannot missing sealedCannot');
    assert(labelText.includes('Change anything in LeapTerm'), 'Label Cannot missing final immutable row');

    // Verify S3: sealed legend is NOT visible before any vibe is installed
    const legendVisibleBefore = await ltPage.locator('.vs-installed-legend').isVisible().catch(() => false);
    assert(!legendVisibleBefore, 'Sealed legend should not be visible before a vibe is installed');

    // Toggle Show code briefly to confirm it works, then collapse or keep clean
    await ltPage.locator('[data-vs="show-code"]').click();
    const codeVisible = await ltPage.evaluate(() => document.body.innerText.includes('function invoke'));
    assert(codeVisible, 'Show code toggle did not reveal vibe source');
    await ltPage.locator('[data-vs="show-code"]').click();

    await ltPage.locator('[data-vs="label-allow"]').scrollIntoViewIfNeeded();
    await assertNoVkErrors(ltPage, `wish1-label-${width}`);
    await snap('03', 'leapterm', 'wish1-label', ltPage);

    // Story 3: Allow and add -> Disk Watch runs live
    await ltPage.locator('[data-vs="label-allow"]').click();
    const diskWatchCard = ltPage.locator('[data-vs="vibe-card"][data-vibe-id="disk-watch"]');
    await diskWatchCard.waitFor({ state: 'visible', timeout: 5000 });
    await ltPage.waitForFunction(() => {
      const card = document.querySelector('[data-vs="vibe-card"][data-vibe-id="disk-watch"]');
      return card && card.querySelectorAll('.vk-bar').length >= 5 && card.querySelectorAll('span.vk-sealed').length >= 1;
    }, null, { timeout: 6000 });

    const dangerBars = await diskWatchCard.locator('.vk-bar.vk-tone-danger').count();
    assert(dangerBars >= 1, `Expected at least one .vk-bar.vk-tone-danger in Disk Watch, found ${dangerBars}`);
    const sealedNames = await diskWatchCard.locator('span.vk-sealed').allInnerTexts();
    assert(
      sealedNames.some((s) => s.includes('db-1.prod.internal') || s.includes('web-1.prod.internal')),
      `Expected real server names inside span.vk-sealed, got: ${JSON.stringify(sealedNames)}`
    );
    // Verify S3: legend line visible once a vibe is installed
    const legendEl = ltPage.locator('.vs-installed-legend');
    assert(await legendEl.isVisible(), 'Expected .vs-installed-legend to be visible once a vibe is installed');
    const legendTextInstalled = await legendEl.textContent();
    assert(
      legendTextInstalled.includes('Values with a lock are sealed. LeapTerm draws them. The vibe never sees them.'),
      `Missing expected S3 sealed legend in LeapTerm panel: ${legendTextInstalled}`
    );

    await diskWatchCard.scrollIntoViewIfNeeded();
    if (!isMobile) {
      assert((await ltPage.evaluate(() => window.scrollY)) === 0, 'LeapTerm page scrolled at 1440x900');
    }
    // Round 3: verify card management actions live inside closed three-dots menu
    assert(!(await diskWatchCard.locator('[data-vs="vibe-menu"]').isVisible()), 'Expected vibe-menu closed by default');
    assert(!(await diskWatchCard.locator('[data-vs="vibe-edit"]').isVisible()), 'Expected vibe-edit hidden when menu is closed');
    assert(!(await diskWatchCard.locator('[data-vs="vibe-remove"]').isVisible()), 'Expected vibe-remove hidden when menu is closed');
    assert(await diskWatchCard.locator('[data-vs="vibe-more"]').isVisible(), 'Expected three-dots vibe-more trigger visible');
    await snap('04', 'leapterm', 'diskwatch-live', ltPage);

    // Inspect Disk Watch via three-dots menu
    await clickCardMenuAction(diskWatchCard, 'vibe-inspect');
    const inspectPane = diskWatchCard.locator('[data-vs="inspect-pane"]');
    await inspectPane.waitFor({ state: 'visible', timeout: 5000 });
    const inspectText = await inspectPane.innerText();
    assert(inspectText.includes('"sealed"'), 'Inspect pane JSON missing "sealed"');
    for (const srv of ['db-1.prod.internal', 'db-2.prod.internal', 'web-1.prod.internal', 'web-2.prod.internal', 'cache-1.prod.internal']) {
      assert(!inspectText.includes(srv), `Inspect pane leaked real server name "${srv}"`);
    }
    assert(inspectText.includes('Sent nothing') && inspectText.includes('Changed nothing'), 'Inspect pane missing Sent/Changed nothing');

    // Verify S1: each sealed handle sits on one line in the inspect pane
    const sealedHandlesInInspect = await inspectPane.locator('.vs-inspect-sealed').allTextContents();
    assert(sealedHandlesInInspect.length >= 1, 'Expected highlighted .vs-inspect-sealed handles in inspect pane');
    for (const h of sealedHandlesInInspect) {
      assert(!/[\r\n]/.test(h), `Sealed handle in inspect pane wraps across lines: ${JSON.stringify(h)}`);
      assert(/^\{\s*"sealed":\s*"h_[^"]+"\s*\}$/.test(h.trim()), `Unexpected sealed handle format: ${JSON.stringify(h)}`);
    }
    const inspectJsonText = await inspectPane.locator('.vs-inspect-json').textContent();
    assert(/"server":\s*\{\s*"sealed":\s*"h_[^"\n]+"\s*\}/.test(inspectJsonText), 'Expected "server": { "sealed": "h_..." } on a single line');

    await inspectPane.scrollIntoViewIfNeeded();
    await snap('05', 'leapterm', 'diskwatch-inspect', ltPage);

    // Story 4: Second wish -> version 2 with "No new permissions"
    const wish2Chip = ltPage.locator('[data-vs="wish-chip"]', { hasText: 'red above 90%' });
    await wish2Chip.waitFor({ state: 'visible', timeout: 5000 });
    await wish2Chip.click();
    await waitForAuthoringToFinish(ltPage);

    // Wait for v2 preview render inside sandbox and ensure no error
    await ltPage.waitForFunction(() => {
      const p = document.querySelector('[data-vs="preview"]');
      return p && (p.querySelectorAll('.vk-bar').length === 3 || p.querySelector('.vk-error'));
    }, null, { timeout: 6000 });
    const v2PreviewErr = await ltPage.locator('[data-vs="preview"] .vk-error').textContent().catch(() => null);
    assert(!v2PreviewErr, `Wish 2 preview failed with error: ${v2PreviewErr}`);

    const v2LabelText = await ltPage.locator('[data-vs="label"]').textContent();
    assert(/Version\s*2/i.test(v2LabelText), `Expected "Version 2" in label, got: ${v2LabelText}`);
    assert(/No new permissions/i.test(v2LabelText), `Expected "No new permissions" in label, got: ${v2LabelText}`);
    await ltPage.locator('[data-vs="label-allow"]').scrollIntoViewIfNeeded();
    await assertNoVkErrors(ltPage, `wish2-label-${width}`);
    await snap('06', 'leapterm', 'wish2-label', ltPage);

    await ltPage.locator('[data-vs="label-allow"]').click();
    await ltPage.waitForFunction(() => {
      const card = document.querySelector('[data-vs="vibe-card"][data-vibe-id="disk-watch"]');
      return card && card.textContent.includes('v2') && card.querySelectorAll('.vk-bar').length === 3;
    }, null, { timeout: 6000 });
    // Verify S4: remix chip is gone once v2 is installed
    const remixAfterV2 = await ltPage.locator('[data-vs="wish-chip"]', { hasText: 'red above 90%' }).count();
    assert(remixAfterV2 === 0, 'S4 failed: remix wish chip still visible after Disk Watch v2 installed');
    await diskWatchCard.scrollIntoViewIfNeeded();
    await snap('07', 'leapterm', 'diskwatch-v2', ltPage);

    // Story 5: Agent chat -> embed marked Temporary -> Pin to Vibe Space
    if (isMobile) {
      await ltPage.locator('[data-app="tab-agent"]').click();
      await ltPage.waitForTimeout(200);
    }
    await ltPage.locator('[data-app="agent-chip"]').click();
    await ltPage.locator('[data-app="agent-message"]').waitFor({ state: 'visible', timeout: 8000 });
    const embedBox = ltPage.locator('[data-vs="embed"]');
    await embedBox.waitFor({ state: 'visible', timeout: 8000 });
    await ltPage.waitForFunction(() => {
      const e = document.querySelector('[data-vs="embed"]');
      return e && e.querySelectorAll('.vk-stat').length >= 2 && e.querySelectorAll('svg.vk-sparkline').length >= 1;
    }, null, { timeout: 6000 });
    const embedText = await embedBox.textContent();
    assert(embedText.includes('Temporary'), 'Agent embed missing "Temporary" badge');
    await embedBox.locator('[data-vs="embed-pin"]').scrollIntoViewIfNeeded();
    await snap('08', 'leapterm', 'agent-embed', ltPage);

    await embedBox.locator('[data-vs="embed-pin"]').click();
    await ltPage.locator('[data-vs="label"]').waitFor({ state: 'visible', timeout: 5000 });
    const pinTitleInput = ltPage.locator('[data-vs="label-title-input"]');
    const pinNoteInput = ltPage.locator('[data-vs="label-note-input"]');
    await pinTitleInput.waitFor({ state: 'visible', timeout: 5000 });
    const prefilledTitle = await pinTitleInput.inputValue();
    assert(prefilledTitle.includes('CPU and memory'), `Expected prefilled defaultTitle on embed pin, got "${prefilledTitle}"`);
    await pinTitleInput.fill('DB-1 CPU Watch');
    await pinNoteInput.fill('Tracks db-1 latency spikes');
    await ltPage.locator('[data-vs="label-allow"]').click();
    await ltPage.waitForFunction(() => {
      const e = document.querySelector('[data-vs="embed"]');
      return e && e.textContent.includes('Pinned to Vibe Space');
    }, null, { timeout: 5000 });

    if (isMobile) {
      await ltPage.locator('[data-app="tab-vibes"]').click();
      await ltPage.waitForTimeout(200);
    }
    const pinnedCard = ltPage.locator('[data-vs="vibe-card"][data-vibe-id="server-load"]');
    await pinnedCard.waitFor({ state: 'visible', timeout: 5000 });
    assert((await pinnedCard.locator('[data-vs="vibe-title"]').textContent()).trim() === 'DB-1 CPU Watch', 'Custom pin title did not render on card');
    assert((await pinnedCard.locator('[data-vs="vibe-note"]').textContent()).trim() === 'Tracks db-1 latency spikes', 'Custom pin note did not render on card');
    await pinnedCard.scrollIntoViewIfNeeded();
    if (!isMobile) {
      assert((await ltPage.evaluate(() => window.scrollY)) === 0, 'LeapTerm page scrolled at 1440x900 on embed-pinned');
    }
    await snap('09', 'leapterm', 'embed-pinned', ltPage);

    // Story 6: Share Disk Watch -> Open as a teammate
    await clickCardMenuAction(diskWatchCard, 'vibe-share');
    const shareInput = ltPage.locator('[data-vs="share-link"]');
    await shareInput.waitFor({ state: 'visible', timeout: 5000 });
    const shareUrl = await shareInput.inputValue();
    assert(shareUrl.includes('#vibe='), `Expected share link to contain #vibe=, got "${shareUrl}"`);
    await snap('10', 'leapterm', 'share-dialog', ltPage);

    const teammateBtn = ltPage.locator('[data-vs="share-target"]', { hasText: /teammate/i });
    await teammateBtn.waitFor({ state: 'visible' });
    const [teammatePage] = await Promise.all([
      context.waitForEvent('page'),
      teammateBtn.click(),
    ]);
    trackErrors(teammatePage, `teammate-${width}`, errorLog);
    await teammatePage.waitForLoadState('networkidle');
    if (isMobile) {
      await teammatePage.locator('[data-app="tab-vibes"]').click();
      await teammatePage.waitForTimeout(200);
    }
    await teammatePage.locator('[data-vs="label"]').waitFor({ state: 'visible', timeout: 6000 });
    const tmInstalledBefore = await teammatePage.locator('[data-vs="vibe-card"]').count();
    assert(tmInstalledBefore === 0, 'Teammate page installed vibe before Allow was clicked');
    const tmLabelText = await teammatePage.locator('[data-vs="label"]').textContent();
    assert(tmLabelText.includes('Reads') && tmLabelText.includes('Shows') && tmLabelText.includes('Cannot'), 'Teammate label missing rows');
    await checkNoHorizontalOverflow(teammatePage, 'teammate');
    await snap('11', 'leapterm', 'teammate-label', teammatePage);

    await teammatePage.locator('[data-vs="label-allow"]').click();
    const tmCard = teammatePage.locator('[data-vs="vibe-card"][data-vibe-id="disk-watch"]');
    await tmCard.waitFor({ state: 'visible', timeout: 5000 });
    await teammatePage.waitForFunction(() => {
      const card = document.querySelector('[data-vs="vibe-card"][data-vibe-id="disk-watch"]');
      return card && card.querySelectorAll('span.vk-sealed').length >= 1;
    }, null, { timeout: 6000 });
    const tmServers = await tmCard.locator('span.vk-sealed').allInnerTexts();
    assert(
      tmServers.length > 0 && !tmServers.some((s) => s.includes('db-1.prod.internal')),
      `Teammate copy did not show different server names: ${JSON.stringify(tmServers)}`
    );
    assert(
      tmServers.some((s) => s.includes('api-east') || s.includes('corp.example')),
      `Teammate servers did not match expected teammate hosts: ${JSON.stringify(tmServers)}`
    );
    const tmRemixCount = await teammatePage.locator('[data-vs="wish-chip"]', { hasText: 'red above 90%' }).count();
    assert(tmRemixCount === 0, 'S4 failed: remix wish chip visible on teammate copy where v2 is already installed');
    await snap('12', 'leapterm', 'teammate-live', teammatePage);
    await teammatePage.close();

    // Story 7a: Open Disk Watch link in Moments -> cannot run here
    const momentsTargetBtn = ltPage.locator('[data-vs="share-target"]', { hasText: /Moments/i });
    if (!(await momentsTargetBtn.isVisible())) {
      await clickCardMenuAction(diskWatchCard, 'vibe-share');
    }
    await momentsTargetBtn.waitFor({ state: 'visible' });
    const [momentsPage] = await Promise.all([
      context.waitForEvent('page'),
      momentsTargetBtn.click(),
    ]);
    trackErrors(momentsPage, `moments-${width}`, errorLog);
    await momentsPage.waitForLoadState('networkidle');
    if (isMobile) {
      // Check feed tab renders first too
      await momentsPage.locator('[data-app="tab-feed"]').click();
      await momentsPage.waitForTimeout(200);
      await momentsPage.locator('[data-app="tab-vibes"]').click();
      await momentsPage.waitForTimeout(200);
    }
    const fromLinkCard = momentsPage.locator('[data-vs="from-link"]');
    await fromLinkCard.waitFor({ state: 'visible', timeout: 6000 });
    const fromLinkText = await fromLinkCard.textContent();
    assert(
      /cannot run here/i.test(fromLinkText) && fromLinkText.includes('telemetry.disk'),
      `Moments from-link card missing expected message, got: ${fromLinkText}`
    );
    await checkNoHorizontalOverflow(momentsPage, 'moments');
    await snap('13', 'moments', 'diskwatch-blocked', momentsPage);

    // Dismiss blocked card
    await fromLinkCard.locator('button', { hasText: /dismiss/i }).click();
    await fromLinkCard.waitFor({ state: 'hidden', timeout: 5000 });

    // Story 7b: "Who are my top fans?" in Moments
    const topFansChip = momentsPage.locator('[data-vs="wish-chip"]', { hasText: 'Who are my top fans?' });
    await topFansChip.click();
    await waitForAuthoringToFinish(momentsPage);
    await momentsPage.locator('[data-vs="label-allow"]').click();

    const topFansCard = momentsPage.locator('[data-vs="vibe-card"][data-vibe-id="top-fans"]');
    await topFansCard.waitFor({ state: 'visible', timeout: 5000 });
    await momentsPage.waitForFunction(() => {
      const card = document.querySelector('[data-vs="vibe-card"][data-vibe-id="top-fans"]');
      return card && card.querySelectorAll('.vk-bar').length === 5 && card.querySelectorAll('span.vk-sealed').length >= 5;
    }, null, { timeout: 6000 });
    const fanNames = await topFansCard.locator('span.vk-sealed').allInnerTexts();
    assert(fanNames.length >= 5 && fanNames.every((n) => n.trim().length > 0), `Expected 5 sealed fan names, got ${JSON.stringify(fanNames)}`);

    await clickCardMenuAction(topFansCard, 'vibe-inspect');
    const fansInspect = topFansCard.locator('[data-vs="inspect-pane"]');
    await fansInspect.waitFor({ state: 'visible', timeout: 5000 });
    const fansInspectText = await fansInspect.innerText();
    assert(fansInspectText.includes('"sealed"'), 'Top fans inspect pane missing "sealed"');
    for (const fan of fanNames) {
      assert(!fansInspectText.includes(fan.trim()), `Top fans inspect pane leaked follower name "${fan}"`);
    }
    // Verify S1 on Moments: each sealed handle sits on one line
    const mSealedHandles = await fansInspect.locator('.vs-inspect-sealed').allTextContents();
    assert(mSealedHandles.length >= 1, 'Expected highlighted .vs-inspect-sealed handles in Moments inspect pane');
    for (const h of mSealedHandles) {
      assert(!/[\r\n]/.test(h), `Moments inspect sealed handle wraps across lines: ${JSON.stringify(h)}`);
    }
    const mLegendEl = momentsPage.locator('.vs-installed-legend');
    assert(await mLegendEl.isVisible(), 'Expected .vs-installed-legend visible in Moments once a vibe is installed');
    const mLegend = await mLegendEl.textContent();
    assert(
      mLegend.includes('Values with a lock are sealed. Moments draws them. The vibe never sees them.'),
      'Missing expected S3 sealed legend in Moments panel'
    );
    await fansInspect.scrollIntoViewIfNeeded();
    if (!isMobile) {
      assert((await momentsPage.evaluate(() => window.scrollY)) === 0, 'C3: Moments window scrolled on inspect at 1440x900');
    }
    await snap('14', 'moments', 'topfans-inspect', momentsPage);

    // Also check "How this app turned it on" and "Show my top 5 posts this month" in Moments
    await momentsPage.locator('button, a', { hasText: 'How this app turned it on' }).first().click();
    await momentsPage.locator('[role="dialog"]').waitFor({ state: 'visible', timeout: 5000 });
    const mHowText = await momentsPage.locator('[role="dialog"]').textContent();
    assert(mHowText.includes('Moments declares what it offers'), 'Moments "How this app turned it on" dialog missing expected wording');
    await momentsPage.keyboard.press('Escape');
    await momentsPage.locator('[role="dialog"]').waitFor({ state: 'hidden', timeout: 5000 });

    const topPostsChip = momentsPage.locator('[data-vs="wish-chip"]', { hasText: 'Show my top 5 posts this month' });
    await topPostsChip.click();
    await waitForAuthoringToFinish(momentsPage);
    await momentsPage.locator('[data-vs="label-allow"]').click();
    const topPostsCard = momentsPage.locator('[data-vs="vibe-card"][data-vibe-id="top-posts"]');
    await topPostsCard.waitFor({ state: 'visible', timeout: 5000 });
    await momentsPage.waitForFunction(() => {
      const card = document.querySelector('[data-vs="vibe-card"][data-vibe-id="top-posts"]');
      return card && card.querySelectorAll('.vk-bar-swatch').length === 5;
    }, null, { timeout: 6000 });

    // Story 7c: Focus timer in Moments + Start changes time
    const momentsFocusAdd = momentsPage.locator('[data-vs="gallery-add"][data-vibe-id="focus-timer"]');
    await momentsFocusAdd.scrollIntoViewIfNeeded();
    await momentsFocusAdd.click();
    await momentsPage.locator('[data-vs="label"]').waitFor({ state: 'visible', timeout: 5000 });
    await momentsPage.locator('[data-vs="label-allow"]').click();

    const momentsFocusCard = momentsPage.locator('[data-vs="vibe-card"][data-vibe-id="focus-timer"]');
    await momentsFocusCard.waitFor({ state: 'visible', timeout: 5000 });
    await momentsPage.waitForFunction(() => {
      const card = document.querySelector('[data-vs="vibe-card"][data-vibe-id="focus-timer"]');
      return card && card.querySelector('.vk-stat-value');
    }, null, { timeout: 6000 });
    const mTimeBefore = await momentsFocusCard.locator('.vk-stat-value').first().innerText();
    await momentsFocusCard.locator('.vk-button', { hasText: /^Start$/i }).click();
    await momentsPage.waitForFunction(
      (prev) => {
        const el = document.querySelector('[data-vs="vibe-card"][data-vibe-id="focus-timer"] .vk-stat-value');
        return el && el.textContent.trim() !== prev.trim();
      },
      mTimeBefore,
      { timeout: 5000 }
    );
    const mTimeAfter = await momentsFocusCard.locator('.vk-stat-value').first().innerText();
    assert(mTimeAfter !== mTimeBefore, `Moments focus timer time did not change after Start (${mTimeBefore} -> ${mTimeAfter})`);
    // S5: Running timer has Pause and no Start, and bar caption shows time left (not 100%)
    assert((await momentsFocusCard.locator('.vk-button', { hasText: /^Pause$/i }).count()) === 1, 'S5 failed in Moments: running timer missing Pause button');
    assert((await momentsFocusCard.locator('.vk-button', { hasText: /^Start$/i }).count()) === 0, 'S5 failed in Moments: running timer should not show Start button');
    const mBarCaption = await momentsFocusCard.locator('.vk-bar-caption').first().textContent();
    assert(/left/i.test(mBarCaption) && !mBarCaption.includes('100%'), `S5 failed in Moments: unexpected bar caption "${mBarCaption}"`);

    // F1: At 1440x900 on Moments, scrolling the Vibe Space panel does not move the feed
    if (!isMobile) {
      await momentsPage.evaluate(() => window.scrollTo(0, 0));
      const f1Result = await momentsPage.evaluate(() => {
        const panel = document.getElementById('vibe-space');
        const feedCard = document.querySelector('.post-card, .feed-card, article');
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
        const beforeFeedTop = feedCard ? feedCard.getBoundingClientRect().top : null;
        const beforeWinY = window.scrollY;
        let delta = 0;
        if (scrollEl) {
          const prev = scrollEl.scrollTop;
          scrollEl.scrollTop = prev > 40 ? prev - 40 : 120;
          delta = Math.abs(scrollEl.scrollTop - prev);
        }
        const afterFeedTop = feedCard ? feedCard.getBoundingClientRect().top : null;
        const afterWinY = window.scrollY;
        return { hasScroller: !!scrollEl, delta, beforeFeedTop, afterFeedTop, beforeWinY, afterWinY };
      });
      assert(f1Result.hasScroller && f1Result.delta > 0, `F1 failed: Moments Vibe Space panel did not scroll independently (${JSON.stringify(f1Result)})`);
      assert(f1Result.beforeFeedTop === f1Result.afterFeedTop && f1Result.afterWinY === f1Result.beforeWinY, `F1 failed: scrolling panel moved feed (${JSON.stringify(f1Result)})`);
    }

    await momentsFocusCard.scrollIntoViewIfNeeded();
    if (!isMobile) {
      assert((await momentsPage.evaluate(() => window.scrollY)) === 0, 'C3: Moments window scrolled instead of panel at 1440x900');
    }
    await snap('15', 'moments', 'focustimer', momentsPage);
    if (isMobile) {
      await momentsPage.locator('[data-app="tab-feed"]').click();
      await momentsPage.waitForTimeout(200);
    } else {
      // Ensure feed is at top for 16-moments-feed-1440
      await momentsPage.evaluate(() => window.scrollTo(0, 0));
    }
    await snap('16', 'moments', 'feed', momentsPage);

    // Round 2 Moments: Revoke follower likes access -> source-banner + sample fallback -> auto recovery
    const followerToggle = momentsPage.locator('[data-app="toggle-follower-source"]');
    await followerToggle.waitFor({ state: 'visible', timeout: 5000 });
    await followerToggle.click();
    if (isMobile) {
      await momentsPage.locator('[data-app="tab-vibes"]').click();
      await momentsPage.waitForTimeout(200);
    }
    const mSourceBanner = topFansCard.locator('[data-vs="source-banner"]');
    await mSourceBanner.waitFor({ state: 'visible', timeout: 6000 });
    assert((await momentsFocusCard.locator('[data-vs="source-banner"]').count()) === 0, 'Portable Focus timer should not show source-banner when follower access is revoked');
    await assertNoVkErrors(momentsPage, `moments-revoked-${width}`);
    await topFansCard.scrollIntoViewIfNeeded();
    if (!isMobile) {
      assert((await momentsPage.evaluate(() => window.scrollY)) === 0, 'C3: Moments window scrolled on source-revoked');
    }
    await momentsPage.waitForTimeout(220);
    await snap('17', 'moments', 'source-revoked', momentsPage);

    // Switch to sample fallback
    await topFansCard.locator('[data-vs="source-use-sample"]').click();
    await topFansCard.locator('[data-vs="source-use-live"]').waitFor({ state: 'visible', timeout: 6000 });
    await momentsPage.waitForFunction(() => {
      const card = document.querySelector('[data-vs="vibe-card"][data-vibe-id="top-fans"]');
      return card && !card.querySelector('.vk-view-stale') && card.querySelectorAll('.vk-bar').length >= 1;
    }, null, { timeout: 6000 });
    await snap('18', 'moments', 'sample-fallback', momentsPage);

    // Restore follower access & return to live
    await followerToggle.waitFor({ state: 'visible', timeout: 5000 });
    await followerToggle.click();
    await topFansCard.locator('[data-vs="source-use-live"]').click();
    await mSourceBanner.waitFor({ state: 'hidden', timeout: 6000 });
    await momentsPage.close();

    // Story 7d: Focus timer in LeapTerm + Start changes time
    // Close share dialog in LeapTerm first
    await ltPage.keyboard.press('Escape');
    await ltPage.locator('[data-vs="share-link"]').waitFor({ state: 'hidden', timeout: 5000 });
    const ltFocusAdd = ltPage.locator('[data-vs="gallery-add"][data-vibe-id="focus-timer"]');
    await ltFocusAdd.scrollIntoViewIfNeeded();
    await ltFocusAdd.click();
    await ltPage.locator('[data-vs="label"]').waitFor({ state: 'visible', timeout: 5000 });
    await ltPage.locator('[data-vs="label-allow"]').click();

    const ltFocusCard = ltPage.locator('[data-vs="vibe-card"][data-vibe-id="focus-timer"]');
    await ltFocusCard.waitFor({ state: 'visible', timeout: 5000 });
    await ltPage.waitForFunction(() => {
      const card = document.querySelector('[data-vs="vibe-card"][data-vibe-id="focus-timer"]');
      return card && card.querySelector('.vk-stat-value');
    }, null, { timeout: 6000 });
    const ltTimeBefore = await ltFocusCard.locator('.vk-stat-value').first().innerText();
    await ltFocusCard.locator('.vk-button', { hasText: /^Start$/i }).click();
    await ltPage.waitForFunction(
      (prev) => {
        const el = document.querySelector('[data-vs="vibe-card"][data-vibe-id="focus-timer"] .vk-stat-value');
        return el && el.textContent.trim() !== prev.trim();
      },
      ltTimeBefore,
      { timeout: 5000 }
    );
    const ltTimeAfter = await ltFocusCard.locator('.vk-stat-value').first().innerText();
    assert(ltTimeAfter !== ltTimeBefore, `LeapTerm focus timer time did not change after Start (${ltTimeBefore} -> ${ltTimeAfter})`);
    // S5: Running timer has Pause and no Start
    assert((await ltFocusCard.locator('.vk-button', { hasText: /^Pause$/i }).count()) === 1, 'S5 failed in LeapTerm: running timer missing Pause button');
    assert((await ltFocusCard.locator('.vk-button', { hasText: /^Start$/i }).count()) === 0, 'S5 failed in LeapTerm: running timer should not show Start button');

    // O1: At 1440x900 with three vibes installed, LeapTerm page itself does not scroll and server list stays in view
    if (!isMobile) {
      const o1Result = await ltPage.evaluate(() => {
        const sh = document.scrollingElement.scrollHeight;
        const ih = window.innerHeight;
        const serverList = document.querySelector('.lt-servers-pane, [data-app="servers"]');
        const rect = serverList ? serverList.getBoundingClientRect() : null;
        return { sh, ih, scrollY: window.scrollY, serverTop: rect ? rect.top : null };
      });
      assert(o1Result.sh <= o1Result.ih + 2, `O1 failed: LeapTerm page scrollHeight=${o1Result.sh} > innerHeight=${o1Result.ih}`);
      assert(o1Result.scrollY === 0 && o1Result.serverTop !== null && o1Result.serverTop >= 0 && o1Result.serverTop < 300, `O1 failed: server list scrolled out of view (${JSON.stringify(o1Result)})`);
    }

    await ltFocusCard.scrollIntoViewIfNeeded();
    if (!isMobile) {
      assert((await ltPage.evaluate(() => window.scrollY)) === 0, 'C3: LeapTerm window scrolled at 1440x900');
    }
    await assertNoVkErrors(ltPage, `leapterm-focustimer-${width}`);
    await snap('19', 'leapterm', 'focustimer', ltPage);

    // Round 2 Beat 20: Edit vibe (wish remix + live JS code edit + Test in sandbox + Save + Revert)
    await diskWatchCard.scrollIntoViewIfNeeded();
    await clickCardMenuAction(diskWatchCard, 'vibe-edit');
    const editDlg = ltPage.locator('[data-vs="edit-dialog"]');
    await editDlg.waitFor({ state: 'visible', timeout: 5000 });
    await editDlg.locator('[data-vs="edit-wish-input"]').fill('Make it red above 85% and show worst 4');
    await editDlg.locator('[data-vs="edit-wish-run"]').click();
    await ltPage.waitForFunction(() => {
      const p = document.querySelector('[data-vs="edit-preview"]');
      return p && p.querySelectorAll('.vk-bar').length === 4 && p.textContent.includes('85%');
    }, null, { timeout: 6000 });
    await editDlg.locator('[data-vs="edit-save"]').click();
    await editDlg.waitFor({ state: 'hidden', timeout: 5000 });
    await ltPage.waitForFunction(() => {
      const card = document.querySelector('[data-vs="vibe-card"][data-vibe-id="disk-watch"]');
      return card && card.textContent.includes('v3') && card.querySelectorAll('.vk-bar').length === 4;
    }, null, { timeout: 6000 });
    assert((await diskWatchCard.locator('.vk-bar.vk-tone-danger').count()) >= 1, 'Remixed v3 Disk Watch missing danger bar above 85%');
    assert((await diskWatchCard.locator('.vk-bar.vk-tone-warn').count()) >= 1, 'Remixed v3 Disk Watch lost warn bars (0.6-0.84) after wish remix');

    // Direct code edit + Test in sandbox + Save -> v4, then Revert -> v3
    await clickCardMenuAction(diskWatchCard, 'vibe-edit');
    await editDlg.waitFor({ state: 'visible', timeout: 5000 });
    await editDlg.locator('[data-vs="edit-tab-code"]').click();
    const srcArea = editDlg.locator('[data-vs="edit-source-input"]');
    const oldSrc = await srcArea.inputValue();
    const editedSrc = oldSrc.replaceAll('Disk usage', 'Disk usage · custom');
    assert(editedSrc !== oldSrc, 'Expected "Disk usage" in disk-watch source for code edit test');
    await srcArea.fill(editedSrc);
    await editDlg.locator('[data-vs="edit-test-btn"]').click();
    await ltPage.waitForFunction(() => {
      const p = document.querySelector('[data-vs="edit-preview"]');
      return p && p.textContent.includes('Disk usage · custom');
    }, null, { timeout: 6000 });
    await editDlg.locator('[data-vs="edit-preview"]').scrollIntoViewIfNeeded();
    await snap('20', 'leapterm', 'edit-code', ltPage);
    await editDlg.locator('[data-vs="edit-save"]').click();
    await editDlg.waitFor({ state: 'hidden', timeout: 5000 });
    await ltPage.waitForFunction(() => {
      const card = document.querySelector('[data-vs="vibe-card"][data-vibe-id="disk-watch"]');
      return card && card.textContent.includes('v4') && card.textContent.includes('Disk usage · custom');
    }, null, { timeout: 6000 });

    // Revert back to v3 via three-dots menu -> Revert
    await clickCardMenuAction(diskWatchCard, 'vibe-revert');
    await ltPage.waitForFunction(() => {
      const card = document.querySelector('[data-vs="vibe-card"][data-vibe-id="disk-watch"]');
      return card && card.textContent.includes('v3') && !card.textContent.includes('Disk usage · custom');
    }, null, { timeout: 6000 });

    // Round 2 Beat 21: Manage cards (Rename, Pin to top, Collapse/Expand, Pause/Resume, Filter, Delete + Undo)
    await clickCardMenuAction(diskWatchCard, 'vibe-rename');
    const inlineTitleInput = diskWatchCard.locator('[data-vs="vibe-title-input"]');
    await inlineTitleInput.waitFor({ state: 'visible', timeout: 5000 });
    await inlineTitleInput.fill('Prod Disk Watch');
    await inlineTitleInput.press('Enter');
    await ltPage.waitForFunction(() => {
      const el = document.querySelector('[data-vs="vibe-card"][data-vibe-id="disk-watch"] [data-vs="vibe-title"]');
      return el && el.textContent.trim() === 'Prod Disk Watch';
    }, null, { timeout: 5000 });

    // Pin Disk Watch to top
    await clickCardMenuAction(diskWatchCard, 'vibe-pin-top');
    await ltPage.waitForFunction(() => {
      const first = document.querySelector('[data-vs="vibe-card"]');
      return first && first.getAttribute('data-vibe-id') === 'disk-watch' && first.textContent.includes('Pinned');
    }, null, { timeout: 5000 });

    // Pause Focus timer
    await ltFocusCard.scrollIntoViewIfNeeded();
    await clickCardMenuAction(ltFocusCard, 'vibe-pause');
    await ltFocusCard.locator('[data-vs="vibe-resume"]').waitFor({ state: 'visible', timeout: 5000 });

    // Collapse and re-expand DB-1 CPU Watch
    await pinnedCard.locator('[data-vs="vibe-collapse"]').click();
    await ltPage.waitForFunction(() => {
      const card = document.querySelector('[data-vs="vibe-card"][data-vibe-id="server-load"]');
      const body = card && card.querySelector('.vs-vibe-card-collapsible');
      return body && (body.hidden || getComputedStyle(body).display === 'none');
    }, null, { timeout: 5000 });
    await pinnedCard.locator('[data-vs="vibe-collapse"]').click();
    await ltPage.waitForFunction(() => {
      const card = document.querySelector('[data-vs="vibe-card"][data-vibe-id="server-load"]');
      const body = card && card.querySelector('.vs-vibe-card-collapsible');
      return body && !body.hidden && getComputedStyle(body).display !== 'none';
    }, null, { timeout: 5000 });

    // Filter installed vibes and capture open three-dots menu
    const filterBox = ltPage.locator('[data-vs="vibe-filter"]');
    await filterBox.scrollIntoViewIfNeeded();
    await filterBox.fill('Prod Disk');
    await ltPage.waitForFunction(() => {
      const cards = Array.from(document.querySelectorAll('[data-vs="vibe-card"]'));
      return cards.filter((c) => c.offsetParent !== null && !c.hidden).length === 1;
    }, null, { timeout: 5000 });
    await diskWatchCard.locator('[data-vs="vibe-more"]').click();
    const openMenu = diskWatchCard.locator('[data-vs="vibe-menu"]');
    await openMenu.waitFor({ state: 'visible', timeout: 5000 });
    // Verify both top (Edit) and bottom (Delete) items are inside the visible menu and not clipped behind bottom tabs
    const menuCheck = await ltPage.evaluate((isMob) => {
      const card = document.querySelector('[data-vs="vibe-card"][data-vibe-id="disk-watch"]');
      const menu = card && card.querySelector('[data-vs="vibe-menu"]');
      const del = card && card.querySelector('[data-vs="vibe-remove"]');
      if (!menu || !del) return { ok: false, reason: 'missing' };
      const mr = menu.getBoundingClientRect();
      const dr = del.getBoundingClientRect();
      const maxBottom = window.innerHeight - (isMob ? 64 : 8);
      return {
        ok: dr.bottom <= mr.bottom + 1 && dr.bottom <= maxBottom && dr.top >= 0,
        menuScrollH: menu.scrollHeight,
        menuClientH: menu.clientHeight,
        delBottom: dr.bottom,
        menuBottom: mr.bottom,
        maxBottom,
      };
    }, isMobile);
    assert(menuCheck.ok, `Open three-dots menu clipped or behind bottom bar: ${JSON.stringify(menuCheck)}`);
    await snap('21', 'leapterm', 'manage-cards', ltPage);
    await diskWatchCard.locator('[data-vs="vibe-more"]').click();
    await diskWatchCard.locator('[data-vs="vibe-menu"]').waitFor({ state: 'hidden', timeout: 5000 });

    await filterBox.fill('');
    await ltPage.waitForFunction(() => {
      const cards = Array.from(document.querySelectorAll('[data-vs="vibe-card"]'));
      return cards.filter((c) => c.offsetParent !== null && !c.hidden).length === 3;
    }, null, { timeout: 5000 });

    // Resume Focus timer
    await ltFocusCard.locator('[data-vs="vibe-resume"]').click();
    await ltFocusCard.locator('[data-vs="vibe-resume"]').waitFor({ state: 'hidden', timeout: 5000 });

    // Delete Disk Watch + Undo
    await clickCardMenuAction(diskWatchCard, 'vibe-remove');
    const undoBanner = ltPage.locator('[data-vs="undo-banner"]');
    await undoBanner.waitFor({ state: 'visible', timeout: 5000 });
    assert((await diskWatchCard.count()) === 0, 'Deleted card still in DOM before Undo');
    await undoBanner.locator('[data-vs="undo-delete"]').click();
    await diskWatchCard.waitFor({ state: 'visible', timeout: 5000 });
    assert((await diskWatchCard.locator('[data-vs="vibe-title"]').textContent()).trim() === 'Prod Disk Watch', 'Undo did not restore custom title');

    // Round 2 Beat 22: Target server offline (db-1.prod.internal) -> Target server offline + last reading -> back online
    if (isMobile) {
      await ltPage.locator('[data-app="tab-servers"]').click();
      await ltPage.waitForTimeout(200);
    }
    const db1Toggle = ltPage.locator('[data-app="toggle-server"][data-server="db-1.prod.internal"]');
    await db1Toggle.waitFor({ state: 'visible', timeout: 5000 });
    await db1Toggle.click();
    if (isMobile) {
      await ltPage.locator('[data-app="tab-vibes"]').click();
      await ltPage.waitForTimeout(200);
    }
    await ltPage.waitForFunction(() => {
      const card = document.querySelector('[data-vs="vibe-card"][data-vibe-id="server-load"]');
      return card && card.textContent.includes('Target server offline') && card.querySelectorAll('.vk-stat').length >= 2;
    }, null, { timeout: 6000 });
    await assertNoVkErrors(ltPage, `server-offline-${width}`);
    await pinnedCard.scrollIntoViewIfNeeded();
    if (!isMobile) {
      assert((await ltPage.evaluate(() => window.scrollY)) === 0, 'C3: LeapTerm window scrolled on server-offline');
    }
    await snap('22', 'leapterm', 'server-offline', ltPage);

    // Bring db-1 back online & verify recovery
    if (isMobile) {
      await ltPage.locator('[data-app="tab-servers"]').click();
      await ltPage.waitForTimeout(200);
    }
    await db1Toggle.click();
    if (isMobile) {
      await ltPage.locator('[data-app="tab-vibes"]').click();
      await ltPage.waitForTimeout(200);
    }
    await ltPage.waitForFunction(() => {
      const card = document.querySelector('[data-vs="vibe-card"][data-vibe-id="server-load"]');
      return card && !card.textContent.includes('Target server offline');
    }, null, { timeout: 6000 });

    // Round 2 Beat 23 & 24: Telemetry feed offline -> .vk-view-stale + source-banner (Focus timer stays live) -> reconnect recovery
    if (isMobile) {
      await ltPage.locator('[data-app="tab-servers"]').click();
      await ltPage.waitForTimeout(200);
    }
    const telemetryToggle = ltPage.locator('[data-app="toggle-telemetry"]');
    await telemetryToggle.waitFor({ state: 'visible', timeout: 5000 });
    await telemetryToggle.click();
    if (isMobile) {
      await ltPage.locator('[data-app="tab-vibes"]').click();
      await ltPage.waitForTimeout(200);
    }
    await diskWatchCard.locator('[data-vs="source-banner"]').waitFor({ state: 'visible', timeout: 6000 });
    await ltPage.waitForFunction(() => {
      const dw = document.querySelector('[data-vs="vibe-card"][data-vibe-id="disk-watch"]');
      const ft = document.querySelector('[data-vs="vibe-card"][data-vibe-id="focus-timer"]');
      return dw && !!dw.querySelector('.vk-view-stale') && dw.querySelectorAll('.vk-bar').length >= 1 &&
        ft && !ft.querySelector('[data-vs="source-banner"]') && !ft.querySelector('.vk-view-stale');
    }, null, { timeout: 6000 });
    await assertNoVkErrors(ltPage, `telemetry-offline-${width}`);
    await diskWatchCard.scrollIntoViewIfNeeded();
    if (!isMobile) {
      assert((await ltPage.evaluate(() => window.scrollY)) === 0, 'C3: LeapTerm window scrolled on telemetry-offline');
    }
    await ltPage.waitForTimeout(220);
    await snap('23', 'leapterm', 'telemetry-offline', ltPage);

    // Reconnect telemetry feed -> automatic recovery
    if (isMobile) {
      await ltPage.locator('[data-app="tab-servers"]').click();
      await ltPage.waitForTimeout(200);
    }
    await telemetryToggle.click();
    if (isMobile) {
      await ltPage.locator('[data-app="tab-vibes"]').click();
      await ltPage.waitForTimeout(200);
    }
    await diskWatchCard.locator('[data-vs="source-banner"]').waitFor({ state: 'hidden', timeout: 6000 });
    await ltPage.waitForFunction(() => {
      const dw = document.querySelector('[data-vs="vibe-card"][data-vibe-id="disk-watch"]');
      return dw && !dw.querySelector('.vk-view-stale') && dw.querySelectorAll('.vk-bar').length >= 1;
    }, null, { timeout: 6000 });
    await assertNoVkErrors(ltPage, `leapterm-recovered-${width}`);
    await ltPage.waitForTimeout(220);
    await snap('24', 'leapterm', 'telemetry-recovered', ltPage);

    await ltPage.close();
  } finally {
    await context.close();
  }
}

async function checkFileUrls(browser, errorLog) {
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  try {
    const pages = [
      { label: 'file-home', file: path.join(DEMO_ROOT, 'index.html'), check: async (p) => (await p.innerText('body')).includes('VibeProtocol demo') },
      { label: 'file-leapterm', file: path.join(DEMO_ROOT, 'apps/leapterm/index.html'), check: async (p) => (await p.locator('#vibe-space [data-vs="wish-input"]').count()) === 1 },
      { label: 'file-moments', file: path.join(DEMO_ROOT, 'apps/moments/index.html'), check: async (p) => (await p.locator('#vibe-space [data-vs="wish-input"]').count()) === 1 },
    ];
    for (const item of pages) {
      const page = await context.newPage();
      trackErrors(page, item.label, errorLog);
      await page.goto(pathToFileURL(item.file).href, { waitUntil: 'load' });
      await page.waitForTimeout(400);
      const ok = await item.check(page);
      assert(ok, `${item.label} did not render expected content under file://`);
      if (item.label === 'file-leapterm') {
        await page.locator('[data-vs="gallery-add"][data-vibe-id="focus-timer"]').click();
        await page.locator('[data-vs="label-allow"]').click();
        await page.waitForFunction(() => {
          const el = document.querySelector('[data-vs="vibe-card"][data-vibe-id="focus-timer"] .vk-stat-value');
          return el && el.textContent.includes('25:00');
        }, null, { timeout: 6000 });
        await assertNoVkErrors(page, 'file-leapterm-mount');
      }
      await page.close();
    }
  } finally {
    await context.close();
  }
}

async function main() {
  const { chromium } = await import(pathToFileURL(PLAYWRIGHT_PATH).href);
  const server = await startDemoServer();
  const browser = await chromium.launch({ headless: true });
  const errorLog = [];
  const shots = [];

  try {
    console.log('Running story walkthrough at 1440x900...');
    await runStoryForViewport(browser, server.baseUrl, { width: 1440, height: 900 }, errorLog, shots);
    console.log('1440x900 walkthrough passed.');

    console.log('Running story walkthrough at 390x844...');
    await runStoryForViewport(browser, server.baseUrl, { width: 390, height: 844 }, errorLog, shots);
    console.log('390x844 walkthrough passed.');

    console.log('Checking file:// rendering for all 3 pages...');
    await checkFileUrls(browser, errorLog);
    console.log('file:// checks passed.');

    assert(errorLog.length === 0, `Console/page errors recorded:\n${errorLog.join('\n')}`);
    console.log(`\nALL STORY CHECKS PASSED. Screenshots (${shots.length}):`);
    for (const s of shots) {
      console.log('  ' + s);
    }
  } finally {
    await browser.close();
    await server.close();
  }
}

main().catch((err) => {
  console.error('\nSTORY CHECK FAILED:', err && err.stack ? err.stack : err.message);
  process.exit(1);
});
