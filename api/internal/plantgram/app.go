package plantgram

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"log"
	"mime"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	_ "github.com/tursodatabase/libsql-client-go/libsql"
	_ "modernc.org/sqlite"
)

type App struct {
	cfg Config
	db  *sql.DB
}

type contextKey string

const authContextKey contextKey = "auth"

type authContext struct {
	HumanID     string
	HouseholdID string
}

func New(cfg Config) (*App, error) {
	if err := os.MkdirAll(filepath.Dir(cfg.DBPath), 0o755); err != nil {
		return nil, err
	}
	if err := os.MkdirAll(cfg.MediaDir, 0o755); err != nil {
		return nil, err
	}

	db, err := sql.Open("libsql", sqliteFileDSN(cfg.DBPath))
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(cfg.DBMaxOpenConns)
	db.SetMaxIdleConns(cfg.DBMaxOpenConns)

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := db.PingContext(ctx); err != nil {
		_ = db.Close()
		return nil, err
	}
	if err := configureDatabase(ctx, db); err != nil {
		_ = db.Close()
		return nil, err
	}
	if err := migrate(ctx, db); err != nil {
		_ = db.Close()
		return nil, err
	}
	return &App{cfg: cfg, db: db}, nil
}

func sqliteFileDSN(path string) string {
	values := url.Values{}
	values.Add("_pragma", "busy_timeout(5000)")
	values.Add("_pragma", "foreign_keys(1)")
	values.Add("_pragma", "journal_mode(WAL)")
	values.Add("_pragma", "synchronous(NORMAL)")
	return "file:" + path + "?" + values.Encode()
}

func configureDatabase(ctx context.Context, db *sql.DB) error {
	for _, stmt := range []string{
		`PRAGMA journal_mode=WAL`,
		`PRAGMA busy_timeout=5000`,
		`PRAGMA foreign_keys=ON`,
		`PRAGMA synchronous=NORMAL`,
	} {
		if _, err := db.ExecContext(ctx, stmt); err != nil {
			return err
		}
	}
	return nil
}

func (a *App) Close() error {
	return a.db.Close()
}

func (a *App) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	mux.HandleFunc("POST /auth/apple", a.handleAppleSignIn)
	mux.HandleFunc("POST /auth/refresh", a.handleRefresh)
	mux.HandleFunc("POST /auth/logout", a.requireAuth(a.handleLogout, false))
	mux.HandleFunc("GET /me", a.requireAuth(a.handleMe, false))
	mux.HandleFunc("PATCH /me", a.requireAuth(a.handleUpdateMe, false))
	mux.HandleFunc("DELETE /me/account", a.requireAuth(a.handleDeleteAccount, false))

	mux.HandleFunc("POST /households", a.requireAuth(a.handleCreateHousehold, false))
	mux.HandleFunc("GET /households", a.requireAuth(a.handleListHouseholds, false))
	mux.HandleFunc("POST /households/{id}/join", a.requireAuth(a.handleJoinHousehold, false))
	mux.HandleFunc("POST /me/active-household", a.requireAuth(a.handleSetActiveHousehold, false))

	mux.HandleFunc("POST /plants", a.requireAuth(a.handleCreatePlant, true))
	mux.HandleFunc("GET /plants", a.requireAuth(a.handleListPlants, true))
	mux.HandleFunc("GET /plants/{id}", a.requireAuth(a.handleGetPlant, true))
	mux.HandleFunc("PATCH /plants/{id}", a.requireAuth(a.handleUpdatePlant, true))
	mux.HandleFunc("GET /plants/{id}/timeline", a.requireAuth(a.handlePlantTimeline, true))

	mux.HandleFunc("POST /planters", a.requireAuth(a.handleCreatePlanter, true))
	mux.HandleFunc("GET /planters", a.requireAuth(a.handleListPlanters, true))
	mux.HandleFunc("PATCH /planters/{id}", a.requireAuth(a.handleUpdatePlanter, true))
	mux.HandleFunc("POST /planters/{id}/plants", a.requireAuth(a.handleAddPlantToPlanter, true))
	mux.HandleFunc("GET /planters/{id}/timeline", a.requireAuth(a.handlePlanterTimeline, true))

	mux.HandleFunc("POST /media", a.requireAuth(a.handleUploadMedia, true))
	mux.HandleFunc("GET /media/{id}", a.requireAuth(a.handleGetMedia, true))

	mux.HandleFunc("GET /feed", a.requireAuth(a.handleFeed, true))
	mux.HandleFunc("POST /posts", a.requireAuth(a.handleCreatePost, true))
	mux.HandleFunc("GET /posts/{id}", a.requireAuth(a.handleGetPost, true))
	mux.HandleFunc("POST /posts/{id}/reactions", a.requireAuth(a.handleAddReaction, true))
	mux.HandleFunc("DELETE /posts/{id}/reactions/{emoji}", a.requireAuth(a.handleDeleteReaction, true))
	mux.HandleFunc("POST /posts/{id}/comments", a.requireAuth(a.handleCreateComment, true))
	mux.HandleFunc("GET /posts/{id}/comments", a.requireAuth(a.handleListComments, true))
	mux.HandleFunc("PATCH /comments/{id}", a.requireAuth(a.handleUpdateComment, true))
	mux.HandleFunc("DELETE /comments/{id}", a.requireAuth(a.handleDeleteComment, true))

	return logRequests(withCommonHeaders(mux))
}

func withCommonHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		next.ServeHTTP(w, r)
	})
}

type loggingResponseWriter struct {
	http.ResponseWriter
	statusCode int
}

func (w *loggingResponseWriter) WriteHeader(statusCode int) {
	if w.statusCode != 0 {
		return
	}
	w.statusCode = statusCode
	w.ResponseWriter.WriteHeader(statusCode)
}

func (w *loggingResponseWriter) Write(data []byte) (int, error) {
	if w.statusCode == 0 {
		w.statusCode = http.StatusOK
	}
	return w.ResponseWriter.Write(data)
}

func logRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		lw := &loggingResponseWriter{ResponseWriter: w}
		next.ServeHTTP(lw, r)
		if lw.statusCode == 0 {
			lw.statusCode = http.StatusOK
		}
		log.Printf("%s %s %d %s %s", r.Method, r.URL.RequestURI(), lw.statusCode, time.Since(start).Round(time.Millisecond), r.RemoteAddr)
	})
}

func (a *App) requireAuth(next http.HandlerFunc, needHousehold bool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		header := r.Header.Get("Authorization")
		if !strings.HasPrefix(header, "Bearer ") {
			writeError(w, http.StatusUnauthorized, "missing bearer token")
			return
		}
		claims, err := a.verifyAccessToken(strings.TrimPrefix(header, "Bearer "))
		if err != nil {
			writeError(w, http.StatusUnauthorized, "invalid bearer token")
			return
		}
		ac := authContext{HumanID: claims.Subject, HouseholdID: claims.HouseholdID}
		if needHousehold && ac.HouseholdID == "" {
			writeError(w, http.StatusForbidden, "active household required")
			return
		}
		if ac.HouseholdID != "" {
			ok, err := a.isHouseholdMember(r.Context(), ac.HouseholdID, ac.HumanID)
			if err != nil {
				writeError(w, http.StatusInternalServerError, "membership check failed")
				return
			}
			if !ok {
				writeError(w, http.StatusForbidden, "not a household member")
				return
			}
		}
		next(w, r.WithContext(context.WithValue(r.Context(), authContextKey, ac)))
	}
}

func authFrom(r *http.Request) authContext {
	v, _ := r.Context().Value(authContextKey).(authContext)
	return v
}

func (a *App) handleRefresh(w http.ResponseWriter, r *http.Request) {
	var req struct {
		RefreshToken string `json:"refresh_token"`
		HouseholdID  string `json:"household_id"`
	}
	if !readJSON(w, r, &req) {
		return
	}
	tokenHash := hashOpaqueToken(req.RefreshToken)
	var tokenID, humanID, expiresAt, revokedAt sql.NullString
	err := a.db.QueryRowContext(r.Context(), `SELECT id, human_id, expires_at, revoked_at FROM refresh_tokens WHERE token_hash = ?`, tokenHash).Scan(&tokenID, &humanID, &expiresAt, &revokedAt)
	if err != nil || revokedAt.Valid {
		writeError(w, http.StatusUnauthorized, "invalid refresh token")
		return
	}
	exp, err := time.Parse(time.RFC3339Nano, expiresAt.String)
	if err != nil || time.Now().After(exp) {
		writeError(w, http.StatusUnauthorized, "expired refresh token")
		return
	}
	if req.HouseholdID != "" {
		ok, err := a.isHouseholdMember(r.Context(), req.HouseholdID, humanID.String)
		if err != nil || !ok {
			writeError(w, http.StatusForbidden, "not a household member")
			return
		}
	}

	newRefresh, newRefreshID, err := a.createRefreshToken(r.Context(), humanID.String)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "refresh failed")
		return
	}
	if _, err = a.db.ExecContext(r.Context(), `UPDATE refresh_tokens SET revoked_at = ?, replaced_by_token_id = ? WHERE id = ?`, nowString(), newRefreshID, tokenID.String); err != nil {
		writeError(w, http.StatusInternalServerError, "refresh failed")
		return
	}
	access, err := a.createAccessToken(humanID.String, req.HouseholdID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "token failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"access_token": access, "refresh_token": newRefresh, "token_type": "Bearer"})
}

func (a *App) handleLogout(w http.ResponseWriter, r *http.Request) {
	var req struct {
		RefreshToken string `json:"refresh_token"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)
	if req.RefreshToken != "" {
		_, _ = a.db.ExecContext(r.Context(), `UPDATE refresh_tokens SET revoked_at = ? WHERE token_hash = ?`, nowString(), hashOpaqueToken(req.RefreshToken))
	}
	w.WriteHeader(http.StatusNoContent)
}

func (a *App) handleMe(w http.ResponseWriter, r *http.Request) {
	ac := authFrom(r)
	var row humanAccount
	err := a.db.QueryRowContext(r.Context(), `SELECT id, email, display_name, profile_media_id, created_at FROM human_accounts WHERE id = ?`, ac.HumanID).Scan(&row.ID, &row.Email, &row.DisplayName, &row.ProfileMediaID, &row.CreatedAt)
	if err != nil {
		writeError(w, http.StatusNotFound, "account not found")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"human": row, "active_household_id": ac.HouseholdID})
}

func (a *App) handleUpdateMe(w http.ResponseWriter, r *http.Request) {
	ac := authFrom(r)
	var req struct {
		DisplayName    string `json:"display_name"`
		ProfileMediaID string `json:"profile_media_id"`
	}
	if !readJSON(w, r, &req) {
		return
	}
	req.DisplayName = strings.TrimSpace(req.DisplayName)
	if req.DisplayName == "" {
		writeError(w, http.StatusBadRequest, "display_name is required")
		return
	}
	if req.ProfileMediaID != "" {
		if ac.HouseholdID == "" {
			writeError(w, http.StatusForbidden, "active household required to set profile media")
			return
		}
		if !a.mediaInHousehold(r.Context(), req.ProfileMediaID, ac.HouseholdID) {
			writeError(w, http.StatusBadRequest, "profile media not found in household")
			return
		}
	}
	if _, err := a.db.ExecContext(r.Context(), `UPDATE human_accounts SET display_name = ?, profile_media_id = NULLIF(?, ''), updated_at = ? WHERE id = ?`, req.DisplayName, req.ProfileMediaID, nowString(), ac.HumanID); err != nil {
		writeError(w, http.StatusInternalServerError, "update profile failed")
		return
	}
	_, _ = a.db.ExecContext(r.Context(), `UPDATE actors SET display_name = ?, profile_media_id = NULLIF(?, '') WHERE human_id = ?`, req.DisplayName, req.ProfileMediaID, ac.HumanID)
	a.handleMe(w, r)
}

func (a *App) handleDeleteAccount(w http.ResponseWriter, r *http.Request) {
	ac := authFrom(r)
	tx, err := a.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "begin account deletion failed")
		return
	}
	defer tx.Rollback()

	type membership struct {
		householdID string
		role        string
	}
	rows, err := tx.QueryContext(r.Context(), `SELECT household_id, role FROM household_members WHERE human_id = ?`, ac.HumanID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "load household memberships failed")
		return
	}
	var memberships []membership
	for rows.Next() {
		var item membership
		if err := rows.Scan(&item.householdID, &item.role); err != nil {
			rows.Close()
			writeError(w, http.StatusInternalServerError, "load household memberships failed")
			return
		}
		memberships = append(memberships, item)
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		writeError(w, http.StatusInternalServerError, "load household memberships failed")
		return
	}
	rows.Close()

	deletedHouseholds := map[string]bool{}
	for _, item := range memberships {
		if item.role != "owner" {
			continue
		}

		var remaining int
		if err := tx.QueryRowContext(r.Context(), `SELECT COUNT(*) FROM household_members WHERE household_id = ? AND human_id <> ?`, item.householdID, ac.HumanID).Scan(&remaining); err != nil {
			writeError(w, http.StatusInternalServerError, "inspect household membership failed")
			return
		}
		if remaining == 0 {
			deletedHouseholds[item.householdID] = true
			continue
		}

		var replacementID string
		if err := tx.QueryRowContext(r.Context(), `SELECT human_id FROM household_members WHERE household_id = ? AND human_id <> ? ORDER BY joined_at, human_id LIMIT 1`, item.householdID, ac.HumanID).Scan(&replacementID); err != nil {
			writeError(w, http.StatusInternalServerError, "choose household owner failed")
			return
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE households SET created_by_human_id = ?, updated_at = ? WHERE id = ?`, replacementID, nowString(), item.householdID); err != nil {
			writeError(w, http.StatusInternalServerError, "transfer household ownership failed")
			return
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE household_members SET role = 'member' WHERE household_id = ? AND human_id = ?`, item.householdID, ac.HumanID); err != nil {
			writeError(w, http.StatusInternalServerError, "update household ownership failed")
			return
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE household_members SET role = 'owner' WHERE household_id = ? AND human_id = ?`, item.householdID, replacementID); err != nil {
			writeError(w, http.StatusInternalServerError, "update household ownership failed")
			return
		}
	}

	// Remove all user-authored discussion content before deleting the account.
	if _, err := tx.ExecContext(r.Context(), `DELETE FROM post_comments WHERE human_id = ?`, ac.HumanID); err != nil {
		writeError(w, http.StatusInternalServerError, "delete comments failed")
		return
	}
	if _, err := tx.ExecContext(r.Context(), `DELETE FROM posts WHERE created_by_human_id = ?`, ac.HumanID); err != nil {
		writeError(w, http.StatusInternalServerError, "delete posts failed")
		return
	}

	for _, item := range memberships {
		if deletedHouseholds[item.householdID] {
			if _, err := tx.ExecContext(r.Context(), `DELETE FROM households WHERE id = ?`, item.householdID); err != nil {
				writeError(w, http.StatusInternalServerError, "delete household failed")
				return
			}
			continue
		}

		var replacementID string
		if err := tx.QueryRowContext(r.Context(), `SELECT human_id FROM household_members WHERE household_id = ? AND human_id <> ? ORDER BY role = 'owner' DESC, joined_at, human_id LIMIT 1`, item.householdID, ac.HumanID).Scan(&replacementID); err != nil {
			writeError(w, http.StatusInternalServerError, "choose ownership replacement failed")
			return
		}
		for _, query := range []string{
			`UPDATE plant_accounts SET created_by_human_id = ? WHERE household_id = ? AND created_by_human_id = ?`,
			`UPDATE planters SET created_by_human_id = ? WHERE household_id = ? AND created_by_human_id = ?`,
			`UPDATE media_assets SET uploaded_by_human_id = ? WHERE household_id = ? AND uploaded_by_human_id = ?`,
			`UPDATE planter_plants SET added_by_human_id = ? WHERE planter_id IN (SELECT id FROM planters WHERE household_id = ?) AND added_by_human_id = ?`,
		} {
			if _, err := tx.ExecContext(r.Context(), query, replacementID, item.householdID, ac.HumanID); err != nil {
				writeError(w, http.StatusInternalServerError, "transfer household content ownership failed")
				return
			}
		}
	}

	if _, err := tx.ExecContext(r.Context(), `DELETE FROM human_accounts WHERE id = ?`, ac.HumanID); err != nil {
		writeError(w, http.StatusInternalServerError, "delete account failed")
		return
	}
	if err := tx.Commit(); err != nil {
		writeError(w, http.StatusInternalServerError, "delete account failed")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (a *App) writeAuthResponse(w http.ResponseWriter, r *http.Request, humanID, householdID string) {
	access, err := a.createAccessToken(humanID, householdID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "token failed")
		return
	}
	refresh, _, err := a.createRefreshToken(r.Context(), humanID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "refresh token failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"access_token": access, "refresh_token": refresh, "token_type": "Bearer"})
}

func (a *App) handleCreateHousehold(w http.ResponseWriter, r *http.Request) {
	ac := authFrom(r)
	var req struct {
		Name string `json:"name"`
	}
	if !readJSON(w, r, &req) {
		return
	}
	req.Name = strings.TrimSpace(req.Name)
	if req.Name == "" {
		writeError(w, http.StatusBadRequest, "name is required")
		return
	}
	id := newID("hhd")
	now := nowString()
	tx, err := a.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "begin transaction failed")
		return
	}
	defer tx.Rollback()
	if _, err = tx.ExecContext(r.Context(), `INSERT INTO households (id, name, created_by_human_id, created_at, updated_at) VALUES (?, ?, ?, ?, ?)`, id, req.Name, ac.HumanID, now, now); err != nil {
		writeError(w, http.StatusInternalServerError, "create household failed")
		return
	}
	if _, err = tx.ExecContext(r.Context(), `INSERT INTO household_members (household_id, human_id, role, joined_at) VALUES (?, ?, 'owner', ?)`, id, ac.HumanID, now); err != nil {
		writeError(w, http.StatusInternalServerError, "create membership failed")
		return
	}
	actorID := newID("act")
	var displayName string
	_ = tx.QueryRowContext(r.Context(), `SELECT display_name FROM human_accounts WHERE id = ?`, ac.HumanID).Scan(&displayName)
	if _, err = tx.ExecContext(r.Context(), `INSERT INTO actors (id, household_id, actor_type, human_id, display_name, created_at) VALUES (?, ?, 'human', ?, ?, ?)`, actorID, id, ac.HumanID, displayName, now); err != nil {
		writeError(w, http.StatusInternalServerError, "create actor failed")
		return
	}
	if err = tx.Commit(); err != nil {
		writeError(w, http.StatusInternalServerError, "create household failed")
		return
	}
	access, _ := a.createAccessToken(ac.HumanID, id)
	writeJSON(w, http.StatusCreated, map[string]any{"household": map[string]string{"id": id, "name": req.Name}, "access_token": access})
}

func (a *App) handleListHouseholds(w http.ResponseWriter, r *http.Request) {
	ac := authFrom(r)
	rows, err := a.db.QueryContext(r.Context(), `SELECT h.id, h.name, hm.role, h.created_at FROM households h JOIN household_members hm ON hm.household_id = h.id WHERE hm.human_id = ? ORDER BY h.created_at DESC`, ac.HumanID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "list households failed")
		return
	}
	defer rows.Close()
	out := []map[string]string{}
	for rows.Next() {
		var id, name, role, createdAt string
		if err := rows.Scan(&id, &name, &role, &createdAt); err != nil {
			writeError(w, http.StatusInternalServerError, "list households failed")
			return
		}
		out = append(out, map[string]string{"id": id, "name": name, "role": role, "created_at": createdAt})
	}
	writeJSON(w, http.StatusOK, map[string]any{"households": out})
}

func (a *App) handleJoinHousehold(w http.ResponseWriter, r *http.Request) {
	ac := authFrom(r)
	householdID := r.PathValue("id")
	var exists int
	if err := a.db.QueryRowContext(r.Context(), `SELECT COUNT(*) FROM households WHERE id = ?`, householdID).Scan(&exists); err != nil || exists == 0 {
		writeError(w, http.StatusNotFound, "household not found")
		return
	}
	now := nowString()
	if _, err := a.db.ExecContext(r.Context(), `INSERT OR IGNORE INTO household_members (household_id, human_id, role, joined_at) VALUES (?, ?, 'member', ?)`, householdID, ac.HumanID, now); err != nil {
		writeError(w, http.StatusInternalServerError, "join household failed")
		return
	}
	if _, err := a.db.ExecContext(r.Context(), `INSERT OR IGNORE INTO actors (id, household_id, actor_type, human_id, display_name, created_at) SELECT ?, ?, 'human', id, display_name, ? FROM human_accounts WHERE id = ?`, newID("act"), householdID, now, ac.HumanID); err != nil {
		writeError(w, http.StatusInternalServerError, "create actor failed")
		return
	}
	access, _ := a.createAccessToken(ac.HumanID, householdID)
	writeJSON(w, http.StatusOK, map[string]any{"household_id": householdID, "access_token": access})
}

func (a *App) handleSetActiveHousehold(w http.ResponseWriter, r *http.Request) {
	ac := authFrom(r)
	var req struct {
		HouseholdID string `json:"household_id"`
	}
	if !readJSON(w, r, &req) {
		return
	}
	ok, err := a.isHouseholdMember(r.Context(), req.HouseholdID, ac.HumanID)
	if err != nil || !ok {
		writeError(w, http.StatusForbidden, "not a household member")
		return
	}
	access, err := a.createAccessToken(ac.HumanID, req.HouseholdID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "token failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"access_token": access, "token_type": "Bearer"})
}

func (a *App) handleCreatePlant(w http.ResponseWriter, r *http.Request) {
	ac := authFrom(r)
	var req struct {
		Name           string `json:"name"`
		Species        string `json:"species"`
		Notes          string `json:"notes"`
		ProfileMediaID string `json:"profile_media_id"`
	}
	if !readJSON(w, r, &req) {
		return
	}
	req.Name = strings.TrimSpace(req.Name)
	if req.Name == "" {
		writeError(w, http.StatusBadRequest, "name is required")
		return
	}
	if req.ProfileMediaID != "" && !a.mediaInHousehold(r.Context(), req.ProfileMediaID, ac.HouseholdID) {
		writeError(w, http.StatusBadRequest, "profile media not found in household")
		return
	}
	id := newID("plt")
	actorID := newID("act")
	now := nowString()
	tx, err := a.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "begin transaction failed")
		return
	}
	defer tx.Rollback()
	if _, err = tx.ExecContext(r.Context(), `INSERT INTO plant_accounts (id, household_id, name, species, notes, profile_media_id, created_by_human_id, created_at, updated_at) VALUES (?, ?, ?, ?, ?, NULLIF(?, ''), ?, ?, ?)`, id, ac.HouseholdID, req.Name, req.Species, req.Notes, req.ProfileMediaID, ac.HumanID, now, now); err != nil {
		writeError(w, http.StatusInternalServerError, "create plant failed")
		return
	}
	if _, err = tx.ExecContext(r.Context(), `INSERT INTO actors (id, household_id, actor_type, plant_id, display_name, profile_media_id, created_at) VALUES (?, ?, 'plant', ?, ?, NULLIF(?, ''), ?)`, actorID, ac.HouseholdID, id, req.Name, req.ProfileMediaID, now); err != nil {
		writeError(w, http.StatusInternalServerError, "create plant actor failed")
		return
	}
	if _, err = tx.ExecContext(r.Context(), `UPDATE plant_accounts SET actor_id = ? WHERE id = ?`, actorID, id); err != nil {
		writeError(w, http.StatusInternalServerError, "link plant actor failed")
		return
	}
	if err = tx.Commit(); err != nil {
		writeError(w, http.StatusInternalServerError, "create plant failed")
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"plant": map[string]string{"id": id, "actor_id": actorID, "name": req.Name, "species": req.Species, "notes": req.Notes}})
}

func (a *App) handleListPlants(w http.ResponseWriter, r *http.Request) {
	ac := authFrom(r)
	rows, err := a.db.QueryContext(r.Context(), `SELECT id, actor_id, name, species, notes, profile_media_id, created_at FROM plant_accounts WHERE household_id = ? ORDER BY name`, ac.HouseholdID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "list plants failed")
		return
	}
	defer rows.Close()
	plants := []plant{}
	for rows.Next() {
		var p plant
		if err := rows.Scan(&p.ID, &p.ActorID, &p.Name, &p.Species, &p.Notes, &p.ProfileMediaID, &p.CreatedAt); err != nil {
			writeError(w, http.StatusInternalServerError, "list plants failed")
			return
		}
		plants = append(plants, p)
	}
	writeJSON(w, http.StatusOK, map[string]any{"plants": plants})
}

func (a *App) handleGetPlant(w http.ResponseWriter, r *http.Request) {
	ac := authFrom(r)
	p, ok := a.getPlant(r.Context(), r.PathValue("id"), ac.HouseholdID)
	if !ok {
		writeError(w, http.StatusNotFound, "plant not found")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"plant": p})
}

func (a *App) handleUpdatePlant(w http.ResponseWriter, r *http.Request) {
	ac := authFrom(r)
	var req struct {
		Name           string `json:"name"`
		Species        string `json:"species"`
		Notes          string `json:"notes"`
		ProfileMediaID string `json:"profile_media_id"`
	}
	if !readJSON(w, r, &req) {
		return
	}
	req.Name = strings.TrimSpace(req.Name)
	if req.Name == "" {
		writeError(w, http.StatusBadRequest, "name is required")
		return
	}
	if req.ProfileMediaID != "" && !a.mediaInHousehold(r.Context(), req.ProfileMediaID, ac.HouseholdID) {
		writeError(w, http.StatusBadRequest, "profile media not found in household")
		return
	}
	res, err := a.db.ExecContext(r.Context(), `UPDATE plant_accounts SET name = ?, species = ?, notes = ?, profile_media_id = NULLIF(?, ''), updated_at = ? WHERE id = ? AND household_id = ?`, req.Name, req.Species, req.Notes, req.ProfileMediaID, nowString(), r.PathValue("id"), ac.HouseholdID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "update plant failed")
		return
	}
	if affected, _ := res.RowsAffected(); affected == 0 {
		writeError(w, http.StatusNotFound, "plant not found")
		return
	}
	_, _ = a.db.ExecContext(r.Context(), `UPDATE actors SET display_name = ?, profile_media_id = NULLIF(?, '') WHERE plant_id = ?`, req.Name, req.ProfileMediaID, r.PathValue("id"))
	a.handleGetPlant(w, r)
}

func (a *App) handleCreatePlanter(w http.ResponseWriter, r *http.Request) {
	ac := authFrom(r)
	var req struct {
		Name     string `json:"name"`
		Location string `json:"location"`
		Notes    string `json:"notes"`
	}
	if !readJSON(w, r, &req) {
		return
	}
	req.Name = strings.TrimSpace(req.Name)
	if req.Name == "" {
		writeError(w, http.StatusBadRequest, "name is required")
		return
	}
	id := newID("pnr")
	now := nowString()
	if _, err := a.db.ExecContext(r.Context(), `INSERT INTO planters (id, household_id, name, location, notes, created_by_human_id, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`, id, ac.HouseholdID, req.Name, req.Location, req.Notes, ac.HumanID, now, now); err != nil {
		writeError(w, http.StatusInternalServerError, "create planter failed")
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"planter": map[string]string{"id": id, "name": req.Name, "location": req.Location, "notes": req.Notes}})
}

func (a *App) handleListPlanters(w http.ResponseWriter, r *http.Request) {
	ac := authFrom(r)
	rows, err := a.db.QueryContext(r.Context(), `SELECT id, name, location, notes, created_at FROM planters WHERE household_id = ? ORDER BY name`, ac.HouseholdID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "list planters failed")
		return
	}
	defer rows.Close()
	var planters []planter
	for rows.Next() {
		var p planter
		if err := rows.Scan(&p.ID, &p.Name, &p.Location, &p.Notes, &p.CreatedAt); err != nil {
			writeError(w, http.StatusInternalServerError, "list planters failed")
			return
		}
		planters = append(planters, p)
	}
	writeJSON(w, http.StatusOK, map[string]any{"planters": planters})
}

func (a *App) handleUpdatePlanter(w http.ResponseWriter, r *http.Request) {
	ac := authFrom(r)
	var req struct {
		Name     string `json:"name"`
		Location string `json:"location"`
		Notes    string `json:"notes"`
	}
	if !readJSON(w, r, &req) {
		return
	}
	if strings.TrimSpace(req.Name) == "" {
		writeError(w, http.StatusBadRequest, "name is required")
		return
	}
	res, err := a.db.ExecContext(r.Context(), `UPDATE planters SET name = ?, location = ?, notes = ?, updated_at = ? WHERE id = ? AND household_id = ?`, strings.TrimSpace(req.Name), req.Location, req.Notes, nowString(), r.PathValue("id"), ac.HouseholdID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "update planter failed")
		return
	}
	if affected, _ := res.RowsAffected(); affected == 0 {
		writeError(w, http.StatusNotFound, "planter not found")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"planter_id": r.PathValue("id")})
}

func (a *App) handleAddPlantToPlanter(w http.ResponseWriter, r *http.Request) {
	ac := authFrom(r)
	var req struct {
		PlantID string `json:"plant_id"`
	}
	if !readJSON(w, r, &req) {
		return
	}
	if !a.plantInHousehold(r.Context(), req.PlantID, ac.HouseholdID) || !a.planterInHousehold(r.Context(), r.PathValue("id"), ac.HouseholdID) {
		writeError(w, http.StatusNotFound, "plant or planter not found")
		return
	}
	if _, err := a.db.ExecContext(r.Context(), `INSERT OR IGNORE INTO planter_plants (planter_id, plant_id, added_by_human_id, added_at) VALUES (?, ?, ?, ?)`, r.PathValue("id"), req.PlantID, ac.HumanID, nowString()); err != nil {
		writeError(w, http.StatusInternalServerError, "add plant to planter failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"planter_id": r.PathValue("id"), "plant_id": req.PlantID})
}

func (a *App) handleUploadMedia(w http.ResponseWriter, r *http.Request) {
	ac := authFrom(r)
	if err := r.ParseMultipartForm(20 << 20); err != nil {
		writeError(w, http.StatusBadRequest, "invalid multipart form")
		return
	}
	file, header, err := r.FormFile("file")
	if err != nil {
		writeError(w, http.StatusBadRequest, "file is required")
		return
	}
	defer file.Close()
	peek := make([]byte, 512)
	n, _ := io.ReadFull(file, peek)
	peek = peek[:n]
	mimeType := http.DetectContentType(peek)
	if !strings.HasPrefix(mimeType, "image/") {
		writeError(w, http.StatusBadRequest, "only image uploads are supported")
		return
	}
	exts, _ := mime.ExtensionsByType(mimeType)
	ext := ".bin"
	if len(exts) > 0 {
		ext = exts[0]
	}
	id := newID("med")
	rel := filepath.Join(ac.HouseholdID, id+ext)
	abs := filepath.Join(a.cfg.MediaDir, rel)
	if err := os.MkdirAll(filepath.Dir(abs), 0o755); err != nil {
		writeError(w, http.StatusInternalServerError, "create media directory failed")
		return
	}
	out, err := os.Create(abs)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "create media failed")
		return
	}
	defer out.Close()
	size, err := out.Write(peek)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "write media failed")
		return
	}
	written, err := io.Copy(out, file)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "write media failed")
		return
	}
	size += int(written)
	if _, err = a.db.ExecContext(r.Context(), `INSERT INTO media_assets (id, household_id, uploaded_by_human_id, original_filename, storage_path, mime_type, size_bytes, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`, id, ac.HouseholdID, ac.HumanID, header.Filename, rel, mimeType, size, nowString()); err != nil {
		writeError(w, http.StatusInternalServerError, "save media failed")
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"media": map[string]any{"id": id, "mime_type": mimeType, "size_bytes": size, "url": "/media/" + id}})
}

func (a *App) handleGetMedia(w http.ResponseWriter, r *http.Request) {
	ac := authFrom(r)
	var storagePath, mimeType string
	err := a.db.QueryRowContext(r.Context(), `SELECT storage_path, mime_type FROM media_assets WHERE id = ? AND household_id = ?`, r.PathValue("id"), ac.HouseholdID).Scan(&storagePath, &mimeType)
	if err != nil {
		writeError(w, http.StatusNotFound, "media not found")
		return
	}
	w.Header().Set("Content-Type", mimeType)
	http.ServeFile(w, r, filepath.Join(a.cfg.MediaDir, storagePath))
}

func (a *App) handleCreatePost(w http.ResponseWriter, r *http.Request) {
	ac := authFrom(r)
	var req struct {
		AuthorActorID string   `json:"author_actor_id"`
		PostType      string   `json:"post_type"`
		Caption       string   `json:"caption"`
		ImageMediaID  string   `json:"image_media_id"`
		OccurredAt    string   `json:"occurred_at"`
		PlantIDs      []string `json:"plant_ids"`
		PlanterIDs    []string `json:"planter_ids"`
	}
	if !readJSON(w, r, &req) {
		return
	}
	if req.PostType == "" {
		req.PostType = "general"
	}
	if !validPostType(req.PostType) {
		writeError(w, http.StatusBadRequest, "invalid post_type")
		return
	}
	if req.AuthorActorID == "" {
		var err error
		req.AuthorActorID, err = a.humanActorID(r.Context(), ac.HumanID, ac.HouseholdID)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "human actor not found")
			return
		}
	} else if !a.actorInHousehold(r.Context(), req.AuthorActorID, ac.HouseholdID) {
		writeError(w, http.StatusBadRequest, "author actor not found in household")
		return
	}
	if req.ImageMediaID != "" && !a.mediaInHousehold(r.Context(), req.ImageMediaID, ac.HouseholdID) {
		writeError(w, http.StatusBadRequest, "image media not found in household")
		return
	}
	for _, id := range req.PlantIDs {
		if !a.plantInHousehold(r.Context(), id, ac.HouseholdID) {
			writeError(w, http.StatusBadRequest, "plant tag not found in household")
			return
		}
	}
	for _, id := range req.PlanterIDs {
		if !a.planterInHousehold(r.Context(), id, ac.HouseholdID) {
			writeError(w, http.StatusBadRequest, "planter tag not found in household")
			return
		}
	}
	occurredAt := nowString()
	if req.OccurredAt != "" {
		t, err := time.Parse(time.RFC3339, req.OccurredAt)
		if err != nil {
			writeError(w, http.StatusBadRequest, "occurred_at must be RFC3339")
			return
		}
		occurredAt = t.UTC().Format(time.RFC3339Nano)
	}
	id := newID("pst")
	now := nowString()
	tx, err := a.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "begin transaction failed")
		return
	}
	defer tx.Rollback()
	if _, err = tx.ExecContext(r.Context(), `INSERT INTO posts (id, household_id, author_actor_id, created_by_human_id, post_type, caption, image_media_id, occurred_at, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, NULLIF(?, ''), ?, ?, ?)`, id, ac.HouseholdID, req.AuthorActorID, ac.HumanID, req.PostType, req.Caption, req.ImageMediaID, occurredAt, now, now); err != nil {
		writeError(w, http.StatusInternalServerError, "create post failed")
		return
	}
	for _, plantID := range dedupe(req.PlantIDs) {
		if _, err = tx.ExecContext(r.Context(), `INSERT INTO post_plant_tags (post_id, plant_id) VALUES (?, ?)`, id, plantID); err != nil {
			writeError(w, http.StatusInternalServerError, "tag plant failed")
			return
		}
	}
	for _, planterID := range dedupe(req.PlanterIDs) {
		if _, err = tx.ExecContext(r.Context(), `INSERT INTO post_planter_tags (post_id, planter_id) VALUES (?, ?)`, id, planterID); err != nil {
			writeError(w, http.StatusInternalServerError, "tag planter failed")
			return
		}
	}
	if err = tx.Commit(); err != nil {
		writeError(w, http.StatusInternalServerError, "create post failed")
		return
	}
	post, err := a.loadPost(r.Context(), id, ac.HouseholdID, ac.HumanID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "load post failed")
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"post": post})
}

func (a *App) handleFeed(w http.ResponseWriter, r *http.Request) {
	ac := authFrom(r)
	cursor := cursorTime(r)
	a.writePostList(w, r, `SELECT id FROM posts WHERE household_id = ? AND (? = '' OR occurred_at < ?) ORDER BY occurred_at DESC, id DESC LIMIT ?`, ac.HouseholdID, cursor, cursor, limit(r))
}

func (a *App) handleGetPost(w http.ResponseWriter, r *http.Request) {
	ac := authFrom(r)
	post, err := a.loadPost(r.Context(), r.PathValue("id"), ac.HouseholdID, ac.HumanID)
	if err != nil {
		writeError(w, http.StatusNotFound, "post not found")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"post": post})
}

func (a *App) handlePlantTimeline(w http.ResponseWriter, r *http.Request) {
	ac := authFrom(r)
	if !a.plantInHousehold(r.Context(), r.PathValue("id"), ac.HouseholdID) {
		writeError(w, http.StatusNotFound, "plant not found")
		return
	}
	cursor := cursorTime(r)
	a.writePostList(w, r, `SELECT p.id FROM posts p JOIN post_plant_tags ppt ON ppt.post_id = p.id WHERE p.household_id = ? AND ppt.plant_id = ? AND (? = '' OR p.occurred_at < ?) ORDER BY p.occurred_at DESC, p.id DESC LIMIT ?`, ac.HouseholdID, r.PathValue("id"), cursor, cursor, limit(r))
}

func (a *App) handlePlanterTimeline(w http.ResponseWriter, r *http.Request) {
	ac := authFrom(r)
	if !a.planterInHousehold(r.Context(), r.PathValue("id"), ac.HouseholdID) {
		writeError(w, http.StatusNotFound, "planter not found")
		return
	}
	cursor := cursorTime(r)
	a.writePostList(w, r, `SELECT p.id FROM posts p JOIN post_planter_tags ppt ON ppt.post_id = p.id WHERE p.household_id = ? AND ppt.planter_id = ? AND (? = '' OR p.occurred_at < ?) ORDER BY p.occurred_at DESC, p.id DESC LIMIT ?`, ac.HouseholdID, r.PathValue("id"), cursor, cursor, limit(r))
}

func (a *App) writePostList(w http.ResponseWriter, r *http.Request, query string, args ...any) {
	ac := authFrom(r)
	rows, err := a.db.QueryContext(r.Context(), query, args...)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "list posts failed")
		return
	}
	defer rows.Close()
	ids := []string{}
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			writeError(w, http.StatusInternalServerError, "list posts failed")
			return
		}
		ids = append(ids, id)
	}
	if err := rows.Err(); err != nil {
		writeError(w, http.StatusInternalServerError, "list posts failed")
		return
	}
	rows.Close()

	posts := []post{}
	for _, id := range ids {
		p, err := a.loadPost(r.Context(), id, ac.HouseholdID, ac.HumanID)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "load post failed")
			return
		}
		posts = append(posts, p)
	}
	var nextCursor *string
	if len(posts) == limit(r) && len(posts) > 0 {
		cursor := posts[len(posts)-1].OccurredAt
		nextCursor = &cursor
	}
	writeJSON(w, http.StatusOK, map[string]any{"posts": posts, "next_cursor": nextCursor})
}

func (a *App) handleAddReaction(w http.ResponseWriter, r *http.Request) {
	ac := authFrom(r)
	var req struct {
		Emoji string `json:"emoji"`
	}
	if !readJSON(w, r, &req) {
		return
	}
	req.Emoji = strings.TrimSpace(req.Emoji)
	if !isEmojiReaction(req.Emoji) {
		writeError(w, http.StatusBadRequest, "enter one emoji")
		return
	}
	if !a.postInHousehold(r.Context(), r.PathValue("id"), ac.HouseholdID) {
		writeError(w, http.StatusNotFound, "post not found")
		return
	}
	if _, err := a.db.ExecContext(r.Context(), `INSERT OR IGNORE INTO post_reactions (post_id, human_id, emoji, created_at) VALUES (?, ?, ?, ?)`, r.PathValue("id"), ac.HumanID, req.Emoji, nowString()); err != nil {
		writeError(w, http.StatusInternalServerError, "react failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"post_id": r.PathValue("id"), "emoji": req.Emoji})
}

func isEmojiReaction(value string) bool {
	runes := []rune(value)
	if len(runes) == 0 || len(runes) > 64 {
		return false
	}

	baseCount := 0
	hasJoiner := false
	hasKeycap := false
	allRegionalIndicators := true

	for _, r := range runes {
		switch {
		case isEmojiModifier(r), isVariationSelector(r), isEmojiTag(r):
			continue
		case r == 0x200C || r == 0x200D:
			hasJoiner = true
			continue
		case r == 0x20E3:
			hasKeycap = true
			continue
		case isKeycapBase(r):
			allRegionalIndicators = false
			continue
		case isEmojiBase(r):
			baseCount++
			if r < 0x1F1E6 || r > 0x1F1FF {
				allRegionalIndicators = false
			}
		default:
			return false
		}
	}

	if hasKeycap {
		return baseCount == 0 && len(runes) >= 2
	}
	if baseCount == 0 {
		return false
	}
	if hasJoiner {
		return true
	}
	return baseCount == 1 || (baseCount == 2 && allRegionalIndicators)
}

func isEmojiBase(r rune) bool {
	return (r >= 0x1F000 && r <= 0x1FAFF) ||
		(r >= 0x2600 && r <= 0x27BF) ||
		r == 0x00A9 || r == 0x00AE || r == 0x203C || r == 0x2049 ||
		r == 0x2122 || r == 0x2139 || (r >= 0x2194 && r <= 0x2199) ||
		(r >= 0x21A9 && r <= 0x21AA) || (r >= 0x231A && r <= 0x231B) ||
		r == 0x2328 || r == 0x23CF || (r >= 0x23E9 && r <= 0x23F3) ||
		(r >= 0x23F8 && r <= 0x23FA) || r == 0x24C2 ||
		(r >= 0x25AA && r <= 0x25AB) || r == 0x25B6 || r == 0x25C0 ||
		(r >= 0x25FB && r <= 0x25FE) || (r >= 0x2934 && r <= 0x2935) ||
		(r >= 0x2B05 && r <= 0x2B07) || (r >= 0x2B1B && r <= 0x2B1C) ||
		r == 0x2B50 || r == 0x2B55 || r == 0x3030 || r == 0x303D ||
		r == 0x3297 || r == 0x3299
}

func isEmojiModifier(r rune) bool {
	return r >= 0x1F3FB && r <= 0x1F3FF
}

func isVariationSelector(r rune) bool {
	return r == 0xFE0E || r == 0xFE0F
}

func isEmojiTag(r rune) bool {
	return r >= 0xE0020 && r <= 0xE007F
}

func isKeycapBase(r rune) bool {
	return r == '#' || r == '*' || (r >= '0' && r <= '9')
}

func (a *App) handleDeleteReaction(w http.ResponseWriter, r *http.Request) {
	ac := authFrom(r)
	if !a.postInHousehold(r.Context(), r.PathValue("id"), ac.HouseholdID) {
		writeError(w, http.StatusNotFound, "post not found")
		return
	}
	emoji, _ := urlPathUnescape(r.PathValue("emoji"))
	_, _ = a.db.ExecContext(r.Context(), `DELETE FROM post_reactions WHERE post_id = ? AND human_id = ? AND emoji = ?`, r.PathValue("id"), ac.HumanID, emoji)
	w.WriteHeader(http.StatusNoContent)
}

func (a *App) handleCreateComment(w http.ResponseWriter, r *http.Request) {
	ac := authFrom(r)
	var req struct {
		Body string `json:"body"`
	}
	if !readJSON(w, r, &req) {
		return
	}
	req.Body = strings.TrimSpace(req.Body)
	if req.Body == "" {
		writeError(w, http.StatusBadRequest, "body is required")
		return
	}
	if !a.postInHousehold(r.Context(), r.PathValue("id"), ac.HouseholdID) {
		writeError(w, http.StatusNotFound, "post not found")
		return
	}
	id := newID("cmt")
	now := nowString()
	if _, err := a.db.ExecContext(r.Context(), `INSERT INTO post_comments (id, post_id, human_id, body, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)`, id, r.PathValue("id"), ac.HumanID, req.Body, now, now); err != nil {
		writeError(w, http.StatusInternalServerError, "comment failed")
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"comment": map[string]string{"id": id, "post_id": r.PathValue("id"), "human_id": ac.HumanID, "body": req.Body, "created_at": now, "updated_at": now}})
}

func (a *App) handleListComments(w http.ResponseWriter, r *http.Request) {
	ac := authFrom(r)
	if !a.postInHousehold(r.Context(), r.PathValue("id"), ac.HouseholdID) {
		writeError(w, http.StatusNotFound, "post not found")
		return
	}
	rows, err := a.db.QueryContext(r.Context(), `SELECT id, post_id, human_id, body, created_at, updated_at FROM post_comments WHERE post_id = ? AND deleted_at IS NULL ORDER BY created_at`, r.PathValue("id"))
	if err != nil {
		writeError(w, http.StatusInternalServerError, "list comments failed")
		return
	}
	defer rows.Close()
	var comments []comment
	for rows.Next() {
		var c comment
		if err := rows.Scan(&c.ID, &c.PostID, &c.HumanID, &c.Body, &c.CreatedAt, &c.UpdatedAt); err != nil {
			writeError(w, http.StatusInternalServerError, "list comments failed")
			return
		}
		comments = append(comments, c)
	}
	writeJSON(w, http.StatusOK, map[string]any{"comments": comments})
}

func (a *App) handleUpdateComment(w http.ResponseWriter, r *http.Request) {
	ac := authFrom(r)
	var req struct {
		Body string `json:"body"`
	}
	if !readJSON(w, r, &req) {
		return
	}
	req.Body = strings.TrimSpace(req.Body)
	if req.Body == "" {
		writeError(w, http.StatusBadRequest, "body is required")
		return
	}
	res, err := a.db.ExecContext(r.Context(), `UPDATE post_comments SET body = ?, updated_at = ? WHERE id = ? AND human_id = ? AND deleted_at IS NULL AND post_id IN (SELECT id FROM posts WHERE household_id = ?)`, req.Body, nowString(), r.PathValue("id"), ac.HumanID, ac.HouseholdID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "update comment failed")
		return
	}
	if affected, _ := res.RowsAffected(); affected == 0 {
		writeError(w, http.StatusNotFound, "comment not found")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"comment_id": r.PathValue("id")})
}

func (a *App) handleDeleteComment(w http.ResponseWriter, r *http.Request) {
	ac := authFrom(r)
	res, err := a.db.ExecContext(r.Context(), `UPDATE post_comments SET deleted_at = ?, updated_at = ? WHERE id = ? AND human_id = ? AND deleted_at IS NULL AND post_id IN (SELECT id FROM posts WHERE household_id = ?)`, nowString(), nowString(), r.PathValue("id"), ac.HumanID, ac.HouseholdID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "delete comment failed")
		return
	}
	if affected, _ := res.RowsAffected(); affected == 0 {
		writeError(w, http.StatusNotFound, "comment not found")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

type accessClaims struct {
	Subject     string `json:"sub"`
	HouseholdID string `json:"household_id,omitempty"`
	ExpiresAt   int64  `json:"exp"`
}

func (a *App) createAccessToken(humanID, householdID string) (string, error) {
	claims := accessClaims{Subject: humanID, HouseholdID: householdID, ExpiresAt: time.Now().Add(a.cfg.AccessTokenTTL).Unix()}
	header := map[string]string{"alg": "HS256", "typ": "JWT"}
	headerBytes, _ := json.Marshal(header)
	claimsBytes, _ := json.Marshal(claims)
	unsigned := base64.RawURLEncoding.EncodeToString(headerBytes) + "." + base64.RawURLEncoding.EncodeToString(claimsBytes)
	mac := hmac.New(sha256.New, []byte(a.cfg.JWTSecret))
	mac.Write([]byte(unsigned))
	return unsigned + "." + base64.RawURLEncoding.EncodeToString(mac.Sum(nil)), nil
}

func (a *App) verifyAccessToken(token string) (accessClaims, error) {
	var claims accessClaims
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return claims, errors.New("invalid token")
	}
	unsigned := parts[0] + "." + parts[1]
	mac := hmac.New(sha256.New, []byte(a.cfg.JWTSecret))
	mac.Write([]byte(unsigned))
	expected := mac.Sum(nil)
	got, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil || !hmac.Equal(got, expected) {
		return claims, errors.New("invalid signature")
	}
	body, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return claims, err
	}
	if err := json.Unmarshal(body, &claims); err != nil {
		return claims, err
	}
	if claims.Subject == "" || time.Now().Unix() >= claims.ExpiresAt {
		return claims, errors.New("expired token")
	}
	return claims, nil
}

func (a *App) createRefreshToken(ctx context.Context, humanID string) (plain string, id string, err error) {
	plain = randomToken(32)
	id = newID("rft")
	_, err = a.db.ExecContext(ctx, `INSERT INTO refresh_tokens (id, human_id, token_hash, expires_at, created_at) VALUES (?, ?, ?, ?, ?)`, id, humanID, hashOpaqueToken(plain), time.Now().Add(a.cfg.RefreshTokenTTL).UTC().Format(time.RFC3339Nano), nowString())
	return plain, id, err
}

func hashOpaqueToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

func readJSON(w http.ResponseWriter, r *http.Request, dst any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		writeError(w, http.StatusBadRequest, "invalid json")
		return false
	}
	return true
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}

func nowString() string {
	return time.Now().UTC().Format(time.RFC3339Nano)
}

func newID(prefix string) string {
	return prefix + "_" + randomToken(16)
}

func randomToken(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return base64.RawURLEncoding.EncodeToString(b)
}

func validPostType(v string) bool {
	switch v {
	case "general", "watering_event", "planting_event", "status_update":
		return true
	default:
		return false
	}
}

func dedupe(in []string) []string {
	seen := map[string]bool{}
	var out []string
	for _, v := range in {
		if v == "" || seen[v] {
			continue
		}
		seen[v] = true
		out = append(out, v)
	}
	return out
}

func limit(r *http.Request) int {
	n, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if n <= 0 || n > 100 {
		return 30
	}
	return n
}

func cursorTime(r *http.Request) string {
	c := r.URL.Query().Get("cursor")
	if c == "" {
		return ""
	}
	if _, err := time.Parse(time.RFC3339Nano, c); err != nil {
		return ""
	}
	return c
}

func urlPathUnescape(v string) (string, error) {
	return url.PathUnescape(v)
}
