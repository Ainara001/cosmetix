'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  createApp,
  validateChatBody,
  toAnthropicBody,
  toGeminiBody,
  readConfig,
  MOCK_PREFIX,
} = require('../app');

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
  assert.deepEqual(r, { ok: true, mode: 'mock', model: null, photoAnalysis: false, dataUse: 'none' });
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
    [ask('x'.repeat(9001)), 413],
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

// ---------------------------------------------------------------- Gemini

function geminiReply(text = 'Здравствуйте!', usage = { promptTokenCount: 10, candidatesTokenCount: 5 }) {
  return async () => ({
    ok: true,
    status: 200,
    headers: new Headers(),
    json: async () => ({ candidates: [{ content: { parts: [{ text }] } }], usageMetadata: usage }),
  });
}

const geminiEnv = {
  GEMINI_API_KEY: 'AQ.test-key',
  GEMINI_MODEL: 'gemini-2.5-flash',
  UPSTREAM_RETRY_MS: '0',
};

test('provider: Gemini key alone selects Gemini, Claude wins when both are set unless forced', () => {
  assert.equal(readConfig(geminiEnv).provider, 'gemini');
  assert.equal(readConfig({ ...geminiEnv, ANTHROPIC_API_KEY: 'sk' }).provider, 'claude');
  assert.equal(
    readConfig({ ...geminiEnv, ANTHROPIC_API_KEY: 'sk', AI_PROVIDER: 'gemini' }).provider,
    'gemini',
  );
  assert.equal(readConfig({}).provider, 'claude'); // no key: mock anyway
});

test('health reports the Gemini provider and model', async () => {
  const s = await start(geminiEnv, geminiReply());
  const r = await (await s.call('/health')).json();
  assert.deepEqual(r, { ok: true, mode: 'gemini', model: 'gemini-2.5-flash', photoAnalysis: false, dataUse: 'unknown' });
  await s.close();
});

test('with a Gemini key the request goes to Gemini, the key only in a header', async () => {
  let seen;
  const s = await start(geminiEnv, async (url, init) => {
    seen = { url, init, body: JSON.parse(init.body) };
    return geminiReply('Ответ')();
  });
  const res = await s.chat({ system: 'Ты помощник', ...ask('Вопрос') });
  const body = await res.json();
  assert.equal(body.text, 'Ответ');
  assert.equal(body.mock, false);
  assert.deepEqual(body.usage, { inputTokens: 10, outputTokens: 5 });
  assert.match(seen.url, /generativelanguage\.googleapis\.com\/v1beta\/models\/gemini-2\.5-flash:generateContent$/);
  assert.equal(seen.init.headers['x-goog-api-key'], 'AQ.test-key');
  assert.ok(!seen.url.includes('AQ.test-key'));
  assert.equal(seen.body.systemInstruction.parts[0].text, 'Ты помощник');
  assert.ok(!JSON.stringify(body).includes('AQ.test-key'));
  await s.close();
});

test('toGeminiBody: roles, images, JSON mode and thinking switched off for 2.5 Flash', () => {
  const config = readConfig(geminiEnv);
  const clean = validateChatBody(
    {
      system: 'S',
      json: true,
      temperature: 0.2,
      messages: [
        { role: 'user', content: 'Первый' },
        { role: 'assistant', content: 'Ответ' },
        { role: 'user', content: 'Фото', images: ['/9j/AAAA'] },
      ],
    },
    config,
  );
  const b = toGeminiBody(clean, config);
  assert.deepEqual(
    b.contents.map((c) => c.role),
    ['user', 'model', 'user'],
  );
  assert.deepEqual(b.contents[2].parts[0], { inlineData: { mimeType: 'image/jpeg', data: '/9j/AAAA' } });
  assert.deepEqual(b.contents[2].parts[1], { text: 'Фото' });
  assert.equal(b.generationConfig.responseMimeType, 'application/json');
  assert.equal(b.generationConfig.temperature, 0.2);
  assert.equal(b.generationConfig.maxOutputTokens, config.maxOutputTokens);
  assert.deepEqual(b.generationConfig.thinkingConfig, { thinkingBudget: 0 });
  assert.match(b.systemInstruction.parts[0].text, /ONE valid JSON object/);

  const pro = readConfig({ GEMINI_API_KEY: 'k', GEMINI_MODEL: 'gemini-2.5-pro' });
  assert.equal(toGeminiBody(validateChatBody(ask(), pro), pro).generationConfig.thinkingConfig, undefined);
});

test('Gemini failures map to clean errors', async () => {
  const fail = (status, json = {}) => async () => ({
    ok: false,
    status,
    headers: new Headers(),
    json: async () => json,
  });
  const cases = [
    [fail(429), 429, 'upstream_rate_limited'],
    [fail(403), 502, 'upstream_auth'],
    [fail(400, { error: { message: 'API key not valid. Please pass a valid API key.' } }), 502, 'upstream_auth'],
    [fail(400, { error: { message: 'Bad field' } }), 503, 'upstream_unavailable'],
    [fail(500), 503, 'upstream_unavailable'],
    // blocked by a safety filter: no candidates at all
    [async () => ({ ok: true, status: 200, headers: new Headers(), json: async () => ({ promptFeedback: { blockReason: 'SAFETY' } }) }), 502, 'upstream_bad_response'],
  ];
  for (const [impl, status, code] of cases) {
    const s = await start(geminiEnv, impl);
    const res = await s.chat(ask());
    const body = await res.json();
    assert.equal(res.status, status);
    assert.equal(body.error, code);
    assert.ok(!JSON.stringify(body).includes('AQ.test-key'));
    await s.close();
  }
});

test('Gemini "high demand" (503): retry, then the fallback model, then report', async () => {
  const busy = { ok: false, status: 503, headers: new Headers(), json: async () => ({}) };
  const urls = [];
  const s = await start(geminiEnv, async (url) => {
    urls.push(String(url));
    return urls.length < 3 ? busy : geminiReply('Получилось')();
  });
  const res = await s.chat(ask());
  assert.equal(res.status, 200);
  assert.equal((await res.json()).text, 'Получилось');
  // main model twice, the third try goes to the fallback model
  assert.equal(urls.length, 3);
  assert.ok(urls[0].includes('gemini-2.5-flash:') && urls[1].includes('gemini-2.5-flash:'));
  assert.ok(urls[2].includes('gemini-flash-lite-latest:'));
  await s.close();

  let always = 0;
  const s2 = await start(geminiEnv, async () => {
    always += 1;
    return busy;
  });
  const res2 = await s2.chat(ask());
  assert.equal(res2.status, 503);
  assert.equal((await res2.json()).error, 'upstream_unavailable');
  assert.equal(always, 5); // 2 on the main model + 3 on the fallback
  await s2.close();

  // without a fallback the old behaviour stays: 3 tries on the main model
  let single = 0;
  const s3 = await start({ ...geminiEnv, GEMINI_FALLBACK_MODEL: '' }, async () => {
    single += 1;
    return busy;
  });
  assert.equal((await s3.chat(ask())).status, 503);
  assert.equal(single, 3);
  await s3.close();
});

// ---- photos of people: switched on only by the operator (free Gemini quota = Unpaid Services) ----

const photoAsk = () => ({
  json: true,
  messages: [{ role: 'user', content: 'look', images: ['/9j/AAAA'] }],
});

test('photo policy: Gemini without a declared paid project keeps photos OFF', () => {
  const c = readConfig(geminiEnv);
  assert.equal(c.photoAnalysis, false);
  assert.equal(c.dataUse, 'unknown');
  assert.equal(readConfig({ ...geminiEnv, GEMINI_BILLING: 'free' }).photoAnalysis, false);
  assert.equal(readConfig({ ...geminiEnv, GEMINI_BILLING: 'free' }).dataUse, 'free');
  assert.equal(readConfig({ ...geminiEnv, GEMINI_BILLING: 'nonsense' }).dataUse, 'unknown');
});

test('photo policy: a declared paid Gemini project turns photos on, an explicit switch always wins', () => {
  assert.equal(readConfig({ ...geminiEnv, GEMINI_BILLING: 'paid' }).photoAnalysis, true);
  assert.equal(readConfig({ ...geminiEnv, GEMINI_BILLING: 'PAID ' }).dataUse, 'paid');
  assert.equal(readConfig({ ...geminiEnv, GEMINI_BILLING: 'paid', PHOTO_ANALYSIS: 'off' }).photoAnalysis, false);
  assert.equal(readConfig({ ...geminiEnv, PHOTO_ANALYSIS: 'on' }).photoAnalysis, true);
});

test('photo policy: other providers default to OFF (their terms were not checked)', () => {
  const c = readConfig({ ANTHROPIC_API_KEY: 'sk' });
  assert.equal(c.provider, 'claude');
  assert.equal(c.photoAnalysis, false);
  assert.equal(c.dataUse, 'unknown');
  assert.equal(readConfig({ ANTHROPIC_API_KEY: 'sk', PHOTO_ANALYSIS: 'on' }).photoAnalysis, true);
});

test('a photo is refused with 503 photo_analysis_disabled and never reaches Gemini', async () => {
  let called = 0;
  const s = await start(geminiEnv, async () => {
    called += 1;
    return geminiReply('{}')();
  });
  const res = await s.chat(photoAsk());
  const body = await res.json();
  assert.equal(res.status, 503);
  assert.equal(body.error, 'photo_analysis_disabled');
  assert.equal(called, 0);
  await s.close();
});

test('text-only chat still works while photos are off', async () => {
  const s = await start(geminiEnv, geminiReply('Привет'));
  const res = await s.chat(ask('Подойдёт ли мне крем?'));
  assert.equal(res.status, 200);
  assert.equal((await res.json()).text, 'Привет');
  await s.close();
});

test('health tells the app whether photos are allowed and how the provider may use data', async () => {
  const off = await start(geminiEnv, geminiReply());
  assert.deepEqual(await (await off.call('/health')).json(), {
    ok: true,
    mode: 'gemini',
    model: 'gemini-2.5-flash',
    photoAnalysis: false,
    dataUse: 'unknown',
  });
  await off.close();
  const on = await start({ ...geminiEnv, GEMINI_BILLING: 'paid' }, geminiReply());
  const h = await (await on.call('/health')).json();
  assert.equal(h.photoAnalysis, true);
  assert.equal(h.dataUse, 'paid');
  await on.close();
});

test('with photos allowed the photo goes to Gemini; with the switch off again it does not', async () => {
  let called = 0;
  const fetchImpl = async () => {
    called += 1;
    return geminiReply('{"skinTone":"light"}')();
  };
  const on = await start({ ...geminiEnv, GEMINI_BILLING: 'paid' }, fetchImpl);
  assert.equal((await on.chat(photoAsk())).status, 200);
  assert.equal(called, 1);
  await on.close();
  const off = await start({ ...geminiEnv, GEMINI_BILLING: 'paid', PHOTO_ANALYSIS: 'off' }, fetchImpl);
  assert.equal((await off.chat(photoAsk())).status, 503);
  assert.equal(called, 1);
  await off.close();
});

// ---- a modified client cannot get a photo through while photos are off ----

test('every way to attach an image is refused while photos are off, and Gemini is never called', async () => {
  let called = 0;
  const s = await start(geminiEnv, async () => {
    called += 1;
    return geminiReply('{}')();
  });
  const attempts = [
    // image in an earlier message, not the last one
    {
      messages: [
        { role: 'user', content: 'a', images: ['/9j/AAAA'] },
        { role: 'assistant', content: 'b' },
        { role: 'user', content: 'c' },
      ],
    },
    // PNG and WebP, and two images
    { messages: [{ role: 'user', content: 'a', images: ['iVBORw0KGgo='] }] },
    { messages: [{ role: 'user', content: 'a', images: ['UklGRgAAAA=='] }] },
    { messages: [{ role: 'user', content: 'a', images: ['/9j/AAAA', 'iVBORw0KGgo='] }] },
    // with the JSON flag, a system prompt and a temperature, as the app sends it
    { system: 'S', json: true, temperature: 0.2, messages: [{ role: 'user', content: 'a', images: ['/9j/AAAA'] }] },
  ];
  for (const body of attempts) {
    const res = await s.chat(body);
    assert.equal(res.status, 503, JSON.stringify(body).slice(0, 80));
    assert.equal((await res.json()).error, 'photo_analysis_disabled');
  }
  assert.equal(called, 0);
  await s.close();
});

test('a bad image is still 4xx while photos are off, never a way past the check', async () => {
  const s = await start(geminiEnv, geminiReply('{}'));
  for (const [body, status] of [
    [{ messages: [{ role: 'user', content: 'a', images: ['not-an-image'] }] }, 415],
    [{ messages: [{ role: 'user', content: 'a', images: ['/9j/A', '/9j/B', '/9j/C'] }] }, 413],
    [{ messages: [{ role: 'assistant', content: 'a', images: ['/9j/AAAA'] }] }, 400],
  ]) {
    assert.equal((await s.chat(body)).status, status);
  }
  await s.close();
});

test('fields the proxy does not know are not forwarded as images', async () => {
  let sent = null;
  const s = await start(geminiEnv, async (url, init) => {
    sent = JSON.parse(init.body);
    return geminiReply('{}')();
  });
  const res = await s.chat({
    image: '/9j/AAAA',
    images: ['/9j/AAAA'],
    attachments: [{ data: '/9j/AAAA' }],
    messages: [{ role: 'user', content: 'Привет', image: '/9j/AAAA', attachments: ['/9j/AAAA'] }],
  });
  assert.equal(res.status, 200);
  assert.ok(sent, 'the text request went to Gemini');
  assert.equal(JSON.stringify(sent).includes('inlineData'), false, 'no image part was built from unknown fields');
  assert.equal(JSON.stringify(sent).includes('/9j/AAAA'), false, 'the unknown fields were dropped');
  await s.close();
});

test('an image smuggled into the text is sent as text, never as an image', async () => {
  let sent = null;
  const s = await start(geminiEnv, async (url, init) => {
    sent = JSON.parse(init.body);
    return geminiReply('{}')();
  });
  const res = await s.chat({ messages: [{ role: 'user', content: 'data:image/jpeg;base64,/9j/AAAA look at this' }] });
  assert.equal(res.status, 200);
  assert.equal(JSON.stringify(sent).includes('inlineData'), false);
  await s.close();
});

test('the switch is checked on every request: turning it off applies at once', async () => {
  // two servers stand for the same code with the operator's setting changed
  const on = await start({ ...geminiEnv, GEMINI_BILLING: 'paid' }, geminiReply('{}'));
  assert.equal((await on.chat({ messages: [{ role: 'user', content: 'a', images: ['/9j/AAAA'] }] })).status, 200);
  await on.close();
  const off = await start({ ...geminiEnv, GEMINI_BILLING: 'paid', PHOTO_ANALYSIS: 'off' }, geminiReply('{}'));
  assert.equal((await off.chat({ messages: [{ role: 'user', content: 'a', images: ['/9j/AAAA'] }] })).status, 503);
  await off.close();
});
