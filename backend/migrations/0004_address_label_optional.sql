-- An address's nickname ("Home", "Work") is optional in the app's form
-- (features/addresses: label is String?); 0001 made it required.
ALTER TABLE addresses MODIFY label VARCHAR(30) NULL;
