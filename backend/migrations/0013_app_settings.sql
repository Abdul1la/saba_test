-- Saba's own switches, set from the admin website (the user's call, 2026-10-05).
-- auto_approve_products: a product a store adds, or changes, goes live at once
-- instead of waiting in the approval queue. On from the start: the user asked
-- for it. Products already waiting stay in the queue for an admin.
CREATE TABLE app_settings (
  name        VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  value       VARCHAR(200) NOT NULL,
  updated_at  DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO app_settings (name, value) VALUES ('auto_approve_products', 'true');
