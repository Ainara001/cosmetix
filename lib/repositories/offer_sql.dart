/// SQL pieces shared by the repositories that read products: the price, the
/// old price, the stock and the check time that come ONLY from verified shop
/// offers (`store_offers`). The demo price of the seed (`products.price`) is
/// never used for display.
const verifiedOfferColumns = '''
  (SELECT MIN(o.price) FROM store_offers o
     WHERE o.product_id = p.id AND o.verification = 'verified'
       AND o.price IS NOT NULL) AS verified_price,
  (SELECT o.old_price FROM store_offers o
     WHERE o.product_id = p.id AND o.verification = 'verified'
       AND o.price IS NOT NULL ORDER BY o.price LIMIT 1) AS verified_old_price,
  (SELECT COUNT(*) FROM store_offers o
     WHERE o.product_id = p.id AND o.verification = 'verified'
       AND o.availability = 'in_stock') AS offers_in_stock,
  (SELECT COUNT(*) FROM store_offers o
     WHERE o.product_id = p.id AND o.verification = 'verified'
       AND o.availability = 'out_of_stock') AS offers_out_of_stock,
  (SELECT MAX(o.checked_at) FROM store_offers o
     WHERE o.product_id = p.id AND o.verification = 'verified'
       AND o.price IS NOT NULL) AS verified_checked_at''';
