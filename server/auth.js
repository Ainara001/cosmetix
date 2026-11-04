'use strict';

const crypto = require('node:crypto');

const SCRYPT = { N: 16384, r: 8, p: 1, keylen: 32 };
const MIN_PASSWORD = 12;

/** `scrypt$N$r$p$salt$hash` (base64); only this string is stored. */
function hashPassword(password) {
  if (typeof password !== 'string' || password.length < MIN_PASSWORD) {
    throw new Error(`The password must have at least ${MIN_PASSWORD} characters`);
  }
  const salt = crypto.randomBytes(16);
  const hash = crypto.scryptSync(password, salt, SCRYPT.keylen, SCRYPT);
  return ['scrypt', SCRYPT.N, SCRYPT.r, SCRYPT.p, salt.toString('base64'), hash.toString('base64')].join('$');
}

function verifyPassword(password, stored) {
  if (typeof password !== 'string' || typeof stored !== 'string') return false;
  const [kind, N, r, p, salt, hash] = stored.split('$');
  if (kind !== 'scrypt' || !hash) return false;
  const expected = Buffer.from(hash, 'base64');
  const actual = crypto.scryptSync(password, Buffer.from(salt, 'base64'), expected.length, {
    N: Number(N),
    r: Number(r),
    p: Number(p),
  });
  return crypto.timingSafeEqual(actual, expected);
}

/** A random secret for the client and the SHA-256 that is stored instead of it. */
function newToken() {
  return crypto.randomBytes(32).toString('base64url');
}

function hashToken(token) {
  return crypto.createHash('sha256').update(String(token)).digest('hex');
}

/** Verifies against a fixed hash so unknown users cost the same time as known ones. */
const DUMMY_HASH = hashPassword('not-a-real-password-just-for-timing');

module.exports = { hashPassword, verifyPassword, newToken, hashToken, DUMMY_HASH, MIN_PASSWORD };
