---
name: github-actions-expert
description: "Expert guidelines for designing robust GitHub Actions CI/CD workflows, build caching, and Docker registry integration."
category: devops
risk: low
source: custom
version: "1.0.0"
date_added: "2026-05-21"
---

# GitHub Actions CI/CD and Container Caching

This skill outlines guidelines and patterns for building robust, secure, and highly optimized CI/CD pipelines in GitHub Actions. It focuses on Docker container building, caching heavy dependencies (like PyTorch and CUDA), and managing multi-container workflows.

## When to Apply

Use this skill when:
- Designing GitHub Actions workflow files (`.github/workflows/*.yml`).
- Optimizing Docker build times for CUDA and PyTorch containers.
- Managing builds for a multi-container architecture (like the 5-container pipeline).
- Setting up secure registry authentication and secrets management.

## Core Guidelines

### 1. Docker Buildx & GitHub Actions Caching (`type=gha`)
Deep learning containers (containing PyTorch, CUDA, and specialized packages like SuGaR or Segment-then-Splat) are massive. To prevent hours of rebuild times in CI:

- **Configure the Container Driver:** Set up Buildx using the `docker-container` driver which supports the `gha` cache backend.
- **Cache Configuration:**
  - `cache-from: type=gha,scope=...`
  - `cache-to: type=gha,mode=max,scope=...`
  - **`mode=max`** is critical: It tells Docker to cache all intermediate build layers (including heavy dependency installs), rather than just the final image.
  - **`scope`** is crucial for multi-container projects: It isolates the cache for each container so they don't overwrite each other.

```yaml
- name: Set up Docker Buildx
  uses: docker/setup-buildx-action@v3
  with:
    driver: docker-container

- name: Build and Push Container A (SAM 3 / CUDA 12.6)
  uses: docker/build-push-action@v6
  with:
    context: ./container_a
    push: true
    tags: ghcr.io/user/sam3-pipeline:latest
    cache-from: type=gha,scope=container-a
    cache-to: type=gha,mode=max,scope=container-a
```

### 2. Multi-Container Orchestration (Different CUDA Versions)
Your pipeline utilizes 5 distinct containers with different CUDA requirements (CUDA >= 12.6, 12.1, 11.8).
- **Matrix Strategy:** Use GitHub Action matrices to compile multiple containers in parallel if they share build logic.
- **Dependency Pipeline:** Define sequential jobs using `needs` if certain containers rely on base images built in previous steps.

### 3. Pipeline Security
- **Least-Privilege Token Permissions:** Restrict the default `GITHUB_TOKEN` permissions in your workflow:
  ```yaml
  permissions:
    contents: read
    packages: write
  ```
- **Use Commit SHAs for Actions:** Pin third-party actions to immutable commit SHAs instead of mutable tags (e.g. `uses: docker/setup-buildx-action@d70b3362` instead of `@v3`) to mitigate supply-chain attacks.
- **Secure Registry Login:** Use GitHub's OIDC or secure secrets (`secrets.GITHUB_TOKEN`) to authenticate to the GitHub Container Registry (`ghcr.io`).

## Troubleshooting & Diagnostics

### Runner running out of disk space
- Deep learning containers easily exceed runner space limits.
- **Clean up space:** Use a cleanup step at the start of the job to remove pre-installed packages (Android SDK, Net Core, etc.) from the GitHub virtual environment if needed.
- **Multi-Stage Builds:** Ensure development libraries and compilers are only used in build stages, and the final production stage uses clean, minimal runtime bases (e.g. `nvidia/cuda:runtime` or distroless).

### Cache is not being hit
- Verify that the `context` path is correct.
- Ensure that the files copied first in your Dockerfile (like `requirements.txt` or `environment.yml`) have not changed. Copying source files *before* installing dependencies will invalidate the cache on every code change.

## Code Review Checklist
- [ ] Buildx setup uses the `docker-container` driver.
- [ ] Docker build uses `cache-to: type=gha,mode=max` for optimal layer caching.
- [ ] Independent container builds are isolated using unique `scope` parameters.
- [ ] Workflow permissions follow the principle of least privilege.
- [ ] Actions are pinned using commit SHAs.
- [ ] Dockerfiles separate dependency installation from code copy instructions.
