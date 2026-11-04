'use strict';

const { HttpError } = require('../http-error');
const { newToken, hashToken } = require('../auth');
const { bad, intParam, optString, requireObject } = require('../validate');
const { Reply } = require('../router');

const MAX_REACTIONS = 2000;
const MAX_EVENTS_PER_REQUEST = 50;
const MAX_PROPS_BYTES = 2000;

function profileJson(r) {
  return {
    userId: r.id,
    birthYear: r.birth_year,
    skinType: r.skin_type,
    skinTone: r.skin_tone,
    undertone: r.undertone,
    colorType: r.color_type,
    skinConcerns: r.skin_concerns,
    city: r.city,
    updatedAt: r.profile_updated_at,
  };
}

function reactionJson(r) {
  return {
    clientId: r.client_id,
    productId: r.product_id,
    title: r.title,
    severity: r.severity,
    date: r.reaction_date,
    notes: r.notes,
    updatedAt: r.updated_at,
  };
}

/** The user behind `Authorization: Bearer <token>`; 401 otherwise. */
async function requireUser(db, req) {
  const m = /^Bearer ([A-Za-z0-9_-]{20,100})$/.exec(req.headers.authorization || '');
  if (!m) throw new HttpError(401, 'unauthorized', 'Missing or malformed user token');
  const r = await db.query(
    `UPDATE app_users SET last_seen_at = now() WHERE token_hash = $1 RETURNING id`,
    [hashToken(m[1])],
  );
  if (r.rowCount === 0) throw new HttpError(401, 'unauthorized', 'Unknown user token');
  return r.rows[0].id;
}

/** Birth year: an integer between 1900 and this year, or null to clear it. */
function parseBirthYear(v, now) {
  if (v === null) return null;
  const year = new Date(now()).getUTCFullYear();
  if (!Number.isInteger(v) || v < 1900 || v > year) {
    throw bad(`"birthYear" must be an integer from 1900 to ${year}, or null`);
  }
  return v;
}

function parseConcerns(v) {
  if (!Array.isArray(v) || v.length > 10) throw bad('"skinConcerns" must be a list of up to 10 items');
  return v.map((x) => {
    if (typeof x !== 'string' || x.trim() === '' || x.length > 80) {
      throw bad('Each skin concern must be a non-empty string up to 80 characters');
    }
    return x.trim();
  });
}

function parseReaction(body, now) {
  requireObject(body);
  const title = optString(body.title, 'title', { max: 200 });
  if (!title) throw bad('"title" is required');
  if (!Number.isInteger(body.severity) || body.severity < 1 || body.severity > 5) {
    throw bad('"severity" must be an integer from 1 to 5');
  }
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(body.date ?? ''));
  const d = m && new Date(Date.UTC(+m[1], +m[2] - 1, +m[3]));
  if (!d || d.getUTCMonth() !== +m[2] - 1 || d.getUTCDate() !== +m[3]) {
    throw bad('"date" must be a real date like 2026-05-31');
  }
  if (d.getTime() > now() + 36 * 3600 * 1000) throw bad('"date" is in the future');
  let productId = null;
  if (body.productId !== undefined && body.productId !== null) {
    productId = intParam(body.productId, 'productId', { min: 1, max: 2147483647 });
    if (!Number.isInteger(body.productId)) throw bad('"productId" must be an integer');
  }
  const notes = optString(body.notes, 'notes', { max: 2000 }) ?? '';
  return { title, severity: body.severity, date: m[0], productId, notes };
}

function parseEvents(body, now) {
  requireObject(body);
  if (!Array.isArray(body.events) || body.events.length === 0) {
    throw bad('"events" must be a non-empty list');
  }
  if (body.events.length > MAX_EVENTS_PER_REQUEST) {
    throw new HttpError(413, 'too_long', `At most ${MAX_EVENTS_PER_REQUEST} events per request`);
  }
  return body.events.map((e) => {
    requireObject(e);
    if (typeof e.type !== 'string' || !/^[a-z][a-z0-9_]{0,39}$/.test(e.type)) {
      throw bad('Event "type" must be snake_case, up to 40 characters');
    }
    let props = {};
    if (e.props !== undefined) {
      if (!e.props || typeof e.props !== 'object' || Array.isArray(e.props)) {
        throw bad('Event "props" must be an object');
      }
      if (Buffer.byteLength(JSON.stringify(e.props)) > MAX_PROPS_BYTES) {
        throw new HttpError(413, 'too_long', `Event "props" is over ${MAX_PROPS_BYTES} bytes`);
      }
      props = e.props;
    }
    let clientTime = null;
    if (e.clientTime !== undefined && e.clientTime !== null) {
      const t = new Date(e.clientTime);
      if (Number.isNaN(t.getTime())) throw bad('Event "clientTime" must be an ISO date-time');
      // the device clock is only informational: drop silly values
      clientTime = Math.abs(t.getTime() - now()) < 400 * 86400000 ? t.toISOString() : null;
    }
    return { type: e.type, props, clientTime };
  });
}

function registerAppUser(router, { devicesLimiter, now }) {
  // A device registers itself: anonymous, no e-mail or password.
  router.add('POST', '/v1/devices', async ({ db, req }) => {
    devicesLimiter.hit(req.socket.remoteAddress || 'unknown');
    const token = newToken();
    const r = await db.query('INSERT INTO app_users (token_hash) VALUES ($1) RETURNING id', [
      hashToken(token),
    ]);
    return new Reply(201, { userId: r.rows[0].id, token });
  });

  router.add('GET', '/v1/profile', async ({ db, req }) => {
    const id = await requireUser(db, req);
    const r = await db.query(
      `SELECT id, birth_year, skin_type, skin_tone, undertone, color_type, skin_concerns, city,
              profile_updated_at FROM app_users WHERE id = $1`,
      [id],
    );
    return profileJson(r.rows[0]);
  });

  // Partial update: absent fields stay, null clears a field.
  router.add('PUT', '/v1/profile', async ({ db, req, body }) => {
    const id = await requireUser(db, req);
    const b = requireObject(await body());
    const sets = [];
    const args = [];
    const set = (col, v) => {
      args.push(v);
      sets.push(`${col} = $${args.length}`);
    };
    if (b.birthYear !== undefined) set('birth_year', parseBirthYear(b.birthYear, now));
    for (const [key, col] of [
      ['skinType', 'skin_type'],
      ['skinTone', 'skin_tone'],
      ['undertone', 'undertone'],
      ['colorType', 'color_type'],
      ['city', 'city'],
    ]) {
      const v = optString(b[key], key, { max: 80 });
      if (v !== undefined) set(col, v);
    }
    if (b.skinConcerns !== undefined) set('skin_concerns', parseConcerns(b.skinConcerns));
    if (sets.length === 0) throw bad('Nothing to update');
    args.push(id);
    const r = await db.query(
      `UPDATE app_users SET ${sets.join(', ')}, profile_updated_at = now() WHERE id = $${args.length}
       RETURNING id, birth_year, skin_type, skin_tone, undertone, color_type, skin_concerns, city,
                 profile_updated_at`,
      args,
    );
    return profileJson(r.rows[0]);
  });

  // Right to be forgotten: removes the user with the profile, reactions and events.
  router.add('DELETE', '/v1/profile', async ({ db, req }) => {
    const id = await requireUser(db, req);
    await db.query('DELETE FROM app_users WHERE id = $1', [id]);
    return new Reply(204, null);
  });

  router.add('GET', '/v1/reactions', async ({ db, req }) => {
    const id = await requireUser(db, req);
    const r = await db.query(
      `SELECT client_id, product_id, title, severity, to_char(reaction_date, 'YYYY-MM-DD') AS reaction_date,
              notes, updated_at FROM reactions WHERE user_id = $1 ORDER BY reaction_date DESC, id DESC`,
      [id],
    );
    return { items: r.rows.map(reactionJson) };
  });

  // Idempotent: the same clientId updates the entry instead of adding another.
  router.add('PUT', '/v1/reactions/:clientId', async ({ db, req, params, body }) => {
    const userId = await requireUser(db, req);
    if (!/^[A-Za-z0-9_.-]{1,64}$/.test(params.clientId)) throw bad('Invalid client id');
    const x = parseReaction(await body(), now);
    if (x.productId !== null) {
      const p = await db.query('SELECT 1 FROM products WHERE id = $1', [x.productId]);
      if (p.rowCount === 0) throw bad('Unknown "productId"');
    }
    const count = await db.query(
      'SELECT count(*)::int AS n FROM reactions WHERE user_id = $1 AND client_id <> $2',
      [userId, params.clientId],
    );
    if (count.rows[0].n >= MAX_REACTIONS) {
      throw new HttpError(413, 'too_long', 'Too many reactions stored');
    }
    const r = await db.query(
      `INSERT INTO reactions (user_id, client_id, product_id, title, severity, reaction_date, notes)
       VALUES ($1,$2,$3,$4,$5,$6,$7)
       ON CONFLICT (user_id, client_id) DO UPDATE SET product_id = EXCLUDED.product_id,
         title = EXCLUDED.title, severity = EXCLUDED.severity,
         reaction_date = EXCLUDED.reaction_date, notes = EXCLUDED.notes, updated_at = now()
       RETURNING client_id, product_id, title, severity,
                 to_char(reaction_date, 'YYYY-MM-DD') AS reaction_date, notes, updated_at`,
      [userId, params.clientId, x.productId, x.title, x.severity, x.date, x.notes],
    );
    return reactionJson(r.rows[0]);
  });

  router.add('DELETE', '/v1/reactions/:clientId', async ({ db, req, params }) => {
    const userId = await requireUser(db, req);
    await db.query('DELETE FROM reactions WHERE user_id = $1 AND client_id = $2', [
      userId,
      params.clientId,
    ]);
    return new Reply(204, null);
  });

  // Activity events (batch). "app_open" is a sign-in to the app.
  router.add('POST', '/v1/events', async ({ db, req, body }) => {
    const userId = await requireUser(db, req);
    const events = parseEvents(await body(), now);
    await db.query(
      `INSERT INTO activity_events (user_id, type, props, client_time)
       SELECT $1, e.type, e.props, e.client_time
         FROM jsonb_to_recordset($2::jsonb) AS e(type text, props jsonb, client_time timestamptz)`,
      [
        userId,
        JSON.stringify(events.map((e) => ({ type: e.type, props: e.props, client_time: e.clientTime }))),
      ],
    );
    return new Reply(201, { accepted: events.length });
  });
}

module.exports = { registerAppUser, requireUser };
