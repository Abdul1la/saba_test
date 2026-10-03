# Setup checklist: the backend on this laptop

Checked on this machine on 2026-09-26: Windows 11 Pro (64-bit), Intel Core i5-8350U, 15.8 GB of memory. The app and web setups stay as they are (`SETUP.md`); this is only what the backend adds.

## 1. What is here already

| Needed | Why | Found | Status |
|---|---|---|---|
| **Node.js 24 LTS** | Runs the backend | 24.15.0 | **Ready.** Supported until April 2028. |
| **npm** | Installs the backend's packages | 11.12.1, with Node | **Ready.** Use npm, not pnpm: the web already uses npm (`package-lock.json`). |
| **Git** | | 2.54.0 | **Ready** |
| **MySQL server** | The database | **8.0.44**, running as the Windows service `MySQL80`, on port **3307** (not the usual 3306), starting with Windows. **8.4.9** is also installed, but not set up: no service, no data folder. | **For now: the 8.0.44 on port 3307** (Q2, changed 2026-09-26). 8.4 later: step 2. |
| **The `mysql` command** | Creating the databases (step 4) | Installed, but not on `PATH` | **Add to `PATH`** (step 3) |
| MySQL Workbench | Looking at the data, optional | 8.0 installed | Ready |
| VS Code | Editing, optional | Installed | Ready |
| Flutter | Running the app's live build | Installed, as used today | Ready |
| Free disk | ≈ 3 GB: packages ≈ 0.3 GB, the MySQL 8.4 data folder, logs, uploaded photos | **16.5 GB free** on `C:` | **Enough.** Keep at least 10 GB free; `flutter clean` in `mobile/` frees the most if it gets tight. |
| Memory | 8 GB is plenty | 15.8 GB | Ready |
| Free ports | 3000 (the API), 3306 (MySQL 8.4), 5173 (the web) | All three free. 3307 and 33060 are taken by MySQL 8.0. | Ready |

**Not needed, and not installed:** Docker, Redis, OpenSSL (Node makes the secrets, step 5). pnpm is installed but won't be used.

## 2. Choose the MySQL server (Q2)

**Recommended: set up 8.4 LTS.** MySQL 8.0 reached end of life in April 2026 and no longer gets security fixes; 8.4 is supported until 2032. Its files are already on the laptop, so only the setup is left:

1. Run `C:\Program Files\MySQL\MySQL Server 8.4\bin\mysql_configurator.exe` (as administrator).
2. Choose **Development Computer**, **port 3306**.
3. Set the **X Protocol port to 33061**. MySQL 8.0 already uses 33060, and two servers on one port won't both start.
4. Set a `root` password and keep it somewhere safe.
5. Run it as a Windows service named `MySQL84`, started at boot.

**Leave 8.0 as it is.** It may hold databases from other projects, and its password is needed to look. Stopping it later is your call, once you know what is in it.

**Or stay on 8.0.44 for now:** everything designed works on it. It needs its `root` password, and the backend's address then uses port 3307. If that password is lost: the MySQL manual's "Resetting the Root Password: Windows Systems" (https://dev.mysql.com/doc/refman/8.0/en/resetting-permissions.html).

## 3. Put the `mysql` command on `PATH`

In PowerShell (for 8.0, write `8.0` instead of `8.4`):

```powershell
[Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path', 'User') + ';C:\Program Files\MySQL\MySQL Server 8.4\bin', 'User')
```

Open a new terminal, then check: `mysql --version`.

## 4. Create the two databases and the backend's own account

The backend never signs in as `root`. Sign in once as root (`mysql -u root -p --port 3306`, or `--port 3307` for 8.0) and run, with a password of your own:

```sql
CREATE DATABASE saba      CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE DATABASE saba_test CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE USER 'saba'@'localhost' IDENTIFIED BY 'choose-a-password';
GRANT ALL PRIVILEGES ON saba.*      TO 'saba'@'localhost';
GRANT ALL PRIVILEGES ON saba_test.* TO 'saba'@'localhost';
```

- `saba` is the development database; `saba_test` is emptied by every test run. Never point the tests at `saba`.
- Check it: `mysql -u saba -p --port 3306 saba -e "select 1"`.

## 5. Two secrets for the backend's `.env`

Run this twice; the first result is `JWT_SECRET`, the second `OTP_SECRET`:

```powershell
node -e "console.log(require('node:crypto').randomBytes(48).toString('base64url'))"
```

The `.env` file itself is made at slice 0 from `.env.example`. It stays out of git.

## 6. Only if you test on a real phone over Wi-Fi

The Android emulator and Chrome reach the backend with nothing extra. A real phone needs Windows to let port 3000 in on your home network (PowerShell, as administrator):

```powershell
New-NetFirewallRule -DisplayName "Saba API (dev)" -Direction Inbound -Protocol TCP -LocalPort 3000 -Profile Private -Action Allow
```

The app is then built with `--dart-define=API_BASE_URL=http://<this laptop's IP>:3000/api/v1` (`BACKEND_PLAN.md` §8.1).

## 7. Ready when

- [ ] Q2 answered, and the chosen MySQL server running
- [ ] `mysql --version` works in a new terminal
- [ ] `saba` and `saba_test` exist, and `saba` can sign in to both
- [ ] The two secrets made
- [ ] Q1 and Q3 answered (`BACKEND_PLAN.md` §2)

Then slice 0 can start: `npm install` in `backend/` fetches everything else the backend uses into its own folder. Nothing is installed system-wide.

**Sources for the version dates:** MySQL's end-of-life notices (https://www.mysql.com/support/eol-notice.html); https://endoflife.date/mysql; https://endoflife.date/nodejs.
