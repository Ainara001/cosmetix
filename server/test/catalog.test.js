'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { SKIP, createTestDb, boot } = require('../testkit/db');
const { createApp } = require('../app');
const { seedCatalog } = require('../db/seed');
const { migrate } = require('../db/migrate');

test('without DATABASE_URL the new routes answer 503, /health keeps working', async () => {
  const { server } = createApp({ env: {}, db: null });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${server.address().port}`;
  for (const path of ['/v1/catalog/products', '/admin', '/admin/api/me']) {
    const r = await fetch(base + path);
    assert.equal(r.status, 503, path);
    assert.equal((await r.json()).error, 'db_not_configured');
  }
  assert.equal((await fetch(`${base}/health`)).status, 200);
  await new Promise((r) => server.close(r));
});

test('PostgreSQL catalog API', { skip: SKIP }, async (t) => {
  const db = await createTestDb();
  const app = await boot({ pool: db.pool });
  t.after(async () => {
    await app.close();
    await db.drop();
  });

  await t.test('seed loads the app catalog and is not repeated', async () => {
    const n = (await db.pool.query('SELECT count(*)::int AS n FROM products')).rows[0].n;
    assert.equal(n, 38);
    assert.equal(await seedCatalog(db.pool), false, 'a filled catalog is left alone');
    assert.equal((await db.pool.query('SELECT count(*)::int AS n FROM products')).rows[0].n, 38);
    assert.deepEqual(await migrate(db.pool), [], 'migrations are applied once');
  });

  await t.test('list: total, paging, fields', async () => {
    const r = await app.call('/v1/catalog/products?limit=5&offset=2');
    assert.equal(r.status, 200);
    assert.equal(r.data.total, 38);
    assert.equal(r.data.items.length, 5);
    assert.deepEqual(r.data.items.map((p) => p.id), [3, 4, 5, 6, 7]);
    const p = r.data.items[0];
    for (const k of ['brand', 'category', 'name', 'price', 'priceSource', 'inci', 'country', 'updatedAt']) {
      assert.ok(k in p, `field ${k}`);
    }
  });

  await t.test('seeded prices are marked as demo values', async () => {
    const r = await app.call('/v1/catalog/products?limit=100');
    assert.ok(r.data.items.every((p) => p.priceSource === 'demo'));
    const d = await app.call('/v1/catalog/products/1');
    assert.ok(d.data.prices.length > 0);
    assert.ok(d.data.prices.every((x) => x.source === 'demo'));
  });

  await t.test('country is empty until somebody fills it in (nothing is guessed)', async () => {
    const r = await app.call('/v1/catalog/products?limit=100');
    assert.ok(r.data.items.every((p) => p.country === null));
  });

  await t.test('filters: category, brand, text search', async () => {
    const cat = await app.call(`/v1/catalog/products?category=${encodeURIComponent('Макияж')}&limit=100`);
    assert.equal(cat.data.total, 17);
    assert.ok(cat.data.items.every((p) => p.category === 'Макияж'));
    const brand = await app.call(`/v1/catalog/products?brand=${encodeURIComponent('3CE')}&limit=100`);
    assert.ok(brand.data.total > 0 && brand.data.items.every((p) => p.brand === '3CE'));
    const q = await app.call('/v1/catalog/products?q=mascara');
    assert.ok(q.data.items.some((p) => p.id === 1));
    // % and _ are matched literally, not as wildcards: four seeded names contain a
    // real "%", but "N%c" (wildcard reading of "N" + anything + "c") matches nothing
    const literal = await app.call('/v1/catalog/products?q=10%25');
    assert.deepEqual(literal.data.items.map((p) => p.name), ['Niacinamide 10% + Zinc 1%']);
    assert.equal((await app.call('/v1/catalog/products?q=N%25c')).data.total, 0);
    assert.equal((await app.call('/v1/catalog/products?q=Retinol_0')).data.total, 0);
  });

  await t.test('bad paging and dates are 400', async () => {
    for (const q of ['limit=0', 'limit=1000', 'offset=-1', 'limit=abc', 'updatedSince=yesterday']) {
      const r = await app.call(`/v1/catalog/products?${q}`);
      assert.equal(r.status, 400, q);
      assert.equal(r.data.error, 'bad_request');
    }
  });

  await t.test('updatedSince returns only newer products', async () => {
    const future = new Date(Date.now() + 3600_000).toISOString();
    assert.equal((await app.call(`/v1/catalog/products?updatedSince=${encodeURIComponent(future)}`)).data.total, 0);
    const past = new Date(Date.now() - 3600_000).toISOString();
    assert.equal((await app.call(`/v1/catalog/products?updatedSince=${encodeURIComponent(past)}`)).data.total, 38);
  });

  await t.test('details: ingredients, traits, prices per shop', async () => {
    const r = await app.call('/v1/catalog/products/1');
    assert.equal(r.status, 200);
    assert.equal(r.data.id, 1);
    assert.ok(Array.isArray(r.data.ingredients));
    assert.ok(r.data.inci.length > 0);
    assert.ok(r.data.sourceUrl.startsWith('https://'));
    assert.deepEqual(Object.keys(r.data.traits).sort(), ['colorTypes', 'concerns', 'skinTypes', 'tags', 'undertones']);
    assert.equal(r.data.prices.length, 13, 'one offer per shop');
  });

  await t.test('details: unknown id is 404, bad id is 400', async () => {
    assert.equal((await app.call('/v1/catalog/products/99999')).status, 404);
    assert.equal((await app.call('/v1/catalog/products/abc')).status, 400);
    assert.equal((await app.call('/v1/catalog/nothing')).status, 404);
  });

  await t.test('reference lists', async () => {
    for (const [path, min] of [
      ['categories', 6],
      ['brands', 20],
      ['stores', 13],
      ['ingredients', 19],
    ]) {
      const r = await app.call(`/v1/catalog/${path}`);
      assert.equal(r.status, 200, path);
      assert.equal(r.data.items.length, min, path);
    }
    const stores = (await app.call('/v1/catalog/stores')).data.items;
    assert.ok(stores.every((s) => s.source), 'every shop names where its position comes from');
  });

  await t.test('wrong method on a known path is 405', async () => {
    assert.equal((await app.call('/v1/catalog/products', { method: 'POST', json: {} })).status, 405);
  });
});

test('APP_TOKEN protects the catalog when configured', { skip: SKIP }, async (t) => {
  const db = await createTestDb();
  const app = await boot({ pool: db.pool, env: { APP_TOKEN: 's3cret' } });
  t.after(async () => {
    await app.close();
    await db.drop();
  });
  assert.equal((await app.call('/v1/catalog/categories')).status, 401);
  assert.equal((await app.call('/v1/catalog/categories', { headers: { 'x-app-token': 's3cret' } })).status, 200);
  assert.equal((await app.call('/v1/devices', { method: 'POST' })).status, 401);
  // the admin panel has its own sign-in, not the app token
  assert.equal((await app.call('/admin/api/me')).status, 401);
});
