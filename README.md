# DevOps Engineer — Take-home Assignment

## Overview

This repo contains a two-service setup built by a previous engineer. It has several issues that are causing problems in our environment.

**Your job:**
1. Get the full system running correctly with `docker-compose up`
2. Find and fix all the issues across the codebase
3. Improve anything else you think should be better
4. Document everything in `FIXES.md`

## Services

- **service-a** — Python/Flask API (port 5000). Exposes `/`, `/health`, and `/data` endpoints.
- **service-b** — Node.js worker. Polls service-a's `/data` endpoint every 10 seconds.

## Structure

```
.
├── service-a/
│   ├── app.py
│   ├── requirements.txt
│   └── Dockerfile
├── service-b/
│   ├── worker.js
│   ├── package.json
│   └── Dockerfile
├── docker-compose.yml
├── .github/
│   └── workflows/
│       └── deploy.yml
├── terraform/
│   └── main.tf
├── k8s/
│   └── deployment.yaml
└── FIXES.md        ← You create this
```

## Deliverables

Submit a link to your forked GitHub repository containing:

1. **Fixed, working code** — `docker-compose up` should start both services with service-b successfully polling service-a
2. **`FIXES.md`** — For every issue you find and fix, document:
   - What was wrong
   - Why it is a problem
   - How you fixed it
   - What could go wrong if it was left unfixed
3. **At least 2 self-initiated improvements** — things that weren't explicitly broken but you improved anyway
4. **Clean commit history** — one commit per logical fix, with clear commit messages

## Evaluation Criteria

- Did you find all the critical issues?
- Are your fixes correct and complete?
- Is your `FIXES.md` clear and specific (not just "fixed security issues")?
- Did you go beyond the brief?
- Is your git history clean and readable?

## Time expectation

We expect this to take **4–6 hours**. You have **3 days** from receiving this email.

Good luck!
