AWS Terraform Base Action
=========================
This repository is home to _base_ GitHub action to simplify the development of
other actions. E.g. this repo contains the shared code stack.

Usage
-----
To use this repo simply define your Terraform IAC `*.tf`, and an actions.yaml
for use w/ GitHub.

Example Dockerfile:
```
FROM apfm/terraform-action-base:latest
WORKDIR /app
COPY *.tf /app/
ADD modules /app/modules/
```

References
----------
- https://github.com/aplaceformom/terraform-template-action
