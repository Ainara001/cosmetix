'use strict';

const fs = require('node:fs');
const path = require('node:path');

const DIR = path.join(__dirname, '..', 'migrations');

/**
 * Applies migrations/NNN_name.sql files that were not applied yet, each in its
 * own transaction. Applied files are remembered in schema_migrations, so the
 * command is safe to run on every start.
 */
async function migrate(pool, { log = () => {} } = {}) {
  await pool.query(
    `CREATE TABLE IF NOT EXISTS schema_migrations (
       name TEXT PRIMARY KEY,
       applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
     )`,
  );
  const done = new Set(
    (await pool.query('SELECT name FROM schema_migrations')).rows.map((r) => r.name),
  );
  const files = fs
    .readdirSync(DIR)
    .filter((f) => /^\d+_.+\.sql$/.test(f))
    .sort();
  const applied = [];
  for (const file of files) {
    if (done.has(file)) continue;
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(fs.readFileSync(path.join(DIR, file), 'utf8'));
      await client.query('INSERT INTO schema_migrations (name) VALUES ($1)', [file]);
      await client.query('COMMIT');
      applied.push(file);
      log(`applied ${file}`);
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }
  }
  return applied;
}

module.exports = { migrate };
