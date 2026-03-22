# FIXES.md

Document every issue you find and fix in this file.

---

## Fix 1: Hardcoded credentials moved to .env for secure configuration

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

