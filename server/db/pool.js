'use strict';

/**
 * One connection pool from DATABASE_URL (postgres://user:pass@host:port/db).
 * Returns null when DATABASE_URL is not set. The `pg` package is loaded only
 * here, only when a database is configured: the AI proxy alone still starts
 * without `npm install`.
 */
function createPool(env = process.env) {
  const url = (env.DATABASE_URL || '').trim();
  if (!url) return null;
  let Pool;
  try {
    ({ Pool } = require('pg'));
  } catch (e) {
    if (e && e.code === 'MODULE_NOT_FOUND') {
      throw new Error('DATABASE_URL is set but the "pg" package is missing: run `npm install` in server/');
    }
    throw e;
  }
  const pool = new Pool({
    connectionString: url,
    max: Number.parseInt(env.PG_POOL_MAX || '10', 10),
    ssl: env.PG_SSL === '1' ? { rejectUnauthorized: true } : undefined,
    // a dead database must answer with an error, not hang the request
    connectionTimeoutMillis: Number.parseInt(env.PG_CONNECT_TIMEOUT_MS || '5000', 10),
    statement_timeout: Number.parseInt(env.PG_STATEMENT_TIMEOUT_MS || '10000', 10),
    idleTimeoutMillis: 30000,
  });
  // Without this handler an error on an idle connection (the database was
  // restarted, the network dropped) is an unhandled 'error' event and stops the
  // whole process, the AI proxy with it. Only the code is logged: the message may
  // name the host.
  pool.on('error', (e) => console.error('database pool error:', (e && (e.code || e.name)) || 'unknown'));
  return pool;
}

module.exports = { createPool };
