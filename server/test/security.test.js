'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const { SKIP, createTestDb, boot, newDevice, createAdmin, adminLogin } = require('../testkit/db');
const { createPool } = require('../db/pool');
const { isDbUnavailable } = require('../db/errors');
const { checkAdminAccess, checkSameOrigin, hostName } = require('../routes/admin-guard');
const { createApp } = require('../app');

const fakeReq = (remoteAddress, host = '127.0.0.1:8787', extra = {}) => ({
  socket: { remoteAddress },
  headers: { host, ...extra },
});

// ---------------------------------------------------------------- guard unit

test('admin access: only this machine by default', () => {
  for (const ok of ['127.0.0.1', '::1', '::ffff:127.0.0.1']) {
    assert.doesNotThrow(() => checkAdminAccess(fakeReq(ok, 'localhost:8787'), {}), ok);
  }
  for (const remote of ['192.168.1.50', '10.0.0.7', '8.8.8.8', '::ffff:192.168.1.5', '', undefined]) {
    assert.throws(
      () => checkAdminAccess(fakeReq(remote), {}),
      (e) => e.status === 403 && e.code === 'admin_local_only',
      String(remote),
    );
  }
});

test('admin access: the Host header must name this machine (DNS rebinding)', () => {
  for (const host of ['localhost', 'localhost:8787', '127.0.0.1:1', '[::1]:8787', 'LOCALHOST:8787']) {
    assert.doesNotThrow(() => checkAdminAccess(fakeReq('127.0.0.1', host), {}), host);
  }
  for (const host of ['evil.test', 'evil.test:8787', '127.0.0.1.evil.test', 'localhost.evil.test', '', 'admin.example.com']) {
    assert.throws(
      () => checkAdminAccess(fakeReq('127.0.0.1', host), {}),
      (e) => e.status === 403 && e.code === 'forbidden_host',
      host,
    );
  }
  assert.equal(hostName('[::1]:8787'), '[::1]');
  assert.equal(hostName('Example.COM:99'), 'example.com');
});

test('admin access: remote only when switched on, and then with a host list', () => {
  const remote = '203.0.113.9';
  assert.throws(() => checkAdminAccess(fakeReq(remote, 'admin.example.com'), { ADMIN_ALLOWED_HOSTS: 'admin.example.com' }));
  const env = { ADMIN_ALLOW_REMOTE: '1', ADMIN_ALLOWED_HOSTS: 'admin.example.com, other.example.com' };
  assert.doesNotThrow(() => checkAdminAccess(fakeReq(remote, 'admin.example.com'), env));
  assert.doesNotThrow(() => checkAdminAccess(fakeReq(remote, 'other.example.com:443'), env));
  assert.throws(() => checkAdminAccess(fakeReq(remote, 'evil.test'), env), (e) => e.code === 'forbidden_host');
  // X-Forwarded-For is never trusted
  assert.throws(() =>
    checkAdminAccess(fakeReq(remote, 'localhost', { 'x-forwarded-for': '127.0.0.1' }), {}),
  );
});

test('same origin: a page of another site is refused', () => {
  const req = (origin) => fakeReq('127.0.0.1', 'localhost:8787', origin === undefined ? {} : { origin });
  assert.doesNotThrow(() => checkSameOrigin(req(undefined)));
  assert.doesNotThrow(() => checkSameOrigin(req('http://localhost:8787')));
  for (const bad of ['http://evil.test', 'http://localhost:9999', 'null', 'garbage', '', 'http://localhost']) {
    assert.throws(() => checkSameOrigin(req(bad)), (e) => e.status === 403, bad);
  }
});

// ---------------------------------------------------------- database errors

test('isDbUnavailable tells "database is down" from "my request is wrong"', () => {
  for (const e of [
    Object.assign(new Error('x'), { code: 'ECONNREFUSED' }),
    Object.assign(new Error('x'), { code: 'ETIMEDOUT' }),
    Object.assign(new Error('x'), { code: '57P01' }),
    Object.assign(new Error('x'), { code: '08006' }),
    Object.assign(new Error('x'), { code: '53300' }),
    Object.assign(new Error('x'), { code: '57014' }),
    new Error('Connection terminated unexpectedly'),
    new Error('timeout exceeded when trying to connect'),
    Object.assign(new AggregateError([Object.assign(new Error('a'), { code: 'ECONNREFUSED' })]), {}),
  ]) {
    assert.equal(isDbUnavailable(e), true, `${e.code || e.message}`);
  }
  for (const e of [
    Object.assign(new Error('dup'), { code: '23505' }),
    Object.assign(new Error('no table'), { code: '42P01' }),
    new TypeError('x is not a function'),
    null,
    undefined,
  ]) {
    assert.equal(isDbUnavailable(e), false, `${e && (e.code || e.message)}`);
  }
});

test('the pool has an error handler (an idle connection that dies must not stop the process)', () => {
  const pool = createPool({ DATABASE_URL: 'postgres://u:p@127.0.0.1:1/db' });
  assert.ok(pool.listenerCount('error') >= 1);
  return pool.end();
});

test('database down: 503 for the database routes, the rest keeps working, nothing leaks', async (t) => {
  const { Pool } = require('pg');
  const dead = new Pool({
    connectionString: 'postgres://dbuser:S3cretPw@127.0.0.1:1/cosmetix_secret_db',
    connectionTimeoutMillis: 1000,
  });
  dead.on('error', () => {});
  const app = await boot({ pool: dead });
  t.after(async () => {
    await app.close();
    await dead.end();
  });
  const errors = [];
  const orig = console.error;
  console.error = (...a) => errors.push(a.join(' '));
  t.after(() => {
    console.error = orig;
  });

  const calls = [
    ['GET', '/v1/catalog/products'],
    ['POST', '/v1/devices'],
    ['POST', '/admin/api/login'],
  ];
  for (const [method, p] of calls) {
    const r = await app.call(p, { method, json: method === 'POST' ? { username: 'a', password: 'b' } : undefined });
    assert.equal(r.status, 503, p);
    assert.equal(r.data.error, 'db_unavailable', p);
    assert.equal(r.headers.get('retry-after'), '5');
    const text = r.text + JSON.stringify([...r.headers]);
    for (const secret of ['S3cretPw', 'dbuser', 'cosmetix_secret_db', '127.0.0.1:1', 'ECONNREFUSED']) {
      assert.ok(!text.includes(secret), `${p} leaks ${secret}`);
    }
  }
  // the AI proxy part is not affected
  assert.equal((await app.call('/health')).status, 200);
  const chat = await app.call('/v1/chat', { method: 'POST', json: { messages: [{ role: 'user', content: 'hi' }] } });
  assert.equal(chat.status, 200);
  // the log has the code only
  assert.ok(errors.length >= 3);
  assert.ok(errors.every((l) => !l.includes('S3cretPw') && !l.includes('dbuser')));
});

test('a bug in a handler is a plain 500 without details', async (t) => {
  const broken = {
    query: async () => {
      throw new Error('boom secret-detail');
    },
    connect: async () => {
      throw new Error('boom secret-detail');
    },
  };
  const { server } = createApp({ env: {}, db: broken });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  t.after(() => new Promise((r) => server.close(r)));
  const orig = console.error;
  console.error = () => {};
  t.after(() => {
    console.error = orig;
  });
  const r = await fetch(`http://127.0.0.1:${server.address().port}/v1/catalog/categories`);
  assert.equal(r.status, 500);
  const text = await r.text();
  assert.ok(!text.includes('secret-detail'));
  assert.equal(JSON.parse(text).error, 'internal');
});

test('start-up with an unreachable database stops with a clear message and no password', () => {
  const run = (url) =>
    spawnSync(process.execPath, ['index.js'], {
      cwd: path.join(__dirname, '..'),
      env: { PATH: process.env.PATH, DATABASE_URL: url, PORT: '0', HOST: '127.0.0.1', PG_CONNECT_TIMEOUT_MS: '1500' },
      timeout: 20000,
      encoding: 'utf8',
    });
  for (const url of ['postgres://dbuser:S3cretPw@127.0.0.1:1/cosmetix_secret_db', 'not a url at all S3cretPw']) {
    const r = run(url);
    assert.equal(r.status, 1, `exit status for ${url}`);
    assert.match(r.stderr, /startup failed/);
    for (const secret of ['S3cretPw', 'cosmetix_secret_db']) {
      assert.ok(!r.stderr.includes(secret) && !r.stdout.includes(secret), `leaks ${secret}`);
    }
  }
});

test('a database that restarts does not stop the server', { skip: SKIP }, async (t) => {
  const pool = createPool({ DATABASE_URL: process.env.TEST_DATABASE_URL });
  const other = createPool({ DATABASE_URL: process.env.TEST_DATABASE_URL });
  t.after(async () => {
    await pool.end();
    await other.end();
  });
  const logged = [];
  const orig = console.error;
  console.error = (...a) => logged.push(a.join(' '));
  t.after(() => {
    console.error = orig;
  });
  const pid = (await pool.query('SELECT pg_backend_pid() AS pid')).rows[0].pid;
  await other.query('SELECT pg_terminate_backend($1)', [pid]);
  await new Promise((r) => setTimeout(r, 300));
  // the dead idle connection was dropped, the next query opens a new one
  assert.equal((await pool.query('SELECT 1 AS ok')).rows[0].ok, 1);
  assert.ok(logged.every((l) => !/password|postgres:\/\//i.test(l)));
});

// ------------------------------------------------------------ admin API walls

test('admin API protection', { skip: SKIP }, async (t) => {
  const db = await createTestDb();
  await createAdmin(db.pool);
  const app = await boot({ pool: db.pool, env: { APP_TOKEN: 'shared-app-token' } });
  t.after(async () => {
    await app.close();
    await db.drop();
  });
  const adminRoutes = app.api.router.routes.filter((r) => r.pattern.startsWith('/admin/api/'));
  const concrete = (pattern) => pattern.replace(/:[a-zA-Z]+/g, '1');

  await t.test('the route list is what we think it is (a new route must be added to this check)', () => {
    assert.deepEqual(
      adminRoutes.map((r) => `${r.method} ${r.pattern}`).sort(),
      [
        'DELETE /admin/api/offers/:id',
        'GET /admin/api/audit',
        'GET /admin/api/categories',
        'GET /admin/api/events',
        'GET /admin/api/me',
        'GET /admin/api/offers',
        'GET /admin/api/products',
        'GET /admin/api/products/:id',
        'GET /admin/api/stats',
        'GET /admin/api/stores',
        'GET /admin/api/users',
        'PATCH /admin/api/products/:id',
        'POST /admin/api/login',
        'POST /admin/api/logout',
        'PUT /admin/api/offers',
      ],
    );
  });

  await t.test('without a session every route except login is 401 (and changes did nothing)', async () => {
    const before = (await db.pool.query('SELECT count(*)::int AS n FROM admin_audit')).rows[0].n;
    for (const r of adminRoutes.filter((x) => x.pattern !== '/admin/api/login')) {
      for (const headers of [{}, { 'x-requested-with': 'cosmetix-admin' }, { cookie: 'cx_admin=' }, { cookie: 'cx_admin=guess' }]) {
        const res = await app.call(concrete(r.pattern), {
          method: r.method,
          headers,
          json: r.method === 'PATCH' ? { price: 1 } : undefined,
        });
        // a change without the CSRF header is refused earlier, with 403: either way no access
        assert.ok([401, 403].includes(res.status), `${r.method} ${r.pattern} ${JSON.stringify(headers)} -> ${res.status}`);
        assert.ok(!res.text.includes('"items"') && !res.text.includes('"username"'));
      }
    }
    assert.equal((await db.pool.query('SELECT count(*)::int AS n FROM admin_audit')).rows[0].n, before);
    assert.equal((await db.pool.query('SELECT price_source FROM products WHERE id = 1')).rows[0].price_source, 'demo');
  });

  await t.test('with a session, every change still needs the CSRF header', async () => {
    const h = await adminLogin(app);
    for (const r of adminRoutes.filter((x) => x.method !== 'GET' && x.pattern !== '/admin/api/login')) {
      const res = await app.call(concrete(r.pattern), { method: r.method, headers: { cookie: h.cookie }, json: { price: 1 } });
      assert.equal(res.status, 403, `${r.method} ${r.pattern}`);
    }
    assert.equal((await app.call('/admin/api/me', { headers: { cookie: h.cookie } })).status, 200, 'reading is fine');
  });

  await t.test('other credentials do not open the admin API, and the admin cookie does not open the app API', async () => {
    const d = await newDevice(app);
    const asApp = { 'x-app-token': 'shared-app-token' };
    // device token, app token and both together
    for (const headers of [d.auth, asApp, { ...d.auth, ...asApp }]) {
      assert.equal((await app.call('/admin/api/me', { headers })).status, 401);
      assert.equal((await app.call('/admin/api/products', { headers })).status, 401);
    }
    // the device token as an admin cookie
    assert.equal((await app.call('/admin/api/me', { headers: { cookie: `cx_admin=${d.token}` } })).status, 401);
    // the admin session does not stand in for a device
    const h = await adminLogin(app);
    assert.equal((await app.call('/v1/profile', { headers: { cookie: h.cookie, ...asApp } })).status, 401);
    assert.equal((await app.call('/v1/events', { method: 'POST', headers: { cookie: h.cookie, ...asApp }, json: { events: [{ type: 'x' }] } })).status, 401);
  });

  await t.test('a page of another site cannot act with the admin cookie', async () => {
    const h = await adminLogin(app);
    for (const origin of ['http://evil.test', 'null']) {
      const res = await app.call('/admin/api/products/1', {
        method: 'PATCH',
        headers: { ...h, origin },
        json: { price: 7 },
      });
      assert.equal(res.status, 403, origin);
      const login = await app.call('/admin/api/login', { method: 'POST', headers: { origin }, json: { username: 'x', password: 'y' } });
      assert.equal(login.status, 403, `login from ${origin}`);
    }
    assert.equal((await db.pool.query('SELECT price FROM products WHERE id = 1')).rows[0].price, 2500);
    // the same site is fine
    const host = new URL(`http://${app.host}`).host;
    const ok = await app.call('/admin/api/products/1', { method: 'PATCH', headers: { ...h, origin: `http://${host}` }, json: { country: 'ТЕСТ' } });
    assert.equal(ok.status, 200);
  });

  await t.test('no CORS: another site cannot read the answers either', async () => {
    const h = await adminLogin(app);
    const get = await app.call('/admin/api/products', { headers: { ...h, origin: 'http://evil.test' } });
    assert.equal(get.headers.get('access-control-allow-origin'), null);
    const pre = await app.call('/admin/api/products/1', {
      method: 'OPTIONS',
      headers: { origin: 'http://evil.test', 'access-control-request-method': 'PATCH', 'access-control-request-headers': 'x-requested-with' },
    });
    assert.ok([404, 405].includes(pre.status));
    assert.equal(pre.headers.get('access-control-allow-origin'), null);
  });

  await t.test('a deleted admin loses the session at once', async () => {
    await createAdmin(db.pool, 'second', 'another long password');
    const h = await adminLogin(app, 'second', 'another long password');
    assert.equal((await app.call('/admin/api/me', { headers: h })).status, 200);
    await db.pool.query("DELETE FROM admins WHERE username = 'second'");
    assert.equal((await app.call('/admin/api/me', { headers: h })).status, 401);
  });

  await t.test('only this machine may open the panel (checked before the sign-in)', async () => {
    // a request that "comes from" another address is refused for the page and the API alike
    for (const p of ['/admin', '/admin/app.js', '/admin/api/me', '/admin/api/login']) {
      let err;
      try {
        await app.api.handle(
          { method: p.endsWith('login') ? 'POST' : 'GET', headers: { host: 'localhost' }, socket: { remoteAddress: '192.168.1.77' } },
          new URL(p, 'http://localhost'),
          async () => ({}),
        );
      } catch (e) {
        err = e;
      }
      assert.ok(err && err.status === 403 && err.code === 'admin_local_only', p);
    }
    // and through a real socket with a foreign Host header
    const res = await new Promise((resolve, reject) => {
      const rq = http.request({ host: '127.0.0.1', port: Number(app.port), path: '/admin', headers: { host: 'evil.test' } }, (r) => {
        r.resume();
        r.on('end', () => resolve(r.statusCode));
      });
      rq.on('error', reject);
      rq.end();
    });
    assert.equal(res, 403);
  });

  await t.test('the app API is not behind the admin wall', async () => {
    assert.equal((await app.call('/v1/catalog/categories', { headers: { 'x-app-token': 'shared-app-token' } })).status, 200);
  });
});
