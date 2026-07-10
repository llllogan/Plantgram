package plantgram

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
)

func TestCorePlantgramFlow(t *testing.T) {
	tmp := t.TempDir()
	app, err := New(Config{
		Addr:            ":0",
		DBPath:          filepath.Join(tmp, "plantgram.db"),
		MediaDir:        filepath.Join(tmp, "media"),
		JWTSecret:       "test-secret",
		AccessTokenTTL:  LoadConfig().AccessTokenTTL,
		RefreshTokenTTL: LoadConfig().RefreshTokenTTL,
		DBMaxOpenConns:  4,
	})
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	t.Cleanup(func() { _ = app.Close() })
	handler := app.Routes()

	humanID, err := app.findOrCreateAppleHuman(t.Context(), "apple-test-user", "logan@example.com", "Logan")
	if err != nil {
		t.Fatalf("findOrCreateAppleHuman: %v", err)
	}
	token, err := app.createAccessToken(humanID, "")
	if err != nil {
		t.Fatalf("createAccessToken: %v", err)
	}

	household := doJSON(t, handler, http.MethodPost, "/households", token, map[string]any{
		"name": "Fern House",
	})
	token = household["access_token"].(string)

	plantResp := doJSON(t, handler, http.MethodPost, "/plants", token, map[string]any{
		"name":    "Monstera",
		"species": "Monstera deliciosa",
	})
	plant := plantResp["plant"].(map[string]any)
	plantID := plant["id"].(string)
	plantActorID := plant["actor_id"].(string)

	postResp := doJSON(t, handler, http.MethodPost, "/posts", token, map[string]any{
		"author_actor_id": plantActorID,
		"post_type":       "watering_event",
		"caption":         "Watered today",
		"plant_ids":       []string{plantID},
	})
	post := postResp["post"].(map[string]any)
	if post["post_type"] != "watering_event" {
		t.Fatalf("post_type = %v", post["post_type"])
	}
	author := post["author"].(map[string]any)
	if author["type"] != "plant" {
		t.Fatalf("author type = %v", author["type"])
	}
	postID := post["id"].(string)

	doJSON(t, handler, http.MethodPost, "/posts/"+postID+"/reactions", token, map[string]any{
		"emoji": "💚",
	})
	doJSON(t, handler, http.MethodPost, "/posts/"+postID+"/comments", token, map[string]any{
		"body": "Looks happy",
	})

	feedResp := doJSON(t, handler, http.MethodGet, "/feed", token, nil)
	feedPosts := feedResp["posts"].([]any)
	if len(feedPosts) != 1 {
		t.Fatalf("feed posts len = %d", len(feedPosts))
	}
	feedPost := feedPosts[0].(map[string]any)
	if feedPost["id"] != postID || int(feedPost["comment_count"].(float64)) != 1 {
		t.Fatalf("unexpected feed post: %#v", feedPost)
	}
	reactions := feedPost["reactions"].([]any)
	if len(reactions) != 1 || reactions[0].(map[string]any)["mine"] != true {
		t.Fatalf("reaction was not marked as mine: %#v", reactions)
	}

	timelineResp := doJSON(t, handler, http.MethodGet, "/plants/"+plantID+"/timeline", token, nil)
	timelinePosts := timelineResp["posts"].([]any)
	if len(timelinePosts) != 1 || timelinePosts[0].(map[string]any)["id"] != postID {
		t.Fatalf("unexpected plant timeline: %#v", timelineResp)
	}
}

func TestMigrationRemovesPasswordAuthColumns(t *testing.T) {
	tmp := t.TempDir()
	db, err := sql.Open("libsql", sqliteFileDSN(filepath.Join(tmp, "plantgram.db")))
	if err != nil {
		t.Fatalf("sql.Open: %v", err)
	}
	t.Cleanup(func() { _ = db.Close() })

	ctx := context.Background()
	if err := configureDatabase(ctx, db); err != nil {
		t.Fatalf("configureDatabase: %v", err)
	}
	_, err = db.ExecContext(ctx, `
CREATE TABLE human_accounts (
	id TEXT PRIMARY KEY,
	email TEXT NOT NULL UNIQUE,
	password_hash TEXT NOT NULL,
	apple_user_id TEXT,
	auth_provider TEXT NOT NULL DEFAULT 'password',
	display_name TEXT NOT NULL,
	profile_media_id TEXT,
	created_at TEXT NOT NULL,
	updated_at TEXT NOT NULL
)`)
	if err != nil {
		t.Fatalf("create old human_accounts: %v", err)
	}
	if err := migrate(ctx, db); err != nil {
		t.Fatalf("migrate: %v", err)
	}

	columns, err := tableColumns(ctx, db, "human_accounts")
	if err != nil {
		t.Fatalf("tableColumns: %v", err)
	}
	if columns["password_hash"] || columns["auth_provider"] {
		t.Fatalf("password auth columns still present: %#v", columns)
	}
	if !columns["apple_user_id"] {
		t.Fatalf("apple_user_id column missing: %#v", columns)
	}
}

func doJSON(t *testing.T, handler http.Handler, method, path, token string, body any) map[string]any {
	t.Helper()

	var requestBody *bytes.Reader
	if body == nil {
		requestBody = bytes.NewReader(nil)
	} else {
		raw, err := json.Marshal(body)
		if err != nil {
			t.Fatalf("marshal request: %v", err)
		}
		requestBody = bytes.NewReader(raw)
	}

	req := httptest.NewRequest(method, path, requestBody)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rr := httptest.NewRecorder()
	handler.ServeHTTP(rr, req)

	if rr.Code < 200 || rr.Code >= 300 {
		t.Fatalf("%s %s returned %d: %s", method, path, rr.Code, rr.Body.String())
	}
	if rr.Body.Len() == 0 {
		return map[string]any{}
	}
	var out map[string]any
	if err := json.Unmarshal(rr.Body.Bytes(), &out); err != nil {
		t.Fatalf("decode response: %v; body=%s", err, rr.Body.String())
	}
	return out
}
