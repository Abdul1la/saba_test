-- Saba's announcements (the user's call, 2026-10-08): from the admin website,
-- one notification to every customer, every store owner, or both, pushed to
-- their phones too. It opens nothing; it is read where it lands. Only the
-- allowed types grow: no row changes.
ALTER TABLE notifications DROP CHECK ck_notifications_type;

ALTER TABLE notifications
  ADD CONSTRAINT ck_notifications_type CHECK (type IN ('ORDER', 'SHIPPING', 'DELIVERY', 'PRODUCT_APPROVAL', 'STORE', 'MESSAGE', 'TICKET', 'PAYMENT', 'ANNOUNCEMENT'));
