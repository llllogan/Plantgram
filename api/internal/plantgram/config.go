package plantgram

import (
	"os"
	"strconv"
	"time"
)

type Config struct {
	Addr            string
	DBPath          string
	MediaDir        string
	JWTSecret       string
	AccessTokenTTL  time.Duration
	RefreshTokenTTL time.Duration
	DBMaxOpenConns  int
}

func LoadConfig() Config {
	return Config{
		Addr:            env("PLANTGRAM_ADDR", ":8080"),
		DBPath:          env("PLANTGRAM_DB_PATH", "./data/plantgram.db"),
		MediaDir:        env("PLANTGRAM_MEDIA_DIR", "./media"),
		JWTSecret:       env("PLANTGRAM_JWT_SECRET", "dev-secret-change-me"),
		AccessTokenTTL:  envDuration("PLANTGRAM_ACCESS_TOKEN_TTL_SECONDS", 15*time.Minute),
		RefreshTokenTTL: envDuration("PLANTGRAM_REFRESH_TOKEN_TTL_SECONDS", 30*24*time.Hour),
		DBMaxOpenConns:  envInt("PLANTGRAM_DB_MAX_OPEN_CONNS", 10),
	}
}

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func envDuration(key string, fallback time.Duration) time.Duration {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	seconds, err := strconv.Atoi(v)
	if err != nil || seconds <= 0 {
		return fallback
	}
	return time.Duration(seconds) * time.Second
}

func envInt(key string, fallback int) int {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	n, err := strconv.Atoi(v)
	if err != nil || n <= 0 {
		return fallback
	}
	return n
}
