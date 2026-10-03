-- Saba v1 schema: every table in DATABASE_DESIGN.md, in foreign-key order.
-- Codes (statuses, governorates, phones, coupon codes) are ascii_bin, so a
-- lowercase 'pending' can't slip past a CHECK that a case-insensitive
-- collation would let through. Money is whole IQD in BIGINT.

CREATE TABLE governorates (
  code        VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  name_en     VARCHAR(40) NOT NULL,
  name_ar     VARCHAR(40) NOT NULL,
  sort_order  TINYINT UNSIGNED NOT NULL,
  PRIMARY KEY (code),
  UNIQUE KEY uq_governorates_sort_order (sort_order)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ------------------------------------------------------------ people ---

CREATE TABLE users (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  role               VARCHAR(8) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  status             VARCHAR(10) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'ACTIVE',
  full_name          VARCHAR(50) NOT NULL,
  full_name_ar       VARCHAR(50) NULL,
  phone              VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NULL,
  phone_digits       VARCHAR(12) CHARACTER SET ascii COLLATE ascii_bin
                       GENERATED ALWAYS AS (SUBSTRING(phone, 5)) STORED,
  email              VARCHAR(254) NULL,
  password_hash      VARCHAR(255) CHARACTER SET ascii COLLATE ascii_bin NULL,
  governorate        VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NULL,
  country            VARCHAR(40) NOT NULL DEFAULT 'Iraq',
  suspension_reason  VARCHAR(500) NULL,
  search_text        VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  created_at         DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at         DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  deleted_at         DATETIME(3) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_users_phone (phone),
  UNIQUE KEY uq_users_email (email),
  KEY ix_users_role_status_created (role, status, created_at),
  CONSTRAINT fk_users_governorate FOREIGN KEY (governorate) REFERENCES governorates (code),
  CONSTRAINT ck_users_role CHECK (role IN ('CUSTOMER', 'MERCHANT', 'ADMIN')),
  CONSTRAINT ck_users_status CHECK (status IN ('ACTIVE', 'SUSPENDED', 'DELETED')),
  CONSTRAINT ck_users_phone CHECK (phone IS NULL OR phone REGEXP '^[+]9647[0-9]{9}$'),
  CONSTRAINT ck_users_live_phone CHECK (status = 'DELETED' OR phone IS NOT NULL),
  CONSTRAINT ck_users_suspension CHECK (status <> 'SUSPENDED' OR suspension_reason IS NOT NULL)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE refresh_tokens (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id         BIGINT UNSIGNED NOT NULL,
  token_hash      BINARY(32) NOT NULL,
  family_id       BINARY(16) NOT NULL,
  expires_at      DATETIME(3) NOT NULL,
  revoked_at      DATETIME(3) NULL,
  replaced_by_id  BIGINT UNSIGNED NULL,
  user_agent      VARCHAR(255) NULL,
  ip              VARCHAR(45) CHARACTER SET ascii COLLATE ascii_bin NULL,
  created_at      DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at      DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_refresh_tokens_hash (token_hash),
  KEY ix_refresh_tokens_user (user_id),
  KEY ix_refresh_tokens_family (family_id),
  CONSTRAINT fk_refresh_tokens_user FOREIGN KEY (user_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE otp_challenges (
  id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  phone        VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  purpose      VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  code_hash    BINARY(32) NOT NULL,
  attempts     TINYINT UNSIGNED NOT NULL DEFAULT 0,
  expires_at   DATETIME(3) NOT NULL,
  verified_at  DATETIME(3) NULL,
  consumed_at  DATETIME(3) NULL,
  ip           VARCHAR(45) CHARACTER SET ascii COLLATE ascii_bin NULL,
  created_at   DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at   DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY ix_otp_challenges_phone_purpose_created (phone, purpose, created_at),
  CONSTRAINT ck_otp_challenges_purpose CHECK (purpose IN ('SIGN_UP', 'PASSWORD_RESET', 'OTHER')),
  CONSTRAINT ck_otp_challenges_phone CHECK (phone REGEXP '^[+]9647[0-9]{9}$'),
  CONSTRAINT ck_otp_challenges_consumed CHECK (consumed_at IS NULL OR verified_at IS NOT NULL)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE admin_actions (
  id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  admin_user_id  BIGINT UNSIGNED NOT NULL,
  action         VARCHAR(30) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  entity_type    VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  entity_id      VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  reason         VARCHAR(500) NULL,
  details        JSON NULL,
  ip             VARCHAR(45) CHARACTER SET ascii COLLATE ascii_bin NULL,
  created_at     DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY ix_admin_actions_entity (entity_type, entity_id, created_at),
  KEY ix_admin_actions_admin (admin_user_id, created_at),
  CONSTRAINT fk_admin_actions_admin FOREIGN KEY (admin_user_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ------------------------------------------------------------ stores ---

CREATE TABLE stores (
  id                   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  owner_user_id        BIGINT UNSIGNED NOT NULL,
  store_name           VARCHAR(40) NOT NULL,
  name_key             VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL,
  status               VARCHAR(10) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'PENDING',
  rejection_reason     VARCHAR(500) NULL,
  suspension_reason    VARCHAR(500) NULL,
  submitted_at         DATETIME(3) NOT NULL,
  answered_at          DATETIME(3) NULL,
  governorate          VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  country              VARCHAR(40) NOT NULL DEFAULT 'Iraq',
  business_type        VARCHAR(20) NULL,
  business_address     VARCHAR(200) NULL,
  business_address_ar  VARCHAR(200) NULL,
  description          VARCHAR(1000) NULL,
  description_ar       VARCHAR(1000) NULL,
  logo_url             VARCHAR(500) NULL,
  banner_url           VARCHAR(500) NULL,
  is_open              TINYINT(1) NOT NULL DEFAULT 1,
  fee_inside           INT NULL,
  time_inside          VARCHAR(10) CHARACTER SET ascii COLLATE ascii_bin NULL,
  fee_outside          INT NULL,
  time_outside         VARCHAR(10) CHARACTER SET ascii COLLATE ascii_bin NULL,
  rating_sum           INT UNSIGNED NOT NULL DEFAULT 0,
  rating_count         INT UNSIGNED NOT NULL DEFAULT 0,
  search_text          VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  created_at           DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at           DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_stores_owner (owner_user_id),
  UNIQUE KEY uq_stores_governorate_name_key (governorate, name_key),
  KEY ix_stores_status_submitted (status, submitted_at),
  KEY ix_stores_status_open_governorate (status, is_open, governorate),
  CONSTRAINT fk_stores_owner FOREIGN KEY (owner_user_id) REFERENCES users (id),
  CONSTRAINT fk_stores_governorate FOREIGN KEY (governorate) REFERENCES governorates (code),
  CONSTRAINT ck_stores_status CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED', 'SUSPENDED')),
  CONSTRAINT ck_stores_fee_inside CHECK (fee_inside IS NULL OR (fee_inside >= 0 AND fee_inside % 250 = 0)),
  CONSTRAINT ck_stores_fee_outside CHECK (fee_outside IS NULL OR (fee_outside >= 0 AND fee_outside % 250 = 0)),
  CONSTRAINT ck_stores_inside_pair CHECK ((fee_inside IS NULL) = (time_inside IS NULL)),
  CONSTRAINT ck_stores_outside_pair CHECK ((fee_outside IS NULL) = (time_outside IS NULL)),
  CONSTRAINT ck_stores_time_inside CHECK (time_inside IS NULL OR time_inside IN ('SAME_DAY', '1_2_DAYS', '2_3_DAYS', '3_5_DAYS', '5_7_DAYS')),
  CONSTRAINT ck_stores_time_outside CHECK (time_outside IS NULL OR time_outside IN ('SAME_DAY', '1_2_DAYS', '2_3_DAYS', '3_5_DAYS', '5_7_DAYS')),
  CONSTRAINT ck_stores_rejection CHECK (status <> 'REJECTED' OR rejection_reason IS NOT NULL),
  CONSTRAINT ck_stores_suspension CHECK (status <> 'SUSPENDED' OR suspension_reason IS NOT NULL)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE store_delivery_governorates (
  store_id     BIGINT UNSIGNED NOT NULL,
  governorate  VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  PRIMARY KEY (store_id, governorate),
  KEY ix_store_delivery_governorates_governorate (governorate, store_id),
  CONSTRAINT fk_store_delivery_governorates_store FOREIGN KEY (store_id) REFERENCES stores (id) ON DELETE CASCADE,
  CONSTRAINT fk_store_delivery_governorates_governorate FOREIGN KEY (governorate) REFERENCES governorates (code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE featured_stores (
  store_id  BIGINT UNSIGNED NOT NULL,
  position  SMALLINT UNSIGNED NOT NULL,
  PRIMARY KEY (store_id),
  UNIQUE KEY uq_featured_stores_position (position),
  CONSTRAINT fk_featured_stores_store FOREIGN KEY (store_id) REFERENCES stores (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- --------------------------------------------------------- catalogue ---

CREATE TABLE categories (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  parent_id   BIGINT UNSIGNED NULL,
  name        VARCHAR(60) NOT NULL,
  name_ar     VARCHAR(60) NOT NULL,
  image_url   VARCHAR(500) NULL,
  position    SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  created_at  DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at  DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY ix_categories_parent_position (parent_id, position),
  CONSTRAINT fk_categories_parent FOREIGN KEY (parent_id) REFERENCES categories (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE brands (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  name        VARCHAR(60) NOT NULL,
  created_at  DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at  DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_brands_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE media_files (
  id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  owner_user_id  BIGINT UNSIGNED NOT NULL,
  storage_key    VARCHAR(200) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  content_type   VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  byte_size      INT UNSIGNED NOT NULL,
  created_at     DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  deleted_at     DATETIME(3) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_media_files_storage_key (storage_key),
  KEY ix_media_files_owner (owner_user_id),
  CONSTRAINT fk_media_files_owner FOREIGN KEY (owner_user_id) REFERENCES users (id),
  CONSTRAINT ck_media_files_content_type CHECK (content_type IN ('image/jpeg', 'image/png', 'image/webp'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE products (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  store_id           BIGINT UNSIGNED NOT NULL,
  category_id        BIGINT UNSIGNED NOT NULL,
  brand_id           BIGINT UNSIGNED NULL,
  name_en            VARCHAR(120) NULL,
  name_ar            VARCHAR(120) NOT NULL,
  description        TEXT NULL,
  description_ar     TEXT NULL,
  warranty           VARCHAR(120) NULL,
  warranty_ar        VARCHAR(120) NULL,
  base_price         BIGINT NOT NULL,
  compare_at_price   BIGINT NULL,
  sale_price         BIGINT NULL,
  sale_ends_at       DATETIME(3) NULL,
  status             VARCHAR(8) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'PENDING',
  rejection_reason   VARCHAR(500) NULL,
  is_active          TINYINT(1) NOT NULL DEFAULT 1,
  taken_down         TINYINT(1) NOT NULL DEFAULT 0,
  taken_down_reason  VARCHAR(500) NULL,
  option_colours     JSON NULL,
  size_guide         TEXT NULL,
  submitted_at       DATETIME(3) NULL,
  search_text        VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  created_at         DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at         DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  deleted_at         DATETIME(3) NULL,
  PRIMARY KEY (id),
  KEY ix_products_store_status (store_id, status, deleted_at),
  KEY ix_products_category_status (category_id, status),
  KEY ix_products_status_submitted (status, submitted_at),
  KEY ix_products_sale_ends (sale_ends_at),
  CONSTRAINT fk_products_store FOREIGN KEY (store_id) REFERENCES stores (id),
  CONSTRAINT fk_products_category FOREIGN KEY (category_id) REFERENCES categories (id),
  CONSTRAINT fk_products_brand FOREIGN KEY (brand_id) REFERENCES brands (id),
  CONSTRAINT ck_products_status CHECK (status IN ('DRAFT', 'PENDING', 'APPROVED', 'REJECTED')),
  CONSTRAINT ck_products_name_ar CHECK (CHAR_LENGTH(TRIM(name_ar)) >= 3),
  CONSTRAINT ck_products_base_price CHECK (base_price > 0 AND base_price % 250 = 0),
  CONSTRAINT ck_products_compare_at CHECK (compare_at_price IS NULL OR (compare_at_price > base_price AND compare_at_price % 250 = 0)),
  CONSTRAINT ck_products_sale_pair CHECK ((sale_price IS NULL) = (sale_ends_at IS NULL)),
  CONSTRAINT ck_products_sale_price CHECK (sale_price IS NULL OR (sale_price > 0 AND sale_price < base_price AND sale_price % 250 = 0)),
  CONSTRAINT ck_products_rejection CHECK (status <> 'REJECTED' OR rejection_reason IS NOT NULL),
  CONSTRAINT ck_products_taken_down CHECK (taken_down = 0 OR taken_down_reason IS NOT NULL)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE product_images (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  product_id  BIGINT UNSIGNED NOT NULL,
  url         VARCHAR(500) NOT NULL,
  position    TINYINT UNSIGNED NOT NULL,
  created_at  DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_product_images_product_position (product_id, position),
  CONSTRAINT fk_product_images_product FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE product_skus (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  product_id    BIGINT UNSIGNED NOT NULL,
  options       JSON NULL,
  option_label  VARCHAR(120) NULL,
  sku_code      VARCHAR(40) NULL,
  price         BIGINT NULL,
  image_url     VARCHAR(500) NULL,
  stock         INT NOT NULL DEFAULT 0,
  created_at    DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at    DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  deleted_at    DATETIME(3) NULL,
  PRIMARY KEY (id),
  KEY ix_product_skus_product (product_id, deleted_at),
  CONSTRAINT fk_product_skus_product FOREIGN KEY (product_id) REFERENCES products (id),
  CONSTRAINT ck_product_skus_stock CHECK (stock >= 0),
  CONSTRAINT ck_product_skus_price CHECK (price IS NULL OR (price > 0 AND price % 250 = 0)),
  CONSTRAINT ck_product_skus_options_label CHECK ((options IS NULL) = (option_label IS NULL)),
  CONSTRAINT ck_product_skus_options_price CHECK ((options IS NULL) = (price IS NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------- shopping ---

CREATE TABLE addresses (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id       BIGINT UNSIGNED NOT NULL,
  label         VARCHAR(30) NOT NULL,
  full_name     VARCHAR(50) NOT NULL,
  full_name_ar  VARCHAR(50) NULL,
  phone         VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  governorate   VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  area          VARCHAR(100) NOT NULL,
  area_ar       VARCHAR(100) NULL,
  street        VARCHAR(150) NULL,
  street_ar     VARCHAR(150) NULL,
  landmark      VARCHAR(150) NOT NULL,
  landmark_ar   VARCHAR(150) NULL,
  instructions  VARCHAR(300) NULL,
  is_default    TINYINT(1) NOT NULL DEFAULT 0,
  default_for   BIGINT UNSIGNED GENERATED ALWAYS AS (IF(is_default = 1, user_id, NULL)) STORED,
  created_at    DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at    DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY ix_addresses_user (user_id),
  UNIQUE KEY uq_addresses_default_for (default_for),
  CONSTRAINT fk_addresses_user FOREIGN KEY (user_id) REFERENCES users (id),
  CONSTRAINT fk_addresses_governorate FOREIGN KEY (governorate) REFERENCES governorates (code),
  CONSTRAINT ck_addresses_phone CHECK (phone REGEXP '^[+]9647[0-9]{9}$'),
  CONSTRAINT ck_addresses_area_landmark CHECK (CHAR_LENGTH(TRIM(area)) > 0 AND CHAR_LENGTH(TRIM(landmark)) > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE coupons (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  store_id          BIGINT UNSIGNED NOT NULL,
  code              VARCHAR(15) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  discount_type     VARCHAR(10) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  value             INT NOT NULL,
  min_order_amount  BIGINT NULL,
  starts_at         DATETIME(3) NOT NULL,
  ends_at           DATETIME(3) NULL,
  usage_limit       INT UNSIGNED NULL,
  used_count        INT UNSIGNED NOT NULL DEFAULT 0,
  is_active         TINYINT(1) NOT NULL DEFAULT 1,
  created_at        DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at        DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_coupons_code (code),
  KEY ix_coupons_store (store_id),
  CONSTRAINT fk_coupons_store FOREIGN KEY (store_id) REFERENCES stores (id),
  CONSTRAINT ck_coupons_code CHECK (code REGEXP '^[A-Z0-9]{3,15}$'),
  CONSTRAINT ck_coupons_discount_type CHECK (discount_type IN ('PERCENTAGE', 'FIXED')),
  CONSTRAINT ck_coupons_value CHECK (value > 0),
  CONSTRAINT ck_coupons_percentage CHECK (discount_type <> 'PERCENTAGE' OR value <= 90),
  CONSTRAINT ck_coupons_fixed CHECK (discount_type <> 'FIXED' OR value % 250 = 0),
  CONSTRAINT ck_coupons_min_order CHECK (min_order_amount IS NULL OR min_order_amount > 0),
  CONSTRAINT ck_coupons_dates CHECK (ends_at IS NULL OR ends_at > starts_at),
  CONSTRAINT ck_coupons_usage CHECK (usage_limit IS NULL OR used_count <= usage_limit)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE carts (
  user_id     BIGINT UNSIGNED NOT NULL,
  coupon_id   BIGINT UNSIGNED NULL,
  created_at  DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at  DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (user_id),
  CONSTRAINT fk_carts_user FOREIGN KEY (user_id) REFERENCES users (id),
  CONSTRAINT fk_carts_coupon FOREIGN KEY (coupon_id) REFERENCES coupons (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE cart_items (
  id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id          BIGINT UNSIGNED NOT NULL,
  sku_id           BIGINT UNSIGNED NOT NULL,
  quantity         SMALLINT UNSIGNED NOT NULL,
  saved_for_later  TINYINT(1) NOT NULL DEFAULT 0,
  created_at       DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at       DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_cart_items_user_sku_saved (user_id, sku_id, saved_for_later),
  CONSTRAINT fk_cart_items_user FOREIGN KEY (user_id) REFERENCES users (id),
  CONSTRAINT fk_cart_items_sku FOREIGN KEY (sku_id) REFERENCES product_skus (id),
  CONSTRAINT ck_cart_items_quantity CHECK (quantity BETWEEN 1 AND 999)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE wishlist_items (
  user_id     BIGINT UNSIGNED NOT NULL,
  product_id  BIGINT UNSIGNED NOT NULL,
  created_at  DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (user_id, product_id),
  CONSTRAINT fk_wishlist_items_user FOREIGN KEY (user_id) REFERENCES users (id),
  CONSTRAINT fk_wishlist_items_product FOREIGN KEY (product_id) REFERENCES products (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ------------------------------------------------------------ orders ---

CREATE TABLE orders (
  id                     BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  order_number           VARCHAR(12) CHARACTER SET ascii COLLATE ascii_bin NULL,
  customer_id            BIGINT UNSIGNED NOT NULL,
  status                 VARCHAR(10) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'PENDING',
  payment_status         VARCHAR(10) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'PENDING',
  payment_method         VARCHAR(4) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'COD',
  subtotal               BIGINT NOT NULL,
  discount               BIGINT NOT NULL DEFAULT 0,
  shipping               BIGINT NOT NULL,
  total                  BIGINT NOT NULL,
  item_count             SMALLINT UNSIGNED NOT NULL,
  coupon_id              BIGINT UNSIGNED NULL,
  coupon_code            VARCHAR(15) CHARACTER SET ascii COLLATE ascii_bin NULL,
  customer_name          VARCHAR(50) NOT NULL,
  customer_name_ar       VARCHAR(50) NULL,
  customer_phone         VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  customer_phone_digits  VARCHAR(12) CHARACTER SET ascii COLLATE ascii_bin
                           GENERATED ALWAYS AS (SUBSTRING(customer_phone, 5)) STORED,
  ship_governorate       VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  ship_area              VARCHAR(100) NOT NULL,
  ship_area_ar           VARCHAR(100) NULL,
  ship_street            VARCHAR(150) NULL,
  ship_street_ar         VARCHAR(150) NULL,
  ship_landmark          VARCHAR(150) NOT NULL,
  ship_landmark_ar       VARCHAR(150) NULL,
  instructions           VARCHAR(300) NULL,
  placed_at              DATETIME(3) NOT NULL,
  delivered_at           DATETIME(3) NULL,
  cancelled_at           DATETIME(3) NULL,
  cancelled_by           VARCHAR(8) CHARACTER SET ascii COLLATE ascii_bin NULL,
  cancel_reason          VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NULL,
  cancel_note            VARCHAR(500) NULL,
  rated_at               DATETIME(3) NULL,
  rating_skips           TINYINT UNSIGNED NOT NULL DEFAULT 0,
  search_text            TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL,
  created_at             DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at             DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_orders_order_number (order_number),
  KEY ix_orders_customer_placed (customer_id, placed_at),
  KEY ix_orders_status_placed (status, placed_at),
  KEY ix_orders_placed (placed_at),
  CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id) REFERENCES users (id),
  CONSTRAINT fk_orders_coupon FOREIGN KEY (coupon_id) REFERENCES coupons (id) ON DELETE SET NULL,
  CONSTRAINT fk_orders_ship_governorate FOREIGN KEY (ship_governorate) REFERENCES governorates (code),
  CONSTRAINT ck_orders_status CHECK (status IN ('PENDING', 'CONFIRMED', 'PROCESSING', 'SHIPPED', 'DELIVERED', 'CANCELLED', 'REFUSED')),
  CONSTRAINT ck_orders_payment_status CHECK (payment_status IN ('PENDING', 'PAID', 'CANCELLED')),
  CONSTRAINT ck_orders_payment_method CHECK (payment_method = 'COD'),
  CONSTRAINT ck_orders_money_steps CHECK (subtotal >= 0 AND subtotal % 250 = 0 AND discount >= 0 AND discount % 250 = 0 AND shipping >= 0 AND shipping % 250 = 0),
  CONSTRAINT ck_orders_discount CHECK (discount <= subtotal),
  CONSTRAINT ck_orders_total CHECK (total = subtotal - discount + shipping),
  CONSTRAINT ck_orders_item_count CHECK (item_count > 0),
  CONSTRAINT ck_orders_paid CHECK ((payment_status = 'PAID') = (status = 'DELIVERED')),
  CONSTRAINT ck_orders_payment_cancelled CHECK ((payment_status = 'CANCELLED') = (status IN ('CANCELLED', 'REFUSED'))),
  CONSTRAINT ck_orders_delivered_at CHECK (status <> 'DELIVERED' OR delivered_at IS NOT NULL),
  CONSTRAINT ck_orders_cancelled_at CHECK (status <> 'CANCELLED' OR cancelled_at IS NOT NULL),
  CONSTRAINT ck_orders_cancelled_by CHECK (cancelled_by IS NULL OR cancelled_by IN ('SHOPPER', 'STORE')),
  CONSTRAINT ck_orders_customer_phone CHECK (customer_phone REGEXP '^[+]9647[0-9]{9}$')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE order_store_parts (
  id                   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  order_id             BIGINT UNSIGNED NOT NULL,
  store_id             BIGINT UNSIGNED NOT NULL,
  status               VARCHAR(10) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'PENDING',
  subtotal             BIGINT NOT NULL,
  discount             BIGINT NOT NULL DEFAULT 0,
  shipping_fee         BIGINT NOT NULL,
  amount_due           BIGINT NOT NULL,
  item_count           SMALLINT UNSIGNED NOT NULL,
  delivery_time        VARCHAR(10) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  courier_name         VARCHAR(50) NULL,
  courier_name_ar      VARCHAR(50) NULL,
  courier_phone        VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NULL,
  cancellation_reason  VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NULL,
  received             TINYINT(1) NULL,
  confirmed_at         DATETIME(3) NULL,
  shipped_at           DATETIME(3) NULL,
  delivered_at         DATETIME(3) NULL,
  cancelled_at         DATETIME(3) NULL,
  billing_month        DATE NULL,
  created_at           DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at           DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_order_store_parts_order_store (order_id, store_id),
  KEY ix_order_store_parts_store_status (store_id, status, created_at),
  KEY ix_order_store_parts_store_billing (store_id, billing_month),
  CONSTRAINT fk_order_store_parts_order FOREIGN KEY (order_id) REFERENCES orders (id),
  CONSTRAINT fk_order_store_parts_store FOREIGN KEY (store_id) REFERENCES stores (id),
  CONSTRAINT ck_order_store_parts_status CHECK (status IN ('PENDING', 'CONFIRMED', 'PROCESSING', 'SHIPPED', 'DELIVERED', 'CANCELLED', 'REFUSED')),
  CONSTRAINT ck_order_store_parts_money_steps CHECK (subtotal >= 0 AND subtotal % 250 = 0 AND discount >= 0 AND discount % 250 = 0 AND shipping_fee >= 0 AND shipping_fee % 250 = 0),
  CONSTRAINT ck_order_store_parts_discount CHECK (discount <= subtotal),
  CONSTRAINT ck_order_store_parts_amount_due CHECK (amount_due = subtotal - discount + shipping_fee),
  CONSTRAINT ck_order_store_parts_item_count CHECK (item_count > 0),
  CONSTRAINT ck_order_store_parts_delivery_time CHECK (delivery_time IN ('SAME_DAY', '1_2_DAYS', '2_3_DAYS', '3_5_DAYS', '5_7_DAYS')),
  CONSTRAINT ck_order_store_parts_billing_month CHECK ((status = 'DELIVERED') = (billing_month IS NOT NULL)),
  CONSTRAINT ck_order_store_parts_billing_first_day CHECK (billing_month IS NULL OR DAY(billing_month) = 1),
  CONSTRAINT ck_order_store_parts_delivered_at CHECK (status <> 'DELIVERED' OR delivered_at IS NOT NULL),
  CONSTRAINT ck_order_store_parts_cancellation CHECK ((status = 'CANCELLED') = (cancellation_reason IS NOT NULL)),
  CONSTRAINT ck_order_store_parts_cancellation_code CHECK (cancellation_reason IS NULL OR cancellation_reason IN ('OUT_OF_STOCK', 'CANNOT_FULFIL', 'ADDRESS_PROBLEM', 'CUSTOMER_ASKED', 'CUSTOMER_CANCELLED')),
  CONSTRAINT ck_order_store_parts_courier CHECK (status NOT IN ('SHIPPED', 'DELIVERED', 'REFUSED') OR (courier_name IS NOT NULL AND courier_phone IS NOT NULL)),
  CONSTRAINT ck_order_store_parts_courier_phone CHECK (courier_phone IS NULL OR courier_phone REGEXP '^[+]9647[0-9]{9}$')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE order_items (
  id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  order_id         BIGINT UNSIGNED NOT NULL,
  part_id          BIGINT UNSIGNED NOT NULL,
  product_id       BIGINT UNSIGNED NOT NULL,
  sku_id           BIGINT UNSIGNED NOT NULL,
  product_name     VARCHAR(120) NOT NULL,
  product_name_ar  VARCHAR(120) NULL,
  variant_label    VARCHAR(120) NULL,
  sku_code         VARCHAR(40) NULL,
  image_url        VARCHAR(500) NULL,
  store_name       VARCHAR(40) NOT NULL,
  unit_price       BIGINT NOT NULL,
  paid_unit_price  BIGINT NOT NULL,
  quantity         SMALLINT UNSIGNED NOT NULL,
  line_total       BIGINT NOT NULL,
  created_at       DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY ix_order_items_order (order_id),
  KEY ix_order_items_part (part_id),
  KEY ix_order_items_product (product_id),
  CONSTRAINT fk_order_items_order FOREIGN KEY (order_id) REFERENCES orders (id),
  CONSTRAINT fk_order_items_part FOREIGN KEY (part_id) REFERENCES order_store_parts (id),
  CONSTRAINT fk_order_items_product FOREIGN KEY (product_id) REFERENCES products (id),
  CONSTRAINT fk_order_items_sku FOREIGN KEY (sku_id) REFERENCES product_skus (id),
  CONSTRAINT ck_order_items_quantity CHECK (quantity > 0),
  CONSTRAINT ck_order_items_unit_price CHECK (unit_price > 0 AND unit_price % 250 = 0),
  CONSTRAINT ck_order_items_paid_unit_price CHECK (paid_unit_price >= 0 AND paid_unit_price <= unit_price AND paid_unit_price % 250 = 0),
  CONSTRAINT ck_order_items_line_total CHECK (line_total = unit_price * quantity)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE order_events (
  id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  order_id     BIGINT UNSIGNED NOT NULL,
  part_id      BIGINT UNSIGNED NULL,
  status       VARCHAR(10) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  note_code    VARCHAR(30) CHARACTER SET ascii COLLATE ascii_bin NULL,
  reason_code  VARCHAR(30) CHARACTER SET ascii COLLATE ascii_bin NULL,
  note         VARCHAR(500) NULL,
  store_name   VARCHAR(40) NULL,
  occurred_at  DATETIME(3) NOT NULL,
  PRIMARY KEY (id),
  KEY ix_order_events_order (order_id, occurred_at),
  CONSTRAINT fk_order_events_order FOREIGN KEY (order_id) REFERENCES orders (id),
  CONSTRAINT fk_order_events_part FOREIGN KEY (part_id) REFERENCES order_store_parts (id),
  CONSTRAINT ck_order_events_status CHECK (status IN ('PENDING', 'CONFIRMED', 'PROCESSING', 'SHIPPED', 'DELIVERED', 'CANCELLED', 'REFUSED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE idempotency_keys (
  user_id       BIGINT UNSIGNED NOT NULL,
  idem_key      VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  request_hash  BINARY(32) NOT NULL,
  response      JSON NOT NULL,
  created_at    DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (user_id, idem_key),
  KEY ix_idempotency_keys_created (created_at),
  CONSTRAINT fk_idempotency_keys_user FOREIGN KEY (user_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ------------------------------------------------------ after a sale ---

CREATE TABLE returns (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  order_id          BIGINT UNSIGNED NOT NULL,
  part_id           BIGINT UNSIGNED NOT NULL,
  store_id          BIGINT UNSIGNED NOT NULL,
  customer_id       BIGINT UNSIGNED NOT NULL,
  status            VARCHAR(10) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'REQUESTED',
  reason            VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  description       VARCHAR(1000) NULL,
  rejection_reason  VARCHAR(12) CHARACTER SET ascii COLLATE ascii_bin NULL,
  refund_amount     BIGINT NOT NULL,
  requested_at      DATETIME(3) NOT NULL,
  answered_at       DATETIME(3) NULL,
  refunded_at       DATETIME(3) NULL,
  refund_month      DATE NULL,
  created_at        DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at        DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY ix_returns_store_status (store_id, status, requested_at),
  KEY ix_returns_customer (customer_id, requested_at),
  KEY ix_returns_store_refund_month (store_id, refund_month),
  KEY ix_returns_order (order_id),
  CONSTRAINT fk_returns_order FOREIGN KEY (order_id) REFERENCES orders (id),
  CONSTRAINT fk_returns_part FOREIGN KEY (part_id) REFERENCES order_store_parts (id),
  CONSTRAINT fk_returns_store FOREIGN KEY (store_id) REFERENCES stores (id),
  CONSTRAINT fk_returns_customer FOREIGN KEY (customer_id) REFERENCES users (id),
  CONSTRAINT ck_returns_status CHECK (status IN ('REQUESTED', 'APPROVED', 'REJECTED', 'REFUNDED')),
  CONSTRAINT ck_returns_reason CHECK (reason IN ('DAMAGED', 'WRONG_ITEM', 'NOT_AS_DESCRIBED', 'MISSING_PARTS', 'CHANGED_MIND', 'OTHER')),
  CONSTRAINT ck_returns_rejection CHECK ((status = 'REJECTED') = (rejection_reason IS NOT NULL)),
  CONSTRAINT ck_returns_rejection_code CHECK (rejection_reason IS NULL OR rejection_reason IN ('USED', 'INCOMPLETE', 'NOT_AS_SAID', 'OTHER')),
  CONSTRAINT ck_returns_answered CHECK (status = 'REQUESTED' OR answered_at IS NOT NULL),
  CONSTRAINT ck_returns_refunded_at CHECK ((status = 'REFUNDED') = (refunded_at IS NOT NULL)),
  CONSTRAINT ck_returns_refund_month CHECK ((status = 'REFUNDED') = (refund_month IS NOT NULL)),
  CONSTRAINT ck_returns_refund_first_day CHECK (refund_month IS NULL OR DAY(refund_month) = 1),
  CONSTRAINT ck_returns_refund_amount CHECK (refund_amount >= 0 AND refund_amount % 250 = 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE return_items (
  id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  return_id      BIGINT UNSIGNED NOT NULL,
  order_item_id  BIGINT UNSIGNED NOT NULL,
  quantity       SMALLINT UNSIGNED NOT NULL,
  refund_amount  BIGINT NOT NULL,
  created_at     DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_return_items_order_item (order_item_id),
  KEY ix_return_items_return (return_id),
  CONSTRAINT fk_return_items_return FOREIGN KEY (return_id) REFERENCES returns (id),
  CONSTRAINT fk_return_items_order_item FOREIGN KEY (order_item_id) REFERENCES order_items (id),
  CONSTRAINT ck_return_items_quantity CHECK (quantity > 0),
  CONSTRAINT ck_return_items_refund_amount CHECK (refund_amount >= 0 AND refund_amount % 250 = 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE stock_movements (
  id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  sku_id         BIGINT UNSIGNED NOT NULL,
  delta          INT NOT NULL,
  reason         VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  part_id        BIGINT UNSIGNED NULL,
  return_id      BIGINT UNSIGNED NULL,
  actor_user_id  BIGINT UNSIGNED NULL,
  created_at     DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY ix_stock_movements_sku (sku_id, created_at),
  CONSTRAINT fk_stock_movements_sku FOREIGN KEY (sku_id) REFERENCES product_skus (id),
  CONSTRAINT fk_stock_movements_part FOREIGN KEY (part_id) REFERENCES order_store_parts (id),
  CONSTRAINT fk_stock_movements_return FOREIGN KEY (return_id) REFERENCES returns (id),
  CONSTRAINT fk_stock_movements_actor FOREIGN KEY (actor_user_id) REFERENCES users (id),
  CONSTRAINT ck_stock_movements_delta CHECK (delta <> 0),
  CONSTRAINT ck_stock_movements_reason CHECK (reason IN ('ORDER_PLACED', 'ORDER_CANCELLED', 'PART_DECLINED', 'PART_REFUSED', 'RETURN_REFUNDED', 'ADJUSTED', 'SET', 'PRODUCT_SAVED', 'SEEDED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE store_reviews (
  id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  store_id     BIGINT UNSIGNED NOT NULL,
  order_id     BIGINT UNSIGNED NOT NULL,
  customer_id  BIGINT UNSIGNED NOT NULL,
  rating       TINYINT UNSIGNED NOT NULL,
  body         VARCHAR(1000) NULL,
  created_at   DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_store_reviews_order_store (order_id, store_id),
  KEY ix_store_reviews_store (store_id, created_at),
  CONSTRAINT fk_store_reviews_store FOREIGN KEY (store_id) REFERENCES stores (id),
  CONSTRAINT fk_store_reviews_order FOREIGN KEY (order_id) REFERENCES orders (id),
  CONSTRAINT fk_store_reviews_customer FOREIGN KEY (customer_id) REFERENCES users (id),
  CONSTRAINT ck_store_reviews_rating CHECK (rating BETWEEN 1 AND 5)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE review_reports (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  review_id         BIGINT UNSIGNED NOT NULL,
  reporter_user_id  BIGINT UNSIGNED NOT NULL,
  reason            VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  created_at        DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_review_reports_review_reporter (review_id, reporter_user_id),
  CONSTRAINT fk_review_reports_review FOREIGN KEY (review_id) REFERENCES store_reviews (id),
  CONSTRAINT fk_review_reports_reporter FOREIGN KEY (reporter_user_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ------------------------------------------------------------- money ---

CREATE TABLE bill_payments (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  store_id      BIGINT UNSIGNED NOT NULL,
  month         DATE NOT NULL,
  paid_on       DATE NOT NULL,
  owed          BIGINT NOT NULL,
  rate_percent  TINYINT UNSIGNED NOT NULL,
  recorded_by   BIGINT UNSIGNED NOT NULL,
  created_at    DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_bill_payments_store_month (store_id, month),
  CONSTRAINT fk_bill_payments_store FOREIGN KEY (store_id) REFERENCES stores (id),
  CONSTRAINT fk_bill_payments_recorded_by FOREIGN KEY (recorded_by) REFERENCES users (id),
  CONSTRAINT ck_bill_payments_month CHECK (DAY(month) = 1),
  CONSTRAINT ck_bill_payments_paid_on CHECK (paid_on >= DATE_ADD(month, INTERVAL 1 MONTH)),
  CONSTRAINT ck_bill_payments_owed CHECK (owed > 0 AND owed % 250 = 0),
  CONSTRAINT ck_bill_payments_rate CHECK (rate_percent BETWEEN 1 AND 100)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ----------------------------------------------------------- talking ---

CREATE TABLE notifications (
  id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id      BIGINT UNSIGNED NOT NULL,
  type         VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  title_en     VARCHAR(300) NOT NULL,
  title_ar     VARCHAR(300) NOT NULL,
  body_en      VARCHAR(1000) NOT NULL,
  body_ar      VARCHAR(1000) NOT NULL,
  entity_type  VARCHAR(15) CHARACTER SET ascii COLLATE ascii_bin NULL,
  entity_id    VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NULL,
  is_read      TINYINT(1) NOT NULL DEFAULT 0,
  created_at   DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at   DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY ix_notifications_user (user_id, id),
  KEY ix_notifications_user_read (user_id, is_read),
  CONSTRAINT fk_notifications_user FOREIGN KEY (user_id) REFERENCES users (id),
  CONSTRAINT ck_notifications_type CHECK (type IN ('ORDER', 'SHIPPING', 'DELIVERY', 'PRODUCT_APPROVAL', 'STORE', 'MESSAGE', 'TICKET', 'PAYMENT')),
  CONSTRAINT ck_notifications_entity_type CHECK (entity_type IS NULL OR entity_type IN ('ORDER', 'STORE_ORDER', 'RETURN', 'STORE_PRODUCT', 'STORE', 'CONVERSATION', 'TICKET')),
  CONSTRAINT ck_notifications_both_languages CHECK (CHAR_LENGTH(TRIM(title_en)) > 0 AND CHAR_LENGTH(TRIM(title_ar)) > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE conversations (
  id                     BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  customer_id            BIGINT UNSIGNED NOT NULL,
  store_id               BIGINT UNSIGNED NOT NULL,
  customer_last_read_id  BIGINT UNSIGNED NULL,
  store_last_read_id     BIGINT UNSIGNED NULL,
  last_message_at        DATETIME(3) NULL,
  created_at             DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at             DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_conversations_customer_store (customer_id, store_id),
  KEY ix_conversations_store_last (store_id, last_message_at),
  KEY ix_conversations_customer_last (customer_id, last_message_at),
  CONSTRAINT fk_conversations_customer FOREIGN KEY (customer_id) REFERENCES users (id),
  CONSTRAINT fk_conversations_store FOREIGN KEY (store_id) REFERENCES stores (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE messages (
  id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  conversation_id  BIGINT UNSIGNED NOT NULL,
  sender           VARCHAR(8) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  body             VARCHAR(2000) NOT NULL,
  sent_at          DATETIME(3) NOT NULL,
  PRIMARY KEY (id),
  KEY ix_messages_conversation (conversation_id, id),
  CONSTRAINT fk_messages_conversation FOREIGN KEY (conversation_id) REFERENCES conversations (id),
  CONSTRAINT ck_messages_sender CHECK (sender IN ('CUSTOMER', 'STORE')),
  CONSTRAINT ck_messages_body CHECK (CHAR_LENGTH(TRIM(body)) > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE support_tickets (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  reference          VARCHAR(10) CHARACTER SET ascii COLLATE ascii_bin NULL,
  opened_by_user_id  BIGINT UNSIGNED NOT NULL,
  opened_by_kind     VARCHAR(8) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  store_id           BIGINT UNSIGNED NULL,
  opener_name        VARCHAR(50) NOT NULL,
  opener_phone       VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  subject            VARCHAR(120) NOT NULL,
  category           VARCHAR(10) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  status             VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'OPEN',
  last_message       VARCHAR(500) NOT NULL,
  created_at         DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at         DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_support_tickets_reference (reference),
  KEY ix_support_tickets_opener (opened_by_user_id, updated_at),
  KEY ix_support_tickets_status (status, updated_at),
  KEY ix_support_tickets_kind_status (opened_by_kind, status),
  CONSTRAINT fk_support_tickets_opener FOREIGN KEY (opened_by_user_id) REFERENCES users (id),
  CONSTRAINT fk_support_tickets_store FOREIGN KEY (store_id) REFERENCES stores (id),
  CONSTRAINT ck_support_tickets_kind CHECK (opened_by_kind IN ('SHOPPER', 'STORE')),
  CONSTRAINT ck_support_tickets_store CHECK ((opened_by_kind = 'STORE') = (store_id IS NOT NULL)),
  CONSTRAINT ck_support_tickets_category CHECK (category IN ('ORDER', 'PAYMENT', 'DELIVERY', 'RETURN', 'PRODUCT', 'ACCOUNT', 'OTHER')),
  CONSTRAINT ck_support_tickets_status CHECK (status IN ('OPEN', 'IN_PROGRESS', 'WAITING_FOR_CUSTOMER', 'RESOLVED', 'CLOSED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE support_messages (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  ticket_id         BIGINT UNSIGNED NOT NULL,
  body              VARCHAR(4000) NOT NULL,
  is_from_customer  TINYINT(1) NOT NULL,
  author_user_id    BIGINT UNSIGNED NOT NULL,
  sent_at           DATETIME(3) NOT NULL,
  PRIMARY KEY (id),
  KEY ix_support_messages_ticket (ticket_id, id),
  CONSTRAINT fk_support_messages_ticket FOREIGN KEY (ticket_id) REFERENCES support_tickets (id),
  CONSTRAINT fk_support_messages_author FOREIGN KEY (author_user_id) REFERENCES users (id),
  CONSTRAINT ck_support_messages_body CHECK (CHAR_LENGTH(TRIM(body)) > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- --------------------------------------------------- home and search ---

CREATE TABLE home_banners (
  id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  position     SMALLINT UNSIGNED NOT NULL,
  title_en     VARCHAR(120) NOT NULL,
  subtitle_en  VARCHAR(120) NOT NULL,
  title_ar     VARCHAR(120) NOT NULL,
  subtitle_ar  VARCHAR(120) NOT NULL,
  image_url    VARCHAR(500) NULL,
  is_active    TINYINT(1) NOT NULL DEFAULT 1,
  created_at   DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at   DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY ix_home_banners_position (position)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE search_terms (
  term_key      VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL,
  display_text  VARCHAR(100) NOT NULL,
  hits          INT UNSIGNED NOT NULL DEFAULT 0,
  created_at    DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at    DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (term_key),
  KEY ix_search_terms_hits (hits)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
