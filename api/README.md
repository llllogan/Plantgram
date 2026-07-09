# Plantgram Backend

Plantgram is a Go REST API for a household-scoped plant social app. It uses a local Turso/libSQL-compatible SQLite database file and stores uploaded images on disk.

## Run Locally

```sh
PLANTGRAM_JWT_SECRET=change-me \
go run ./cmd/server
```

Defaults:

- `PLANTGRAM_ADDR=:8080`
- `PLANTGRAM_DB_PATH=./data/plantgram.db`
- `PLANTGRAM_MEDIA_DIR=./media`
- `PLANTGRAM_DB_MAX_OPEN_CONNS=10`
- `PLANTGRAM_ACCESS_TOKEN_TTL_SECONDS=900`
- `PLANTGRAM_REFRESH_TOKEN_TTL_SECONDS=2592000`

The DB path and media directory are regular filesystem paths. In a future Docker image, mount one volume at the DB directory and another volume at the media directory.

## API Shape

- Humans register and log in with email/password.
- Auth uses short-lived JWT access tokens and rotating opaque refresh tokens.
- Humans must create or join a household before using household-scoped resources.
- Plants are separate accounts from humans and cannot log in.
- Posts are the unified feed item. `post_type` controls UI rendering, for example `general`, `watering_event`, `planting_event`, or `status_update`.
- Posts can be authored by a human actor or a plant actor, can tag plants and planters, and support emoji reactions and comments.

## Verify

```sh
GOCACHE=/tmp/plantgram-go-cache GOMODCACHE=/tmp/plantgram-go-mod go test ./...
```
