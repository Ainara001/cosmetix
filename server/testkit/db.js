'use strict';

const crypto = require('node:crypto');
const { Pool } = require('pg');

const { createApp } = require('../app');
const { migrate } = require('../db/migrate');
const { seedCatalog } = require('../db/seed');
const { hashPassword } = require('../auth');

/**
 * Tests that need PostgreSQL run only when TEST_DATABASE_URL points at a
 * database that may be written to. Each test file works in its own random
 * schema and drops it at the end, so nothing else in that database is touched.
 */
const TEST_URL = (process.env.TEST_DATABASE_URL || '').trim();
const SKIP = TEST_URL
  ? false
  : 'TEST_DATABASE_URL is not set: PostgreSQL tests skipped (see server/README.md)';

async function createTestDb({ seed = true } = {}) {
  const schema = `t_${crypto.randomBytes(6).toString('hex')}`;
  const admin = new Pool({ connectionString: TEST_URL, max: 1 });
  await admin.query(`CREATE SCHEMA ${schema}`);
  const pool = new Pool({
    connectionString: TEST_URL,
    max: 4,
    options: `-c search_path=${schema}`,
  });
  await migrate(pool);
  if (seed) await seedCatalog(pool);
  return {
    pool,
    async drop() {
      await pool.end();
      await admin.query(`DROP SCHEMA ${schema} CASCADE`);
      await admin.end();
    },
  };
}

/** The app on a random port, with `call(path, {method, json, headers})`. */
async function boot({ pool, env = {}, now } = {}) {
  const { server, api } = createApp({ env, db: pool, now });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${server.address().port}`;
  async function call(path, { method = 'GET', json, headers = {}, body } = {}) {
    const res = await fetch(base + path, {
      method,
      redirect: 'manual',
      headers: { ...(json !== undefined ? { 'content-type': 'application/json' } : {}), ...headers },
      body: json !== undefined ? JSON.stringify(json) : body,
    });
    const text = await res.text();
    let data = null;
    try {
      data = text ? JSON.parse(text) : null;
    } catch {
      // not JSON (static files)
    }
    return { status: res.status, data, text, headers: res.headers };
  }
  return { call, api, close: () => new Promise((r) => server.close(r)) };
}

/** Registers a device and returns { userId, auth } for later calls. */
async function newDevice(app) {
  const r = await app.call('/v1/devices', { method: 'POST' });
  return { userId: r.data.userId, token: r.data.token, auth: { authorization: `Bearer ${r.data.token}` } };
}

const ADMIN_USER = 'tester';
const ADMIN_PASSWORD = 'correct horse battery';

async function createAdmin(pool, username = ADMIN_USER, password = ADMIN_PASSWORD) {
  await pool.query('INSERT INTO admins (username, password_hash) VALUES ($1, $2)', [
    username,
    hashPassword(password),
  ]);
}

/** Signs in and returns the headers an admin request needs (cookie + CSRF header). */
async function adminLogin(app, username = ADMIN_USER, password = ADMIN_PASSWORD) {
  const r = await app.call('/admin/api/login', { method: 'POST', json: { username, password } });
  if (r.status !== 200) throw new Error(`admin login failed: ${r.status}`);
  const cookie = r.headers.get('set-cookie').split(';')[0];
  return { cookie, 'x-requested-with': 'cosmetix-admin' };
}

module.exports = {
  SKIP,
  createTestDb,
  boot,
  newDevice,
  createAdmin,
  adminLogin,
  ADMIN_USER,
  ADMIN_PASSWORD,
};
