-- The seven categories v1 sells and their sub-categories, as MockData.categories
-- has them. Reference data: every environment gets them, production included.
-- Ids are fixed so the seed and the tests can name them. Pictures come later:
-- the demo's are placeholders, set by the development seed only.

INSERT INTO categories (id, parent_id, name, name_ar, position) VALUES
  (1, NULL, 'Phones',          'هواتف',          1),
  (2, NULL, 'Laptops',         'حواسيب محمولة',  2),
  (3, NULL, 'Headphones',      'سماعات',         3),
  (4, NULL, 'Smartwatches',    'ساعات ذكية',     4),
  (5, NULL, 'Cameras',         'كاميرات',        5),
  (6, NULL, 'Home appliances', 'أجهزة منزلية',   6),
  (7, NULL, 'Accessories',     'إكسسوارات',      7);

INSERT INTO categories (id, parent_id, name, name_ar, position) VALUES
  (8,  1, 'Smartphones',    'هواتف ذكية',     1),
  (9,  1, 'Tablets',        'أجهزة لوحية',    2),
  (10, 2, 'Ultrabooks',     'حواسيب نحيفة',   1),
  (11, 2, 'Gaming laptops', 'حواسيب ألعاب',   2),
  (12, 7, 'Cases & Covers', 'أغطية وحافظات',  1),
  (13, 7, 'Chargers',       'شواحن',          2);
