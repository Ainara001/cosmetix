'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { SKIP, createTestDb, boot, createAdmin, adminLogin } = require('../testkit/db');
const { parseOffer } = require('../routes/offers');

const NOW = Date.UTC(2026, 10, 7, 12, 0, 0);
const ok = (extra = {}) => ({
  productId: 1,
  storeId: 1,
  price: 5600,
  availability: 'in_stock',
  source: 'shelf price, shop visit',
  method: 'manual_visit',
  verification: 'verified',
  checkedAt: new Date(NOW - 3600_000).toISOString(),
  ...extra,
});

test('an offer is validated like the app and the database do', () => {
  const o = parseOffer(ok({ oldPrice: 7000, url: 'https://shop.example/p/1', urlKind: 'product' }), NOW);
  assert.equal(o.price, 5600);
  assert.equal(o.city, 'Астана');
  assert.equal(o.urlKind, 'product');
  const bad = {
    'no source': { source: '  ' },
    'an unknown method': { method: 'scrape' },
    'a zero price': { price: 0 },
    'a fractional price': { price: 10.5 },
    'an old price below the price': { oldPrice: 5000 },
    'a link without its kind': { url: 'https://shop.example/p/1' },
    'a kind without a link': { urlKind: 'product' },
    'a link that is not http(s)': { url: 'javascript:alert(1)', urlKind: 'product' },
    'a check time in the future': { checkedAt: new Date(NOW + 86400_000).toISOString() },
    'a verified offer that says nothing': { price: null, availability: 'unknown' },
    'an unknown field': { sneaky: 1 },
    'an unknown availability': { availability: 'maybe' },
  };
  for (const [name, extra] of Object.entries(bad)) {
    assert.throws(() => parseOffer(ok(extra), NOW), { code: 'bad_request' }, name);
  }
  // a link-only offer is fine when the link opens the product
  parseOffer(ok({ price: null, availability: 'unknown', url: 'https://shop.example/p/1', urlKind: 'product' }), NOW);
  // not verified: it may say nothing yet
  parseOffer(ok({ price: null, availability: 'unknown', verification: 'unverified' }), NOW);
});

test('shop offers: manual entry in the admin panel', { skip: SKIP }, async (t) => {
  const db = await createTestDb();
  await createAdmin(db.pool);
  const app = await boot({ pool: db.pool });
  t.after(async () => {
    await app.close();
    await db.drop();
  });
  const put = (json, headers) => app.call('/admin/api/offers', { method: 'PUT', json, headers });
  const publicOffers = async (id) => (await app.call(`/v1/products/${id}/offers`)).data.items;
  const hdr = await adminLogin(app);

  await t.test('every offer call needs a sign-in', async () => {
    assert.equal((await app.call('/admin/api/offers')).status, 401);
    assert.equal((await app.call('/admin/api/stores')).status, 401);
    assert.equal((await put(ok(), { 'x-requested-with': 'cosmetix-admin' })).status, 401);
    const gone = await app.call('/admin/api/offers/1', {
      method: 'DELETE',
      headers: { 'x-requested-with': 'cosmetix-admin' },
    });
    assert.equal(gone.status, 401);
    // and a signed-in change needs the CSRF header
    assert.equal((await put(ok(), { cookie: hdr.cookie })).status, 403);
  });

  await t.test('without a verified offer the app gets no price at all', async () => {
    // the seed's demo rows in `prices` are not offers
    assert.deepEqual(await publicOffers(1), []);
  });

  await t.test('a verified offer is saved, logged and shown to the app', async () => {
    const r = await put(ok({ oldPrice: 7000, url: 'https://shop.example/p/1', urlKind: 'product' }), hdr);
    assert.equal(r.status, 200, JSON.stringify(r.data));
    assert.equal(r.data.price, 5600);
    assert.equal(r.data.checkedBy, 'tester');
    const items = await publicOffers(1);
    assert.equal(items.length, 1);
    assert.equal(items[0].url, 'https://shop.example/p/1');
    assert.equal(items[0].urlKind, 'product');
    assert.equal(items[0].method, 'manual_visit');
    assert.ok(items[0].checkedAt);
    assert.ok(items[0].source);
    const audit = (await app.call('/admin/api/audit', { headers: hdr })).data.items;
    assert.ok(audit.some((a) => a.changes.offer && a.productId === 1));
  });

  await t.test('a second entry for the same shop replaces the first', async () => {
    const r = await put(ok({ price: 5300 }), hdr);
    assert.equal(r.status, 200);
    const items = await publicOffers(1);
    assert.equal(items.length, 1);
    assert.equal(items[0].price, 5300);
    assert.equal(items[0].url, null);
  });

  await t.test('unverified and disputed offers are kept but never shown to the app', async () => {
    await put(ok({ storeId: 2, verification: 'unverified' }), hdr);
    await put(ok({ storeId: 3, verification: 'disputed' }), hdr);
    assert.equal((await publicOffers(1)).length, 1);
    const all = (await app.call('/admin/api/offers?productId=1', { headers: hdr })).data.items;
    assert.equal(all.length, 3);
  });

  await t.test('bad input is refused with a clear 400', async () => {
    for (const extra of [{ price: 0 }, { source: '' }, { method: 'scrape' }, { url: 'https://x.example' }]) {
      const r = await put(ok({ storeId: 4, ...extra }), hdr);
      assert.equal(r.status, 400, JSON.stringify(extra));
    }
    assert.equal((await put(ok({ storeId: 4, checkedAt: '2999-01-01T00:00:00Z' }), hdr)).status, 400);
  });

  await t.test('an unknown product or shop is a 404, not a server error', async () => {
    assert.equal((await put(ok({ productId: 999999 }), hdr)).status, 404);
    assert.equal((await put(ok({ storeId: 999999 }), hdr)).status, 404);
  });

  await t.test('the shops for the entry form', async () => {
    const s = (await app.call('/admin/api/stores', { headers: hdr })).data.items;
    assert.ok(s.length > 0);
    assert.ok(s[0].name);
  });

  await t.test('withdrawing an offer is logged', async () => {
    const id = (await publicOffers(1))[0].id;
    const r = await app.call(`/admin/api/offers/${id}`, { method: 'DELETE', headers: hdr });
    assert.equal(r.status, 200);
    assert.deepEqual(await publicOffers(1), []);
    const again = await app.call(`/admin/api/offers/${id}`, { method: 'DELETE', headers: hdr });
    assert.equal(again.status, 404);
    const audit = (await app.call('/admin/api/audit', { headers: hdr })).data.items;
    assert.ok(audit.some((a) => a.changes.offerDeleted));
  });

  await t.test('the public snapshot has only verified offers, matched by names', async () => {
    await put(ok({ productId: 2, storeId: 1, price: 4100, oldPrice: 5000, verification: 'verified' }), hdr);
    await put(ok({ productId: 3, storeId: 2, verification: 'unverified' }), hdr);
    const snap = await app.call('/v1/catalog/offers');
    assert.equal(snap.status, 200);
    assert.ok(snap.data.generatedAt);
    const items = snap.data.items;
    assert.ok(items.every((i) => i.verification === 'verified'));
    assert.ok(items.every((i) => i.brand && i.productName && i.storeName && i.storeAddress));
    assert.ok(items.some((i) => i.productId === 2 && i.price === 4100 && i.oldPrice === 5000));
    assert.ok(!items.some((i) => i.productId === 3));
    // a withdrawn offer leaves the snapshot
    const id = items.find((i) => i.productId === 2).id;
    await app.call(`/admin/api/offers/${id}`, { method: 'DELETE', headers: hdr });
    const after = (await app.call('/v1/catalog/offers')).data.items;
    assert.ok(!after.some((i) => i.id === id));
  });

  await t.test('the database itself refuses what validation refuses', async () => {
    const insert = (cols) => {
      const base = { product_id: 1, store_id: 5, source: 's', method: 'manual_visit', checked_at: new Date() };
      const row = { ...base, ...cols };
      const keys = Object.keys(row);
      return db.pool.query(
        `INSERT INTO store_offers (${keys.join(',')}) VALUES (${keys.map((_, i) => `$${i + 1}`).join(',')})`,
        Object.values(row),
      );
    };
    await assert.rejects(insert({ price: 0 }), { code: '23514' });
    await assert.rejects(insert({ method: 'scrape' }), { code: '23514' });
    await assert.rejects(insert({ availability: 'maybe' }), { code: '23514' });
    await assert.rejects(insert({ source: '  ' }), { code: '23514' });
    await assert.rejects(insert({ url: 'ftp://x', url_kind: 'product' }), { code: '23514' });
    await assert.rejects(insert({ url_kind: 'product' }), { code: '23514' });
    await assert.rejects(insert({ verification: 'verified' }), { code: '23514' });
    await assert.rejects(insert({ price: 100, old_price: 90 }), { code: '23514' });
  });
});
