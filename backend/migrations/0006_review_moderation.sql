-- Reported reviews reach Saba (the user's call, 2026-09-29, before launch: app
-- stores check that a report goes somewhere). Saba removes a review, which
-- takes it off the store's page and out of its rating, or dismisses its
-- reports, which keeps it. The reporter's words were accepted and dropped
-- before; now they are kept.
ALTER TABLE store_reviews
  ADD COLUMN removed_at DATETIME(3) NULL,
  ADD COLUMN removed_by BIGINT UNSIGNED NULL,
  ADD CONSTRAINT fk_store_reviews_removed_by FOREIGN KEY (removed_by) REFERENCES users (id),
  ADD CONSTRAINT ck_store_reviews_removed CHECK ((removed_at IS NULL) = (removed_by IS NULL));

ALTER TABLE review_reports
  ADD COLUMN description VARCHAR(500) NULL,
  ADD COLUMN status VARCHAR(10) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'OPEN',
  ADD COLUMN handled_at DATETIME(3) NULL,
  ADD COLUMN handled_by BIGINT UNSIGNED NULL,
  ADD KEY ix_review_reports_status (status, created_at),
  ADD CONSTRAINT fk_review_reports_handled_by FOREIGN KEY (handled_by) REFERENCES users (id),
  ADD CONSTRAINT ck_review_reports_status CHECK (status IN ('OPEN', 'DISMISSED', 'REMOVED')),
  ADD CONSTRAINT ck_review_reports_handled CHECK ((status = 'OPEN') = (handled_at IS NULL) AND (handled_at IS NULL) = (handled_by IS NULL));
