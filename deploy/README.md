# Production Deployment (Ubuntu + certbot)

Exposes the app through Nginx with a real Let's Encrypt certificate:

| URL                         | What              | TLS |
|-----------------------------|-------------------|-----|
| `https://your-domain/`        | Frontend (React)  | ✅ |
| `https://your-domain/api/*`   | Backend API       | ✅ |
| `http://your-domain/api/*`    | Backend API       | HTTP |
| `http://your-domain/`         | Redirects → HTTPS | — |

```
Internet --HTTPS--> Nginx :443 (certbot cert)
                     ├── /        → /var/www/html      (React, FRONTEND HTTPS)
                     └── /api/*   → 127.0.0.1:8080     (BACKEND HTTPS)
Internet --HTTP-->  Nginx :80
                     ├── /api/*   → 127.0.0.1:8080     (BACKEND HTTP)
                     └── other    → 301 redirect HTTPS (frontend is HTTPS-only)
```

The backend WAR stays on **plain HTTP :8080** internally. Nginx does ALL TLS,
so there is no keystore to manage on the server.

## Files

- `nginx-http.conf` — bootstrap config (port 80 only). Deployed FIRST so
  `certbot certonly --nginx` can complete its HTTP-01 challenge.
- `nginx-three-tier.conf` — final config (443 HTTPS for frontend+API,
  80 HTTP for /api only, 80 redirect for the rest).
- `application-production.properties` — backend `production` Spring profile
  (`server.ssl.enabled=false`, single HTTP connector on :8080).
- `setup-ubuntu.sh` — one-command deployment implementing the two-phase flow.

## How the two-phase cert issuance works

Let's Encrypt must verify you own the domain via an HTTP-01 challenge
(`http://your-domain/.well-known/acme-challenge/...`), so a cert file can be
referenced before it exists.

1. `certbot certonly --nginx` — obtains the cert without editing your config.
2. After issuance, the FINAL config can reference
   `/etc/letsencrypt/live/<domain>/{fullchain,privkey}.pem`.

> Why not `certbot --nginx` (the auto-installer)? It rewrites your config and
> adds a server-level redirect that would force `/api` over HTTP → HTTPS too.
> Here we want `/api` available over BOTH protocols, so we keep full control.

## Run it

```bash
sudo bash deploy/setup-ubuntu.sh
```

That installs everything, then shows the verification results. Manual version:

```bash
# 1. Install
sudo apt update && sudo apt install -y nginx certbot python3-certbot-nginx mysql-server tomcat10 openjdk-17-jre maven
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - && sudo apt install -y nodejs

# 2. Database
sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'root';"
sudo mysql -u root -proot < database/init.sql

# 3. Backend (WAR -> Tomcat, production profile, plain HTTP)
sudo cp backend/target/backend-1.0.0.war /var/lib/tomcat10/webapps/ROOT.war
echo 'JAVA_OPTS="-Dspring.profiles.active=production -DDB_URL=jdbc:mysql://localhost:3306/devops_practice_db -DDB_USERNAME=devops_app -DDB_PASSWORD=REPLACE_ME"' | sudo tee /etc/default/tomcat10
sudo systemctl restart tomcat10
curl http://127.0.0.1:8080/api/health   # backend healthy?

# 4. Frontend -> /var/www/html (relative /api URL -> works over HTTP and HTTPS)
cd frontend && REACT_APP_API_URL=/api npm ci && npm run build
sudo cp -r build/* /var/www/html/

# 5. Nginx phase 1 (bootstrap) so certbot challenge can run
sudo sed 's/app.yoursite.com/your-real-domain/g' deploy/nginx-http.conf | sudo tee /etc/nginx/sites-available/three-tier
sudo ln -sf /etc/nginx/sites-available/three-tier /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx

# 6. Get the real certificate (auto-renews)
sudo certbot certonly --nginx -d your-real-domain.com \
  --non-interactive --agree-tos -m you@your-domain.com

# 7. Nginx phase 2 (final config: frontend HTTPS, backend HTTPS + HTTP)
sudo sed 's/app.yoursite.com/your-real-domain/g' deploy/nginx-three-tier.conf | sudo tee /etc/nginx/sites-available/three-tier
sudo nginx -t && sudo systemctl reload nginx

# 8. Verify
curl -sI https://your-real-domain/            # 200 frontend
curl -s  https://your-real-domain/api/health  # backend via HTTPS
curl -s  http://your-real-domain/api/health   # backend via HTTP
curl -sI http://your-real-domain/             # 301 Location: https://...
curl -s  https://your-real-domain/api/items   # items JSON
sudo certbot certificates                     # expiry dates
```

## Renewal

Certbot certs last 90 days. The `certbot` package installs a systemd timer
that checks daily and renews automatically (uses the same HTTP-01 challenge;
phase-1 nginx is already running, so renewal is seamless):
```bash
sudo systemctl list-timers certbot.timer      # check it's active
sudo certbot renew --dry-run                   # dry-run a renewal
```

## Security notes

- The backend `ssl/` folder (mkcert keys) is git-ignored — dev-only, not deployed.
- Set a real `DB_PASS` in `setup-ubuntu.sh`.
- Let's Encrypt won't issue certs for raw IPs — the domain must be pointed
  at this server (A record) before step 6.
- `/etc/letsencrypt/live/<domain>` contains symlinks that always point at the
  current cert, so phase-2 Nginx needs no change after renewals.