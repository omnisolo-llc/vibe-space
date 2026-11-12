import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
export const DEMO_ROOT = path.resolve(__dirname, '..');

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
