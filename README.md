# DevOps Practice Project

A simple three-tier application (React + Spring Boot + MySQL) that you can build, run, and
push to GitHub — then practice DevOps with it in as many ways as you want
(Docker, Kubernetes, CI/CD, Terraform, monitoring, etc.).

## Architecture

| Tier     | Technology                 | Folder       | Port |
|----------|----------------------------|--------------|------|
| Frontend | React 18 (create-react-app)| `frontend/`  | 3000 |
| Backend  | Java 17 + Spring Boot 3    | `backend/`   | 8080 |
| Database | MySQL 8                    | `database/`  | 3306 |

```
Browser
   │
   ▼
[Frontend]  React  —  http://localhost:3000
   │
   │  REST API (axios)
   ▼
[Backend]   Spring Boot  —  http://localhost:8080/api
   │
   │  JPA / JDBC
   ▼
[Database]  MySQL  —  devops_practice_db
```

## Prerequisites

- Java 17+ (LTS)
- Maven 3.8+
- Node.js 18+
- MySQL 8+

```bash
java -version      # must show 17+
mvn -version
node -v
npm -v
mysql --version
```

## 1. Set up the database

```bash
mysql -u root -p < database/init.sql
```

This creates the `devops_practice_db` database with an `items` table and seed data.

If you don't have MySQL installed locally, it's a great first Docker exercise:

```bash
docker run -d --name mysql \
  -p 3306:3306 \
  -e MYSQL_ROOT_PASSWORD=root \
  -e MYSQL_DATABASE=devops_practice_db \
  mysql:8
```

## 2. Run the backend (Spring Boot - WAR)

```bash
cd backend
mvn clean package
mvn spring-boot:run     # option A: run directly (works even with WAR packaging)
```

**Option B — deploy the WAR to an external Tomcat:**
```bash
cp target/backend-1.0.0.war "C:\Program Files\Apache Software Foundation\Tomcat 10\webapps\"
cd "C:\Program Files\Apache Software Foundation\Tomcat 10\bin" && catalina.bat run
```

The WAR doesn't bundle Tomcat (scope `provided`), so `java -jar target/backend-1.0.0.war`
is intentionally NOT supported when deploying manually.

**The API now runs on BOTH:**

| Protocol | URL                  | Description       |
|----------|----------------------|-------------------|
| HTTPS    | https://localhost:8443/api | Secure backend (mkcert cert) |
| HTTP     | http://localhost:8080/api  | Plain backend      |

| Method | URL                  | Description       |
|--------|----------------------|-------------------|
| GET    | /api/health          | Health check      |
| GET    | /api/items           | List all items    |
| POST   | /api/items           | Add an item       |
| DELETE | /api/items/{id}      | Delete an item    |

Config is controlled by environment variables (see `application.properties`):

| Variable    | Default                              |
|-------------|--------------------------------------|
| DB_URL      | jdbc:mysql://localhost:3306/devops_practice_db |
| DB_USERNAME | root                                 |
| DB_PASSWORD | root                                 |
| PORT        | 8443 (HTTPS)                         |
| HTTP_PORT   | 8080 (HTTP)                          |

### HTTPS (mkcert locally-trusted certs)

The app uses HTTPS with `mkcert` so your browser trusts the cert (no warnings).

```bash
mkcert -install                              # one-time: install local CA
cd backend/src/main/resources/ssl
mkcert -key-file localhost.key -cert-file localhost.pem localhost 127.0.0.1 ::1
openssl pkcs12 -export \
  -in localhost.pem -inkey localhost.key \
  -out localhost.p12 -name devops-practice -passout pass:changeit
```

Spring Boot loads the keystore from `application.properties`
(`server.ssl.key-store=classpath:ssl/localhost.p12`, password `changeit`).
The `ssl/` folder is git-ignored — don't commit private keys.

For the frontend build, point it at the HTTPS backend:
```bash
REACT_APP_API_URL=https://localhost:8443/api npm run build
```

Run tests:
```bash
cd backend
mvn test
```

## 3. Run the frontend (React)

```bash
cd frontend
npm install
npm start
```

Open `http://localhost:3000`. It talks to the backend at `https://localhost:8443/api`.

### Serve the production build on BOTH HTTP + HTTPS

```bash
cd frontend
npm run build    # creates build/ folder
npm run serve    # serves build/ on http://localhost:3000 AND https://localhost:3001
```

| Protocol | URL                        |
|----------|----------------------------|
| HTTP     | http://localhost:3000      |
| HTTPS    | https://localhost:3001     |

(Uses the same mkcert certs from `backend/src/main/resources/ssl/`.)

The API URL is configurable (build-time env var):
```bash
REACT_APP_API_URL=https://localhost:8443/api npm run build
```

## 4. Push to GitHub

```bash
git init
git add .
git commit -m "Initial commit: three-tier devops practice app"
git branch -M main
git remote add origin https://github.com/<your-username>/<your-repo>.git
git push -u origin main
```

## 5. Production deployment (Ubuntu + certbot)

The `deploy/` folder contains everything to deploy this app on an Ubuntu
server with a real Let's Encrypt certificate via certbot + Nginx TLS
termination: `deploy/setup-ubuntu.sh`, `deploy/nginx-three-tier.conf`,
`deploy/README.md`, and a `production` Spring profile
(`application-production.properties`). See `deploy/README.md` for the full
guide.

## API examples

```bash
# Health check
curl http://localhost:8080/api/health

# List items
curl http://localhost:8080/api/items

# Add an item
curl -X POST http://localhost:8080/api/items \
  -H "Content-Type: application/json" \
  -d '{"name":"Learn load balancing"}'

# Delete an item
curl -X DELETE http://localhost:8080/api/items/1
```

## Project structure

```
├── frontend/                     # React app (npm build)
│   ├── public/
│   ├── src/
│   │   ├── App.js                # UI + API calls
│   │   └── index.js
│   └── package.json
├── backend/                      # Spring Boot app (mvn package)
│   ├── pom.xml
│   └── src/main/java/com/devops/practice/app/
│       ├── DevOpsPracticeApplication.java
│       ├── config/CorsConfig.java
│       ├── controller/           # REST controllers
│       ├── service/              # Business logic
│       ├── repository/           # Spring Data JPA
│       └── entity/Item.java
│   └── src/main/resources/application.properties
└── database/
    └── init.sql                  # Tables + seed data
```

## Ideas for DevOps practice

Once your code is on GitHub, try:

1. **Docker** — write `Dockerfile`s for frontend/backend, then a `docker-compose.yml` for all three tiers
2. **GitHub Actions** — add a CI workflow that runs `mvn test` + `npm build` on every push
3. **Kubernetes** — create manifests/configmaps/secrets, deploy with Minikube or kind
4. **Helm** — package your Kubernetes manifests as Helm charts
5. **Terraform** — provision the cloud infra (EC2/ECS/RDS) with IaC
6. **Monitoring** — wire Prometheus + Grafana to the Spring Actuator `/actuator/prometheus`
7. **CI/CD** — build images on push, scan with Trivy, deploy to ECS/EKS/self-hosted
8. **Database** — practice migrations, `mysqldump` backups, replication

Happy practicing!