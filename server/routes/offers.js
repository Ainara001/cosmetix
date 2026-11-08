'use strict';

const { HttpError } = require('../http-error');
const { bad, intParam, optString, requireObject } = require('../validate');
const { rowsOf } = require('../offer_import');
const { requireAdmin } = require('./admin');

const AVAILABILITY = ['in_stock', 'out_of_stock', 'unknown'];
const URL_KINDS = ['product', 'search', 'none'];
const METHODS = ['manual_visit', 'manual_site', 'partner_feed', 'official_api', 'import_file'];
const VERIFICATION = ['verified', 'unverified', 'disputed'];
const MAX_PRICE = 10_000_000;
const FUTURE_SLACK_MS = 5 * 60 * 1000;

function price(v, name) {
  if (v === undefined || v === null) return null;
  if (!Number.isInteger(v) || v <= 0 || v > MAX_PRICE) {
    throw bad(`"${name}" must be a whole number of tenge from 1 to ${MAX_PRICE}`);
  }
  return v;
}

function oneOf(v, list, name, def) {
  const x = v === undefined ? def : v;
  if (!list.includes(x)) throw bad(`"${name}" must be one of: ${list.join(', ')}`);
  return x;
}

/**
 * An offer from the panel, validated. The same rules as the database checks and
 * as the app's: no source, no price of zero, a link needs its kind, a verified
 * offer must say something, the check time is not in the future.
 */
function parseOffer(body, now = Date.now()) {
  requireObject(body);
  const known = [
    'productId', 'storeId', 'city', 'price', 'oldPrice', 'availability', 'url', 'urlKind',
    'volumeText', 'variantText', 'source', 'method', 'verification', 'checkedAt', 'note',
  ];
  const unknown = Object.keys(body).filter((k) => !known.includes(k));
  if (unknown.length) throw bad(`Unknown fields: ${unknown.join(', ')}`);
  const productId = intParam(body.productId, 'productId', { min: 1, max: 2147483647 });
  const storeId = intParam(body.storeId, 'storeId', { min: 1, max: 2147483647 });
  if (productId === undefined || storeId === undefined) throw bad('"productId" and "storeId" are required');
  const source = optString(body.source, 'source', { max: 300 });
  if (!source) throw bad('"source" (where the information comes from) is required');
  const method = oneOf(body.method, METHODS, 'method');
  const p = price(body.price, 'price');
  const old = price(body.oldPrice, 'oldPrice');
  if (old !== null && (p === null || old <= p)) throw bad('"oldPrice" must be above "price"');
  const availability = oneOf(body.availability, AVAILABILITY, 'availability', 'unknown');
  const url = optString(body.url, 'url', { max: 1000 });
  const urlKind = oneOf(body.urlKind, URL_KINDS, 'urlKind', url ? undefined : 'none');
  if (url !== null && url !== undefined) {
    let u;
    try {
      u = new URL(url);
    } catch {
      throw bad('"url" is not a valid address');
    }
    if (u.protocol !== 'https:' && u.protocol !== 'http:') throw bad('"url" must be an http(s) address');
    if (urlKind === 'none') throw bad('Say whether "url" opens the product or a search ("urlKind")');
  } else if (urlKind !== 'none') {
    throw bad('"urlKind" needs a "url"');
  }
  const verification = oneOf(body.verification, VERIFICATION, 'verification', 'unverified');
  if (verification === 'verified' && p === null && availability === 'unknown' && urlKind !== 'product') {
    throw bad('A verified offer must give a price, a checked stock or a link to the product');
  }
  const checkedAt = new Date(body.checkedAt === undefined ? now : body.checkedAt);
  if (Number.isNaN(checkedAt.getTime())) throw bad('"checkedAt" must be an ISO date-time');
  if (checkedAt.getTime() > now + FUTURE_SLACK_MS) throw bad('"checkedAt" is in the future');
  return {
    productId, storeId, price: p, oldPrice: old, availability,
    url: url ?? null, urlKind,
    city: optString(body.city, 'city', { max: 60 }) ?? 'Астана',
    volumeText: optString(body.volumeText, 'volumeText', { max: 60 }) ?? null,
    variantText: optString(body.variantText, 'variantText', { max: 120 }) ?? null,
    source, method, verification, checkedAt,
    note: optString(body.note, 'note', { max: 500 }) ?? null,
  };
}

function offerJson(r) {
  return {
    id: Number(r.id),
    productId: r.product_id,
    storeId: r.store_id,
    storeName: r.store_name,
    chain: r.chain,
    city: r.city,
    price: r.price,
    oldPrice: r.old_price,
    availability: r.availability,
    url: r.url,
    urlKind: r.url_kind,
    volumeText: r.volume_text,
    variantText: r.variant_text,
    source: r.source,
    method: r.method,
    verification: r.verification,
    checkedAt: r.checked_at,
    checkedBy: r.checked_by,
    note: r.note,
  };
}

const SELECT = `
  SELECT o.*, s.name AS store_name, s.chain AS chain
    FROM store_offers o JOIN stores s ON s.id = o.store_id`;

function registerOffers(router, { now = () => Date.now() } = {}) {
  // For the app: only VERIFIED offers. The demo rows of `prices` are not offers.
  router.add('GET', '/v1/products/:id/offers', async ({ db, params }) => {
    const id = intParam(params.id, 'id', { min: 1, max: 2147483647 });
    const rows = await db.query(
      `${SELECT} WHERE o.product_id = $1 AND o.verification = 'verified'
        ORDER BY o.price NULLS LAST, o.id`,
      [id],
    );
    return { items: rows.rows.map(offerJson) };
  });

  // The whole public snapshot for the app: every VERIFIED offer, each with the
  // brand and name of its product and the name and address of its shop (the app
  // matches by these, not by database ids). A withdrawn or unverified offer is
  // simply not in it, so the app that replaces its copy by this list drops it.
  // Nothing about users is read or written here.
  router.add('GET', '/v1/catalog/offers', async ({ db }) => {
    const rows = await db.query(
      `SELECT o.*, b.name AS brand, p.name AS product_name,
              s.name AS store_name, s.chain AS chain, s.address AS store_address
         FROM store_offers o
         JOIN products p ON p.id = o.product_id
         JOIN brands b ON b.id = p.brand_id
         JOIN stores s ON s.id = o.store_id
        WHERE o.verification = 'verified'
        ORDER BY o.product_id, o.price NULLS LAST, o.id
        LIMIT 5000`,
    );
    return {
      generatedAt: new Date(now()).toISOString(),
      items: rows.rows.map((r) => ({
        ...offerJson(r),
        brand: r.brand,
        productName: r.product_name,
        storeAddress: r.store_address,
        updatedAt: r.updated_at,
      })),
    };
  });

  router.add('GET', '/admin/api/stores', async ({ db, req }) => {
    await requireAdmin(db, req);
    const r = await db.query('SELECT id, name, chain, address FROM stores ORDER BY id');
    return { items: r.rows };
  });

  router.add('GET', '/admin/api/offers', async ({ db, req, url }) => {
    await requireAdmin(db, req);
    const productId = intParam(url.searchParams.get('productId'), 'productId', { min: 1, max: 2147483647 });
    const rows = await db.query(
      `${SELECT} ${productId ? 'WHERE o.product_id = $1' : ''} ORDER BY o.checked_at DESC, o.id DESC LIMIT 200`,
      productId ? [productId] : [],
    );
    return { items: rows.rows.map(offerJson) };
  });

  // Adds or replaces the offer of this product in this shop; everything is logged.
  router.add('PUT', '/admin/api/offers', async ({ db, req, body }) => {
    const admin = await requireAdmin(db, req);
    const o = parseOffer(await body(), now());
    const client = await db.connect();
    try {
      await client.query('BEGIN');
      const before = await client.query(
        'SELECT price, availability, url, verification, checked_at FROM store_offers WHERE product_id = $1 AND store_id = $2',
        [o.productId, o.storeId],
      );
      let r;
      try {
        r = await client.query(
          `INSERT INTO store_offers
             (product_id, store_id, city, price, old_price, availability, url, url_kind,
              volume_text, variant_text, source, method, verification, checked_at, checked_by, note)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16)
           ON CONFLICT (product_id, store_id) DO UPDATE SET
             city = EXCLUDED.city, price = EXCLUDED.price, old_price = EXCLUDED.old_price,
             availability = EXCLUDED.availability, url = EXCLUDED.url, url_kind = EXCLUDED.url_kind,
             volume_text = EXCLUDED.volume_text, variant_text = EXCLUDED.variant_text,
             source = EXCLUDED.source, method = EXCLUDED.method, verification = EXCLUDED.verification,
             checked_at = EXCLUDED.checked_at, checked_by = EXCLUDED.checked_by, note = EXCLUDED.note,
             updated_at = now()
           RETURNING id`,
          [o.productId, o.storeId, o.city, o.price, o.oldPrice, o.availability, o.url, o.urlKind,
            o.volumeText, o.variantText, o.source, o.method, o.verification, o.checkedAt,
            admin.username, o.note],
        );
      } catch (e) {
        if (e.code === '23503') throw new HttpError(404, 'not_found', 'Product or shop not found');
        throw e;
      }
      await client.query(
        'INSERT INTO admin_audit (admin_id, username, product_id, changes) VALUES ($1,$2,$3,$4)',
        [admin.id, admin.username, o.productId, JSON.stringify({
          offer: { storeId: o.storeId, from: before.rows[0] || null,
            to: { price: o.price, availability: o.availability, url: o.url, verification: o.verification } },
        })],
      );
      await client.query('COMMIT');
      const out = await db.query(`${SELECT} WHERE o.id = $1`, [r.rows[0].id]);
      return offerJson(out.rows[0]);
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }
  });

  // Batch import from a JSON array or a CSV string. Every row is validated on
  // its own: a bad row is rejected with its reason and does not fail the rest.
  // Rows enter as `unverified` unless they say otherwise; the run is logged.
  router.add('POST', '/admin/api/offers/import', async ({ db, req, body }) => {
    const admin = await requireAdmin(db, req);
    const raw = await body();
    const data = raw && raw.data !== undefined ? raw.data : raw;
    const rows = rowsOf(data);
    if (!Array.isArray(rows) || rows.length === 0) {
      throw new HttpError(400, 'bad_request', 'Nothing to import');
    }
    const imported = [];
    const rejected = [];
    for (let i = 0; i < rows.length; i++) {
      try {
        const o = parseOffer(rows[i], now());
        let r;
        try {
          r = await db.query(
            `INSERT INTO store_offers
               (product_id, store_id, city, price, old_price, availability, url, url_kind,
                volume_text, variant_text, source, method, verification, checked_at, checked_by, note)
             VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16)
             ON CONFLICT (product_id, store_id) DO UPDATE SET
               city = EXCLUDED.city, price = EXCLUDED.price, old_price = EXCLUDED.old_price,
               availability = EXCLUDED.availability, url = EXCLUDED.url, url_kind = EXCLUDED.url_kind,
               volume_text = EXCLUDED.volume_text, variant_text = EXCLUDED.variant_text,
               source = EXCLUDED.source, method = EXCLUDED.method, verification = EXCLUDED.verification,
               checked_at = EXCLUDED.checked_at, checked_by = EXCLUDED.checked_by, note = EXCLUDED.note,
               updated_at = now()
             RETURNING id`,
            [o.productId, o.storeId, o.city, o.price, o.oldPrice, o.availability, o.url, o.urlKind,
              o.volumeText, o.variantText, o.source, o.method, o.verification, o.checkedAt,
              admin.username, o.note],
          );
        } catch (e) {
          if (e.code === '23503') throw new Error('Product or shop not found');
          throw e;
        }
        imported.push({ id: Number(r.rows[0].id), productId: o.productId, storeId: o.storeId });
      } catch (e) {
        rejected.push({ row: i + 1, reason: e.message || String(e) });
      }
    }
    if (imported.length) {
      await db.query(
        'INSERT INTO admin_audit (admin_id, username, product_id, changes) VALUES ($1,$2,$3,$4)',
        [admin.id, admin.username, null, JSON.stringify({
          offerImport: { imported: imported.length, rejected: rejected.length },
        })],
      );
    }
    return { imported: imported.length, rejected };
  });

  router.add('DELETE', '/admin/api/offers/:id', async ({ db, req, params }) => {
    const admin = await requireAdmin(db, req);
    const id = intParam(params.id, 'id', { min: 1 });
    const r = await db.query('DELETE FROM store_offers WHERE id = $1 RETURNING product_id, store_id', [id]);
    if (r.rowCount === 0) throw new HttpError(404, 'not_found', 'Offer not found');
    await db.query(
      'INSERT INTO admin_audit (admin_id, username, product_id, changes) VALUES ($1,$2,$3,$4)',
      [admin.id, admin.username, r.rows[0].product_id, JSON.stringify({ offerDeleted: { storeId: r.rows[0].store_id } })],
    );
    return { deleted: true };
  });
}

module.exports = { registerOffers, parseOffer };
