-- S10 push notifications (BACKEND_PLAN.md §7): each phone's push address, a
-- Firebase Cloud Messaging registration token. One row per token: a token that
-- signs in to another account moves to it, so one account's pushes never
-- reach the next person on that phone. The language is the phone's, sent by
-- the app with the token and again when it changes.
CREATE TABLE device_tokens (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  token       VARCHAR(1024) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  user_id     BIGINT UNSIGNED NOT NULL,
  platform    VARCHAR(8) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  language    CHAR(2) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  created_at  DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at  DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_device_tokens_token (token),
  KEY ix_device_tokens_user (user_id),
  CONSTRAINT fk_device_tokens_user FOREIGN KEY (user_id) REFERENCES users (id),
  CONSTRAINT ck_device_tokens_platform CHECK (platform IN ('ANDROID', 'IOS')),
  CONSTRAINT ck_device_tokens_language CHECK (language IN ('en', 'ar'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
