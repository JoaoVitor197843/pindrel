// Command migrate applies the embedded schema migrations and exits. The API does the same at startup;
// this exists for a database that has to be ready before anything starts (the CI job that runs the
// database tests) and for running the migrations by hand.
package main

import (
	"context"
	"log"
	"plany/internal/config"
	"plany/internal/database"
	"time"

	"github.com/joho/godotenv"
)

func main() {
	godotenv.Load()
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("failed on configuration: %v", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	pool, err := database.NewConnection(ctx, cfg.Database)
	if err != nil {
		log.Fatalf("failed to connect to postgres: %v", err)
	}
	defer pool.Close()
	if err := database.Migrate(ctx, pool, database.Migrations()); err != nil {
		log.Fatalf("failed to migrate the database: %v", err)
	}
	log.Println("database is up to date")
}
