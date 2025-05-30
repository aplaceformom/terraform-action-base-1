AWS Terraform Base Action
=========================

> **Note**: This is a fork of [apfm-actions/terraform-action-base](https://github.com/apfm-actions/terraform-action-base) maintained in the `aplaceformom` organization to provide public container images via GitHub Container Registry.

This repository is home to _base_ GitHub action to simplify the development of
other actions. E.g. this repo contains the shared code stack.

Usage
-----
To use this repo simply define your Terraform IAC `*.tf`, and an actions.yaml
for use w/ GitHub.

Example Dockerfile:
```dockerfile
# Using the public GitHub Container Registry image
FROM ghcr.io/aplaceformom/terraform-action-base-1:latest

# Or using the Docker Hub image (if still needed)
# FROM apfm/terraform-action-base:latest

WORKDIR /app
COPY *.tf /app/
ADD modules /app/modules/
```

Container Images
----------------
This fork provides container images via GitHub Container Registry:
- `ghcr.io/aplaceformom/terraform-action-base-1:latest`
- `ghcr.io/aplaceformom/terraform-action-base-1:<commit-sha>`

The images include:
- Alpine Linux 3.12.7
- Terraform 0.12.31
- AWS CLI 1.18.49
- Credstash 1.17.1
- S3cmd 2.1.0

References
----------
- https://github.com/aplaceformom/terraform-template-action
