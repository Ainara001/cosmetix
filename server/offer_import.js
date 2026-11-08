'use strict';

/**
 * Turns a CSV string or a JSON array of offer rows into plain objects for
 * `parseOffer` in routes/offers.js. This file does only PARSING and no
 * validation or database work, so it can be tested without PostgreSQL.
 *
 * CSV: the first line is a header with the field names, then one offer per
 * line, comma-separated. Commas inside a value are not supported (a `source`
 * or `note` with a comma must be imported as JSON). Numeric fields
 * (`productId`, `storeId`, `price`, `oldPrice`) are converted to numbers;
 * empty optional fields become null.
 */

const NUMERIC = new Set(['productId', 'storeId', 'price', 'oldPrice']);

// Fields that may be empty and mean "no value" rather than "": url,
// volumeText, variantText, note, city, price, oldPrice.
const NULLABLE = new Set([
  'price',
  'oldPrice',
  'url',
  'volumeText',
  'variantText',
  'note',
  'city',
]);

function cell(value, name) {
  const t = value === undefined || value === null ? '' : String(value).trim();
  if (name === 'urlKind' && t === '') return 'none';
  if (t === '' && NULLABLE.has(name)) return null;
  if (NUMERIC.has(name)) {
    if (t === '') return null;
    const n = Number(t);
    return Number.isNaN(n) ? null : n;
  }
  return t;
}

function csvToRows(csv) {
  const text = String(csv).replace(/^\uFEFF/, '');
  const lines = text.split(/\r?\n/).filter((l) => l.trim() !== '');
  if (lines.length === 0) return [];
  const header = lines[0].split(',').map((h) => h.trim());
  return lines.slice(1).map((line) => {
    const vals = line.split(',');
    const row = {};
    header.forEach((name, j) => {
      if (name) row[name] = cell(vals[j], name);
    });
    return row;
  });
}

/** JSON array (as-is) or CSV string -> array of row objects. */
function rowsOf(data) {
  if (Array.isArray(data)) return data;
  return csvToRows(data);
}

module.exports = { csvToRows, rowsOf };
