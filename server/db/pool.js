'use strict';

const { Pool } = require('pg');

/** One connection pool from DATABASE_URL (postgres://user:pass@host:port/db). */
function createPool(env = process.env) {
  const url = (env.DATABASE_URL || '').trim();
  if (!url) return null;
  return new Pool({
    connectionString: url,
    max: Number.parseInt(env.PG_POOL_MAX || '10', 10),
    ssl: env.PG_SSL === '1' ? { rejectUnauthorized: true } : undefined,
  });
}

module.exports = { createPool };
