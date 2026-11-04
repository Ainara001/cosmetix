'use strict';

const { HttpError } = require('../http-error');

const LOOPBACK = new Set(['127.0.0.1', '::1', '::ffff:127.0.0.1']);
const LOCAL_HOSTS = ['localhost', '127.0.0.1', '[::1]'];

/** `Host: example.com:8787` -> `example.com`; `[::1]:8787` -> `[::1]`. */
function hostName(header) {
  const h = String(header || '').trim().toLowerCase();
  if (h.startsWith('[')) return h.slice(0, h.indexOf(']') + 1);
  return h.split(':')[0];
}

/**
 * Who may even see the admin panel (page and API), checked before anything else.
 *
 *  * By default only this machine: the connection must come from a loopback
 *    address and the Host header must name it (localhost, 127.0.0.1, [::1]).
 *    The panel is plain HTTP, so a password typed from another device would
 *    cross the network in clear text. The Host check also stops "DNS rebinding"
 *    (a web page that points its own name at 127.0.0.1 to reach the panel).
 *  * ADMIN_ALLOW_REMOTE=1 lifts the loopback rule. Do that only behind HTTPS
 *    (a reverse proxy that terminates TLS), with ADMIN_COOKIE_SECURE=1 and
 *    ADMIN_ALLOWED_HOSTS=admin.example.com (comma separated) so the Host header
 *    is still checked. Headers such as X-Forwarded-For are never trusted here.
 */
function checkAdminAccess(req, env) {
  const extra = (env.ADMIN_ALLOWED_HOSTS || '')
    .split(',')
    .map((h) => h.trim().toLowerCase())
    .filter(Boolean);
  const remoteOk = env.ADMIN_ALLOW_REMOTE === '1';
  if (!remoteOk && !LOOPBACK.has(req.socket.remoteAddress || '')) {
    throw new HttpError(
      403,
      'admin_local_only',
      'The admin panel is available only on the machine the server runs on',
    );
  }
  const allowed = remoteOk ? extra : [...LOCAL_HOSTS, ...extra];
  if (allowed.length > 0 && !allowed.includes(hostName(req.headers.host))) {
    throw new HttpError(403, 'forbidden_host', 'This host name is not allowed for the admin panel');
  }
}

/**
 * A change that comes from a page of another site carries its Origin: refuse it.
 * Requests without an Origin (curl, tests) are fine, they have no browser session
 * to abuse; the cookie is SameSite=Strict as well.
 */
function checkSameOrigin(req) {
  const origin = req.headers.origin;
  if (origin === undefined) return;
  let host = '';
  try {
    host = new URL(origin).host;
  } catch {
    // "null" and garbage fall through to the refusal
  }
  if (!host || host !== String(req.headers.host || '').toLowerCase()) {
    throw new HttpError(403, 'forbidden', 'Cross-site request refused');
  }
}

module.exports = { checkAdminAccess, checkSameOrigin, hostName };
