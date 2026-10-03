-- Report and block (the reviewer's item 3, 2026-09-30: Apple 1.2 and Google
-- require both for user-to-user content). A shopper or a store reports a
-- product, a store or a chat; Saba sees the reports grouped by what they are
-- about. A chat report keeps its last messages as evidence, since Saba has no
-- chat inbox. Either side of a chat can block the other: while one side has,
-- nobody writes in it.
CREATE TABLE reports (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  target_type       VARCHAR(12) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  target_id         BIGINT UNSIGNED NOT NULL,
  reporter_user_id  BIGINT UNSIGNED NOT NULL,
  reason            VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  description       VARCHAR(500) NULL,
  evidence          JSON NULL,
  status            VARCHAR(10) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'OPEN',
  created_at        DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  handled_at        DATETIME(3) NULL,
  handled_by        BIGINT UNSIGNED NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_reports_target_reporter (target_type, target_id, reporter_user_id),
  KEY ix_reports_status (status, created_at),
  CONSTRAINT fk_reports_reporter FOREIGN KEY (reporter_user_id) REFERENCES users (id),
  CONSTRAINT fk_reports_handled_by FOREIGN KEY (handled_by) REFERENCES users (id),
  CONSTRAINT ck_reports_target_type CHECK (target_type IN ('PRODUCT', 'STORE', 'CONVERSATION')),
  CONSTRAINT ck_reports_reason CHECK (reason IN ('COUNTERFEIT', 'PROHIBITED', 'MISLEADING', 'OFFENSIVE', 'SPAM', 'OTHER')),
  CONSTRAINT ck_reports_status CHECK (status IN ('OPEN', 'DISMISSED', 'ACTIONED')),
  CONSTRAINT ck_reports_handled CHECK ((status = 'OPEN') = (handled_at IS NULL) AND (handled_at IS NULL) = (handled_by IS NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

ALTER TABLE conversations
  ADD COLUMN customer_blocked_at DATETIME(3) NULL,
  ADD COLUMN store_blocked_at DATETIME(3) NULL;
