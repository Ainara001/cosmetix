'use strict';

const fs = require('node:fs');
const path = require('node:path');

// Tiny .env loader (no dependencies); real environment variables win.
const envFile = path.join(__dirname, '.env');
if (fs.existsSync(envFile)) {
  for (const line of fs.readFileSync(envFile, 'utf8').split(/\r?\n/)) {
    const m = /^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/.exec(line);
    if (m && !line.trim().startsWith('#') && process.env[m[1]] === undefined) {
      process.env[m[1]] = m[2].replace(/^["']|["']$/g, '');
    }
  }
}

const { createApp } = require('./app');

const { server, config, mock } = createApp();
const port = Number.parseInt(process.env.PORT || '8787', 10);
server.listen(port, '0.0.0.0', () => {
  console.log(
    `Cosmetix AI proxy on :${port} — ${
      mock ? 'MOCK mode (no ANTHROPIC_API_KEY)' : `Claude model ${config.model}`
    }`,
  );
});
