# DigiByte Core Docker

Docker images for DigiByte Core, published through GitHub Container Registry (GHCR).

## Initial target

- DigiByte Core v9.26.7
- Architecture: linux/amd64
- Future support: linux/arm64

## Goals

- Build images from official DigiByte Core releases.
- Verify release artifacts before packaging.
- Publish versioned images using GitHub Actions.
- Preserve persistent blockchain data.
- Support Docker Compose and TrueNAS SCALE.
- Never include RPC passwords in images.

## Status

Work in progress. No production-ready image published yet.
