'use strict';

const http = require('node:http');

const ANTHROPIC_URL = 'https://api.anthropic.com/v1/messages';
const ANTHROPIC_VERSION = '2023-06-01';
const MOCK_PREFIX =
  '[ТЕСТОВЫЙ РЕЖИМ: ключ Claude API не задан, это не настоящий ответ ИИ] ';

/** Hard limits for one request (protect the budget and the upstream API). */
const LIMITS = {
  bodyBytes: 7 * 1024 * 1024,
  messages: 20,
  textChars: 6000, // one message
  totalChars: 24000, // system + all messages
  images: 2,
  imageBase64Chars: 6 * 1024 * 1024,
};

function intEnv(env, name, fallback) {
  const n = Number.parseInt(env[name] ?? '', 10);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

function readConfig(env) {
  return {
    apiKey: (env.ANTHROPIC_API_KEY || '').trim(),
    model: (env.CLAUDE_MODEL || 'claude-haiku-5-5').trim(),
    appToken: (env.APP_TOKEN || '').trim(),
    maxOutputTokens: intEnv(env, 'MAX_OUTPUT_TOKENS', 600),
    ratePerMinute: intEnv(env, 'RATE_LIMIT_PER_MIN', 20),
    dailyTokenBudget: intEnv(env, 'DAILY_TOKEN_BUDGET', 200000),
    upstreamTimeoutMs: intEnv(env, 'UPSTREAM_TIMEOUT_MS', 45000),
    forceMock: env.MOCK === '1',
  };
}

class HttpError extends Error {
  constructor(status, code, message, extra = {}) {
    super(message);
    this.status = status;
    this.code = code;
    this.extra = extra;
  }
}

function sniffImageType(b64) {
  // JPEG starts with /9j/, PNG with iVBOR, WebP (RIFF) with UklGR
  if (b64.startsWith('/9j/')) return 'image/jpeg';
  if (b64.startsWith('iVBOR')) return 'image/png';
  if (b64.startsWith('UklGR')) return 'image/webp';
  return null;
}

/** Validates the app request and returns a clean copy. */
function validateChatBody(body, config) {
  if (!body || typeof body !== 'object') {
    throw new HttpError(400, 'bad_request', 'Body must be a JSON object');
  }
  const { system, messages, json, temperature, maxTokens } = body;
  if (!Array.isArray(messages) || messages.length === 0) {
    throw new HttpError(400, 'bad_request', '"messages" must be a non-empty list');
  }
  if (messages.length > LIMITS.messages) {
    throw new HttpError(413, 'too_long', 'Too many messages');
  }
  let total = 0;
  if (system !== undefined) {
    if (typeof system !== 'string') {
      throw new HttpError(400, 'bad_request', '"system" must be a string');
    }
    total += system.length;
  }
  let imageCount = 0;
  const clean = [];
  for (const m of messages) {
    if (!m || (m.role !== 'user' && m.role !== 'assistant')) {
      throw new HttpError(400, 'bad_request', 'Message role must be user or assistant');
    }
    if (typeof m.content !== 'string' || m.content.trim() === '') {
      throw new HttpError(400, 'bad_request', 'Message content must be a non-empty string');
    }
    if (m.content.length > LIMITS.textChars) {
      throw new HttpError(413, 'too_long', 'A message is too long');
    }
    total += m.content.length;
    const images = [];
    if (m.images !== undefined) {
      if (!Array.isArray(m.images) || m.role !== 'user') {
        throw new HttpError(400, 'bad_request', 'Only user messages can carry images');
      }
      for (const img of m.images) {
        imageCount += 1;
        if (typeof img !== 'string' || img.length === 0 || imageCount > LIMITS.images) {
          throw new HttpError(413, 'too_long', 'Too many or invalid images');
        }
        if (img.length > LIMITS.imageBase64Chars) {
          throw new HttpError(413, 'too_long', 'An image is too large');
        }
        const type = sniffImageType(img);
        if (!type) {
          throw new HttpError(415, 'bad_image', 'Only JPEG, PNG or WebP images are accepted');
        }
        images.push({ type, data: img });
      }
    }
    clean.push({ role: m.role, content: m.content, images });
  }
  if (total > LIMITS.totalChars) {
    throw new HttpError(413, 'too_long', 'The request is too long');
  }
  if (clean[clean.length - 1].role !== 'user') {
    throw new HttpError(400, 'bad_request', 'The last message must be from the user');
  }
  const wantsJson = json === true;
  let temp = typeof temperature === 'number' ? temperature : undefined;
  if (temp !== undefined) temp = Math.min(1, Math.max(0, temp));
  const requested = Number.isInteger(maxTokens) && maxTokens > 0 ? maxTokens : config.maxOutputTokens;
  return {
    system: typeof system === 'string' && system.trim() ? system : undefined,
    messages: clean,
    json: wantsJson,
    temperature: temp,
    maxTokens: Math.min(requested, config.maxOutputTokens),
  };
}

function toAnthropicBody(req, config) {
  let system = req.system || '';
  if (req.json) {
    system +=
      '\n\nReply with ONE valid JSON object only: no markdown fences, no text before or after it.';
  }
  const messages = req.messages.map((m) => {
    if (m.images.length === 0) return { role: m.role, content: m.content };
    return {
      role: m.role,
      content: [
        ...m.images.map((i) => ({
          type: 'image',
          source: { type: 'base64', media_type: i.type, data: i.data },
        })),
        { type: 'text', text: m.content },
      ],
    };
  });
  const body = { model: config.model, max_tokens: req.maxTokens, messages };
  if (system.trim()) body.system = system.trim();
  if (req.temperature !== undefined) body.temperature = req.temperature;
  return body;
}

function createApp({ env = process.env, fetchImpl = fetch, now = () => Date.now() } = {}) {
  const config = readConfig(env);
  const mock = config.forceMock || config.apiKey === '';

  /** ip -> request timestamps within the last minute */
  const hits = new Map();
  const budget = { day: '', used: 0 };

  function today() {
    return new Date(now()).toISOString().slice(0, 10);
  }

  function rollBudget() {
    const d = today();
    if (budget.day !== d) {
      budget.day = d;
      budget.used = 0;
    }
  }

  function checkRate(ip) {
    const t = now();
    const recent = (hits.get(ip) || []).filter((x) => t - x < 60000);
    if (recent.length >= config.ratePerMinute) {
      const retryAfter = Math.max(1, Math.ceil((60000 - (t - recent[0])) / 1000));
      hits.set(ip, recent);
      throw new HttpError(429, 'rate_limited', 'Too many requests, try again later', {
        retryAfter,
      });
    }
    recent.push(t);
    hits.set(ip, recent);
  }

  function checkBudget() {
    rollBudget();
    if (budget.used >= config.dailyTokenBudget) {
      throw new HttpError(429, 'budget_exceeded', 'The daily AI budget is used up', {
        retryAfter: 3600,
      });
    }
  }

  function authorize(req) {
    if (!config.appToken) return;
    if (req.headers['x-app-token'] !== config.appToken) {
      throw new HttpError(401, 'unauthorized', 'Missing or wrong app token');
    }
  }

  async function readBody(req) {
    const chunks = [];
    let size = 0;
    for await (const chunk of req) {
      size += chunk.length;
      if (size > LIMITS.bodyBytes) {
        throw new HttpError(413, 'too_long', 'The request body is too large');
      }
      chunks.push(chunk);
    }
    try {
      return JSON.parse(Buffer.concat(chunks).toString('utf8'));
    } catch {
      throw new HttpError(400, 'bad_request', 'Invalid JSON');
    }
  }

  async function callClaude(clean) {
    let res;
    try {
      res = await fetchImpl(ANTHROPIC_URL, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          'x-api-key': config.apiKey,
          'anthropic-version': ANTHROPIC_VERSION,
        },
        body: JSON.stringify(toAnthropicBody(clean, config)),
        signal: AbortSignal.timeout(config.upstreamTimeoutMs),
      });
    } catch (e) {
      if (e && (e.name === 'TimeoutError' || e.name === 'AbortError')) {
        throw new HttpError(504, 'upstream_timeout', 'Claude did not answer in time');
      }
      throw new HttpError(503, 'upstream_unavailable', 'Claude API is not reachable');
    }
    if (res.status === 429) {
      throw new HttpError(429, 'upstream_rate_limited', 'Claude API is busy, try again later', {
        retryAfter: Number(res.headers.get('retry-after')) || 30,
      });
    }
    if (res.status === 401 || res.status === 403) {
      // never leak details about the key
      throw new HttpError(502, 'upstream_auth', 'The server is not configured correctly');
    }
    if (!res.ok) {
      throw new HttpError(503, 'upstream_unavailable', 'Claude API is unavailable');
    }
    let data;
    try {
      data = await res.json();
    } catch {
      throw new HttpError(502, 'upstream_bad_response', 'Unreadable answer from Claude');
    }
    const text = Array.isArray(data.content)
      ? data.content
          .filter((b) => b && b.type === 'text')
          .map((b) => b.text)
          .join('')
      : '';
    if (!text.trim()) {
      throw new HttpError(502, 'upstream_bad_response', 'Empty answer from Claude');
    }
    const usage = {
      inputTokens: data.usage?.input_tokens ?? 0,
      outputTokens: data.usage?.output_tokens ?? 0,
    };
    return { text, usage };
  }

  function mockAnswer(clean) {
    if (clean.json) {
      throw new HttpError(
        503,
        'mock_no_structured',
        'Structured answers are not available in test mode',
      );
    }
    const last = clean.messages[clean.messages.length - 1].content;
    return {
      text:
        MOCK_PREFIX +
        'Я не могу дать настоящий совет без ключа Claude API. ' +
        `Ваш вопрос: «${last.slice(0, 120)}».`,
      usage: { inputTokens: 0, outputTokens: 0 },
    };
  }

  const server = http.createServer(async (req, res) => {
    const send = (status, payload, headers = {}) => {
      const body = JSON.stringify(payload);
      res.writeHead(status, {
        'content-type': 'application/json; charset=utf-8',
        'content-length': Buffer.byteLength(body),
        'cache-control': 'no-store',
        ...headers,
      });
      res.end(body);
    };
    try {
      const url = new URL(req.url, 'http://localhost');
      if (req.method === 'GET' && url.pathname === '/health') {
        return send(200, { ok: true, mode: mock ? 'mock' : 'claude', model: mock ? null : config.model });
      }
      if (req.method === 'POST' && url.pathname === '/v1/chat') {
        authorize(req);
        checkRate(req.socket.remoteAddress || 'unknown');
        checkBudget();
        const clean = validateChatBody(await readBody(req), config);
        const result = mock ? mockAnswer(clean) : await callClaude(clean);
        rollBudget();
        budget.used += result.usage.inputTokens + result.usage.outputTokens;
        return send(200, { text: result.text, mock, usage: result.usage });
      }
      throw new HttpError(404, 'not_found', 'Not found');
    } catch (e) {
      if (e instanceof HttpError) {
        const headers = e.extra.retryAfter ? { 'retry-after': String(e.extra.retryAfter) } : {};
        return send(e.status, { error: e.code, message: e.message, ...e.extra }, headers);
      }
      // unexpected: no details to the client, nothing sensitive in the log
      console.error('unexpected error:', e && e.name);
      return send(500, { error: 'internal', message: 'Internal error' });
    }
  });

  return { server, config, mock, budget };
}

module.exports = { createApp, validateChatBody, toAnthropicBody, readConfig, MOCK_PREFIX, LIMITS };
