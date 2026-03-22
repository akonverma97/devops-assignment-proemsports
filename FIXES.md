# FIXES.md

Document every issue you find and fix in this file.

---

## Fix : Hardcoded credentials moved to .env for secure configuration

**What was wrong:**
Credentials were directly defined inside Docker-related configuration (e.g., Dockerfile or compose setup), making them part of the codebase and potentially exposed in version control.

**Why it is a problem:**
Hardcoding sensitive data like passwords or API keys is a major security risk. If the repository is shared or made public, these credentials can be easily accessed. It also makes changing credentials harder across environments (dev, staging, production).

**How I fixed it:**
Removed all hardcoded credentials from Docker configuration and moved them into a .env file. Updated the application and Docker setup to read values from environment variables.

```dockerfile
# Removed from Dockerfile:
ENV SECRET_KEY=supersecret123   # DELETED
ENV DB_PASSWORD=admin1234       # DELETED

# docker-compose.yml now reads from .env file:
environment:
  - SECRET_KEY=${SECRET_KEY}
  - DB_PASSWORD=${DB_PASSWORD}
```

```bash
# .env file (gitignored — never commit this)
SECRET_KEY=supersecret123
DB_PASSWORD=admin1234
```
---

## Fix : Wrong service URL in docker-compose.yml

**What was wrong:**
`SERVICE_A_URL` was set to `http://localhost:5000`. Inside a Docker container, `localhost` refers to the container itself, not to another service.

**Why it is a problem:**
`service-b` could never reach `service-a`. Every poll attempt failed with a connection refused error, making the entire two-service system non-functional from the moment it starts.

**How I fixed it:**
Changed `SERVICE_A_URL` to `http://service-a:5000`. In Docker Compose, services communicate using their service name as the hostname, which Docker's internal DNS resolves automatically.

```yaml
# Before
environment:
  - SERVICE_A_URL=http://localhost:5000

# After
environment:
  - SERVICE_A_URL=http://service-a:5000
```

**What could go wrong if left unfixed:**
`service-b` logs connection errors every 10 seconds and never successfully polls `service-a`. The system appears to start but is completely broken at runtime.



---
 
## Fix: Running as root — service-a Dockerfile
 
**What was wrong:**
The Dockerfile explicitly set `USER root`, which means the Flask application runs as the root user inside the container. Additionally, `COPY . .` was done before installing dependencies, breaking Docker's layer caching. The full `python:3.11` base image was used when a slim variant is sufficient.
 
**Why it is a problem:**
Running as root inside a container is dangerous. If the Flask app has a vulnerability, an attacker gets root access inside the container. With certain misconfigurations like volume mounts or privileged mode, root inside the container can translate to root on the host machine. The broken layer cache also meant every code change triggered a full `pip install` reinstall, making builds unnecessarily slow.
 
**How I fixed it:**
Removed `USER root` and created a non-privileged `appuser` instead. Restructured the `COPY` order so dependencies are installed first and cached separately from the source code. Switched to the slim base image and added `--no-cache-dir` to keep the image lean.
 
```dockerfile
# Before
FROM python:3.11
 
WORKDIR /app
 
COPY . .
RUN pip install -r requirements.txt
 
EXPOSE 5000
 
USER root
CMD ["python", "app.py"]
 
# After
FROM python:3.11-slim
 
WORKDIR /app
 
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
 
COPY . .
 
EXPOSE 5000
 
RUN adduser --disabled-password --gecos "" appuser
USER appuser
 
CMD ["python", "app.py"]
```
 
**What changed:**
- `python:3.11` → `python:3.11-slim` — saves ~700MB, no build tooling needed at runtime
- `COPY . .` split into two steps — `requirements.txt` copied first so the pip install layer is cached
- `pip install --no-cache-dir` — does not store pip's download cache inside the image
- `USER root` deleted — replaced with `adduser` creating a non-privileged `appuser`
 
**What could go wrong if left unfixed:**
A compromised Flask process has full root access inside the container. Slow builds on every code change because the entire pip install re-runs even when `requirements.txt` has not changed.
 
---
 
## Fix 4: Running as root — service-b Dockerfile
 
**What was wrong:**
Same root user issue as service-a. `COPY . .` was done before `npm install`, breaking layer caching. `npm install` was used instead of `npm ci`, which does not enforce the lockfile and can silently install different package versions than what was tested locally.
 
**Why it is a problem:**
Running the Node.js worker as root means any vulnerability in the worker or its npm dependencies gives an attacker root inside the container. `npm install` can silently resolve different package versions than `package-lock.json` specifies, causing environment drift between local dev and production.
 
**How I fixed it:**
Removed `USER root` and created a non-privileged `appuser`. Restructured the `COPY` order to copy `package*.json` first so the `npm ci` layer is cached independently. Replaced `npm install` with `npm ci` for strict, reproducible installs.
 
```dockerfile
# Before
FROM node:18
 
WORKDIR /app
 
COPY . .
RUN npm install
 
USER root
CMD ["node", "worker.js"]
 
# After
FROM node:18-slim
 
WORKDIR /app
 
COPY package*.json ./
RUN npm ci
 
COPY . .
 
RUN adduser --disabled-password --gecos "" appuser
USER appuser
 
CMD ["node", "worker.js"]
```
 
**What changed:**
- `node:18` → `node:18-slim` — saves ~500MB, only the Node.js runtime is needed
- `COPY package*.json ./` copied first — `npm ci` layer is cached and only re-runs when `package.json` or `package-lock.json` changes
- `npm install` → `npm ci` — strict install that respects `package-lock.json` exactly
- `USER root` deleted — replaced with `adduser` creating a non-privileged `appuser`
 
**What could go wrong if left unfixed:**
Any vulnerability in the Node.js process or npm dependencies gives an attacker root inside the container. Silent package version drift between environments. Full `npm install` on every build even for one-line code changes.
 
---
 
## Fix 5: Missing package-lock.json for npm ci
 
**What was wrong:**
`package-lock.json` was not present in the `service-b` directory, which is required for `npm ci` to work.
 
**Why it is a problem:**
`npm ci` strictly requires a lockfile. Without it the Docker build fails completely with an `EUSAGE` error, blocking the entire build pipeline.
 
**How I fixed it:**
Generated `package-lock.json` locally and committed it to the repo.
 
```bash
cd service-b
npm install        # generates package-lock.json
cd ..
git add service-b/package-lock.json
git commit -m "fix: add package-lock.json to enable npm ci"
```
 
**What could go wrong if left unfixed:**
Docker build for `service-b` fails every time with a hard error. The service cannot be built or deployed.
 
---



## Fix 1: [Short title of the issue]

**What was wrong:**


**Why it is a problem:**


**How I fixed it:**


**What could go wrong if left unfixed:**

---

## Fix 2: [Short title of the issue]

...

---

## Self-initiated Improvements

### Improvement 1:


### Improvement 2:

