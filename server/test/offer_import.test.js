'use strict';

const test = require('node:test');
const assert = require('node:assert');

const { csvToRows, rowsOf } = require('../offer_import');

test('csvToRows parses a header and converts numeric fields', () => {
  const rows = csvToRows(
    'productId,storeId,price,oldPrice,availability,source,method,checkedAt\n' +
      '1,2,4500,,in_stock,shelf,manual_visit,2026-11-08T10:00:00Z\n' +
      '3,4,,1990,out_of_stock,site,import_file,2026-11-08T10:00:00Z',
  );
  assert.equal(rows.length, 2);
  assert.equal(rows[0].productId, 1);
  assert.equal(rows[0].storeId, 2);
  assert.equal(rows[0].price, 4500);
  assert.equal(rows[0].oldPrice, null);
  assert.equal(rows[0].availability, 'in_stock');
  assert.equal(rows[0].method, 'manual_visit');
  assert.equal(rows[1].price, null);
  assert.equal(rows[1].oldPrice, 1990);
  assert.equal(rows[1].availability, 'out_of_stock');
});

test('empty optional cells become null and an empty urlKind becomes none', () => {
  const rows = csvToRows('productId,storeId,url,urlKind,note\n1,2,,,note');
  assert.equal(rows.length, 1);
  assert.equal(rows[0].url, null);
  assert.equal(rows[0].urlKind, 'none');
  assert.equal(rows[0].note, 'note');
});

test('rowsOf passes a JSON array through unchanged', () => {
  const arr = [{ productId: 1, storeId: 2 }];
  assert.strictEqual(rowsOf(arr), arr);
});

test('a BOM and blank lines are ignored', () => {
  const rows = csvToRows('\uFEFFproductId,storeId,price\n\n1,2,100\n');
  assert.equal(rows.length, 1);
  assert.equal(rows[0].price, 100);
});

test('an empty CSV has no rows', () => {
  assert.deepEqual(csvToRows(''), []);
  assert.deepEqual(csvToRows('productId,storeId\n'), []);
});
