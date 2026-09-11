# AWS Deployment — Build Locally, Upload to 2x EC2 + LightSail Managed DB

Deploy the three-tier app with:
- **2 EC2 instances** (frontend nginx, backend Tomcat) — you build artifacts
  **on your laptop** and **upload** them with `scp`. No Maven/Node on servers.
- **1 LightSail managed database** (managed MySQL) — no DB instance to run.

## Architecture

```
                    (HTTPS :443)
Browser  ───────────────────────────►  EC2 FRONTEND  (ubuntu, nginx + certbot)
                                      ├── /         →  React build  (uploaded)
                                      └── /api/*    ─HTTP :8080──► EC2 BACKEND (ubuntu, Tomcat)
                                                                   └── MySQL :3306 ──► LightSail MANAGED DB
                                                                                        (devops_practice_db)
```

- Build on your laptop → `scp` the **WAR** and the **React `build/`** folder
  onto the EC2 boxes → start Tomcat / Nginx.
- LightSail DB is the only database; EC2 backend connects to it.

## Resources & reference values

| Resource | Purpose | Inbound (Security Group) |
|----------|--------|--------------------------|
| EC2 `fe-server` (t3.micro/m2), Ubuntu 24.04 | frontend: nginx + React + certbot | 22 (your IP), 80, 443 (0.0.0.0/0) |
| EC2 `be-server` (t3.micro/m2), Ubuntu 24.04 | backend: Tomcat + WAR | 22 (your IP), 8080 (**source: fe SG**) |
| LightSail `db` (managed MySQL 8.0, 2 GB) | database | Public mode? allow your + backend IPs only |

| Value | Meaning |
|-------|---------|
| `KEY_FILE` | your EC2 `.pem` key path, e.g. `C:\Users\You\Downloads\mykey.pem` |
| `FE_IP` / `BE_IP` | EC2 public IPs (use **Elastic IPs** so they don't change) |
| `BE_PRIV_IP` | backend EC2 **private** IP (Security Groups console / VPC console) |
| `DB_ENDPOINT` | LightSail DB hostname (Databases → your DB) |
| `DB_USER` / `DB_PASS` | master user/password you set on the LightSail DB |
| `YOUR_DOMAIN` | domain, A record → `FE_IP` |

> Put both EC2 instances in the **same region / default VPC** so the frontend
> reaches the backend over private IPs, and create them under the **same free
> tier** (`t2.micro`/`t3.micro`, both eligible).

---

## Step 1 — Build the artifacts on your laptop (Windows / Git Bash)

### Backend → WAR

```bash
cd "C:\Users\Ashok Togaru\Desktop\three-tier application\backend"
export JAVA_HOME="/c/Program Files/Eclipse Adoptium/jdk-17.0.20.101-hotspot"
export PATH="$JAVA_HOME/bin:/c/tools/apache-maven-3.9.9/bin:$PATH"
mvn -q clean package          # skip tests:  mvn -q clean package -DskipTests
ls target/backend-1.0.0.war    # <-- artifact to upload
```

### Frontend → static build (uses the relative /api URL → no CORS)

```bash
cd "C:\Users\Ashok Togaru\Desktop\three-tier application\frontend"
export PATH="/c/Program Files/nodejs:$PATH"
REACT_APP_API_URL=/api npm run build
ls build/index.html             # <-- artifact folder to upload
```

> Both are already built locally today. If you want a fresh build, run the
> commands above; otherwise just upload the existing `target/` and `build/`.

---

## Step 2 — Create the resources (console)

1. **LightSail database** — Databases → Create database → MySQL 8.0, 2 GB.
   Set master username/password. Wait for *Running*, copy the hostname.
   Networking: set **Public** access and add firewall rules allowing
   **your laptop's IP** and the **backend EC2 public IP** (so the backend can
   load the schema and the app can connect). (Private + VPC peering is the
   harder alternative — see notes at the end.)
2. **Two EC2 instances** — Ubuntu Server 24.04, `t2.micro`/`t3.micro`, same
   region/VPC, same key pair (`KEY_FILE`).
3. **Security Groups**:
   - `sg-frontend`: 22 (your IP), 80 + 443 (0.0.0.0/0).
   - `sg-backend`: 22 (your IP), 8080 (source = `sg-frontend`).
   Attach `sg-frontend` to the frontend box, `sg-backend` to the backend box.
4. Allocate **Elastic IPs** to both EC2 instances (Networking → Elastic IPs).

---

## Step 3 — Upload the artifacts (run on your laptop)

```bash
# key file: Git Bash needs correct permissions
chmod 400 "$KEY_FILE"

# BACKEND: WAR + schema script
scp -i "$KEY_FILE" backend/target/backend-1.0.0.war ubuntu@$BE_IP:/tmp/
scp -i "$KEY_FILE" database/init.sql              ubuntu@$BE_IP:/tmp/

# FRONTEND: React build (whole folder)
scp -i "$KEY_FILE" -r frontend/build ubuntu@$FE_IP:/tmp/fe-build

# (optional) your own SSL-over-ssh test:
ssh -i "$KEY_FILE" ubuntu@$FE_IP "echo ok"
```

---

## Step 4 — Backend EC2 (`BE_IP`)

```bash
ssh -i "$KEY_FILE" ubuntu@$BE_IP
```

Install runtime + DB client (NO build tools needed):

```bash
sudo apt update
sudo apt install -y openjdk-17-jre tomcat10 mysql-client
```

Load the schema into the managed DB (from `/tmp/init.sql` you uploaded):

```bash
mysql -h "$DB_ENDPOINT" -P 3306 -u "$DB_USER" -p < /tmp/init.sql
# creates devops_practice_db + tables + seed data
```

Deploy the WAR as ROOT and configure the backend to talk to the managed DB:

```bash
sudo cp /tmp/backend-1.0.0.war /var/lib/tomcat10/webapps/ROOT.war

sudo tee /etc/default/tomcat10 >/dev/null <<EOF
JAVA_OPTS="-Dspring.profiles.active=production \
  -DDB_URL=jdbc:mysql://DB_ENDPOINT:3306/devops_practice_db \
  -DDB_USERNAME=DB_USER \
  -DDB_PASSWORD=DB_PASS"
EOF
sudo systemctl restart tomcat10
```

Trust the frontend proxy (real client IPs in logs) — in
`/etc/tomcat10/server.xml` inside `<Host>`:

```xml
<Valve className="org.apache.catalina.valves.RemoteIpValve"
       internalProxies="FE_PRIVATE_IP"          <!-- frontend EC2 private IP -->
       remoteIpHeader="x-forwarded-for"
       protocolHeader="x-forwarded-proto" />
```

Verify on the server:

```bash
curl http://localhost:8080/api/health      # {"status":"healthy",...}
curl http://localhost:8080/api/items
curl -X POST http://localhost:8080/api/items -H "Content-Type: application/json" -d '{"name":"EC2 test"}'
```

---

## Step 5 — Frontend EC2 (`FE_IP`)

```bash
ssh -i "$KEY_FILE" ubuntu@$FE_IP
```

```bash
sudo apt update
sudo apt install -y nginx certbot python3-certbot-nginx
sudo rm -rf /var/www/html/*
sudo cp -r /tmp/fe-build/* /var/www/html/
```

`/etc/nginx/sites-available/three-tier` — note `proxy_pass` targets the
**backend private IP**:

```nginx
server {
    listen 443 ssl http2;
    server_name YOUR_DOMAIN;

    ssl_certificate     /etc/letsencrypt/live/YOUR_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/YOUR_DOMAIN/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;

    root /var/www/html;
    index index.html;

    location /api/ {
        proxy_pass http://BE_PRIV_IP:8080;
        proxy_http_version 1.1;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 60s;
        proxy_connect_timeout 60s;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }
}

server {
    listen 80;
    server_name YOUR_DOMAIN;

    location /api/ {
        proxy_pass http://BE_PRIV_IP:8080;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto http;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}
```

Install + enable, then issue the HTTPS cert:

```bash
sudo sed -i "s/YOUR_DOMAIN/YOUR_REAL_DOMAIN/g; s/BE_PRIV_IP/REAL-IP/g" /etc/nginx/sites-available/three-tier
sudo ln -sf /etc/nginx/sites-available/three-tier /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx

sudo certbot certonly --nginx -d YOUR_REAL_DOMAIN \
  --non-interactive --agree-tos -m you@your-domain.com
sudo sed -i "s/YOUR_DOMAIN/YOUR_REAL_DOMAIN/g" /etc/nginx/sites-available/three-tier
sudo nginx -t && sudo systemctl reload nginx
```

---

## Step 6 — Verify from your laptop

```bash
curl -sI https://YOUR_REAL_DOMAIN/              # 200 frontend (HTTPS)
curl -s  https://YOUR_REAL_DOMAIN/api/health   # backend → managed DB (end-to-end)
curl -s  https://YOUR_REAL_DOMAIN/api/items    # seed rows present
curl -s  http://YOUR_REAL_DOMAIN/api/health    # backend over HTTP too
curl -sI http://YOUR_REAL_DOMAIN/              # 301 → https
curl -X POST https://YOUR_REAL_DOMAIN/api/items -H "Content-Type: application/json" \
     -d '{"name":"Deployed from laptop"}'      # write end-to-end
```

---

## Next deploy = upload only

Because you build locally, redeploying is just re-running two `scp`s + one
`systemctl restart` — great for practicing CI/CD later:

```bash
scp -i "$KEY_FILE" backend/target/backend-1.0.0.war ubuntu@$BE_IP:/tmp/
ssh -i "$KEY_FILE" ubuntu@$BE_IP "sudo cp /tmp/backend-1.0.0.war /var/lib/tomcat10/webapps/ROOT.war && sudo systemctl restart tomcat10"

scp -i "$KEY_FILE" -r frontend/build ubuntu@$FE_IP:/tmp/fe-build
ssh -i "$KEY_FILE" ubuntu@$FE_IP "sudo rm -rf /var/www/html/* && sudo cp -r /tmp/fe-build/* /var/www/html/"
```

## Security notes

- Keep managed DB at **Public + IP allow-listed** (backend EC2 + your IP), or
  step up to **Private + VPC peering** between your VPC and LightSail — more
  setup, no internet exposure.
- Only the frontend exposes public ports (80/443); backend 8080 is open only
  to the frontend SG; SSH 22 to your IP only.
- EC2 key `.pem` is the root credential — never upload/commit it.
- Elastic IPs stop bills issues when rebooting; delete them when not in use.
- Stop both EC2 instances when idle (managed DB keeps backing up on its own).
- Certs renew automatically via `certbot.timer` on the frontend.