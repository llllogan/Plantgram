FROM golang:1.26-alpine AS build

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/plantgram-api ./cmd/server

FROM alpine:3.22

RUN apk add --no-cache ca-certificates \
    && addgroup -S plantgram && adduser -S -G plantgram plantgram \
    && mkdir -p /var/lib/plantgram/data /var/lib/plantgram/media \
    && chown -R plantgram:plantgram /var/lib/plantgram

WORKDIR /app
COPY --from=build /out/plantgram-api /app/plantgram-api

USER plantgram
EXPOSE 8080
VOLUME ["/var/lib/plantgram/data", "/var/lib/plantgram/media"]

ENTRYPOINT ["/app/plantgram-api"]
