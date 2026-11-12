import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
export const DEMO_ROOT = path.resolve(__dirname, '..');

/**
 * Loads Playwright without hardcoding a single checkout layout path.
 */
export async function loadPlaywright() {
  const candidates = [
    process.env.PLAYWRIGHT_PATH,
    path.resolve(DEMO_ROOT, '../../../cloud/web/node_modules/playwright/index.mjs'),
    path.resolve(DEMO_ROOT, '../../../website/node_modules/playwright/index.mjs'),
    path.resolve(DEMO_ROOT, '../node_modules/playwright/index.mjs'),
  ].filter(Boolean);
  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) {
      return import(pathToFileURL(candidate).href);
    }
  }
  return import('playwright');
}

function findCachedChromiumExecutable() {
  if (process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH && fs.existsSync(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH)) {
    return process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH;
  }
  const cacheDir = path.join(os.homedir(), '.cache', 'ms-playwright');
  if (!fs.existsSync(cacheDir)) return null;
  const entries = fs.readdirSync(cacheDir).sort().reverse();
  for (const entry of entries) {
    if (entry.startsWith('chromium_headless_shell-')) {
      const bin = path.join(cacheDir, entry, 'chrome-headless-shell-linux64', 'chrome-headless-shell');
      if (fs.existsSync(bin)) return bin;
    }
    if (entry.startsWith('chromium-')) {
      const bin = path.join(cacheDir, entry, 'chrome-linux64', 'chrome');
      if (fs.existsSync(bin)) return bin;
    }
  }
  return null;
}

/**
 * Launches headless Chromium, falling back to any cached ms-playwright binary
 * if the active Playwright package targets a slightly newer revision.
 */
export async function launchChromium(chromium) {
  try {
    return await chromium.launch({ headless: true });
  } catch (err) {
    const executablePath = findCachedChromiumExecutable();
    if (executablePath) {
      return chromium.launch({ headless: true, executablePath });
    }
    throw err;
  }
}

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.md': 'text/markdown; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
};

/**
 * Starts a local HTTP server on 127.0.0.1 with an ephemeral port serving DEMO_ROOT,
 * recording any requests to /leak and serving optional virtual routes.
 */
export async function startDemoServer(virtualRoutes = {}) {
  const leaks = [];

  const server = http.createServer((req, res) => {
    const reqUrl = new URL(req.url || '/', 'http://127.0.0.1');
    const pathname = decodeURIComponent(reqUrl.pathname);

    if (pathname === '/leak' || pathname.startsWith('/leak/')) {
      const chunks = [];
      req.on('data', (c) => chunks.push(c));
      req.on('end', () => {
        leaks.push({
          method: req.method,
          url: req.url,
          headers: req.headers,
          body: Buffer.concat(chunks).toString('utf8'),
          at: Date.now(),
        });
        res.writeHead(200, { 'Content-Type': 'text/plain', 'Access-Control-Allow-Origin': '*' });
        res.end('recorded');
      });
      return;
    }

    if (Object.prototype.hasOwnProperty.call(virtualRoutes, pathname)) {
      const route = virtualRoutes[pathname];
      res.writeHead(route.status || 200, { 'Content-Type': route.contentType || 'text/html; charset=utf-8' });
      res.end(route.body);
      return;
    }

    let relPath = pathname.replace(/^\/+/, '');
    if (!relPath || relPath.endsWith('/')) {
      relPath += 'index.html';
    }
    const filePath = path.resolve(DEMO_ROOT, relPath);
    if (!filePath.startsWith(DEMO_ROOT + path.sep) && filePath !== DEMO_ROOT) {
      res.writeHead(403, { 'Content-Type': 'text/plain' });
      res.end('Forbidden');
      return;
    }

    fs.readFile(filePath, (err, data) => {
      if (err) {
        res.writeHead(err.code === 'ENOENT' ? 404 : 500, { 'Content-Type': 'text/plain' });
        res.end(err.code === 'ENOENT' ? 'Not found' : 'Server error');
        return;
      }
      const ext = path.extname(filePath).toLowerCase();
      res.writeHead(200, { 'Content-Type': MIME_TYPES[ext] || 'application/octet-stream' });
      res.end(data);
    });
  });

  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });

  const addr = server.address();
  const baseUrl = `http://127.0.0.1:${addr.port}`;

  return {
    baseUrl,
    port: addr.port,
    leaks,
    clearLeaks() {
      leaks.length = 0;
    },
    close() {
      return new Promise((resolve) => server.close(() => resolve()));
    },
  };
}
