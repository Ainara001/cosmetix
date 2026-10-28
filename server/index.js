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
// 0.0.0.0 lets a real iPhone on the same Wi-Fi reach the proxy; use
// HOST=127.0.0.1 when only the iOS Simulator on this Mac needs it
const host = process.env.HOST || '0.0.0.0';
server.listen(port, host, () => {
  console.log(
    `Cosmetix AI proxy on ${host}:${port} — ${
      mock
        ? 'MOCK mode (no GEMINI_API_KEY / ANTHROPIC_API_KEY)'
        : `${config.provider} model ${config.model}`
    }`,
  );
});
