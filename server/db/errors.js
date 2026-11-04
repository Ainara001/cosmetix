'use strict';

// Node network errors and PostgreSQL error classes that mean "the database
// cannot be reached right now" (not "the request is wrong").
const NETWORK_CODES = new Set([
  'ECONNREFUSED',
  'ECONNRESET',
  'ETIMEDOUT',
  'ENOTFOUND',
  'EAI_AGAIN',
  'EPIPE',
  'EHOSTUNREACH',
  'ENETUNREACH',
]);

// 57014 = statement_timeout hit, 53300 = too many connections
const PG_CODES = new Set(['57014', '53300']);

// pg's own errors have no code
const MESSAGES = /Connection terminated|timeout exceeded when trying to connect|not queryable|Client has encountered a connection error|Connection ended unexpectedly/i;

/** True when the database is down, unreachable, overloaded or too slow. */
function isDbUnavailable(e) {
  if (!e) return false;
  if (e.name === 'AggregateError' && Array.isArray(e.errors)) {
    return e.errors.some(isDbUnavailable);
  }
  const code = typeof e.code === 'string' ? e.code : '';
  if (NETWORK_CODES.has(code) || PG_CODES.has(code)) return true;
  // class 08 = connection exception, 57Pxx = the server is shutting down / starting
  if (/^08/.test(code) || /^57P/.test(code)) return true;
  return MESSAGES.test(String(e.message || ''));
}

module.exports = { isDbUnavailable };
