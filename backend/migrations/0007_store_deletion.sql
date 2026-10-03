-- A store owner deletes their account (the user's call, 2026-09-29: Apple and
-- Google refuse an app that only deactivates). Asking closes the store at
-- once; the hourly run deletes the account once its orders and returns are
-- finished, the return window has passed and Saba is paid. The store row
-- stays, CLOSED, for the orders, returns and bills that name it.
ALTER TABLE stores
  ADD COLUMN deletion_requested_at DATETIME(3) NULL,
  ADD COLUMN closed_at DATETIME(3) NULL,
  DROP CHECK ck_stores_status;

ALTER TABLE stores
  ADD CONSTRAINT ck_stores_status CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED', 'SUSPENDED', 'CLOSED')),
  ADD CONSTRAINT ck_stores_closed CHECK ((status = 'CLOSED') = (closed_at IS NOT NULL)
                                         AND (closed_at IS NULL OR (is_open = 0 AND deletion_requested_at IS NOT NULL)));
