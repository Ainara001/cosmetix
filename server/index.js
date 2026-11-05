'use strict';

require('./env').loadEnv();

const { createApp } = require('./app');
const { createPool } = require('./db/pool');
const { migrate } = require('./db/migrate');

async function main() {
  // DATABASE_URL turns on the catalog / profile API and the admin panel
  const db = createPool();
  if (db && process.env.AUTO_MIGRATE !== '0') {
    const applied = await migrate(db, { log: (m) => console.log(`database: ${m}`) });
    if (applied.length === 0) console.log('database: schema is up to date');
  }

  const { server, config, mock } = createApp({ db });
  if (!mock && config.photoAnalysis && config.provider === 'gemini' && config.dataUse !== 'paid') {
    console.warn(
      'WARNING: photo analysis is ON but GEMINI_BILLING is not "paid". On the free Gemini quota Google may use and ' +
        'review what is sent and personal data must not be sent (https://ai.google.dev/gemini-api/terms).',
    );
  }
  const port = Number.parseInt(process.env.PORT || '8787', 10);
  // 0.0.0.0 lets a real iPhone on the same Wi-Fi reach the proxy; use
  // HOST=127.0.0.1 when only the iOS Simulator on this Mac needs it
  const host = process.env.HOST || '0.0.0.0';
  server.listen(port, host, () => {
    console.log(
      `Cosmetix server on ${host}:${port} — AI: ${
        mock
          ? 'MOCK mode (no GEMINI_API_KEY / ANTHROPIC_API_KEY)'
          : `${config.provider} model ${config.model}`
      } — database: ${db ? 'PostgreSQL' : 'not configured (catalog API and admin are off)'}`,
    );
  });
}

main().catch((e) => {
  console.error('startup failed:', e.message);
  process.exit(1);
});
