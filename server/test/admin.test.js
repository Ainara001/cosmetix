'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  SKIP,
  createTestDb,
  boot,
  newDevice,
  createAdmin,
  adminLogin,
  ADMIN_USER,
  ADMIN_PASSWORD,
} = require('../testkit/db');
const { hashPassword, verifyPassword } = require('../auth');

test('password hashing', () => {
  const h = hashPassword('a long enough password');
  assert.match(h, /^scrypt\$/);
  assert.ok(!h.includes('a long enough password'));
  assert.equal(verifyPassword('a long enough password', h), true);
  assert.equal(verifyPassword('another long password', h), false);
  assert.equal(verifyPassword('x', 'garbage'), false);
  assert.throws(() => hashPassword('short'), /at least 12/);
  assert.notEqual(hashPassword('a long enough password'), h, 'every hash has its own salt');
});

test('admin panel', { skip: SKIP }, async (t) => {
  const db = await createTestDb();
  await createAdmin(db.pool);
  const app = await boot({ pool: db.pool });
  t.after(async () => {
    await app.close();
    await db.drop();
  });

  await t.test('the page and its files are served with a strict CSP', async () => {
    for (const path of ['/admin', '/admin/app.js', '/admin/style.css']) {
      const r = await app.call(path);
      assert.equal(r.status, 200, path);
      assert.match(r.headers.get('content-security-policy'), /default-src 'none'/);
      assert.match(r.headers.get('content-security-policy'), /frame-ancestors 'none'/);
      assert.equal(r.headers.get('x-content-type-options'), 'nosniff');
    }
    assert.match((await app.call('/admin')).headers.get('content-type'), /text\/html/);
    assert.match((await app.call('/admin')).text, /Cosmetix/);
    // the page loads nothing from other sites and has no inline script
    const html = (await app.call('/admin')).text;
    assert.ok(!/https?:\/\//.test(html));
    assert.ok(!/<script(?![^>]*\bsrc=)/.test(html));
  });

  await t.test('every admin API call needs a sign-in', async () => {
    for (const path of ['me', 'products', 'products/1', 'categories', 'events', 'stats', 'users', 'audit']) {
      const r = await app.call(`/admin/api/${path}`);
      assert.equal(r.status, 401, path);
    }
    const patch = await app.call('/admin/api/products/1', {
      method: 'PATCH',
      json: { price: 1 },
      headers: { 'x-requested-with': 'cosmetix-admin' },
    });
    assert.equal(patch.status, 401);
  });

  await t.test('wrong credentials: same answer for a wrong password and an unknown user', async () => {
    const a = await app.call('/admin/api/login', { method: 'POST', json: { username: ADMIN_USER, password: 'wrong password!!' } });
    const b = await app.call('/admin/api/login', { method: 'POST', json: { username: 'nobody', password: 'wrong password!!' } });
    assert.equal(a.status, 401);
    assert.equal(b.status, 401);
    assert.deepEqual(a.data, b.data);
    assert.equal(a.headers.get('set-cookie'), null);
    assert.equal((await app.call('/admin/api/login', { method: 'POST', json: {} })).status, 401);
    assert.equal((await app.call('/admin/api/login', { method: 'POST', json: [] })).status, 400);
  });

  await t.test('sign in sets an HttpOnly SameSite=Strict cookie; the token is stored hashed', async () => {
    const r = await app.call('/admin/api/login', { method: 'POST', json: { username: ADMIN_USER, password: ADMIN_PASSWORD } });
    assert.equal(r.status, 200);
    const cookie = r.headers.get('set-cookie');
    assert.match(cookie, /HttpOnly/);
    assert.match(cookie, /SameSite=Strict/);
    assert.match(cookie, /Path=\/admin/);
    const token = cookie.split(';')[0].split('=')[1];
    const rows = (await db.pool.query('SELECT token_hash FROM admin_sessions')).rows;
    assert.ok(rows.length >= 1 && rows.every((x) => x.token_hash !== token));
    const me = await app.call('/admin/api/me', { headers: { cookie: `cx_admin=${token}` } });
    assert.deepEqual(me.data, { username: ADMIN_USER });
    // a forged cookie does not work
    assert.equal((await app.call('/admin/api/me', { headers: { cookie: 'cx_admin=forged' } })).status, 401);
  });

  await t.test('changes without the CSRF header are refused even when signed in', async () => {
    const h = await adminLogin(app);
    const r = await app.call('/admin/api/products/1', { method: 'PATCH', json: { price: 1 }, headers: { cookie: h.cookie } });
    assert.equal(r.status, 403);
    assert.equal((await app.call('/admin/api/products/1', { headers: h })).data.price !== 1, true);
  });

  await t.test('edit a product: name, category, country, INCI, price', async () => {
    const h = await adminLogin(app);
    const before = (await app.call('/admin/api/products/1', { headers: h })).data;
    assert.equal(before.priceSource, 'demo');
    assert.equal(before.country, null);

    const r = await app.call('/admin/api/products/1', {
      method: 'PATCH',
      headers: h,
      json: { name: 'Super Slim Waterproof Mascara (edit)', category: 'Тестовая категория', country: 'Корея', inci: 'Aqua, Glycerin', price: 2990 },
    });
    assert.equal(r.status, 200);
    assert.equal(r.data.name, 'Super Slim Waterproof Mascara (edit)');
    assert.equal(r.data.category, 'Тестовая категория');
    assert.equal(r.data.country, 'Корея');
    assert.equal(r.data.inci, 'Aqua, Glycerin');
    assert.equal(r.data.price, 2990);
    assert.equal(r.data.priceSource, 'admin', 'an edited price is no longer a demo value');
    assert.ok(new Date(r.data.updatedAt) > new Date(before.updatedAt));

    // the app sees the change
    const pub = await app.call('/v1/catalog/products/1');
    assert.equal(pub.data.country, 'Корея');
    assert.equal(pub.data.priceSource, 'admin');
    assert.ok((await app.call('/v1/catalog/categories')).data.items.some((c) => c.name === 'Тестовая категория'));
    // and so does an app that syncs by date
    const since = await app.call(`/v1/catalog/products?updatedSince=${encodeURIComponent(before.updatedAt)}`);
    assert.deepEqual(since.data.items.map((p) => p.id), [1]);

    // the other shops' prices are untouched
    assert.ok(pub.data.prices.every((p) => p.source === 'demo'));
  });

  await t.test('every change is written to the audit log with old and new value', async () => {
    const h = await adminLogin(app);
    await app.call('/admin/api/products/2', { method: 'PATCH', headers: h, json: { country: 'Япония' } });
    // the same value again is not a change
    await app.call('/admin/api/products/2', { method: 'PATCH', headers: h, json: { country: 'Япония' } });
    const log = (await app.call('/admin/api/audit', { headers: h })).data.items;
    const mine = log.filter((x) => x.productId === 2);
    assert.equal(mine.length, 1);
    assert.equal(mine[0].username, ADMIN_USER);
    assert.deepEqual(mine[0].changes, { country: { from: null, to: 'Япония' } });
  });

  await t.test('country can be cleared again', async () => {
    const h = await adminLogin(app);
    const r = await app.call('/admin/api/products/2', { method: 'PATCH', headers: h, json: { country: '' } });
    assert.equal(r.data.country, null);
  });

  await t.test('product edit: validation', async () => {
    const h = await adminLogin(app);
    const bad = [
      [{ price: -1 }, 'negative price'],
      [{ price: 12.5 }, 'fractional price'],
      [{ price: '100' }, 'price as text'],
      [{ price: 20_000_000 }, 'huge price'],
      [{ name: '   ' }, 'empty name'],
      [{ category: '' }, 'empty category'],
      [{ inci: 'x'.repeat(8001) }, 'long INCI'],
      [{ brand: 'Other' }, 'unknown field'],
      [{ id: 5 }, 'id is not editable'],
      [{}, 'nothing to update'],
    ];
    for (const [json, name] of bad) {
      const r = await app.call('/admin/api/products/3', { method: 'PATCH', headers: h, json });
      assert.equal(r.status, 400, name);
    }
    assert.equal((await app.call('/admin/api/products/99999', { method: 'PATCH', headers: h, json: { price: 5 } })).status, 404);
    assert.equal((await app.call('/admin/api/products/abc', { method: 'PATCH', headers: h, json: { price: 5 } })).status, 400);
    // nothing of the rejected requests got saved
    const p = (await app.call('/admin/api/products/3', { headers: h })).data;
    assert.equal(p.priceSource, 'demo');
  });

  await t.test('renaming onto an existing product of the same brand is 409', async () => {
    const h = await adminLogin(app);
    const a = (await app.call('/admin/api/products/3', { headers: h })).data;
    const sameBrand = (await app.call(`/admin/api/products?q=${encodeURIComponent(a.brand)}&limit=100`, { headers: h })).data.items.find(
      (p) => p.id !== 3,
    );
    assert.ok(sameBrand, 'the seed has two products of one brand');
    const r = await app.call('/admin/api/products/3', { method: 'PATCH', headers: h, json: { name: sameBrand.name } });
    // 409 only when the brand really matches
    assert.equal(r.status, sameBrand.brand === a.brand ? 409 : 200);
  });

  await t.test('text in the INCI or name is stored as is (the panel escapes it on display)', async () => {
    const h = await adminLogin(app);
    const payload = '<img src=x onerror=alert(1)>';
    const r = await app.call('/admin/api/products/4', { method: 'PATCH', headers: h, json: { inci: payload } });
    assert.equal(r.data.inci, payload);
    const code = (await app.call('/admin/app.js')).text;
    assert.ok(!/\.(innerHTML|outerHTML)|insertAdjacentHTML|document\.write|eval\(/.test(code), 'the panel never writes HTML');
  });

  await t.test('product list in the panel: search and category filter', async () => {
    const h = await adminLogin(app);
    const all = (await app.call('/admin/api/products?limit=100', { headers: h })).data;
    assert.equal(all.total, 38);
    const q = (await app.call('/admin/api/products?q=retinol', { headers: h })).data;
    assert.ok(q.total >= 1 && q.items.every((p) => /retinol/i.test(p.name + p.brand)));
    assert.equal((await app.call('/admin/api/products?limit=101', { headers: h })).status, 400);
  });

  await t.test('activity: events, logins, stats and devices', async () => {
    const h = await adminLogin(app);
    const d1 = await newDevice(app);
    const d2 = await newDevice(app);
    await app.call('/v1/events', {
      method: 'POST',
      headers: d1.auth,
      json: { events: [{ type: 'app_open' }, { type: 'product_view', props: { productId: 7 } }, { type: 'app_open' }] },
    });
    await app.call('/v1/events', { method: 'POST', headers: d2.auth, json: { events: [{ type: 'app_open' }] } });
    await app.call('/v1/profile', { method: 'PUT', headers: d1.auth, json: { birthYear: 1995, city: 'Астана' } });

    const opens = (await app.call('/admin/api/events?type=app_open', { headers: h })).data;
    assert.equal(opens.total, 3);
    assert.ok(opens.items.every((e) => e.type === 'app_open'));
    assert.deepEqual(opens.items.map((e) => e.userId).sort(), [d1.userId, d1.userId, d2.userId].sort());

    const mine = (await app.call(`/admin/api/events?userId=${d1.userId}`, { headers: h })).data;
    assert.equal(mine.total, 3);
    assert.deepEqual(mine.items.find((e) => e.type === 'product_view').props, { productId: 7 });
    assert.equal((await app.call('/admin/api/events?userId=nope', { headers: h })).status, 400);

    const paged = (await app.call('/admin/api/events?limit=2&offset=0', { headers: h })).data;
    assert.equal(paged.items.length, 2);
    assert.equal(paged.total, 4);

    const s = (await app.call('/admin/api/stats', { headers: h })).data;
    assert.equal(s.opens24h, 3);
    assert.equal(s.events, 4);
    assert.equal(s.eventsByType7d.find((x) => x.type === 'app_open').n, 3);
    assert.equal(s.opensByDay[0].opens, 3);
    assert.equal(s.opensByDay[0].users, 2);
    assert.ok(s.users >= 2);

    // the device list shows activity, but no profile data
    const users = (await app.call('/admin/api/users', { headers: h })).data;
    const u1 = users.items.find((u) => u.id === d1.userId);
    assert.equal(u1.opens, 2);
    assert.equal(u1.events, 3);
    assert.deepEqual(Object.keys(u1).sort(), ['createdAt', 'events', 'id', 'lastSeenAt', 'opens']);
  });

  await t.test('logout ends the session', async () => {
    const h = await adminLogin(app);
    assert.equal((await app.call('/admin/api/me', { headers: h })).status, 200);
    const out = await app.call('/admin/api/logout', { method: 'POST', headers: h });
    assert.equal(out.status, 204);
    assert.match(out.headers.get('set-cookie'), /Max-Age=0/);
    assert.equal((await app.call('/admin/api/me', { headers: h })).status, 401);
  });

  await t.test('an expired session does not work', async () => {
    const h = await adminLogin(app);
    await db.pool.query("UPDATE admin_sessions SET expires_at = now() - interval '1 minute'");
    assert.equal((await app.call('/admin/api/me', { headers: h })).status, 401);
  });
});

test('admin login is locked after 10 wrong passwords', { skip: SKIP }, async (t) => {
  const db = await createTestDb({ seed: false });
  await createAdmin(db.pool);
  const app = await boot({ pool: db.pool });
  t.after(async () => {
    await app.close();
    await db.drop();
  });
  const wrong = () => app.call('/admin/api/login', { method: 'POST', json: { username: ADMIN_USER, password: 'wrong password!!' } });
  for (let i = 0; i < 10; i += 1) assert.equal((await wrong()).status, 401);
  const locked = await wrong();
  assert.equal(locked.status, 429);
  // even the right password waits
  const right = await app.call('/admin/api/login', { method: 'POST', json: { username: ADMIN_USER, password: ADMIN_PASSWORD } });
  assert.equal(right.status, 429);
});
