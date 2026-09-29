package database_test

// import (
// 	"context"
// 	"os"
// 	"plany/internal/database"
// 	"testing"
// 	"time"

// 	"github.com/joho/godotenv"
// )

// func TestMain(m *testing.M) {
// 	godotenv.Load("../../.env")
// 	os.Exit(m.Run())
// }
// func TestConnect_MongoConnection(t *testing.T) {
// 	client, err := database.DefaultConnect(os.Getenv("MONGO_URI"))
// 	if err != nil {
// 		t.Fatal(err)
// 	}
// 	defer client.Disconnect(context.Background())
// }

// func TestRetry_DatabaseRetry(t *testing.T) {
// 	client, err := database.Connect("mongodb://localhost:1", 5, 10*time.Microsecond, 20*time.Microsecond)
// 	if err == nil {
// 		t.Fatal("Expected connection error, but Connect returned sucessfully")
// 		defer client.Disconnect(context.Background())
// 	}
// }
