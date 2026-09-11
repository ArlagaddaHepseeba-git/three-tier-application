# DevOps Practice Project

A simple **To-Do list app** (React + Spring Boot + MySQL) designed for practicing
**DevOps** — the job of automating how software is built, tested, and deployed.

Think of it like a restaurant split into 3 parts:

| Part | What it does | Technology | Port |
|------|--------------|------------|------|
| **Frontend** | The waiter — what you see | React | 3000 |
| **Backend** | The kitchen — the logic | Spring Boot (Java) | 8080 |
| **Database** | The fridge — where data is stored | MySQL | 3306 |

```
Browser
   │
   ▼
[Frontend]  React  —  http://localhost:3000
   │
   │  REST API (axios / HTTP)
   ▼
[Backend]   Spring Boot  —  http://localhost:8080/api
   │
   │  JPA (Java ↔ MySQL adapter)
   ▼
[Database]  MySQL  —  devops_practice_db
```

---

## What the app does

A simple list you can:
- **See** existing items (starts with 7 sample items)
- **Add** new items
- **Delete** items
- **Check** that the backend is alive ("healthy" / "Unreachable" status)

---

## Screenshots

> Add your screenshots here: save each image into `docs/screenshots/`
> with the exact filename below, then commit.

![App home page](docs/screenshots/app-home.png)
*The app running at http://localhost:3000*

![Items API](docs/screenshots/api-items.png)
*Backend data: http://localhost:8080/api/items*

![Grafana dashboard](docs/screenshots/grafana-dashboard.png)
*Live monitoring at http://localhost:3001*

![GitHub Actions](docs/screenshots/github-actions.png)
*CI results — Actions tab on GitHub*

![Database in DBeaver](docs/screenshots/dbeaver-database.png)
*The database seen in DBeaver*

---

## Run it on your computer

### Step 0 — One-time installs

You need these installed: **Java 17**, **Maven**, **Node.js**, **MySQL**.
Check them with:

```bash
java -version
mvn -version
node -v
mysql --version
```

### Step 1 — Start the database

```bash
mysql -u root -p < database/init.sql
```

This one-time command creates the database, tables, and 7 sample items.

### Step 2 — Start the backend (Terminal 1)

```bash
cd backend
mvn clean package
mvn spring-boot:run
```

Wait until you see `Tomcat started on ports 8443 (https), 8080 (http)`.

### Step 3 — Start the frontend (Terminal 2)

```bash
cd frontend
npm install        # only the first time
npm start
```

### Step 4 — Open the app

Open **http://localhost:3000** in your browser.

**Tip:** if the status shows red "Unreachable", the frontend is pointing at the
HTTPS backend which the browser doesn't trust yet. Easiest fix: start it against
plain HTTP instead:

```bash
REACT_APP_API_URL=http://localhost:8080/api npm start
```

---

## Backend API (what the kitchen accepts)

| Method | URL                | Action       |
|--------|--------------------|--------------|
| GET    | /api/health        | Is it alive? |
| GET    | /api/items         | List all     |
| POST   | /api/items         | Add one      |
| DELETE | /api/items/{id}    | Delete one   |

Example:

```bash
curl http://localhost:8080/api/items
curl -X POST http://localhost:8080/api/items -H "Content-Type: application/json" -d '{"name":"Learn load balancing"}'
```

---

## The full DevOps toolkit (in this repo)

Each tool's config lives in its own folder, and every one is **auto-checked by CI**
on every push (see the `Actions` tab on GitHub).

| Tool | What it does in plain words | Folder |
|------|-----------------------------|--------|
| **GitHub Actions (CI)** | Builds + tests your code automatically on every push | `.github/workflows/ci.yml` |
| **Docker** | Packages each part (frontend/backend/database) into named boxes that run anywhere | `backend/Dockerfile`, `frontend/Dockerfile`, `docker-compose.yml` |
| **Kubernetes** | The "air traffic controller" — runs those boxes, keeps copies alive, restarts them if they crash | `k8s/` |
| **Terraform** | Cloud-as-code — writes the AWS server setup as text files | `terraform/` |
| **Prometheus + Grafana** | Watches the app live and shows pretty graphs | `monitoring/` |

### Run everything at once with Docker

```bash
docker compose up
```

Open **http://localhost:3000**. (Needs Docker Desktop. Stop the local backend + MySQL first — they use the same ports.)

### Run monitoring (Prometheus + Grafana)

```bash
cd monitoring
docker compose -f docker-compose.monitoring.yml up
```

- Prometheus: http://localhost:9090
- Grafana: **http://localhost:3001** (login not required)

### Deploy to Kubernetes

```bash
docker build -t three-tier/backend ./backend
docker build -t three-tier/frontend ./frontend
kubectl apply -f k8s/
```

Open **http://localhost:30000**. (Needs Docker + Minikube/kind.)

### Deploy to AWS (free tier)

```bash
cd terraform
terraform init
terraform apply        # type "yes"
```

Terraform creates a server that automatically installs the app and gives you a public URL.

---

## Project structure

```
three-tier-application/
├── frontend/          # React app (what you see)
├── backend/           # Spring Boot app (business logic)
├── database/          # MySQL setup script
├── deploy/            # Production deployment scripts
├── k8s/               # Kubernetes manifests
├── terraform/         # AWS infrastructure-as-code
├── monitoring/        # Prometheus + Grafana configs
└── .github/workflows/ # CI/CD pipeline
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| "Unreachable" / items won't load | Use `REACT_APP_API_URL=http://localhost:8080/api npm start` |
| Backend won't start | Is MySQL running? Is `database/init.sql` applied? |
| Port 3000 already in use | Close the other React app, or change port |
| Docker port conflict (3306/8080) | Stop the local backend + MySQL before `docker compose up` |