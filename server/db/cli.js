'use strict';

// node db/cli.js migrate | seed | create-admin <username>
require('../env').loadEnv();

const { createPool } = require('./pool');
const { migrate } = require('./migrate');
const { seedCatalog } = require('./seed');
const { hashPassword } = require('../auth');

async function readPassword() {
  if (process.env.ADMIN_PASSWORD) return process.env.ADMIN_PASSWORD;
  if (!process.stdin.isTTY) {
    throw new Error('Set ADMIN_PASSWORD or run in a terminal to type the password');
  }
  const readline = require('node:readline');
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  // do not echo the password
  rl._writeToOutput = (s) => {
    if (s.includes('Password')) process.stdout.write(s);
  };
  const pw = await new Promise((resolve) => rl.question('Password (min 12 characters): ', resolve));
  rl.close();
  process.stdout.write('\n');
  return pw;
}

async function main() {
  const [cmd, arg] = process.argv.slice(2);
  const pool = createPool();
  if (!pool) {
    console.error('DATABASE_URL is not set (see server/.env.example)');
    process.exit(1);
  }
  try {
    if (cmd === 'migrate') {
      const applied = await migrate(pool, { log: console.log });
      console.log(applied.length ? `done: ${applied.length} applied` : 'already up to date');
    } else if (cmd === 'seed') {
      const done = await seedCatalog(pool);
      console.log(
        done
          ? 'catalog loaded from seed/catalog.json'
          : 'the catalog already has products: nothing changed',
      );
    } else if (cmd === 'create-admin') {
      if (!arg) throw new Error('Usage: node db/cli.js create-admin <username>');
      const password = await readPassword();
      const hash = hashPassword(password);
      await pool.query(
        `INSERT INTO admins (username, password_hash) VALUES ($1, $2)
         ON CONFLICT (username) DO UPDATE SET password_hash = EXCLUDED.password_hash`,
        [arg, hash],
      );
      // an old session must not outlive a password change
      await pool.query(
        'DELETE FROM admin_sessions WHERE admin_id = (SELECT id FROM admins WHERE username = $1)',
        [arg],
      );
      console.log(`admin "${arg}" saved`);
    } else {
      console.error('Usage: node db/cli.js migrate | seed | create-admin <username>');
      process.exit(1);
    }
  } finally {
    await pool.end();
  }
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
