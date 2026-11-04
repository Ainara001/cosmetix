'use strict';

const { HttpError } = require('../http-error');
const { intParam, likePattern } = require('../validate');

/** One product row as the API returns it (also used by the admin panel). */
const PRODUCT_SELECT = `
  SELECT p.id, b.name AS brand, c.name AS category, p.name, p.zone, p.price,
         p.price_source, p.old_price, p.in_stock, p.art, p.color, p.shade,
         p.description, p.natural_percent, p.featured, p.trending, p.inci,
         p.source_url, p.country, p.created_at, p.updated_at
    FROM products p
    JOIN brands b ON b.id = p.brand_id
    JOIN categories c ON c.id = p.category_id`;

function productJson(r) {
  return {
    id: r.id,
    brand: r.brand,
    category: r.category,
    name: r.name,
    zone: r.zone,
    price: r.price,
    // 'demo' = placeholder value of the app seed, not a real shop price
    priceSource: r.price_source,
    oldPrice: r.old_price,
    inStock: r.in_stock,
    art: r.art,
    color: Number(r.color),
    shade: r.shade === null ? null : Number(r.shade),
    description: r.description,
    naturalPercent: r.natural_percent,
    featured: r.featured,
    trending: r.trending,
    inci: r.inci,
    sourceUrl: r.source_url,
    country: r.country,
    createdAt: r.created_at,
    updatedAt: r.updated_at,
  };
}

const TRAIT_KEYS = {
  skin_type: 'skinTypes',
  color_type: 'colorTypes',
  undertone: 'undertones',
  concern: 'concerns',
  tag: 'tags',
};

/**
 * WHERE clause shared by the app catalog and the admin list.
 * Filters: category, brand (exact names), q (name or brand contains),
 * updatedSince (ISO date-time).
 */
function productFilter(query) {
  const where = [];
  const args = [];
  const get = (k) => query.get(k);
  if (get('category')) {
    args.push(get('category'));
    where.push(`c.name = $${args.length}`);
  }
  if (get('brand')) {
    args.push(get('brand'));
    where.push(`b.name = $${args.length}`);
  }
  if (get('q')) {
    args.push(likePattern(get('q').trim().slice(0, 100)));
    where.push(`(p.name ILIKE $${args.length} OR b.name ILIKE $${args.length})`);
  }
  if (get('updatedSince')) {
    const t = new Date(get('updatedSince'));
    if (Number.isNaN(t.getTime())) {
      throw new HttpError(400, 'bad_request', '"updatedSince" must be an ISO date-time');
    }
    args.push(t.toISOString());
    // JSON timestamps have millisecond precision: compare at the same precision,
    // otherwise a client that sends back the updatedAt it received sees that row again
    where.push(`date_trunc('milliseconds', p.updated_at) > $${args.length}`);
  }
  return { sql: where.length ? `WHERE ${where.join(' AND ')}` : '', args };
}

async function listProducts(db, query, { maxLimit = 200, defLimit = 100 } = {}) {
  const limit = intParam(query.get('limit'), 'limit', { min: 1, max: maxLimit, def: defLimit });
  const offset = intParam(query.get('offset'), 'offset', { min: 0, def: 0 });
  const f = productFilter(query);
  const total = await db.query(
    `SELECT count(*)::int AS n FROM products p
       JOIN brands b ON b.id = p.brand_id JOIN categories c ON c.id = p.category_id ${f.sql}`,
    f.args,
  );
  const rows = await db.query(
    `${PRODUCT_SELECT} ${f.sql} ORDER BY p.id LIMIT $${f.args.length + 1} OFFSET $${f.args.length + 2}`,
    [...f.args, limit, offset],
  );
  return { items: rows.rows.map(productJson), total: total.rows[0].n, limit, offset };
}

async function productDetails(db, id) {
  const r = await db.query(`${PRODUCT_SELECT} WHERE p.id = $1`, [id]);
  if (r.rowCount === 0) throw new HttpError(404, 'not_found', 'Product not found');
  const [ing, traits, prices] = await Promise.all([
    db.query(
      `SELECT i.id, i.name, i.description, i.risk, i.is_allergen, i.group_key
         FROM product_ingredients pi JOIN ingredients i ON i.id = pi.ingredient_id
        WHERE pi.product_id = $1 ORDER BY i.id`,
      [id],
    ),
    db.query(
      'SELECT kind, value, source FROM product_traits WHERE product_id = $1 ORDER BY kind, value',
      [id],
    ),
    db.query(
      `SELECT store_id, price, in_stock, qty, source, updated_at
         FROM prices WHERE product_id = $1 ORDER BY store_id`,
      [id],
    ),
  ]);
  const t = Object.fromEntries(Object.values(TRAIT_KEYS).map((k) => [k, []]));
  for (const row of traits.rows) {
    const key = TRAIT_KEYS[row.kind];
    if (!t[key].includes(row.value)) t[key].push(row.value);
  }
  return {
    ...productJson(r.rows[0]),
    ingredients: ing.rows.map((i) => ({
      id: i.id,
      name: i.name,
      description: i.description,
      risk: i.risk,
      isAllergen: i.is_allergen,
      groupKey: i.group_key,
    })),
    traits: t,
    prices: prices.rows.map((p) => ({
      storeId: p.store_id,
      price: p.price,
      inStock: p.in_stock,
      qty: p.qty,
      source: p.source,
      updatedAt: p.updated_at,
    })),
  };
}

function registerCatalog(router) {
  router.add('GET', '/v1/catalog/products', async ({ db, url }) =>
    listProducts(db, url.searchParams),
  );

  router.add('GET', '/v1/catalog/products/:id', async ({ db, params }) => {
    const id = intParam(params.id, 'id', { min: 1, max: 2147483647 });
    return productDetails(db, id);
  });

  router.add('GET', '/v1/catalog/categories', async ({ db }) => ({
    items: (await db.query('SELECT id, name FROM categories ORDER BY name')).rows,
  }));

  router.add('GET', '/v1/catalog/brands', async ({ db }) => ({
    items: (await db.query('SELECT id, name FROM brands ORDER BY name')).rows,
  }));

  router.add('GET', '/v1/catalog/stores', async ({ db }) => ({
    items: (
      await db.query(
        'SELECT id, name, chain, address, lat, lng, hours, source FROM stores ORDER BY id',
      )
    ).rows,
  }));

  router.add('GET', '/v1/catalog/ingredients', async ({ db }) => ({
    items: (
      await db.query(
        `SELECT id, name, description, risk, is_allergen AS "isAllergen", group_key AS "groupKey"
           FROM ingredients ORDER BY id`,
      )
    ).rows,
  }));
}

module.exports = { registerCatalog, listProducts, productDetails, productJson, PRODUCT_SELECT };
