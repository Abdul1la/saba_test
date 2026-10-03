-- The SMS code at sign-up can be switched off with a setting (the user's call,
-- 2026-10-01: no SMS at launch; password reset keeps its code). Each account
-- keeps when its number was proven, null for never, so the unchecked ones can
-- be asked for a code at their next sign-in once SMS is back on.
ALTER TABLE users ADD COLUMN phone_verified_at DATETIME(3) NULL;

-- Until now every number was proven by its sign-up code, and an admin's was
-- given by whoever ran create-admin on the server.
UPDATE users SET phone_verified_at = created_at WHERE phone IS NOT NULL;

-- SIGN_UP_NO_CODE: a sign-up let through without a code while the setting is
-- off. VERIFY_PHONE: the code an unchecked account is asked for at sign-in.
ALTER TABLE otp_challenges DROP CHECK ck_otp_challenges_purpose;

ALTER TABLE otp_challenges
  ADD CONSTRAINT ck_otp_challenges_purpose CHECK (purpose IN ('SIGN_UP', 'SIGN_UP_NO_CODE', 'PASSWORD_RESET', 'VERIFY_PHONE', 'OTHER'));
