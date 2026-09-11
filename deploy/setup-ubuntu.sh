#!/usr/bin/env bash
# ==============================================================
# Production deployment script for the three-tier app on Ubuntu 24.04
# HTTPS via Let's Encrypt (certbot) + Nginx TLS termination
#
#   Nginx :443 (certbot cert) -> serves React build   = FRONTEND HTTPS
#   Nginx :443 /api/*         -> proxy to Tomcat :8080 = BACKEND HTTPS
#   Nginx :80  /api/*         -> proxy to Tomcat :8080 = BACKEND HTTP
#   Nginx :80  everything else -> 301 redirect HTTPS    (frontend)
#     Tomcat10 :8080 (backend WAR, production profile, plain HTTP)
#     MySQL (devops_practice_db)
#
# Usage:  sudo bash deploy/setup-ubuntu.sh
# Run it once after pointing your domain (A record) at this server.
# ==============================================================
set -euo pipefail

# ==================== CONFIGURE THESE =========================
DOMAIN="app.yoursite.com"          # must resolve (A record) to this server
CERTBOT_EMAIL="admin@yoursite.com" # cert expiry emails
DB_NAME="devops_practice_db"       # matches database/init.sql
DB_USER="devops_app"               # dedicated app user (more secure than root)
DB_PASS="ChangeMe_EnterShadows"    # CHANGE THIS
REPO_URL="https://github.com/YOUR-USER/YOUR-REPO.git" # CHANGE THIS
# ==============================================================

echo "==> [1/9] Install system packages (Java, Maven, Node, Nginx, certbot, MySQL, Tomcat)"
sudo apt update
sudo apt install -y openjdk-17-jre nginx certbot python3-certbot-nginx mysql-server tomcat10 curl
# Node 20 from NodeSource (Ubuntu's bundled node is too old for CRA)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
sudo apt install -y maven

echo "==> [2/9] Clone the repo"
cd /opt
sudo git clone "$REPO_URL" three-tier-app || sudo git -C /opt/three-tier-app pull
cd /opt/three-tier-app

echo "==> [3/9] Create database + import init.sql"
sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'root';" 2>/dev/null || true
sudo mysql -u root -proot < database/init.sql
sudo mysql -u root -proot -e \
  "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
   GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
   FLUSH PRIVILEGES;"

echo "==> [4/9] Build the backend WAR"
cd /opt/three-tier-app/backend
sudo mvn -q clean package -DskipTests
sudo cp target/backend-1.0.0.war /var/lib/tomcat10/webapps/ROOT.war

echo "==> [5/9] Configure Tomcat (production profile + DB env vars)"
sudo tee /etc/default/tomcat10 >/dev/null <<EOF
# Production profile: Nginx handles TLS, backend stays on plain HTTP 8080.
JAVA_OPTS="-Dspring.profiles.active=production \
  -DDB_URL=jdbc:mysql://localhost:3306/$DB_NAME \
  -DDB_USERNAME=$DB_USER \
  -DDB_PASSWORD=$DB_PASS"
EOF
sudo systemctl restart tomcat10
echo "    Waiting for the API to come up on :8080..."
for i in $(seq 1 30); do
  if curl -sf http://127.0.0.1:8080/api/health >/dev/null; then break; fi
  sleep 2
done
curl -s http://127.0.0.1:8080/api/health && echo " [OK] backend is up"

echo "==> [6/9] Build the frontend (relative /api URL -> same origin via Nginx)"
cd /opt/three-tier-app/frontend
sudo npm ci
REACT_APP_API_URL=/api sudo -E npm run build
sudo rm -rf /var/www/html/* /var/www/html/.[!.]* 2>/dev/null || true
sudo cp -r build/* /var/www/html/

echo "==> [7/9] Nginx - phase 1: bootstrap (HTTP only, so certbot can run)"
sudo sed "s/app.yoursite.com/$DOMAIN/g" /opt/three-tier-app/deploy/nginx-http.conf \
  > /etc/nginx/sites-available/three-tier
sudo ln -sf /etc/nginx/sites-available/three-tier /etc/nginx/sites-enabled/three-tier
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
echo "    Bootstrap live at http://$DOMAIN (read to receive the cert challenge)"

echo "==> [8/9] Issue the Let's Encrypt certificate (certbot certonly)"
sudo certbot certonly --nginx -d "$DOMAIN" \
  --non-interactive --agree-tos \
  -m "$CERTBOT_EMAIL"
echo "    Cert issued and stored in /etc/letsencrypt/live/$DOMAIN/"

echo "    Nginx - phase 2: install FINAL config (Frontend HTTPS + Backend HTTPS + HTTP)"
sudo sed "s/app.yoursite.com/$DOMAIN/g" /opt/three-tier-app/deploy/nginx-three-tier.conf \
  > /etc/nginx/sites-available/three-tier
sudo nginx -t
sudo systemctl reload nginx

echo "==> [9/9] Verify (frontend HTTPS, backend HTTPS, backend HTTP)"
echo "    - https://$DOMAIN/               (Frontend HTTPS)"
echo "    - https://$DOMAIN/api/health     (Backend HTTPS)"
echo "    - http://$DOMAIN/api/health      (Backend HTTP)"
curl -s "https://$DOMAIN/api/health" && echo " [OK] backend over HTTPS"
curl -s "http://$DOMAIN/api/health"  && echo " [OK] backend over HTTP"
curl -sI "http://$DOMAIN/" | grep -qi '^location: https' && echo " [OK] frontend redirects HTTP -> HTTPS"
sudo certbot certificates
echo -n "    Auto-renewal timer: "
sudo systemctl list-timers certbot.timer --no-pager | grep -q certbot.timer && echo "enabled" || echo "NOT enabled, run: sudo systemctl enable --now certbot.timer"

echo ""
echo "=============================================================="
echo " Done. The app is live at https://$DOMAIN"
echo " Cert auto-renews via certbot.timer (check: renew --dry-run)."
echo "=============================================================="