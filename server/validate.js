'use strict';

const { HttpError } = require('./http-error');

function bad(message) {
  return new HttpError(400, 'bad_request', message);
}

/** Integer query parameter within [min, max]; the default when absent. */
function intParam(value, name, { min = 0, max = 1e9, def } = {}) {
  if (value === undefined || value === null || value === '') return def;
  const n = Number(value);
  if (!Number.isInteger(n) || n < min || n > max) {
    throw bad(`"${name}" must be an integer from ${min} to ${max}`);
  }
  return n;
}

/** Optional string: undefined stays undefined, null stays null, '' becomes null. */
function optString(value, name, { max = 200 } = {}) {
  if (value === undefined) return undefined;
  if (value === null) return null;
  if (typeof value !== 'string') throw bad(`"${name}" must be a string`);
  const v = value.trim();
  if (v.length > max) throw bad(`"${name}" is longer than ${max} characters`);
  return v === '' ? null : v;
}

function requireObject(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    throw bad('Body must be a JSON object');
  }
  return body;
}

/** LIKE pattern for a "contains" search: the user's % and _ are matched literally. */
function likePattern(q) {
  return `%${q.replace(/[\\%_]/g, (c) => `\\${c}`)}%`;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

module.exports = { bad, intParam, optString, requireObject, likePattern, UUID_RE };
