'use strict';

const { HttpError } = require('./http-error');

/**
 * In-memory sliding-window limiter: `limit` hits per `windowMs` for a key.
 * Good enough for one server process; put a real limiter in front when the
 * server is scaled out.
 */
function createLimiter({ limit, windowMs, now = () => Date.now() }) {
  const hits = new Map();
  return {
    /** Counts one hit and throws 429 when the key is over the limit. */
    hit(key) {
      const t = now();
      const recent = (hits.get(key) || []).filter((x) => t - x < windowMs);
      if (recent.length >= limit) {
        hits.set(key, recent);
        throw new HttpError(429, 'rate_limited', 'Too many requests, try again later', {
          retryAfter: Math.max(1, Math.ceil((windowMs - (t - recent[0])) / 1000)),
        });
      }
      recent.push(t);
      hits.set(key, recent);
      // forget keys that went quiet so the map cannot grow forever
      if (hits.size > 10000) {
        for (const [k, v] of hits) if (v.every((x) => t - x >= windowMs)) hits.delete(k);
      }
    },
    /** Is the key already over the limit? (does not count a hit) */
    blocked(key) {
      const t = now();
      return (hits.get(key) || []).filter((x) => t - x < windowMs).length >= limit;
    },
    reset(key) {
      hits.delete(key);
    },
  };
}

module.exports = { createLimiter };
