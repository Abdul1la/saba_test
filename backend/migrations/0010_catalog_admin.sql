-- Saba's own pages for categories, Home banners and brands (the user's call,
-- 2026-10-01): until now they changed only in the database, and the live one
-- starts with no banners and no brands.
--
-- A category is hidden (off Home, Browse, the filters and the store's picker;
-- its products stay on sale) or deleted once empty: its products are moved to
-- another first, and the row stays, deleted, for the deleted products that
-- still name it. A banner opens a product, a store, a category or nothing, and
-- its words are optional. A brand a store types waits, PENDING, until Saba
-- approves a product that uses it or saves the brand itself.
ALTER TABLE categories
  ADD COLUMN is_hidden TINYINT(1) NOT NULL DEFAULT 0,
  ADD COLUMN deleted_at DATETIME(3) NULL;

ALTER TABLE home_banners
  MODIFY title_en VARCHAR(120) NULL,
  MODIFY subtitle_en VARCHAR(120) NULL,
  MODIFY title_ar VARCHAR(120) NULL,
  MODIFY subtitle_ar VARCHAR(120) NULL,
  ADD COLUMN link_type VARCHAR(10) CHARACTER SET ascii COLLATE ascii_bin NULL,
  ADD COLUMN link_id BIGINT UNSIGNED NULL,
  ADD CONSTRAINT ck_home_banners_link CHECK ((link_type IS NULL) = (link_id IS NULL)
                                             AND (link_type IS NULL OR link_type IN ('PRODUCT', 'STORE', 'CATEGORY')));

ALTER TABLE brands
  ADD COLUMN name_ar VARCHAR(60) NULL,
  ADD COLUMN status VARCHAR(10) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'APPROVED',
  ADD CONSTRAINT ck_brands_status CHECK (status IN ('APPROVED', 'PENDING'));
