'use strict';

const fs = require('node:fs');
const path = require('node:path');

const { HttpError } = require('../http-error');
const { Router, Reply } = require('../router');
const { createLimiter } = require('../ratelimit');
const { registerCatalog } = require('./catalog');
const { registerAppUser } = require('./app-user');
const { registerAdmin } = require('./admin');

const ADMIN_DIR = path.join(__dirname, '..', 'admin');
const STATIC = {
  '/admin': ['index.html', 'text/html; charset=utf-8'],
  '/admin/': ['index.html', 'text/html; charset=utf-8'],
  '/admin/app.js': ['app.js', 'text/javascript; charset=utf-8'],
  '/admin/style.css': ['style.css', 'text/css; charset=utf-8'],
};

// The panel loads nothing from other sites and cannot be put in a frame.
const ADMIN_HEADERS = {
  'content-security-policy':
    "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; " +
    "img-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
  'x-content-type-options': 'nosniff',
  'referrer-policy': 'no-referrer',
  'x-frame-options': 'DENY',
};

/**
 * The database-backed part of the server: catalog and user API for the app
 * (/v1/...) and the admin panel (/admin). Returns `handle(req, url, readBody)`
 * which gives a Reply, or null when the path is not one of ours.
 */
function createApi({ db, env = process.env, now = () => Date.now() }) {
  const router = new Router();
  const cookieSecure = env.ADMIN_COOKIE_SECURE === '1';
  registerCatalog(router);
  registerAppUser(router, {
    devicesLimiter: createLimiter({ limit: 20, windowMs: 3600 * 1000, now }),
    now,
  });
  registerAdmin(router, {
    // 10 wrong passwords per 15 minutes from one address
    loginLimiter: createLimiter({ limit: 10, windowMs: 15 * 60 * 1000, now }),
    cookieSecure,
  });

  const files = new Map();
  function staticFile(name) {
    if (!files.has(name)) files.set(name, fs.readFileSync(path.join(ADMIN_DIR, name)));
    return files.get(name);
  }

  return {
    isApiPath(pathname) {
      return pathname.startsWith('/v1/') || pathname === '/admin' || pathname.startsWith('/admin/');
    },
    isAdminPath(pathname) {
      return pathname === '/admin' || pathname.startsWith('/admin/');
    },

    async handle(req, url, readBody) {
      const { pathname } = url;
      if (!this.isApiPath(pathname)) return null;
      if (!db) {
        throw new HttpError(503, 'db_not_configured', 'The database is not configured (DATABASE_URL)');
      }
      if (req.method === 'GET' && STATIC[pathname]) {
        const [file, type] = STATIC[pathname];
        return new Reply(200, staticFile(file), { 'content-type': type }, true);
      }
      const m = router.match(req.method, pathname);
      if (!m) throw new HttpError(404, 'not_found', 'Not found');
      const out = await m.handler({ db, req, url, params: m.params, body: readBody });
      return out instanceof Reply ? out : new Reply(200, out);
    },

    adminHeaders: ADMIN_HEADERS,
  };
}

module.exports = { createApi, ADMIN_HEADERS };
