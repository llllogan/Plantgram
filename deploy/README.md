# CCM deployment

The backend is deployed as the `plantgram-api` Compose stack. The GitHub Actions
workflow builds a SHA-tagged image and sends `deploy/docker-compose.yml` to CCM.

## GitHub configuration

Create a GitHub environment named `plantgram-api` with:

- Variable `CCM_URL`: the base URL of the reachable CCM instance.
- Secret `PLANTGRAM_JWT_SECRET`: a strong production JWT signing secret.

The deploy runner is configured as `self-hosted` with the `linux` label because
it must be able to reach CCM. Keep that runner at version 2.329.0 or newer for
the current checkout, Docker login, and Docker build actions. The target Docker
host must also be able to pull the repository's GHCR image.

## CCM configuration

CCM must define a matching stack id before the workflow can deploy:

```yaml
stacks:
  plantgram-api:
    target: app-host
    deploy_subdir: plantgram-api
```

The target's SSH user needs permission to run Docker Compose. Configure the
actual host, user, and deploy root in CCM's target configuration; no host or
secret values belong in this repository.
