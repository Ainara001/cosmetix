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
  return new Pool({
    connectionString: url,
    max: Number.parseInt(env.PG_POOL_MAX || '10', 10),
    ssl: env.PG_SSL === '1' ? { rejectUnauthorized: true } : undefined,
  });
}

module.exports = { createPool };
