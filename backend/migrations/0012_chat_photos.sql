-- Photos in chats, both ways (the user's call, 2026-10-01): a shopper shows a
-- damaged item, a store shows what is in stock. A message is words or one
-- photo. The photo is private to its chat: kept privately and opened only
-- through links the server signs. When its sender's account is deleted, or
-- Saba removes it, the message keeps a "removed" mark; the file goes at the
-- next hourly run, unless an open report still shows it (then once that report
-- is closed, so deleting an account never destroys evidence).
ALTER TABLE messages
  MODIFY body VARCHAR(2000) NULL,
  ADD COLUMN photo_key VARCHAR(100) CHARACTER SET ascii COLLATE ascii_bin NULL,
  ADD COLUMN photo_removed_at DATETIME(3) NULL,
  ADD COLUMN photo_removed_by VARCHAR(8) CHARACTER SET ascii COLLATE ascii_bin NULL,
  ADD COLUMN photo_deleted_at DATETIME(3) NULL,
  ADD KEY ix_messages_photo_key (photo_key),
  ADD KEY ix_messages_photo_removed (photo_removed_at),
  DROP CHECK ck_messages_body;

ALTER TABLE messages
  ADD CONSTRAINT ck_messages_body CHECK ((body IS NOT NULL AND CHAR_LENGTH(TRIM(body)) > 0) OR photo_key IS NOT NULL),
  ADD CONSTRAINT ck_messages_photo_removed CHECK ((photo_removed_at IS NULL) = (photo_removed_by IS NULL)
                                                 AND (photo_removed_by IS NULL OR photo_removed_by IN ('ACCOUNT', 'SABA'))
                                                 AND (photo_removed_at IS NULL OR photo_key IS NOT NULL)
                                                 AND (photo_deleted_at IS NULL OR photo_removed_at IS NOT NULL));
