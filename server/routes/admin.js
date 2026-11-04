'use strict';

const { HttpError } = require('../http-error');
const { verifyPassword, newToken, hashToken, DUMMY_HASH } = require('../auth');
const { bad, intParam, optString, requireObject, UUID_RE } = require('../validate');
const { Reply } = require('../router');
const { listProducts, productDetails } = require('./catalog');

const COOKIE = 'cx_admin';
const SESSION_HOURS = 12;
// A custom header on every change: a page of another site cannot send it
// without a CORS preflight, which this server never allows.
const CSRF_HEADER = 'cosmetix-admin';

function cookieHeader(value, { maxAgeSec, secure }) {
  return [
    `${COOKIE}=${value}`,
    'Path=/admin',
    'HttpOnly',
    'SameSite=Strict',
    `Max-Age=${maxAgeSec}`,
    ...(secure ? ['Secure'] : []),
  ].join('; ');
}

function readCookie(req, name) {
  for (const part of (req.headers.cookie || '').split(';')) {
    const i = part.indexOf('=');
    if (i > 0 && part.slice(0, i).trim() === name) return part.slice(i + 1).trim();
  }
  return null;
}

/** The signed-in admin of this request, or 401. Changes also need the CSRF header. */
async function requireAdmin(db, req) {
  if (req.method !== 'GET' && req.headers['x-requested-with'] !== CSRF_HEADER) {
    throw new HttpError(403, 'forbidden', 'Missing x-requested-with header');
  }
  const token = readCookie(req, COOKIE);
  if (!token) throw new HttpError(401, 'unauthorized', 'Sign in first');
  const r = await db.query(
    `SELECT a.id, a.username FROM admin_sessions s JOIN admins a ON a.id = s.admin_id
      WHERE s.token_hash = $1 AND s.expires_at > now()`,
    [hashToken(token)],
  );
  if (r.rowCount === 0) throw new HttpError(401, 'unauthorized', 'Sign in first');
  return r.rows[0];
}

const MAX_PRICE = 10_000_000;

/** Fields the panel may change on a product, validated; returns column -> value. */
function parseProductPatch(body) {
  requireObject(body);
  const out = {};
  const known = ['name', 'category', 'inci', 'country', 'price', 'description'];
  const unknown = Object.keys(body).filter((k) => !known.includes(k));
  if (unknown.length) throw bad(`Unknown fields: ${unknown.join(', ')}`);
  if (body.name !== undefined) {
    const v = optString(body.name, 'name', { max: 200 });
    if (!v) throw bad('"name" cannot be empty');
    out.name = v;
  }
  if (body.category !== undefined) {
    const v = optString(body.category, 'category', { max: 60 });
    if (!v) throw bad('"category" cannot be empty');
    out.category = v;
  }
  if (body.inci !== undefined) out.inci = optString(body.inci, 'inci', { max: 8000 }) ?? '';
  if (body.description !== undefined) {
    out.description = optString(body.description, 'description', { max: 2000 }) ?? '';
  }
  if (body.country !== undefined) out.country = optString(body.country, 'country', { max: 60 });
  if (body.price !== undefined) {
    if (!Number.isInteger(body.price) || body.price < 0 || body.price > MAX_PRICE) {
      throw bad(`"price" must be a whole number of tenge from 0 to ${MAX_PRICE}`);
    }
    out.price = body.price;
  }
  if (Object.keys(out).length === 0) throw bad('Nothing to update');
  return out;
}

function registerAdmin(router, { loginLimiter, cookieSecure }) {
  router.add('POST', '/admin/api/login', async ({ db, req, body }) => {
    const ip = req.socket.remoteAddress || 'unknown';
    if (loginLimiter.blocked(ip)) {
      throw new HttpError(429, 'rate_limited', 'Too many failed sign-ins, try again later', {
        retryAfter: 900,
      });
    }
    const b = requireObject(await body());
    const username = typeof b.username === 'string' ? b.username.trim().slice(0, 100) : '';
    const password = typeof b.password === 'string' ? b.password.slice(0, 200) : '';
    const r = await db.query('SELECT id, password_hash FROM admins WHERE username = $1', [username]);
    // same work whether the user exists or not
    const ok = verifyPassword(password, r.rowCount ? r.rows[0].password_hash : DUMMY_HASH);
    if (!ok || r.rowCount === 0) {
      loginLimiter.hit(ip);
      throw new HttpError(401, 'unauthorized', 'Wrong username or password');
    }
    loginLimiter.reset(ip);
    const token = newToken();
    await db.query('DELETE FROM admin_sessions WHERE expires_at < now()');
    await db.query(
      `INSERT INTO admin_sessions (token_hash, admin_id, expires_at)
       VALUES ($1, $2, now() + $3 * interval '1 hour')`,
      [hashToken(token), r.rows[0].id, SESSION_HOURS],
    );
    return new Reply(
      200,
      { username },
      { 'set-cookie': cookieHeader(token, { maxAgeSec: SESSION_HOURS * 3600, secure: cookieSecure }) },
    );
  });

  router.add('POST', '/admin/api/logout', async ({ db, req }) => {
    await requireAdmin(db, req);
    await db.query('DELETE FROM admin_sessions WHERE token_hash = $1', [
      hashToken(readCookie(req, COOKIE)),
    ]);
    return new Reply(204, null, { 'set-cookie': cookieHeader('', { maxAgeSec: 0, secure: cookieSecure }) });
  });

  router.add('GET', '/admin/api/me', async ({ db, req }) => {
    const a = await requireAdmin(db, req);
    return { username: a.username };
  });

  router.add('GET', '/admin/api/products', async ({ db, req, url }) => {
    await requireAdmin(db, req);
    return listProducts(db, url.searchParams, { maxLimit: 100, defLimit: 50 });
  });

  router.add('GET', '/admin/api/products/:id', async ({ db, req, params }) => {
    await requireAdmin(db, req);
    return productDetails(db, intParam(params.id, 'id', { min: 1, max: 2147483647 }));
  });

  router.add('GET', '/admin/api/categories', async ({ db, req }) => {
    await requireAdmin(db, req);
    return { items: (await db.query('SELECT id, name FROM categories ORDER BY name')).rows };
  });

  router.add('PATCH', '/admin/api/products/:id', async ({ db, req, params, body }) => {
    const admin = await requireAdmin(db, req);
    const id = intParam(params.id, 'id', { min: 1, max: 2147483647 });
    const patch = parseProductPatch(await body());
    const client = await db.connect();
    try {
      await client.query('BEGIN');
      const cur = await client.query(
        `SELECT p.name, c.name AS category, p.inci, p.country, p.price, p.description
           FROM products p JOIN categories c ON c.id = p.category_id WHERE p.id = $1 FOR UPDATE OF p`,
        [id],
      );
      if (cur.rowCount === 0) throw new HttpError(404, 'not_found', 'Product not found');
      const before = cur.rows[0];
      // only what really changes is saved and logged
      const changes = {};
      for (const [k, v] of Object.entries(patch)) {
        if (before[k] !== v && !(before[k] === null && v === null)) changes[k] = { from: before[k], to: v };
      }
      if (Object.keys(changes).length > 0) {
        const sets = [];
        const args = [];
        const set = (col, v) => {
          args.push(v);
          sets.push(`${col} = $${args.length}`);
        };
        if ('category' in changes) {
          const c = await client.query(
            `INSERT INTO categories (name) VALUES ($1)
             ON CONFLICT (name) DO UPDATE SET name = EXCLUDED.name RETURNING id`,
            [patch.category],
          );
          set('category_id', c.rows[0].id);
        }
        for (const col of ['name', 'inci', 'country', 'description']) {
          if (col in changes) set(col, patch[col]);
        }
        if ('price' in changes) {
          set('price', patch.price);
          // an edited price is no longer the placeholder from the seed
          sets.push("price_source = 'admin'");
        }
        args.push(id);
        try {
          await client.query(
            `UPDATE products SET ${sets.join(', ')}, updated_at = now() WHERE id = $${args.length}`,
            args,
          );
        } catch (e) {
          if (e.code === '23505') {
            throw new HttpError(409, 'conflict', 'This brand already has a product with that name');
          }
          throw e;
        }
        await client.query(
          'INSERT INTO admin_audit (admin_id, username, product_id, changes) VALUES ($1,$2,$3,$4)',
          [admin.id, admin.username, id, JSON.stringify(changes)],
        );
      }
      await client.query('COMMIT');
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }
    return productDetails(db, id);
  });

  router.add('GET', '/admin/api/events', async ({ db, req, url }) => {
    await requireAdmin(db, req);
    const q = url.searchParams;
    const limit = intParam(q.get('limit'), 'limit', { min: 1, max: 200, def: 50 });
    const offset = intParam(q.get('offset'), 'offset', { min: 0, def: 0 });
    const where = [];
    const args = [];
    if (q.get('type')) {
      args.push(q.get('type'));
      where.push(`e.type = $${args.length}`);
    }
    if (q.get('userId')) {
      if (!UUID_RE.test(q.get('userId'))) throw bad('"userId" must be a UUID');
      args.push(q.get('userId'));
      where.push(`e.user_id = $${args.length}`);
    }
    const w = where.length ? `WHERE ${where.join(' AND ')}` : '';
    const total = await db.query(`SELECT count(*)::int AS n FROM activity_events e ${w}`, args);
    const rows = await db.query(
      `SELECT e.id, e.user_id, e.type, e.props, e.client_time, e.created_at
         FROM activity_events e ${w} ORDER BY e.created_at DESC, e.id DESC
        LIMIT $${args.length + 1} OFFSET $${args.length + 2}`,
      [...args, limit, offset],
    );
    return {
      total: total.rows[0].n,
      limit,
      offset,
      items: rows.rows.map((e) => ({
        id: Number(e.id),
        userId: e.user_id,
        type: e.type,
        props: e.props,
        clientTime: e.client_time,
        createdAt: e.created_at,
      })),
    };
  });

  // Counts for the overview. "users" are anonymous devices, not people.
  router.add('GET', '/admin/api/stats', async ({ db, req }) => {
    await requireAdmin(db, req);
    const [totals, byType, opensByDay] = await Promise.all([
      db.query(
        `SELECT (SELECT count(*) FROM app_users)::int AS users,
                (SELECT count(*) FROM app_users WHERE last_seen_at > now() - interval '24 hours')::int AS active_24h,
                (SELECT count(*) FROM activity_events WHERE type = 'app_open'
                   AND created_at > now() - interval '24 hours')::int AS opens_24h,
                (SELECT count(*) FROM activity_events WHERE type = 'app_open'
                   AND created_at > now() - interval '7 days')::int AS opens_7d,
                (SELECT count(*) FROM activity_events)::int AS events`,
      ),
      db.query(
        `SELECT type, count(*)::int AS n FROM activity_events
          WHERE created_at > now() - interval '7 days' GROUP BY type ORDER BY n DESC LIMIT 20`,
      ),
      db.query(
        `SELECT to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD') AS day, count(*)::int AS opens,
                count(DISTINCT user_id)::int AS users
           FROM activity_events WHERE type = 'app_open' AND created_at > now() - interval '14 days'
          GROUP BY day ORDER BY day DESC`,
      ),
    ]);
    const t = totals.rows[0];
    return {
      users: t.users,
      activeUsers24h: t.active_24h,
      opens24h: t.opens_24h,
      opens7d: t.opens_7d,
      events: t.events,
      eventsByType7d: byType.rows,
      opensByDay: opensByDay.rows,
    };
  });

  // No profile data here: only who exists, when seen and how active.
  router.add('GET', '/admin/api/users', async ({ db, req, url }) => {
    await requireAdmin(db, req);
    const limit = intParam(url.searchParams.get('limit'), 'limit', { min: 1, max: 200, def: 50 });
    const offset = intParam(url.searchParams.get('offset'), 'offset', { min: 0, def: 0 });
    const total = await db.query('SELECT count(*)::int AS n FROM app_users');
    const rows = await db.query(
      `SELECT u.id, u.created_at, u.last_seen_at,
              (SELECT count(*) FROM activity_events e WHERE e.user_id = u.id)::int AS events,
              (SELECT count(*) FROM activity_events e WHERE e.user_id = u.id AND e.type = 'app_open')::int AS opens
         FROM app_users u ORDER BY u.last_seen_at DESC LIMIT $1 OFFSET $2`,
      [limit, offset],
    );
    return {
      total: total.rows[0].n,
      limit,
      offset,
      items: rows.rows.map((u) => ({
        id: u.id,
        createdAt: u.created_at,
        lastSeenAt: u.last_seen_at,
        events: u.events,
        opens: u.opens,
      })),
    };
  });

  router.add('GET', '/admin/api/audit', async ({ db, req, url }) => {
    await requireAdmin(db, req);
    const limit = intParam(url.searchParams.get('limit'), 'limit', { min: 1, max: 200, def: 50 });
    const rows = await db.query(
      `SELECT a.id, a.username, a.product_id, p.name AS product_name, a.changes, a.created_at
         FROM admin_audit a LEFT JOIN products p ON p.id = a.product_id
        ORDER BY a.created_at DESC, a.id DESC LIMIT $1`,
      [limit],
    );
    return {
      items: rows.rows.map((a) => ({
        id: Number(a.id),
        username: a.username,
        productId: a.product_id,
        productName: a.product_name,
        changes: a.changes,
        createdAt: a.created_at,
      })),
    };
  });
}

module.exports = { registerAdmin, requireAdmin, parseProductPatch, CSRF_HEADER };
