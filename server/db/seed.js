'use strict';

const fs = require('node:fs');
const path = require('node:path');

const CATALOG = path.join(__dirname, '..', 'seed', 'catalog.json');

const TRAIT_TABLES = [
  ['product_skin_types', 'skin_type', 'skin_type'],
  ['product_color_types', 'color_type', 'color_type'],
  ['product_undertones', 'undertone', 'undertone'],
  ['product_concerns', 'concern', 'concern'],
  ['product_tags', 'tag', 'tag'],
];

/**
 * Loads seed/catalog.json (exported from the app's SQLite seed by
 * tool/export_server_seed.dart) into an EMPTY catalog. Returns false when the
 * catalog already has products: it never overwrites edits made in the admin.
 */
async function seedCatalog(pool, { file = CATALOG } = {}) {
  const data = JSON.parse(fs.readFileSync(file, 'utf8'));
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const { rows } = await client.query('SELECT count(*)::int AS n FROM products');
    if (rows[0].n > 0) {
      await client.query('ROLLBACK');
      return false;
    }

    const brandId = new Map();
    const categoryId = new Map();
    for (const p of data.products) {
      if (!brandId.has(p.brand)) {
        const r = await client.query('INSERT INTO brands (name) VALUES ($1) RETURNING id', [p.brand]);
        brandId.set(p.brand, r.rows[0].id);
      }
      if (!categoryId.has(p.category)) {
        const r = await client.query('INSERT INTO categories (name) VALUES ($1) RETURNING id', [
          p.category,
        ]);
        categoryId.set(p.category, r.rows[0].id);
      }
    }

    for (const s of data.stores) {
      await client.query(
        `INSERT INTO stores (id, name, chain, address, lat, lng, hours, source)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
        [s.id, s.name, s.chain, s.address, s.lat, s.lng, s.hours, s.source],
      );
    }
    for (const i of data.ingredients) {
      await client.query(
        `INSERT INTO ingredients (id, name, description, risk, is_allergen, group_key)
         VALUES ($1,$2,$3,$4,$5,$6)`,
        [i.id, i.name, i.description, i.risk, i.is_allergen === 1, i.group_key],
      );
    }
    for (const p of data.products) {
      await client.query(
        `INSERT INTO products (id, brand_id, category_id, name, zone, price, price_source, old_price,
           in_stock, art, color, shade, description, natural_percent, featured, trending,
           inci, source_url, created_at)
         VALUES ($1,$2,$3,$4,$5,$6,'demo',$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,
                 now() - ($18::bigint * interval '1 millisecond'))`,
        [
          p.id,
          brandId.get(p.brand),
          categoryId.get(p.category),
          p.name,
          p.zone,
          p.price,
          p.old_price,
          p.in_stock === 1,
          p.art,
          p.color,
          p.shade,
          p.description,
          p.natural_percent,
          p.featured === 1,
          p.trending === 1,
          p.inci,
          p.source_url,
          p.age_ms,
        ],
      );
    }
    for (const r of data.product_ingredients) {
      await client.query(
        'INSERT INTO product_ingredients (product_id, ingredient_id) VALUES ($1,$2)',
        [r.product_id, r.ingredient_id],
      );
    }
    for (const r of data.product_prices) {
      await client.query(
        `INSERT INTO prices (product_id, store_id, price, in_stock, qty, source)
         VALUES ($1,$2,$3,$4,$5,$6)`,
        [r.product_id, r.store_id, r.price, r.in_stock === 1, r.qty, r.source],
      );
    }
    for (const [table, kind, column] of TRAIT_TABLES) {
      for (const r of data[table]) {
        await client.query(
          'INSERT INTO product_traits (product_id, kind, value, source) VALUES ($1,$2,$3,$4)',
          [r.product_id, kind, r[column], r.source],
        );
      }
    }
    // the rows above were inserted with explicit ids: move the sequences on
    for (const t of ['products', 'stores', 'ingredients']) {
      await client.query(
        `SELECT setval(pg_get_serial_sequence('${t}', 'id'), (SELECT max(id) FROM ${t}))`,
      );
    }
    await client.query('COMMIT');
    return true;
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

module.exports = { seedCatalog };
