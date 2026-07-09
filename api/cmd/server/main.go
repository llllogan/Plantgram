package main

import (
	"log"
	"net/http"
	"os"

	"plantgram/internal/plantgram"
)

func main() {
	cfg := plantgram.LoadConfig()
	app, err := plantgram.New(cfg)
	if err != nil {
		log.Fatalf("start plantgram: %v", err)
	}
	defer app.Close()

	log.Printf("plantgram api listening on %s", cfg.Addr)
	if err := http.ListenAndServe(cfg.Addr, app.Routes()); err != nil {
		log.Fatal(err)
	}
}

func init() {
	if os.Getenv("PLANTGRAM_JWT_SECRET") == "" {
		log.Println("warning: PLANTGRAM_JWT_SECRET is not set; using development secret")
	}
}
