-- The reviewer's item 16 (2026-09-30): the hourly clean-up deletes expired
-- refresh tokens by expires_at, which had no index, so it read the whole
-- table. Old (rotated) tokens stay until they expire: a stolen one sent again
-- must still be recognised, so its whole sign-in can be ended.
ALTER TABLE refresh_tokens ADD KEY ix_refresh_tokens_expires (expires_at);
