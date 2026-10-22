'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { createApp, validateChatBody, toAnthropicBody, readConfig, MOCK_PREFIX } = require('../app');

async function start(env, fetchImpl, now) {
  const { server, ...rest } = createApp({ env, fetchImpl, now });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${server.address().port}`;
  const call = (path, init = {}) =>
    fetch(base + path, {
      ...init,
      headers: { 'content-type': 'application/json', ...(init.headers || {}) },
    });
  const chat = (body, headers) =>
    call('/v1/chat', { method: 'POST', body: JSON.stringify(body), headers });
  return { call, chat, close: () => new Promise((r) => server.close(r)), ...rest };
}

const ask = (text = 'Привет') => ({ messages: [{ role: 'user', content: text }] });

function claudeReply(text = 'Здравствуйте!', usage = { input_tokens: 10, output_tokens: 5 }) {
  return async () => ({
    ok: true,
    status: 200,
    headers: new Headers(),
    json: async () => ({ content: [{ type: 'text', text }], usage }),
  });
}

test('health reports mock mode without a key', async () => {
  const s = await start({}, claudeReply());
  const r = await (await s.call('/health')).json();
  assert.deepEqual(r, { ok: true, mode: 'mock', model: null });
  await s.close();
});

test('mock mode answers are clearly marked and never call Anthropic', async () => {
  let called = false;
  const s = await start({}, async () => {
    called = true;
  });
  const res = await s.chat(ask('Подойдёт ли мне крем?'));
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.mock, true);
  assert.ok(body.text.startsWith(MOCK_PREFIX));
  assert.equal(called, false);
  await s.close();
});

test('mock mode refuses structured (JSON) requests instead of inventing data', async () => {
  const s = await start({}, claudeReply());
  const res = await s.chat({ ...ask(), json: true });
  assert.equal(res.status, 503);
  assert.equal((await res.json()).error, 'mock_no_structured');
  await s.close();
});

test('with a key the request goes to Claude with the right headers and model', async () => {
  let seen;
  const s = await start({ ANTHROPIC_API_KEY: 'sk-test', CLAUDE_MODEL: 'claude-haiku-5-5' }, async (url, init) => {
    seen = { url, init, body: JSON.parse(init.body) };
    return claudeReply('Ответ')();
  });
  const res = await s.chat({ system: 'Ты помощник', ...ask('Вопрос') });
  const body = await res.json();
  assert.equal(body.text, 'Ответ');
  assert.equal(body.mock, false);
  assert.equal(seen.url, 'https://api.anthropic.com/v1/messages');
  assert.equal(seen.init.headers['x-api-key'], 'sk-test');
  assert.equal(seen.init.headers['anthropic-version'], '2023-06-01');
  assert.equal(seen.body.model, 'claude-haiku-5-5');
  assert.equal(seen.body.system, 'Ты помощник');
  assert.deepEqual(seen.body.messages, [{ role: 'user', content: 'Вопрос' }]);
  await s.close();
});

test('the API key is never returned to the client', async () => {
  const s = await start({ ANTHROPIC_API_KEY: 'sk-secret-123' }, claudeReply());
  const raw = await (await s.chat(ask())).text();
  const health = await (await s.call('/health')).text();
  assert.ok(!raw.includes('sk-secret-123'));
  assert.ok(!health.includes('sk-secret-123'));
  await s.close();
});

test('output tokens are capped by the server limit', () => {
  const config = readConfig({ MAX_OUTPUT_TOKENS: '300' });
  const clean = validateChatBody({ ...ask(), maxTokens: 99999 }, config);
  assert.equal(clean.maxTokens, 300);
  assert.equal(validateChatBody({ ...ask(), maxTokens: 100 }, config).maxTokens, 100);
});

test('JSON mode adds an instruction and images become image blocks', () => {
  const config = readConfig({ ANTHROPIC_API_KEY: 'k' });
  const clean = validateChatBody(
    { system: 'S', json: true, messages: [{ role: 'user', content: 'look', images: ['/9j/AAAA'] }] },
    config,
  );
  const body = toAnthropicBody(clean, config);
  assert.match(body.system, /JSON object only/);
  assert.equal(body.messages[0].content[0].type, 'image');
  assert.equal(body.messages[0].content[0].source.media_type, 'image/jpeg');
  assert.equal(body.messages[0].content[1].text, 'look');
});

test('validation: bad shapes, long text, wrong images are rejected', async () => {
  const s = await start({}, claudeReply());
  const bad = [
    [{}, 400],
    [{ messages: [] }, 400],
    [{ messages: [{ role: 'system', content: 'x' }] }, 400],
    [{ messages: [{ role: 'user', content: '' }] }, 400],
    [{ messages: [{ role: 'assistant', content: 'last is assistant' }] }, 400],
    [ask('x'.repeat(6001)), 413],
    [{ messages: [{ role: 'user', content: 'a', images: ['not-an-image'] }] }, 415],
    [{ messages: [{ role: 'user', content: 'a', images: ['/9j/A', '/9j/B', '/9j/C'] }] }, 413],
    [{ messages: Array.from({ length: 21 }, () => ({ role: 'user', content: 'a' })) }, 413],
  ];
  for (const [body, status] of bad) {
    const res = await s.chat(body);
    assert.equal(res.status, status, JSON.stringify(body).slice(0, 80));
  }
  const res = await s.call('/v1/chat', { method: 'POST', body: '{not json' });
  assert.equal(res.status, 400);
  await s.close();
});

test('total prompt length is limited', async () => {
  const s = await start({}, claudeReply());
  const long = 'y'.repeat(5000);
  const res = await s.chat({
    system: 'z'.repeat(5000),
    messages: [
      { role: 'user', content: long },
      { role: 'assistant', content: long },
      { role: 'user', content: long },
      { role: 'assistant', content: long },
      { role: 'user', content: long },
    ],
  });
  assert.equal(res.status, 413);
  await s.close();
});

test('rate limit per client returns 429 with Retry-After, then recovers', async () => {
  let t = 1_000_000;
  const s = await start({ RATE_LIMIT_PER_MIN: '3' }, claudeReply(), () => t);
  for (let i = 0; i < 3; i++) assert.equal((await s.chat(ask())).status, 200);
  const limited = await s.chat(ask());
  assert.equal(limited.status, 429);
  assert.equal((await limited.json()).error, 'rate_limited');
  assert.ok(Number(limited.headers.get('retry-after')) >= 1);
  t += 61_000;
  assert.equal((await s.chat(ask())).status, 200);
  await s.close();
});

test('daily token budget stops further requests and resets next day', async () => {
  let t = Date.parse('2026-10-22T10:00:00Z');
  const s = await start(
    { ANTHROPIC_API_KEY: 'k', DAILY_TOKEN_BUDGET: '20' },
    claudeReply('ok', { input_tokens: 15, output_tokens: 10 }),
    () => t,
  );
  assert.equal((await s.chat(ask())).status, 200); // uses 25 >= 20
  const stopped = await s.chat(ask());
  assert.equal(stopped.status, 429);
  assert.equal((await stopped.json()).error, 'budget_exceeded');
  t += 24 * 3600 * 1000;
  assert.equal((await s.chat(ask())).status, 200);
  await s.close();
});

test('app token is required when configured', async () => {
  const s = await start({ APP_TOKEN: 'secret' }, claudeReply());
  assert.equal((await s.chat(ask())).status, 401);
  assert.equal((await s.chat(ask(), { 'x-app-token': 'wrong' })).status, 401);
  assert.equal((await s.chat(ask(), { 'x-app-token': 'secret' })).status, 200);
  await s.close();
});

test('upstream failures map to clean errors', async () => {
  const cases = [
    [{ ok: false, status: 429, headers: new Headers({ 'retry-after': '12' }) }, 429, 'upstream_rate_limited'],
    [{ ok: false, status: 401, headers: new Headers() }, 502, 'upstream_auth'],
    [{ ok: false, status: 529, headers: new Headers() }, 503, 'upstream_unavailable'],
    [{ ok: true, status: 200, headers: new Headers(), json: async () => ({ content: [] }) }, 502, 'upstream_bad_response'],
  ];
  for (const [reply, status, code] of cases) {
    const s = await start({ ANTHROPIC_API_KEY: 'k', RATE_LIMIT_PER_MIN: '100' }, async () => reply);
    const res = await s.chat(ask());
    assert.equal(res.status, status);
    assert.equal((await res.json()).error, code);
    await s.close();
  }
});

test('timeouts and network errors are reported without details', async () => {
  const timeout = await start({ ANTHROPIC_API_KEY: 'k' }, async () => {
    const e = new Error('slow');
    e.name = 'TimeoutError';
    throw e;
  });
  const r1 = await timeout.chat(ask());
  assert.equal(r1.status, 504);
  assert.equal((await r1.json()).error, 'upstream_timeout');
  await timeout.close();

  const down = await start({ ANTHROPIC_API_KEY: 'k' }, async () => {
    throw new TypeError('fetch failed: ECONNREFUSED 1.2.3.4');
  });
  const r2 = await down.chat(ask());
  const body = await r2.text();
  assert.equal(r2.status, 503);
  assert.ok(!body.includes('1.2.3.4'));
  await down.close();
});

test('unknown routes are 404', async () => {
  const s = await start({}, claudeReply());
  assert.equal((await s.call('/nope')).status, 404);
  await s.close();
});
