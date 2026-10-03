# Putting Saba live

**Hosting: DigitalOcean for the server, the database and the photos (decided 2026-09-30).**

One guide, start to finish. Replace `example.com` with Saba's domain everywhere. It follows the code as of 30 September 2026; if the code and this guide ever disagree, `backend/src/config.ts` and `backend/.env.example` are right.

## Contents

1. [What you need first](#1-what-you-need-first)
2. [Create the services](#2-create-the-services)
3. [Put the backend on the Droplet](#3-put-the-backend-on-the-droplet)
4. [The admin website](#4-the-admin-website)
5. [The app](#5-the-app)
6. [Fill the blanks in the public pages](#6-fill-the-blanks-in-the-public-pages)
7. [Backups](#7-backups)
8. [Keeping it running](#8-keeping-it-running)
9. [Day one: what the person running Saba should know](#9-day-one-what-the-person-running-saba-should-know)
10. [Before the launch: fill the shop, then the final checks](#10-before-the-launch)

## The setup

| Part | What runs it | Address | Cost per month |
|---|---|---|---|
| The API, and the public pages `/delete-account` and `/privacy` | Node 24 on one Droplet (Ubuntu LTS, 1-2 GB), behind Caddy (HTTPS) | `https://api.example.com` | $6-12 |
| The admin website | Built files, served by the same Caddy | `https://admin.example.com` | (same Droplet) |
| The database | DigitalOcean Managed MySQL, 1 GiB | private, TLS only | $15.15 |
| Photos | DigitalOcean Spaces, with its CDN | `https://saba-media.fra1.cdn.digitaloceanspaces.com` | $5 (250 GB storage, 1 TB transfer) |

Other costs: the domain, OTPIQ credit, the Apple Developer Program ($99 a year), the Google Play Console ($25 once).

How it fits: the phone app and the admin website call the API over HTTPS. Caddy takes the request and passes it to the API on port 3000. The API talks to MySQL over TLS. A store's photo goes to the API, the API puts it in the Space, and everyone loads it from the Space's CDN.

Each command block says where it runs: **your computer**, **Droplet, root**, or **Droplet, saba**. On the Droplet, `su - saba` makes you the `saba` user; `exit` takes you back to root.

---

## 1. What you need first

Get all of this before you start. Every secret goes into the client's password manager, never into chat or email.

| # | What | Details | Used in |
|---|---|---|---|
| 1 | Domain and DNS access | Two names: `api.<domain>` (the API and the public pages) and `admin.<domain>` (the admin website). You will add two A records. | 2.2 |
| 2 | DigitalOcean account | In the client's name, with a payment card and two-factor sign-in on. The client invites you to its team. | 2 |
| 3 | A private Git repository | The code has no remote yet. Push it to a private GitHub (or GitLab) repository that you can reach. | 3.5 |
| 4 | OTPIQ | An account with credit, a **live** API key (`sk_live_...`), an **approved sender ID** (11 characters at most), and the channel to use (`auto`, `sms`, `whatsapp`, ...). | 3.6 |
| 5 | Firebase | The project `saba-marketplace` exists. Its Android and iOS apps are `com.sabacompany.sabamarketplace`, and their two files are already in the app (2026-10-01). Still needed: a service-account JSON (Project settings, Service accounts, Generate new private key). | 5.2 |
| 6 | Apple | Apple Developer Program membership, App Store Connect access, the App ID `com.sabacompany.sabamarketplace` with Push Notifications on, and an APNs key (the `.p8` file, its Key ID and the Team ID) uploaded to Firebase. A Mac with Xcode for the iOS build. | 5.2, 5.4 |
| 7 | Google Play Console | The account. Google's rule today: a **personal** account made after 13 November 2023 must run a closed test with at least 12 testers for 14 days before the app can go to production; an **organization** account needs a D-U-N-S number instead. Plan the time for it. | 5.3 |
| 8 | Android upload key | Made and kept by whoever publishes the app, the owner of the Google Play account (decided 2026-09-30). That person signs every Android release. | 5.3 |
| 9 | Support contacts | The support email, and the support WhatsApp number (digits only, international form, like `9647701234567`). | 6 |
| 10 | How long records are kept | How long orders, invoices, returns and bills are kept after an account is deleted: the lawyer's answer, in English and in Arabic. | 6 |
| 11 | The privacy page's facts | The company that runs Saba, in English and in Arabic; the date the policy starts. | 6 |
| 12 | Staff admins | For each one: full name, email and an Iraqi mobile number. A number used for an admin can't also be a shopper's or a store's. | 3.7, 9 |
| 13 | Reviewer accounts | Two Iraqi numbers the team can get an SMS on: one for a test shopper, one for a test store. The app stores' reviewers sign in with them. | 5.5 |
| 14 | Store listings | App name, short and long description in English and Arabic, screenshots, icon. | 5.5 |

---

## 2. Create the services

Use one region for everything. Frankfurt (FRA1) is the closest to Iraq.

### 2.1 The Droplet

1. Create, Droplets.
2. Region: Frankfurt (FRA1). Image: Ubuntu 24.04 LTS (or a newer LTS).
3. Size: Basic, Regular. $6 (1 GB) to start, or $12 (2 GB).
4. Authentication: your SSH key.
5. Turn on the free Monitoring (metrics and alerts).
6. Hostname: `saba-api`. Create it, and note its public IPv4 address.

### 2.2 DNS

Where the domain's DNS is managed, add:

| Type | Name | Value |
|---|---|---|
| A | `api` | the Droplet's IPv4 address |
| A | `admin` | the Droplet's IPv4 address |

Caddy (3.9) gets the HTTPS certificates by itself once these names point at the Droplet.

### 2.3 The database (Managed MySQL)

1. Create, Databases, MySQL. Choose **MySQL 8.4** if it is offered (the long-term version; MySQL 8.0's support ended in April 2026). Write down the exact version shown, such as `8.4.3`: Saba's tests must pass on it before the launch (the end of this section).
2. The same region (FRA1) and the same VPC network as the Droplet.
3. The cheapest plan: 1 GiB, $15.15 a month. Name: `saba-db`.
4. When it is ready, on its page:
   - **Network Access, Add Trusted Sources:** the Droplet `saba-api`. Only it can connect.
   - **Users & Databases:** add a database `saba` and a user `saba`. Copy the user's password.
   - **Overview, Connection Details:** choose **Private network**, user `saba`, database `saba`. Note the host (it starts with `private-`) and the port (`25060`). Click **Download CA certificate**: you get `ca-certificate.crt`.
   - **Settings, Global SQL mode, Edit:** DigitalOcean's MySQL starts with extra modes, among them `ANSI_QUOTES` (double quotes then name a column instead of quoting text) and `PIPES_AS_CONCAT` (`||` then joins text instead of meaning "or"). Saba's SQL is written and tested for MySQL's normal mode. (`IGNORE_SPACE` doesn't matter: the database driver turns it on for each of Saba's connections anyway.) Set exactly these six, MySQL's defaults:
     `ONLY_FULL_GROUP_BY`, `STRICT_TRANS_TABLES`, `NO_ZERO_IN_DATE`, `NO_ZERO_DATE`, `ERROR_FOR_DIVISION_BY_ZERO`, `NO_ENGINE_SUBSTITUTION`.
     You check it from the Droplet in 3.4.
   - **Settings, Upgrade window, Edit:** a quiet day and hour.

DigitalOcean backs this database up by itself (section 7).

**Run Saba's tests on that version first (your computer).** So far they have run on MySQL 8.0.44 only. Before the launch, run them once on the exact version the database shows, in Docker, never on the live database. In Git Bash or a Mac/Linux terminal, in the repository's `backend` folder, with Node 24 and Docker installed:

```bash
docker run -d --name saba-version-check -e MYSQL_ROOT_PASSWORD=check -e MYSQL_DATABASE=saba_test -p 3310:3306 mysql:8.4.3
until docker logs saba-version-check 2>&1 | grep -q "port: 3306"; do sleep 2; done
npm ci
DATABASE_URL_TEST="mysql://root:check@127.0.0.1:3310/saba_test" npm test
docker rm -f saba-version-check
```

Replace `8.4.3` with the version DigitalOcean shows. The `until` line waits for MySQL to finish starting. The run takes about 15 minutes, and its last lines must say `fail 0`. If anything fails, ask a developer before the launch.

### 2.4 Photos (Spaces)

1. Spaces Object Storage, **Create Bucket**: region FRA1, **Standard Storage**, **Enable Content Delivery Network (CDN)** on, name `saba-media`. File listing stays private (the default).
2. A second bucket the same way, but with the CDN off: `saba-backups`. It holds the weekly database copies (7.2). The $5 plan covers all buckets.
3. Spaces Object Storage, Access Keys. Make two keys:
   - `saba-media-key`: limited access, Read/Write/Delete, bucket `saba-media`. It goes in the API's `.env`.
   - `saba-backups-key`: limited access, Read/Write/Delete, bucket `saba-backups`. It goes in the backup settings (7.2).

   Each secret is shown once: put it in the password manager at once.
4. The addresses you need later:
   - S3 endpoint: `https://fra1.digitaloceanspaces.com`
   - The photos' CDN address: `https://saba-media.fra1.cdn.digitaloceanspaces.com`

**No CORS rule on the Space.** The app and the admin website send photos to the API, never to the Space; the API puts each one there, public to read. The app and the website only show them (the website with plain `<img>` tags).

---

## 3. Put the backend on the Droplet

### 3.1 First login, swap, firewall

**Your computer:** `ssh root@<droplet-ip>`

**Droplet, root:**

```bash
apt update && apt upgrade -y
```

On a 1 GB Droplet, add 1 GB of swap (the website build needs the memory):

```bash
fallocate -l 1G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

Firewall: SSH, HTTP and HTTPS only. The API listens on port 3000 on every network interface, so this firewall is what keeps port 3000 private.

```bash
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443
ufw --force enable
```

### 3.2 Install Node 24, Caddy and the tools

**Droplet, root:**

```bash
curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
apt-get install -y nodejs git mysql-client s3cmd rsync
node --version     # must start with v24
which npm          # /usr/bin/npm (the systemd unit in 3.8 uses this path)
```

Caddy, from its official package repository (caddyserver.com/docs/install):

```bash
apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
chmod o+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg /etc/apt/sources.list.d/caddy-stable.list
apt-get update && apt-get install -y caddy
```

### 3.3 A user for Saba, and its folders

The API runs as the user `saba`, never as root.

**Droplet, root:**

```bash
adduser --disabled-password --gecos "" saba
install -d -m 700 -o saba -g saba /home/saba/secrets /home/saba/backups
install -d -o saba -g saba /var/www/saba-admin
```

| Path | What is there |
|---|---|
| `/home/saba/app` | The code (a git clone) |
| `/home/saba/app/backend/.env` | The API's settings and secrets |
| `/home/saba/secrets/` | The database's CA certificate, the Firebase file, and the settings the backup uses |
| `/home/saba/backups/` | The weekly copy waits here while it uploads; the backup log |
| `/var/www/saba-admin/` | The built admin website, served by Caddy |

### 3.4 The database's certificate, and a check

**Your computer:**

```bash
scp ca-certificate.crt root@<droplet-ip>:/home/saba/secrets/
```

**Droplet, root:**

```bash
chown saba:saba /home/saba/secrets/ca-certificate.crt && chmod 600 /home/saba/secrets/ca-certificate.crt
```

**Droplet, saba:** make `~/secrets/db.cnf` with `nano ~/secrets/db.cnf`. The `mysql` and `mysqldump` tools read it; the backup (7.2) uses it too.

```ini
[client]
host=<the private host from 2.3>
port=25060
user=saba
password=<the saba user's password>
ssl-mode=VERIFY_IDENTITY
ssl-ca=/home/saba/secrets/ca-certificate.crt
```

```bash
chmod 600 ~/secrets/db.cnf
mysql --defaults-extra-file=$HOME/secrets/db.cnf -e "SELECT VERSION(), @@GLOBAL.sql_mode"
```

It must connect, and the SQL mode must be exactly the six modes from 2.3. If not, fix it (2.3) before you go on.

`VERIFY_IDENTITY` checks the certificate and that it names this host, as the API does. If this fails with a hostname error, the certificate doesn't name the private host, and the API won't connect either: use the host the certificate names (the database's page lists the hosts), in `db.cnf` and in `DATABASE_URL`.

### 3.5 The code

**Droplet, saba:** give the Droplet read-only access to the repository with a deploy key.

```bash
mkdir -p -m 700 ~/.ssh
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub
```

Add the printed line as a deploy key in the repository's settings (on GitHub: Settings, Deploy keys; leave write access off). Then clone (the first time, answer `yes` to trust the Git host):

```bash
git clone git@github.com:<owner>/<repo>.git ~/app
cd ~/app/backend
npm ci --omit=dev
```

`tsx` is one of the runtime dependencies, so `npm start` and the scripts work without the development packages.

### 3.6 The `.env` file

Only `backend/src/config.ts` reads it, from the `backend` folder. It checks every value at start. A missing or wrong value stops the server with a message that names the variable (never its value). `npm run migrate` and `npm run create-admin` read the same file, and refuse to run until it is complete.

**Droplet, saba:** make two random secrets. Run this twice: the first result is `JWT_SECRET`, the second `OTP_SECRET`.

```bash
node -e "console.log(require('node:crypto').randomBytes(48).toString('base64url'))"
```

Then `nano ~/app/backend/.env`, paste this, and fill in every `<...>`:

```ini
NODE_ENV=production
PORT=3000
API_PREFIX=/api/v1
TRUST_PROXY=1

DATABASE_URL=mysql://saba:<password>@<private host>:25060/saba
DATABASE_CA_FILE=/home/saba/secrets/ca-certificate.crt
DB_POOL_SIZE=10

JWT_SECRET=<first random secret>
OTP_SECRET=<second random secret>

CORS_ORIGINS=https://admin.example.com

MEDIA_STORAGE=s3
S3_ENDPOINT=https://fra1.digitaloceanspaces.com
S3_REGION=fra1
S3_BUCKET=saba-media
S3_ACCESS_KEY_ID=<saba-media-key's access key>
S3_SECRET_ACCESS_KEY=<saba-media-key's secret>
MEDIA_BASE_URL=https://saba-media.fra1.cdn.digitaloceanspaces.com

SMS_PROVIDER=otpiq
OTPIQ_API_KEY=<sk_live_...>
OTPIQ_CHANNEL=auto
OTPIQ_SENDER_ID=<the approved sender ID>
# off: sign-up needs no SMS code (the client's choice at launch); password reset still sends one.
PHONE_VERIFICATION=off

# Empty until the Firebase file is on the Droplet (5.2).
PUSH_PROVIDER=
FCM_SERVICE_ACCOUNT_FILE=

LOG_LEVEL=info
```

```bash
chmod 600 ~/app/backend/.env
```

| Variable | Value | Where the value comes from | Secret |
|---|---|---|---|
| `NODE_ENV` | `production` | Fixed. Turns on the production checks and turns off the API docs. | no |
| `PORT` | `3000` | Fixed. Caddy passes requests to this port. | no |
| `API_PREFIX` | `/api/v1` | Fixed. The app and the website expect it. | no |
| `TRUST_PROXY` | `1` | Fixed: one proxy (Caddy on the same machine) stands in front. Required in production; `true` is refused (it trusts any address a client claims). With `false` behind Caddy, every shopper would share Caddy's address and one set of SMS and sign-in limits. | no |
| `DATABASE_URL` | `mysql://saba:<password>@<host>:25060/saba` | The database's Connection details (2.3). A password with `@ : / #` in it must be URL-encoded. | **yes** |
| `DATABASE_CA_FILE` | `/home/saba/secrets/ca-certificate.crt` | The certificate from 2.3. With it, the API and the scripts connect with TLS and check the certificate. Not a readable certificate: the API refuses to start. | no, but keep it |
| `DB_POOL_SIZE` | `10` | The default. | no |
| `JWT_SECRET` | 64 random characters | The `node -e` command above. It signs the access tokens and the sign-up proofs; changing it later voids the ones in use. | **yes** |
| `OTP_SECRET` | 64 other random characters | The same command, run again. Must differ from `JWT_SECRET`. Changing it later voids the SMS codes in flight. | **yes** |
| `CORS_ORIGINS` | `https://admin.example.com` | The admin website's address, no `/` at the end (a comma-separated list if there are more). Required in production. | no |
| `MEDIA_STORAGE` | `s3` | Fixed. Production refuses `disk`: a server's disk is lost with the server. | no |
| `S3_ENDPOINT` | `https://fra1.digitaloceanspaces.com` | The Space's region endpoint, with no path. | no |
| `S3_REGION` | `fra1` | The Space's region. | no |
| `S3_BUCKET` | `saba-media` | The photos bucket (2.4). | no |
| `S3_ACCESS_KEY_ID` | the key's access key | `saba-media-key` (2.4). | **yes** |
| `S3_SECRET_ACCESS_KEY` | the key's secret | `saba-media-key` (2.4), shown once. | **yes** |
| `MEDIA_BASE_URL` | `https://saba-media.fra1.cdn.digitaloceanspaces.com` | The Space's CDN address, no `/` at the end. Photo addresses start with it. | no |
| `SMS_PROVIDER` | `otpiq` | Fixed. Required in production. | no |
| `OTPIQ_API_KEY` | `sk_live_...` | OTPIQ's dashboard. A `sk_dev_` key only reaches the test number set in OTPIQ. | **yes** |
| `OTPIQ_CHANNEL` | `auto` | The client's choice: `auto`, `sms`, `whatsapp`, `telegram`, `whatsapp-sms`, `telegram-sms`, `whatsapp-telegram-sms`. | no |
| `OTPIQ_SENDER_ID` | e.g. `Saba` | The sender name OTPIQ approved, 11 characters at most. Empty: the API sends no sender ID. | no |
| `PHONE_VERIFICATION` | `off` at launch, later `on` | The client's choice (2026-10-01). `off`: sign-up needs no SMS code, and the account is marked "number not checked". Password reset always sends its code, so OTPIQ stays required. `on`: sign-up needs the code again, and an unchecked account is asked for one at its next sign-in. Switching needs only this line and a restart (3.12), no new app. Left out: `on`. | no |
| `PUSH_PROVIDER` | empty, later `fcm` | `fcm` once the Firebase file is in place (5.2). | no |
| `FCM_SERVICE_ACCOUNT_FILE` | empty, later `/home/saba/secrets/firebase-service-account.json` | Firebase: Project settings, Service accounts, Generate new private key. | **yes (the file)** |
| `LOG_LEVEL` | `info` | The default. | no |

Leave these out on the server: `DATABASE_URL_TEST` (tests only), `MEDIA_DIR` (photos on disk, development only), `DOCS_ENABLED` (the API docs stay off in production), `OTPIQ_BASE_URL` (the default is OTPIQ's address). Never run `npm test` or `npm run seed` on the server.

### 3.7 Build the database, and the first admin

**Droplet, saba:**

```bash
cd ~/app/backend
npm run migrate
npm run create-admin -- --name "Full Name" --email name@example.com --phone "0770 123 4567"
```

- `migrate` lists the migrations it ran. Run it again and it says `Nothing to migrate.`
- `create-admin` asks for the password (8 to 128 characters), so it never lands in the shell's history. It prints `Admin <id> created: ...`. Run it once per staff admin.
- **The live database starts empty.** Never load a copy of a laptop's database, and never run `npm run seed` (demo data; it refuses in production anyway).
- If this first `migrate` stops with an error, it may have left some tables. Fix the cause, delete the database `saba` and add it again (Users & Databases), then run `migrate` again.

### 3.8 Run it with systemd

**Droplet, root:** `nano /etc/systemd/system/saba-api.service`

```ini
[Unit]
Description=Saba API
After=network-online.target
Wants=network-online.target

[Service]
User=saba
WorkingDirectory=/home/saba/app/backend
ExecStart=/usr/bin/npm start
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
systemctl daemon-reload
systemctl enable --now saba-api
systemctl status saba-api
curl -s http://127.0.0.1:3000/api/v1/health
```

- The health answer contains `"status":"ok"`. It is a `503` when the database does not answer.
- `npm start` runs `tsx src/server.ts` in the `backend` folder, which reads `.env` from there.
- `Restart=always`: systemd starts it again if it stops, and `enable` starts it at every boot.
- On stop, the API stops taking requests, ends the live-update streams (the apps reconnect by themselves), finishes the rest (10 seconds at most) and closes the database pool.
- If it keeps restarting, look at the log (3.11): a bad setting shows as `Invalid configuration:` with the variable's name.

### 3.9 Caddy: HTTPS, the admin website, and a cap on requests

The API limits sign-ins and SMS codes itself, but not everything else. Caddy caps how many requests one address may send. Its standard build can't do that, so first add the `caddy-ratelimit` plugin.

**Droplet, root:**

```bash
caddy add-package github.com/mholt/caddy-ratelimit
caddy list-modules | grep rate_limit     # must print: http.handlers.rate_limit
apt-mark hold caddy                      # an upgrade would bring back a build without the plugin
```

Then replace everything in `/etc/caddy/Caddyfile` with:

```
api.example.com {
	route {
		rate_limit {
			zone per_address {
				key    {remote_host}
				events 600
				window 1m
			}
		}
		reverse_proxy 127.0.0.1:3000
	}
}

admin.example.com {
	root * /var/www/saba-admin
	encode zstd gzip
	try_files {path} /index.html
	file_server
}
```

```bash
systemctl restart caddy
```

- Caddy gets and renews the certificates itself. Ports 80 and 443 must be open (3.1), and the two names must point here (2.2).
- **The cap:** 600 requests a minute from one address. Past that, Caddy answers `429 Too Many Requests` until the minute is over. Iraqi mobile networks put many phones behind one address, so the cap is generous. If real shoppers get 429s (`journalctl -u caddy` shows them), raise `events` and restart Caddy.
- `route` keeps the cap before the API. `restart` (not `reload`) is needed after the plugin, since the program itself changed.
- **Updating Caddy later**, so the plugin stays: `apt-mark unhold caddy && apt-get install --only-upgrade caddy && caddy add-package github.com/mholt/caddy-ratelimit && apt-mark hold caddy && systemctl restart caddy`.
- The API block has no `encode` on purpose: the live updates are a long stream, and compression can hold it back.
- `try_files`: the admin website handles its own paths, so any path that is not a file gets `index.html`.

### 3.10 Check it from outside

**Your computer:**

```bash
curl -fsS https://api.example.com/api/v1/health
curl -m 5 http://<droplet-ip>:3000/api/v1/health
```

The first answers with `"status":"ok"`. The second must time out: the firewall keeps port 3000 closed.

### 3.11 Logs

The API writes one JSON line per request and event to standard output; systemd's journal keeps them.

**Droplet, root:**

```bash
journalctl -u saba-api -f                                    # follow live
journalctl -u saba-api -n 200 --no-pager                     # the last 200 lines
journalctl -u saba-api --since today | grep '"level":50'     # errors today (40 = warnings)
journalctl -u caddy -n 100 --no-pager                        # Caddy: certificates, proxy errors
```

### 3.12 Deploy an update

**Droplet, saba:**

```bash
cd ~/app && git pull
cd backend
npm ci --omit=dev
npm run migrate
```

**Droplet, root:**

```bash
systemctl restart saba-api
curl -fsS https://api.example.com/api/v1/health
```

- If `website/` changed, build it again (section 4). If `mobile/` changed, make new store builds (section 5).
- Every schema change is a new file in `backend/migrations/`. A migration that has run is never edited: the runner refuses it.
- DigitalOcean's MySQL refuses a new table without a primary key.
- MySQL can't undo a `CREATE TABLE`, so a migration that fails half-way leaves what it made. Restore to the minute before (7.1), or fix it by hand.

---

## 4. The admin website

Build it on the Droplet, with the API's address inside.

**Droplet, saba:**

```bash
cd ~/app/website
npm ci
VITE_API_BASE_URL=https://api.example.com/api/v1 npm run build
rsync -a --delete dist/ /var/www/saba-admin/
```

- `npm run build` runs `tsc && vite build` and writes `dist/`. Without `VITE_API_BASE_URL` it stops with an error: `localhost` is only for development.
- `CORS_ORIGINS` in the API's `.env` must be exactly `https://admin.example.com`, or browsers are refused.
- Never deploy `npm run build:demo`: that is the demo, with mock data and no server.

Open `https://admin.example.com` and sign in with the admin's email (or phone number) and the password from 3.7.

---

## 5. The app

### 5.1 The server's address in every release

Every release build gets these two settings:

```
--dart-define=APP_ENV=production --dart-define=API_BASE_URL=https://api.example.com/api/v1
```

- `APP_ENV=production` forces the demo mode off and turns off request logging.
- A release built without `API_BASE_URL` refuses to start.
- Version: `mobile/pubspec.yaml` says `version: 1.0.0+1`. Every upload to a store needs a higher number after the `+` (Android's version code, iOS's build number). Raise it there, or add `--build-number=<n>` to the build command.

### 5.2 Firebase and push

Push needs Firebase in these places. Until they are all in, phones get no push, and everything else works.

1. **The app:** done (2026-10-01). It has its Firebase code, and the project's two files: `google-services.json` in `mobile/android/app/`, and `GoogleService-Info.plist` in `mobile/ios/Runner/`, in the Runner target.
2. **Apple:** the APNs key uploaded to Firebase (Project settings, Cloud Messaging, Apple app configuration), and Push Notifications on the App ID `com.sabacompany.sabamarketplace`. The app asks for push, so iOS signing fails without that capability.
3. **The server:** the service-account file, two lines in `.env`, a restart (below).

**Your computer:** the file Firebase gave has a long name; this copies it under a short one.

```bash
scp <the Firebase file>.json root@<droplet-ip>:/home/saba/secrets/firebase-service-account.json
```

**Droplet, root:**

```bash
chown saba:saba /home/saba/secrets/firebase-service-account.json && chmod 600 /home/saba/secrets/firebase-service-account.json
```

**Droplet, saba:** in `~/app/backend/.env`, set:

```ini
PUSH_PROVIDER=fcm
FCM_SERVICE_ACCOUNT_FILE=/home/saba/secrets/firebase-service-account.json
```

**Droplet, root:**

```bash
systemctl restart saba-api
journalctl -u saba-api -n 20 --no-pager
```

The server's side is on when the start no longer logs `Push notifications are OFF`. Until then everything else works, and notifications still show inside the app.

### 5.3 Android: signing and the release build

With Play App Signing, Google keeps the key that signs what shoppers install. You sign each upload with an **upload key**. The person who publishes the app (the owner of the Google Play account, who holds the upload key) does this once:

**The key holder's computer:**

```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

`keytool` comes with Java; Android Studio has one (`flutter doctor -v` prints where).

1. Keep `upload-keystore.jks` and its passwords in the password manager, plus one copy offline. Never in git.
2. Copy `mobile/android/key.properties.example` to `mobile/android/key.properties` and fill it in: `storeFile` is the full path to the `.jks` file, written with `/` even on Windows (`C:/keys/upload-keystore.jks`; a `\` breaks it), and `keyAlias` is `upload`. `mobile/android/.gitignore` keeps `key.properties` and `.jks` files out of git.
3. Build:

   ```bash
   cd mobile
   flutter build appbundle --release --dart-define=APP_ENV=production --dart-define=API_BASE_URL=https://api.example.com/api/v1
   ```

   The file is `mobile/build/app/outputs/bundle/release/app-release.aab`. A release build without `android/key.properties` stops with an error; it never signs with the debug key, which Google Play refuses.
4. Upload it in the Play Console. At the first upload, accept Play App Signing.

If the upload key is ever lost, the Play account's owner can ask Google to reset it. The app stays the same.

### 5.4 iOS

On a Mac with Xcode, signed in to the client's Apple Developer team:

1. Open `mobile/ios/Runner.xcworkspace`. Target Runner, Signing & Capabilities: choose the team. The bundle ID is `com.sabacompany.sabamarketplace`, and Push Notifications must be among the capabilities (5.2).
2. In App Store Connect, create the app with that bundle ID.
3. Build:

   ```bash
   cd mobile
   flutter build ipa --release --dart-define=APP_ENV=production --dart-define=API_BASE_URL=https://api.example.com/api/v1
   ```

4. Upload the `.ipa` from `mobile/build/ios/ipa/` with Apple's Transporter app.

### 5.5 Store listings

Fill in the two public pages first (section 6).

| Where | Field | Value |
|---|---|---|
| Play Console, App content | Privacy policy | `https://api.example.com/privacy` |
| Play Console, App content, Data safety | Delete account URL (in the data deletion questions) | `https://api.example.com/delete-account` |
| Play Console, App content | App access | The reviewer shopper's and store's phone numbers and passwords |
| App Store Connect, App Privacy | Privacy Policy URL | `https://api.example.com/privacy` |
| App Store Connect, App Review Information | Sign-in required | The same reviewer accounts |

The reviewer accounts: sign up in the live app with the two numbers from item 13 in section 1 (one shopper, one store), and approve the store in the admin website. Reviewers sign in with the phone number and the password; they need no SMS.

---

## 6. Fill the blanks in the public pages

The API shows two pages to anyone, in Arabic and English:

- `/delete-account`: `backend/public/delete-account.html`, Google Play's account-deletion page.
- `/privacy`: `backend/public/privacy.html`, the privacy policy for both stores.

Their `{{...}}` blanks hold the client's answers. The app carries its own copy of the privacy policy, with the same blanks, so **fill them before the app's release build (section 5)**. Fill them in the repository (one find-and-replace per blank, every place it appears), commit, push, then deploy (3.12).

| Blank | In | What goes there | Example |
|---|---|---|---|
| `{{SUPPORT_EMAIL}}` | both pages, the app | Saba's support email | `support@saba.iq` |
| `{{WHATSAPP}}` | both pages, the app | Saba's support WhatsApp number: digits only, international form, no `+`, no spaces. The page adds the `+` and links to `wa.me`. | `9647701234567` |
| `{{RECORDS_KEPT_EN}}` | both pages, the app | How long orders, invoices, returns and bills are kept, in English: the lawyer's answer. It reads "we keep them for ...". | `5 years` |
| `{{RECORDS_KEPT_AR}}` | both pages, the app | The same, in Arabic. It reads "نحتفظ بها ...". | `خمس سنوات` |
| `{{COMPANY_NAME_EN}}` | `privacy.html`, the app | Who runs Saba, as named in the store listings, in English | `Example Trading Co.` |
| `{{COMPANY_NAME_AR}}` | `privacy.html`, the app | The same, in Arabic | `شركة المثال التجارية` |
| `{{POLICY_DATE}}` | `privacy.html` | The day the page last changed, in digits (one date shows in both languages) | `2026-10-15` |

"The app" is `mobile/lib/features/legal/legal_screen.dart`. It has no `{{POLICY_DATE}}`: its date is the `legalUpdated` line in `mobile/lib/core/localization/strings_en.dart` and `strings_ar.dart`, in words. Set it to the same day.

Two more things in `privacy.html`, from the note at its top:

- It names DigitalOcean as Saba's host. If Saba is hosted elsewhere, change that line in both languages.
- It is repeated, word for word, as the app's own privacy page. Change one, change the other: the app's tests fail until they match.

**Check that nothing is left.** In the repository:

```bash
awk '/<!--/{c=1} !c && /\{\{/{print FILENAME ":" FNR ": " $0} /-->/{c=0}' backend/public/delete-account.html backend/public/privacy.html
grep -n '{{' mobile/lib/features/legal/legal_screen.dart
```

They print every line that still has a blank. The `awk` skips the note at the top of each page, which names the blanks on purpose. No output: done.

The same check on the live pages, after the deploy:

```bash
for page in delete-account privacy; do curl -fsS https://api.example.com/$page | awk '/<!--/{c=1} !c && /\{\{/{print} /-->/{c=0}'; done
```

No output: done. An error from `curl` means the page is not served.

---

## 7. Backups

### 7.1 What DigitalOcean does for the database

- A backup every day, kept 7 days, and a restore to any moment in those 7 days (point in time).
- To restore: the database's **Backups** tab, restore, choose the day and the time. DigitalOcean makes a **new** database cluster; the old one keeps running. Then:
  1. Add the Droplet to the new cluster's trusted sources, and check its SQL mode (2.3).
  2. Put the new host in `DATABASE_URL` (in `.env`) and in `~/secrets/db.cnf`. Download the new cluster's CA certificate over `/home/saba/secrets/ca-certificate.crt`.
  3. `systemctl restart saba-api`, and check `/api/v1/health`.
  4. Delete the old cluster once you are sure.

### 7.2 A weekly copy, kept about three months

Once a week the Droplet dumps the database over TLS and uploads it to the `saba-backups` Space. There are 13 slots, named by the week's number, so each copy replaces the one from 13 weeks before.

Where the credentials live:

- `/home/saba/secrets/db.cnf` (3.4): the database user and password.
- `/home/saba/secrets/s3cfg`: the `saba-backups-key` (2.4).

**Droplet, saba:** `nano ~/secrets/s3cfg`

```ini
[default]
access_key = <saba-backups-key's access key>
secret_key = <saba-backups-key's secret>
host_base = fra1.digitaloceanspaces.com
host_bucket = %(bucket)s.fra1.digitaloceanspaces.com
use_https = True
```

Then `nano ~/backup-db.sh`:

```bash
#!/bin/bash
# The weekly copy of the live database, to the saba-backups Space (DEPLOYMENT.md, 7.2).
# 13 slots by week number: each copy replaces the one from 13 weeks before.
set -euo pipefail
slot=$(( 10#$(date +%V) % 13 ))
file=/home/saba/backups/saba-slot-$slot.sql.gz
mysqldump --defaults-extra-file=/home/saba/secrets/db.cnf --single-transaction --set-gtid-purged=OFF --no-tablespaces saba | gzip > "$file"
s3cmd --config=/home/saba/secrets/s3cfg put "$file" s3://saba-backups/db/
rm "$file"
```

```bash
chmod 600 ~/secrets/s3cfg
chmod 700 ~/backup-db.sh
~/backup-db.sh
s3cmd --config=$HOME/secrets/s3cfg ls s3://saba-backups/db/
(crontab -l 2>/dev/null; echo '0 2 * * 0 /home/saba/backup-db.sh >> /home/saba/backups/backup.log 2>&1') | crontab -
```

- The first run is by hand; `ls` must show the copy.
- Cron runs it every Sunday at 02:00 server time (UTC, so 05:00 in Baghdad). Look at `~/backups/backup.log` now and then.
- If `s3cmd` says access denied, the key needs more rights: make a Full Access key and put it in `s3cfg`.

**To use a copy**, load it into a new, empty database (Users & Databases, add one), never over the live one. Do this once after the first copy, so you know it works.

**Droplet, saba:**

```bash
s3cmd --config=$HOME/secrets/s3cfg get s3://saba-backups/db/saba-slot-<n>.sql.gz
gunzip -c saba-slot-<n>.sql.gz | mysql --defaults-extra-file=$HOME/secrets/db.cnf <the empty database>
```

`s3cmd ls` shows each slot's date, to find the newest.

### 7.3 Photos

Photos live only in the `saba-media` Space. Nothing else keeps a copy: a photo deleted there is gone.

### 7.4 Keep these safe

Keep a copy of each in the client's password manager.

| What | Where | If it is lost |
|---|---|---|
| `.env` | `/home/saba/app/backend/.env` | Make it again from 3.6. New secrets void the access tokens, sign-ups and SMS codes in flight; the apps get new access tokens by themselves. |
| `db.cnf`, `s3cfg` | `/home/saba/secrets/` | Make them again from the database's and the Space's pages. |
| The database's CA certificate | `/home/saba/secrets/ca-certificate.crt` | Download it again from the database's page. |
| Firebase's service-account file | `/home/saba/secrets/firebase-service-account.json` | Make a new one in Firebase, and delete the old one there. |
| The Android upload key and its passwords | The key holder's computer, and one copy offline | The Play account's owner asks Google for an upload key reset. |
| The APNs key (`.p8`) | Uploaded to Firebase | Apple lets you download it once only. Make a new one if needed. |

The Droplet itself holds nothing else: the code is in git, the data in the database and the Space.

---

## 8. Keeping it running

- **Restarts:** systemd restarts the API if it stops, and starts it at boot. Caddy is a service too.
- **Housekeeping needs no cron.** The API runs its clean-up a minute after it starts, then every hour: old request keys and SMS codes, expired sign-ins, and the store deletions that are ready. The log shows a `housekeeping` line each hour. (`npm run housekeeping` is one run of the same job, for a host's scheduler; not needed here.)
- **Health:** `https://api.example.com/api/v1/health` answers `"status":"ok"` when the API and its database are up, and `503` when the database does not answer. Point an uptime check at it (DigitalOcean: Monitoring, Uptime).
- **Certificates:** Caddy renews them.
- **Ubuntu:** security updates install by themselves. When the login message says *System restart required*, run `reboot` at a quiet hour; everything starts again by itself.
- **One copy of the API only.** The live updates and the sign-in limits are kept in the API's memory. A second copy, or a second server, needs Redis first (`BACKEND_PLAN.md` §12).

Set DigitalOcean alerts (Monitoring): the Droplet's disk above 80% and memory above 90%, and the same for the database.

What to watch, once a week (**Droplet, root**):

```bash
df -h /                                                           # disk: the journal caps its own size; photos are not on this disk
free -h                                                           # memory
journalctl -u saba-api --since "7 days ago" | grep '"level":50'   # errors
journalctl -u saba-api | grep remainingCredit | tail -n 1         # OTPIQ credit left, as of the last SMS
cat /home/saba/backups/backup.log                                 # the weekly copies
```

- **OTPIQ credit:** each SMS logs OTPIQ's remaining credit; also look at OTPIQ's dashboard. At zero, no sign-up or password-reset code reaches anyone. `OTPIQ refused the SMS` in the log is the first sign.
- **The database:** its page shows CPU, memory, disk and connections.

---

## 9. Day one: what the person running Saba should know

- **The live database starts empty.** It has only the 19 governorates and the 13 categories (7 main, 6 sub) that the migrations add, and the admins made with `create-admin`. No stores, no products, no shoppers, no orders. Stores sign up in the app. A new store, and each new product, waits in the admin website's approval queue until Saba's staff approve it.
- **Brands: none at first.** Saba adds them on the admin website's Brands page (10.1). Stores choose from that list, or type a new name: a typed name waits on the Brands page, marked "New", until Saba checks it, and approving the store's product approves it too.
- **Home banners: none at first.** Saba adds them on the admin website's Banners page (10.1). With no banners, Home has no banner strip; the rest of Home works.
- **Category pictures: none at first.** The 13 categories come without pictures. Saba adds them on the admin website's Categories page (10.1).
- **Featured stores: none at first**, so Home leaves that row out. Saba's staff choose them in the admin website.
- **Each text is in one language.** A store types its description and address once; a shopper types an address once, in the language they use. The Arabic copies in the database (`description_ar`, `business_address_ar`, `area_ar` and the like) stay empty, and then both languages show the same text. The demo seed filled both languages, so the demo looked fully translated; the live shop will not. Product names are different: the store's form asks for an Arabic name (required) and an English name (optional), and English readers see the Arabic name when there is no English one.
- **Push is off** until Firebase is in (5.2). The API logs `Push notifications are OFF` at each start. Notifications still show inside the app.
- **Phone checks at sign-up are off** (`PHONE_VERIFICATION=off`, 3.6): anyone can sign up without an SMS code, so the API logs `Phone checks at sign-up are OFF` at each start. What it means:
  - Every account made this way shows **"number not checked"** in the admin website, and the Customers and Stores lists can show only those.
  - Someone may sign up with another person's number. When the real owner asks support (for example on WhatsApp, from that number), use **Free this number** on the account in the admin website. A shopper's account is deleted at once (not while an order is still open). A store's owner is shut out at once, and the store closes at the next hourly run. The owner can then sign up. A number that was checked with a code can never be freed this way.
  - Password reset still sends its SMS code. A store's approval call is a good moment to check its number by hand.
  - To turn checks back on, set `PHONE_VERIFICATION=on` in `.env` and restart (`systemctl restart saba-api`). New sign-ups need a code again, and each unchecked account is signed out and asked for a code at its next sign-in. No new app is needed.
- **Another admin:** there is no screen for it. On the Droplet (**Droplet, saba**):

  ```bash
  cd ~/app/backend
  npm run create-admin -- --name "Full Name" --email name@example.com --phone "0770 123 4567"
  ```

  It asks for the password, which never shows on the screen. The number must not belong to a shopper's or a store's account.
- **Someone leaves Saba:** suspend their staff account the same day (**Droplet, saba**):

  ```bash
  cd ~/app/backend
  npm run suspend-admin -- --email name@example.com --reason "Left Saba"
  ```

  It shuts them out at their next click, and ends every sign-in they hold. `--phone` works instead of `--email`. To let them back in, run it with `--restore` instead of `--reason`: they sign in afresh.
- **SQL by hand is for reading only.** Never change orders, stock or money by hand.

---

## 10. Before the launch

### 10.1 Fill the shop: banners, brands, category pictures

The live database starts with no banners, no brands and no category pictures. Before the shop opens, sign in to the admin website (`https://admin.example.com`) as an admin and add them:

1. **Categories:** give each of the 13 categories a picture. Categories can also be added, renamed, reordered or hidden here.
2. **Brands:** add the brands stores will sell, each with its English and Arabic name. Stores choose from this list. A name a store types itself shows here as "New" until Saba checks it.
3. **Banners:** add at least one: a picture, optional words in English and Arabic, what a tap opens, switched on. Before stores have products, a banner can open a category or nothing. Put the banners in the order Home should show them.

Then check on a phone: Home shows the banners in that order, and every category has its picture.

### 10.2 Final checks

- [ ] The shop is filled (10.1): Home shows the banners, every category has a picture, and the Brands page has the brands.
- [ ] Saba's tests passed on the database's exact MySQL version (end of 2.3).
- [ ] `curl -fsS https://api.example.com/api/v1/health` answers `"status":"ok"`.
- [ ] The request cap works (3.9): from your computer, `for i in $(seq 650); do curl -s -o /dev/null -w '%{http_code}\n' https://api.example.com/api/v1/health; done | sort | uniq -c` shows some `429` lines. Your address is then capped for a minute.
- [ ] `journalctl -u saba-api -n 50` shows `Saba API listening` with `"env":"production"`, and no `Invalid configuration`.
- [ ] Port 3000 is closed from outside (3.10).
- [ ] The database's SQL mode has no `ANSI` in it (3.4).
- [ ] Both public pages open, and the blank check prints nothing (section 6).
- [ ] `https://admin.example.com` opens, and each staff admin can sign in.
- [ ] On a real phone, with the release build: a shopper signs up with a real Iraqi number, and the SMS code arrives from the approved sender.
- [ ] A test store signs up and uploads a logo and a product photo. The photo shows in the app and in the admin website, and its address starts with `https://saba-media.fra1.cdn.digitaloceanspaces.com/`. If the log says `object storage refused the upload: 403`, the Spaces key has too few rights: make a Full Access key and put it in `.env`.
- [ ] The admin approves the store and the product in the admin website's approval queue, and the product shows in the shop (the store must be open).
- [ ] A small test order is placed and then cancelled.
- [ ] Push, if Firebase is in: the start no longer logs `Push notifications are OFF`, and an order's change reaches the phone as a push.
- [ ] Backups: the database's Backups tab lists one; the weekly copy ran once by hand, and it loaded once into a spare database (7.2).
- [ ] Every secret is in the password manager (7.4); the upload key also has an offline copy.
- [ ] DigitalOcean alerts and an uptime check on `/api/v1/health` are set (section 8).
- [ ] Store listings: privacy URL, delete-account URL, Data safety, App access, screenshots (5.5); Google's closed-test rule met, if it applies (item 7 in section 1).
- [ ] No demo anywhere: the releases were built with `APP_ENV=production`, the website with `npm run build` (not `build:demo`), and `npm run seed` never ran on this database.
- [ ] After the checks, the test store's owner closes it in the app: its products leave the shop, and the reviewers can still sign in to it.
