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
 
## Fix : Running as root — service-b Dockerfile
 
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
 
## Fix : Missing package-lock.json for npm ci
 
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

## Fix : Hardcoded credentials in GitHub Actions workflow
 
**What was wrong:**
The `.github/workflows/deploy.yml` file had real Docker Hub credentials hardcoded directly in the workflow file — username and password were both visible in plain text. A hardcoded server IP with root SSH access was also present.
 
**Why it is a problem:**
Any file committed to a GitHub repository is visible to everyone with repo access. If the repo is public, the credentials are exposed to the entire internet. Even in a private repo, credentials in code are a serious security risk — they get copied, shared, and leaked. The password is also permanently in the git history even after deletion.
 
**How I fixed it:**
Removed all hardcoded credentials. Moved them to GitHub repository secrets which are encrypted, never exposed in logs, and not visible even to repo admins after being set. Used `--password-stdin` instead of passing the password via CLI flag.
 
```yaml
# Before — credentials hardcoded in plain text
- name: Build and push
  run: |
    docker login -u myuser -p admin@123
    docker build -t myorg/devops-app:latest ./service-a
    docker push myorg/devops-app:latest
 
# After — credentials read from GitHub secrets
- name: Log in to Docker Hub
  run: echo "${{ secrets.DOCKER_PASSWORD }}" | docker login -u "${{ secrets.DOCKER_USERNAME }}" --password-stdin
 
- name: Build and push service-a
  run: |
    docker build -t ${{ secrets.DOCKER_USERNAME }}/devops-app:latest ./service-a
    docker push ${{ secrets.DOCKER_USERNAME }}/devops-app:latest
```
 
**Secrets added to GitHub:**
 
| Secret Name | Description |
|---|---|
| `DOCKER_USERNAME` | Docker Hub username |
| `DOCKER_PASSWORD` | Docker Hub password or access token |
 
**What changed:**
- Hardcoded `akondocker97` → `${{ secrets.DOCKER_USERNAME }}`
- Hardcoded password → `${{ secrets.DOCKER_PASSWORD }}` via `--password-stdin`
- Removed hardcoded root SSH with IP address — needs proper `SSH_PRIVATE_KEY` secret
 
**What could go wrong if left unfixed:**
Docker Hub account gets compromised. Anyone with repo access can pull, push, or delete your Docker images. If the repo is public, credentials are exposed to the entire internet and bots will find them within minutes.
 
---


## Fix : Kubernetes deployment not accessible from localhost
 
**What was wrong:**
The `k8s/deployment.yaml` had three issues:
- `image: myorg/devops-app:latest` was a fake placeholder image name, not a real Docker Hub image
- The Service had no `type` defined, defaulting to `ClusterIP` which is only accessible inside the cluster
- No `nodePort` was set, so there was no way to reach the app from the browser or curl on the Mac
- No `livenessProbe` or `readinessProbe` defined, so Kubernetes had no way to detect a crashed pod
- No resource `limits` set, only `requests`
 
**Why it is a problem:**
With a fake image name the pod fails to start because Kubernetes cannot pull the image from Docker Hub. With `ClusterIP` as the service type, the app is completely unreachable from outside the cluster — `curl http://localhost:30500/health` returns connection refused. Without health probes, Kubernetes keeps routing traffic to a crashed or unresponsive pod with no automatic recovery.
 
**How I fixed it:**
Updated the image to the real Docker Hub image `akondocker97/devops-app:latest`. Changed the Service type to `NodePort` with `nodePort: 30500` so the app is reachable from localhost. Added `livenessProbe` and `readinessProbe` pointing to the `/health` endpoint. Added resource `limits` alongside the existing `requests`.
 
```yaml
# Before
containers:
- name: service-a
  image: myorg/devops-app:latest        # fake image
  ports:
  - containerPort: 5000
  resources:
    requests:
      memory: "64Mi"
      cpu: "50m"
                                        # no probes
                                        # no limits
 
---
apiVersion: v1
kind: Service
spec:
  selector:
    app: service-a
  ports:                                # no type = ClusterIP only
  - port: 5000
    targetPort: 5000
                                        # no nodePort
```
 
```yaml
# After
containers:
- name: service-a
  image: akondocker97/devops-app:latest
  ports:
  - containerPort: 5000
  resources:
    requests:
      memory: "64Mi"
      cpu: "50m"
    limits:
      memory: "128Mi"
      cpu: "200m"
  livenessProbe:
    httpGet:
      path: /health
      port: 5000
    initialDelaySeconds: 10
    periodSeconds: 15
  readinessProbe:
    httpGet:
      path: /health
      port: 5000
    initialDelaySeconds: 5
    periodSeconds: 10
 
---
apiVersion: v1
kind: Service
spec:
  selector:
    app: service-a
  type: NodePort
  ports:
  - port: 5000
    targetPort: 5000
    nodePort: 30500
```
 
**What could go wrong if left unfixed:**
Pod fails to start due to image pull error. App is completely unreachable from outside the cluster. Crashed pods are not restarted automatically. A runaway pod can consume all CPU and memory on the node, affecting other workloads.
 
---
 
## How to deploy and test locally
 
### Prerequisites
- Docker Desktop running with Kubernetes enabled
- `kubectl` installed (`brew install kubectl`)
- Image pushed to Docker Hub (`akondocker97/devops-app:latest`)
 
### Deploy to local Kubernetes
 
```bash
# Apply the deployment
kubectl apply -f k8s/deployment.yaml
 
# Watch pod come up
kubectl get pods -w
 
# Expected output:
# NAME                         READY   STATUS    RESTARTS   AGE
# service-a-796c6fffd9-xxxxx   1/1     Running   0          22s
```
 
### Access the app
 
Docker Desktop on Mac does not always expose NodePort to localhost directly. Use port-forward instead:
 
```bash
# Terminal 1 — keep this running
kubectl port-forward svc/service-a 5000:5000
 
# Expected output:
# Forwarding from 127.0.0.1:5000 -> 5000
```
 
```bash
# Terminal 2 — test all endpoints
curl http://localhost:5000/health
# Expected: {"status": "healthy"}
 
curl http://localhost:5000/data
# Expected: {"records": [1, 2, 3, 4, 5], "source": "service-a"}
 
curl http://localhost:5000/
# Expected: {"status": "ok", "service": "service-a", "message": "Hello from Service A!"}
```
 
### Useful commands
 
```bash
# Check pod status
kubectl get pods
 
# Check service
kubectl get svc
 
# View pod logs
kubectl logs -l app=service-a
 
# Describe pod (useful for debugging)
kubectl describe pod -l app=service-a
 
# Delete and redeploy
kubectl delete -f k8s/deployment.yaml
kubectl apply -f k8s/deployment.yaml
 
# Stop everything
kubectl delete -f k8s/deployment.yaml
```
 
**What could go wrong if left unfixed:**
Without port-forward or a proper ingress, the app is unreachable on Mac even with NodePort set. The deployment would silently appear healthy while being completely inaccessible for testing and verification.
 
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

