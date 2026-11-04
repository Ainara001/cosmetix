'use strict';

const { HttpError } = require('./http-error');

/** Compiles '/v1/catalog/products/:id' to a RegExp with named groups. */
function compile(pattern) {
  const re = pattern.replace(/:([a-zA-Z]+)/g, '(?<$1>[^/]+)');
  return new RegExp(`^${re}$`);
}

/** A tiny method + path router; handlers get (ctx) and return a JSON-able value. */
class Router {
  constructor() {
    this.routes = [];
  }

  add(method, pattern, handler) {
    this.routes.push({ method, re: compile(pattern), handler });
  }

  /**
   * Finds the handler. Returns null for an unknown path and throws 405 when the
   * path exists but the method does not.
   */
  match(method, pathname) {
    let pathKnown = false;
    for (const r of this.routes) {
      const m = r.re.exec(pathname);
      if (!m) continue;
      pathKnown = true;
      if (r.method === method) return { handler: r.handler, params: { ...m.groups } };
    }
    if (pathKnown) throw new HttpError(405, 'method_not_allowed', 'Method not allowed');
    return null;
  }
}

/** A non-200 answer, extra headers or a non-JSON body from a handler. */
class Reply {
  constructor(status, body, headers = {}, raw = false) {
    this.status = status;
    this.body = body;
    this.headers = headers;
    this.raw = raw; // body is already a string/Buffer with its own content-type
  }
}

module.exports = { Router, Reply };
