'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { SKIP, createTestDb, boot, newDevice } = require('../testkit/db');

test('device, profile, reactions, events', { skip: SKIP }, async (t) => {
  const db = await createTestDb();
  const fixedNow = Date.parse('2026-06-15T10:00:00Z');
  const app = await boot({ pool: db.pool, now: () => fixedNow });
  t.after(async () => {
    await app.close();
    await db.drop();
  });
  const put = (path, auth, json) => app.call(path, { method: 'PUT', headers: auth, json });

  await t.test('a device gets an id and a token; only the token hash is stored', async () => {
    const d = await newDevice(app);
    assert.match(d.userId, /^[0-9a-f-]{36}$/);
    assert.ok(d.token.length >= 40);
    const row = (await db.pool.query('SELECT token_hash FROM app_users WHERE id = $1', [d.userId])).rows[0];
    assert.notEqual(row.token_hash, d.token);
    assert.equal(row.token_hash.length, 64);
  });

  await t.test('profile needs a valid token', async () => {
    assert.equal((await app.call('/v1/profile')).status, 401);
    assert.equal((await app.call('/v1/profile', { headers: { authorization: 'Bearer nonsense' } })).status, 401);
    const unknown = 'Bearer ' + 'a'.repeat(43);
    assert.equal((await app.call('/v1/profile', { headers: { authorization: unknown } })).status, 401);
  });

  await t.test('profile: partial update, only the year of birth is kept', async () => {
    const d = await newDevice(app);
    const first = await app.call('/v1/profile', { headers: d.auth });
    assert.equal(first.status, 200);
    assert.equal(first.data.birthYear, null);
    assert.deepEqual(first.data.skinConcerns, []);

    const r = await put('/v1/profile', d.auth, {
      birthYear: 2001,
      skinType: 'Сухая',
      skinConcerns: ['Сухость и шелушение', 'Пигментация'],
    });
    assert.equal(r.status, 200);
    assert.equal(r.data.birthYear, 2001);
    assert.equal(r.data.skinType, 'Сухая');

    // an absent field stays, null clears
    const r2 = await put('/v1/profile', d.auth, { city: 'Астана', skinType: null });
    assert.equal(r2.data.birthYear, 2001);
    assert.equal(r2.data.skinType, null);
    assert.equal(r2.data.city, 'Астана');
    assert.deepEqual(r2.data.skinConcerns, ['Сухость и шелушение', 'Пигментация']);

    // there is no column for a full date of birth
    const cols = (
      await db.pool.query(
        `SELECT column_name FROM information_schema.columns
          WHERE table_schema = current_schema() AND table_name = 'app_users'`,
      )
    ).rows.map((c) => c.column_name);
    assert.ok(!cols.some((c) => /birth/.test(c) && c !== 'birth_year'));
    assert.ok(!cols.some((c) => /mail|password|phone|name$/.test(c)));
  });

  await t.test('birth year is validated against the server clock', async () => {
    const d = await newDevice(app);
    for (const bad of [1899, 2027, '2001', 2001.5, true, {}]) {
      const r = await put('/v1/profile', d.auth, { birthYear: bad });
      assert.equal(r.status, 400, JSON.stringify(bad));
    }
    assert.equal((await put('/v1/profile', d.auth, { birthYear: 2026 })).status, 200, 'this year is allowed');
    assert.equal((await put('/v1/profile', d.auth, { birthYear: null })).data.birthYear, null);
  });

  await t.test('profile: other validation', async () => {
    const d = await newDevice(app);
    assert.equal((await put('/v1/profile', d.auth, {})).status, 400, 'nothing to update');
    assert.equal((await put('/v1/profile', d.auth, { city: 5 })).status, 400);
    assert.equal((await put('/v1/profile', d.auth, { city: 'x'.repeat(81) })).status, 400);
    assert.equal((await put('/v1/profile', d.auth, { skinConcerns: 'dry' })).status, 400);
    assert.equal((await put('/v1/profile', d.auth, { skinConcerns: ['', 'a'] })).status, 400);
    const r = await app.call('/v1/profile', { method: 'PUT', headers: d.auth, body: '{bad json' });
    assert.equal(r.status, 400);
  });

  await t.test('users cannot see each other', async () => {
    const a = await newDevice(app);
    const b = await newDevice(app);
    await put('/v1/profile', a.auth, { birthYear: 1990 });
    assert.equal((await app.call('/v1/profile', { headers: b.auth })).data.birthYear, null);
    await put('/v1/reactions/r1', a.auth, { title: 'Покраснение', severity: 3, date: '2026-06-01' });
    assert.equal((await app.call('/v1/reactions', { headers: b.auth })).data.items.length, 0);
    // b "deleting" a's entry does nothing
    await app.call('/v1/reactions/r1', { method: 'DELETE', headers: b.auth });
    assert.equal((await app.call('/v1/reactions', { headers: a.auth })).data.items.length, 1);
  });

  await t.test('reactions: idempotent upsert, list, delete', async () => {
    const d = await newDevice(app);
    const body = { productId: 1, title: 'Покраснение', severity: 3, date: '2026-06-01', notes: 'после крема' };
    const r1 = await put('/v1/reactions/local-7', d.auth, body);
    assert.equal(r1.status, 200);
    assert.equal(r1.data.date, '2026-06-01');
    const r2 = await put('/v1/reactions/local-7', d.auth, { ...body, severity: 4 });
    assert.equal(r2.data.severity, 4);
    const list = await app.call('/v1/reactions', { headers: d.auth });
    assert.equal(list.data.items.length, 1, 'same clientId = same entry');
    assert.equal(list.data.items[0].productId, 1);
    assert.equal(list.data.items[0].notes, 'после крема');
    assert.equal((await app.call('/v1/reactions/local-7', { method: 'DELETE', headers: d.auth })).status, 204);
    assert.equal((await app.call('/v1/reactions', { headers: d.auth })).data.items.length, 0);
  });

  await t.test('reactions: validation', async () => {
    const d = await newDevice(app);
    const ok = { title: 'Зуд', severity: 2, date: '2026-06-01' };
    const cases = [
      [{ ...ok, severity: 0 }, 'severity 0'],
      [{ ...ok, severity: 6 }, 'severity 6'],
      [{ ...ok, severity: '3' }, 'severity string'],
      [{ ...ok, title: '  ' }, 'empty title'],
      [{ ...ok, date: '2026-02-30' }, 'impossible date'],
      [{ ...ok, date: '01.06.2026' }, 'date format'],
      [{ ...ok, date: '2026-12-31' }, 'future date'],
      [{ ...ok, productId: 99999 }, 'unknown product'],
      [{ ...ok, productId: '1' }, 'product id as text'],
      [{ ...ok, notes: 'x'.repeat(2001) }, 'long notes'],
    ];
    for (const [body, name] of cases) {
      const r = await put('/v1/reactions/x1', d.auth, body);
      assert.equal(r.status, 400, name);
    }
    assert.equal((await put('/v1/reactions/bad id!', d.auth, ok)).status, 400, 'client id');
    assert.equal((await put('/v1/reactions/ok-id', d.auth, { ...ok, productId: null })).status, 200);
  });

  await t.test('events: batch insert, then they show up with the right user', async () => {
    const d = await newDevice(app);
    const r = await app.call('/v1/events', {
      method: 'POST',
      headers: d.auth,
      json: {
        events: [
          { type: 'app_open' },
          { type: 'product_view', props: { productId: 5 }, clientTime: '2026-06-15T09:59:00Z' },
        ],
      },
    });
    assert.equal(r.status, 201);
    assert.equal(r.data.accepted, 2);
    const rows = (
      await db.pool.query('SELECT type, props, client_time FROM activity_events WHERE user_id = $1 ORDER BY id', [
        d.userId,
      ])
    ).rows;
    assert.deepEqual(rows.map((x) => x.type), ['app_open', 'product_view']);
    assert.deepEqual(rows[1].props, { productId: 5 });
    assert.equal(rows[1].client_time.toISOString(), '2026-06-15T09:59:00.000Z');
    assert.equal(rows[0].client_time, null);
  });

  await t.test('events: validation and limits', async () => {
    const d = await newDevice(app);
    const post = (json) => app.call('/v1/events', { method: 'POST', headers: d.auth, json });
    assert.equal((await post({ events: [] })).status, 400);
    assert.equal((await post({})).status, 400);
    assert.equal((await post({ events: [{ type: 'Bad Type' }] })).status, 400);
    assert.equal((await post({ events: [{ type: 'a'.repeat(41) }] })).status, 400);
    assert.equal((await post({ events: [{ type: 'x', props: [1] }] })).status, 400);
    assert.equal((await post({ events: [{ type: 'x', clientTime: 'soon' }] })).status, 400);
    assert.equal((await post({ events: [{ type: 'x', props: { t: 'y'.repeat(2100) } }] })).status, 413);
    const many = Array.from({ length: 51 }, () => ({ type: 'tap' }));
    assert.equal((await post({ events: many })).status, 413);
    // one bad event rejects the whole batch: nothing half-saved
    assert.equal((await post({ events: [{ type: 'ok_one' }, { type: 'NO' }] })).status, 400);
    const n = (await db.pool.query('SELECT count(*)::int AS n FROM activity_events WHERE user_id = $1', [d.userId]))
      .rows[0].n;
    assert.equal(n, 0);
    // a silly device clock is dropped, not stored
    await post({ events: [{ type: 'x', clientTime: '1990-01-01T00:00:00Z' }] });
    const row = (await db.pool.query('SELECT client_time FROM activity_events WHERE user_id = $1', [d.userId])).rows[0];
    assert.equal(row.client_time, null);
  });

  await t.test('events need a token', async () => {
    assert.equal((await app.call('/v1/events', { method: 'POST', json: { events: [{ type: 'app_open' }] } })).status, 401);
  });

  await t.test('DELETE /v1/profile removes the user with all their data', async () => {
    const d = await newDevice(app);
    await put('/v1/profile', d.auth, { birthYear: 1999 });
    await put('/v1/reactions/z1', d.auth, { title: 'Сыпь', severity: 2, date: '2026-06-01' });
    await app.call('/v1/events', { method: 'POST', headers: d.auth, json: { events: [{ type: 'app_open' }] } });
    assert.equal((await app.call('/v1/profile', { method: 'DELETE', headers: d.auth })).status, 204);
    for (const table of ['app_users', 'reactions', 'activity_events']) {
      const col = table === 'app_users' ? 'id' : 'user_id';
      const n = (await db.pool.query(`SELECT count(*)::int AS n FROM ${table} WHERE ${col} = $1`, [d.userId])).rows[0].n;
      assert.equal(n, 0, table);
    }
    assert.equal((await app.call('/v1/profile', { headers: d.auth })).status, 401);
  });
});

test('device registration is rate limited per address', { skip: SKIP }, async (t) => {
  const db = await createTestDb({ seed: false });
  const app = await boot({ pool: db.pool });
  t.after(async () => {
    await app.close();
    await db.drop();
  });
  for (let i = 0; i < 20; i += 1) {
    assert.equal((await app.call('/v1/devices', { method: 'POST' })).status, 201);
  }
  const r = await app.call('/v1/devices', { method: 'POST' });
  assert.equal(r.status, 429);
  assert.equal(r.data.error, 'rate_limited');
  assert.ok(Number(r.headers.get('retry-after')) > 0);
});
