# FIXES.md
 
**DevOps Take-Home Assignment — Bug Report & Fix Documentation**
 
---
 
## Summary
 
| # | Issue | Severity | File |
|---|---|---|---|
| 1 | Wrong service URL in docker-compose.yml | 🔴 CRITICAL | `docker-compose.yml` |
| 2 | Secrets hardcoded in service-a Dockerfile | 🔴 CRITICAL | `service-a/Dockerfile` |
| 3 | Running as root in service-a Dockerfile | 🟠 SECURITY | `service-a/Dockerfile` |
| 4 | Running as root in service-b Dockerfile | 🟠 SECURITY | `service-b/Dockerfile` |
| 5 | `npm install` instead of `npm ci` + missing lockfile | 🟡 RELIABILITY | `service-b/Dockerfile` |
| 6 | Hardcoded credentials in GitHub Actions workflow | 🔴 CRITICAL | `.github/workflows/deploy.yml` |
| 7 | Docker Hub requires PAT token not password | 🔴 CRITICAL | GitHub Secrets |
| 8 | Fake image name in Kubernetes deployment | 🔴 CRITICAL | `k8s/deployment.yaml` |
| 9 | Hardcoded AWS credentials in Terraform | 🔴 CRITICAL | `terraform/main.tf` |
| 10 | Security group open to all ports | 🟠 SECURITY | `terraform/main.tf` |
| 11 | Missing vpc_id in security group | 🟠 SECURITY | `terraform/main.tf` |
| 12 | All values hardcoded — no variables | 🟡 RELIABILITY | `terraform/main.tf` |
| 13 | Missing VPC, subnet, IGW and route table | 🟡 RELIABILITY | `terraform/main.tf` |
 
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

## Fix : Docker Hub authentication failing — requires Personal Access Token (PAT)

**What was wrong:**
The GitHub Actions pipeline was using the Docker Hub account password directly as `DOCKER_PASSWORD` secret. Docker Hub now requires a Personal Access Token (PAT) instead of a plain password for CLI and API authentication.

**Why it is a problem:**
Docker Hub blocked the login with this error:
```
Error response from daemon: unauthorized: your account must log in with a
Personal Access Token (PAT)
```
This caused the entire pipeline to fail at the login step, meaning no image could be built or pushed to Docker Hub. The build and deploy jobs both fail as a result.

**How I fixed it:**
Generated a Personal Access Token on Docker Hub with `Read & Write` access and updated the `DOCKER_PASSWORD` GitHub secret with the PAT value instead of the account password. No changes were needed to the pipeline file itself — it already used `--password-stdin` which is the correct and secure way to pass credentials to Docker.

**Steps to generate and apply the PAT:**

1. Go to Docker Hub and generate the token:
```
https://hub.docker.com
→ Account Settings
→ Security
→ Personal Access Tokens
→ Generate New Token
  → Description: github-actions
  → Access: Read & Write
  → Click Generate
  → Copy the token: dckr_pat_xxxxxxxxxxxx
```

2. Update the GitHub secret:
```
GitHub Repo
→ Settings
→ Secrets and variables
→ Actions
→ DOCKER_PASSWORD → Edit
→ Paste the PAT token
→ Click Update secret
```

3. Trigger the pipeline:
```bash
git commit --allow-empty -m "fix: switch Docker Hub auth to PAT token"
git push origin main
```

**What the pipeline login step looks like — no changes needed:**

```yaml
- name: Log in to Docker Hub
  run: echo "${{ secrets.DOCKER_PASSWORD }}" | docker login -u "${{ secrets.DOCKER_USERNAME }}" --password-stdin
```

- `DOCKER_USERNAME` — stays as `akondocker97`, no change needed
- `DOCKER_PASSWORD` — updated from plain password to PAT token `dckr_pat_xxxxxxxxxxxx`

**What could go wrong if left unfixed:**
The pipeline fails on every push at the Docker login step. No images can be built or pushed to Docker Hub. The deploy job never runs because it depends on the build job succeeding. The entire CI/CD pipeline is broken.

---

**Git commit:**

```bash
git commit --allow-empty -m "fix: switch Docker Hub auth to PAT token"
git push origin main
```

--

## Fix : Hardcoded AWS credentials in Terraform provider
 
**What was wrong:**
Real AWS `access_key` and `secret_key` values were hardcoded directly in the provider block of `main.tf`.
 
**Why it is a problem:**
Committing credentials to a git repository exposes them permanently in the commit history. Even if deleted in a later commit, they remain readable via `git log`. Anyone with repo access can use the keys to provision AWS resources, incur costs, or exfiltrate data. Bots scan GitHub continuously for exposed AWS keys and can use them within minutes.
 
**How I fixed it:**
Removed the hardcoded credentials entirely from the provider block. Terraform's AWS provider automatically reads from environment variables `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` or from `~/.aws/credentials`. Region is now read from `var.aws_region` defined in `variables.tf`.
 
```hcl
# Before — credentials hardcoded in plain text
provider "aws" {
  region     = "us-east-1"
  access_key = "AKIAIOSFODNN7EXAMPLE"
  secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
}
 
# After — credentials from environment variables
provider "aws" {
  region = var.aws_region
}
```
 
Set credentials via environment variables:
```bash
export AWS_ACCESS_KEY_ID=your_real_key
export AWS_SECRET_ACCESS_KEY=your_real_secret
```
 
**What could go wrong if left unfixed:**
AWS account compromised. Attacker can spin up infrastructure, mine cryptocurrency, or exfiltrate data — all billed to the account owner.
 
---
 
## Fix : Security group open to all ports from all IPs
 
**What was wrong:**
Both ingress and egress rules allowed all TCP ports (0–65535) from `0.0.0.0/0`. No `description` was set on rules. `vpc_id` was missing from the security group.
 
**Why it is a problem:**
Fully open firewall exposes SSH (22), database ports, and admin interfaces to the entire internet. Without `vpc_id`, the security group attaches to the default VPC which may not be the intended network. Missing descriptions make it impossible to understand the purpose of each rule during audits.
 
**How I fixed it:**
Restricted ingress to port 5000 only. Restricted egress to port 443 (HTTPS) only. Added `description` to each rule. Attached security group to the created VPC using `aws_vpc.main.id`.
 
```hcl
# Before — all ports open, no vpc_id, no descriptions
resource "aws_security_group" "app_sg" {
  name = "app-sg"
 
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
 
  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
 
# After — restricted ports, vpc_id added, descriptions added
resource "aws_security_group" "app_sg" {
  name        = "${local.project_name}-sg"
  description = "Security group for devops-app"
  vpc_id      = aws_vpc.main.id
 
  ingress {
    description = "Allow app traffic on port 5000"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
 
  egress {
    description = "Allow HTTPS outbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
 
  tags = local.tags
}
```
 
**What could go wrong if left unfixed:**
Instance completely exposed to the internet. Automated bots attempt brute-force on port 22 within minutes of launch. Security group in wrong VPC causes unpredictable network behaviour.
 
---
 
## Fix : All static values hardcoded in resource blocks
 
**What was wrong:**
AMI ID, instance type, region, and all other values were hardcoded directly in the resource and provider blocks with no variables.
 
**Why it is a problem:**
Hardcoded values make the config impossible to reuse across environments (dev, staging, prod) without editing source files directly. Changes require a code commit. No documentation of what values are configurable.
 
**How I fixed it:**
Extracted all values into a separate `variables.tf` file with descriptions and sensible defaults. Resources now reference `var.*` instead of hardcoded strings.
 
```hcl
# Before — hardcoded everywhere
resource "aws_instance" "app" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t2.micro"
}
 
# After — values from variables.tf
resource "aws_instance" "app" {
  ami           = var.ami_id
  instance_type = var.instance_type
}
```
 
**What could go wrong if left unfixed:**
Cannot deploy to multiple environments. Easy to introduce typos when copying values. No single source of truth for configurable values.
 
---
 
## Fix : Duplicate variables in variables.tf
 
**What was wrong:**
`variables.tf` had `aws_region`, `ami_id`, `instance_type`, `vpc_cidr`, `subnet_cidr`, and `availability_zone` declared twice each.
 
**Why it is a problem:**
Terraform throws a validation error and refuses to run:
```
Error: Duplicate variable declaration
```
The entire infrastructure cannot be planned or applied until duplicates are removed.
 
**How I fixed it:**
Removed all duplicate variable declarations. Each variable now appears exactly once in `variables.tf`.
 
```hcl
# Before — duplicate declarations (causes terraform error)
variable "aws_region" { ... }
variable "aws_region" { ... }  # duplicate — ERROR
 
variable "ami_id" { ... }
variable "ami_id" { ... }      # duplicate — ERROR
 
# After — each variable declared exactly once
variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}
 
variable "ami_id" {
  description = "AMI ID for EC2 instance"
  type        = string
  default     = "ami-0c55b159cbfafe1f0"
}
```
 
**What could go wrong if left unfixed:**
`terraform plan` and `terraform apply` both fail immediately. No infrastructure can be created or modified until the error is fixed.
 
---
 
## Fix : Missing VPC, subnet, internet gateway and route table
 
**What was wrong:**
The original `main.tf` had only an EC2 instance and a security group. There was no VPC, subnet, internet gateway, or route table defined. The EC2 instance would be placed in the default AWS VPC with no controlled networking.
 
**Why it is a problem:**
Using the default VPC is insecure and uncontrolled. There is no isolation between this project and other resources in the account. The default VPC cannot be version-controlled or reproduced consistently across accounts or regions.
 
**How I fixed it:**
Added a complete networking stack managed by Terraform: VPC → Internet Gateway → Public Subnet → Route Table (with IGW route) → Route Table Association → Security Group → EC2 in the subnet.
 
```hcl
# Added — full networking stack
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags       = local.tags
}
 
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = local.tags
}
 
resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.subnet_cidr
  availability_zone = var.availability_zone
  tags              = local.tags
}
 
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
 
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
 
  tags = local.tags
}
 
resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
```
 
**What could go wrong if left unfixed:**
EC2 instance placed in default VPC with no controlled networking. Cannot reproduce infrastructure across accounts. No isolation between project resources and other AWS resources in the account.
 
---
 
## Self-Initiated Improvement: Added locals block for consistent tagging
 
Instead of repeating tag values in every resource, a `locals` block defines tags once and all resources reference `local.tags`. This ensures every resource has consistent `Name`, `Environment`, `Project`, and `ManagedBy` tags automatically.
 
```hcl
locals {
  project_name = "${var.environment}-${var.project}"
  tags = {
    Name        = local.project_name
    Environment = var.environment
    Project     = var.project
    ManagedBy   = "Terraform"
  }
}
```
 
Every resource simply uses:
```hcl
tags = local.tags
```
 
This means adding a new tag only requires changing one place — the `locals` block — instead of editing every resource individually.
 
---



