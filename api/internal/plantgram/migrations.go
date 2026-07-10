package plantgram

import (
	"context"
	"database/sql"
	"strings"
)

const schema = `
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS human_accounts (
	id TEXT PRIMARY KEY,
	email TEXT NOT NULL UNIQUE,
	apple_user_id TEXT NOT NULL UNIQUE,
	display_name TEXT NOT NULL,
	profile_media_id TEXT,
	created_at TEXT NOT NULL,
	updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS households (
	id TEXT PRIMARY KEY,
	name TEXT NOT NULL,
	created_by_human_id TEXT NOT NULL REFERENCES human_accounts(id),
	created_at TEXT NOT NULL,
	updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS household_members (
	household_id TEXT NOT NULL REFERENCES households(id) ON DELETE CASCADE,
	human_id TEXT NOT NULL REFERENCES human_accounts(id) ON DELETE CASCADE,
	role TEXT NOT NULL CHECK (role IN ('owner', 'member')),
	joined_at TEXT NOT NULL,
	PRIMARY KEY (household_id, human_id)
);

CREATE TABLE IF NOT EXISTS actors (
	id TEXT PRIMARY KEY,
	household_id TEXT REFERENCES households(id) ON DELETE CASCADE,
	actor_type TEXT NOT NULL CHECK (actor_type IN ('human', 'plant')),
	human_id TEXT REFERENCES human_accounts(id) ON DELETE CASCADE,
	plant_id TEXT,
	display_name TEXT NOT NULL,
	profile_media_id TEXT,
	created_at TEXT NOT NULL,
	UNIQUE (household_id, human_id),
	UNIQUE (plant_id),
	CHECK (
		(actor_type = 'human' AND human_id IS NOT NULL AND plant_id IS NULL) OR
		(actor_type = 'plant' AND plant_id IS NOT NULL AND human_id IS NULL)
	)
);

CREATE TABLE IF NOT EXISTS media_assets (
	id TEXT PRIMARY KEY,
	household_id TEXT REFERENCES households(id) ON DELETE CASCADE,
	uploaded_by_human_id TEXT NOT NULL REFERENCES human_accounts(id),
	original_filename TEXT NOT NULL,
	storage_path TEXT NOT NULL,
	mime_type TEXT NOT NULL,
	size_bytes INTEGER NOT NULL,
	created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS plant_accounts (
	id TEXT PRIMARY KEY,
	household_id TEXT NOT NULL REFERENCES households(id) ON DELETE CASCADE,
	actor_id TEXT UNIQUE REFERENCES actors(id),
	name TEXT NOT NULL,
	species TEXT NOT NULL DEFAULT '',
	notes TEXT NOT NULL DEFAULT '',
	profile_media_id TEXT REFERENCES media_assets(id),
	created_by_human_id TEXT NOT NULL REFERENCES human_accounts(id),
	created_at TEXT NOT NULL,
	updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS planters (
	id TEXT PRIMARY KEY,
	household_id TEXT NOT NULL REFERENCES households(id) ON DELETE CASCADE,
	name TEXT NOT NULL,
	location TEXT NOT NULL DEFAULT '',
	notes TEXT NOT NULL DEFAULT '',
	created_by_human_id TEXT NOT NULL REFERENCES human_accounts(id),
	created_at TEXT NOT NULL,
	updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS planter_plants (
	planter_id TEXT NOT NULL REFERENCES planters(id) ON DELETE CASCADE,
	plant_id TEXT NOT NULL REFERENCES plant_accounts(id) ON DELETE CASCADE,
	added_by_human_id TEXT NOT NULL REFERENCES human_accounts(id),
	added_at TEXT NOT NULL,
	PRIMARY KEY (planter_id, plant_id)
);

CREATE TABLE IF NOT EXISTS refresh_tokens (
	id TEXT PRIMARY KEY,
	human_id TEXT NOT NULL REFERENCES human_accounts(id) ON DELETE CASCADE,
	token_hash TEXT NOT NULL UNIQUE,
	expires_at TEXT NOT NULL,
	revoked_at TEXT,
	replaced_by_token_id TEXT,
	created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS posts (
	id TEXT PRIMARY KEY,
	household_id TEXT NOT NULL REFERENCES households(id) ON DELETE CASCADE,
	author_actor_id TEXT NOT NULL REFERENCES actors(id),
	created_by_human_id TEXT NOT NULL REFERENCES human_accounts(id),
	post_type TEXT NOT NULL CHECK (post_type IN ('general', 'watering_event', 'planting_event', 'status_update')),
	caption TEXT NOT NULL DEFAULT '',
	image_media_id TEXT REFERENCES media_assets(id),
	occurred_at TEXT NOT NULL,
	created_at TEXT NOT NULL,
	updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS post_plant_tags (
	post_id TEXT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
	plant_id TEXT NOT NULL REFERENCES plant_accounts(id) ON DELETE CASCADE,
	PRIMARY KEY (post_id, plant_id)
);

CREATE TABLE IF NOT EXISTS post_planter_tags (
	post_id TEXT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
	planter_id TEXT NOT NULL REFERENCES planters(id) ON DELETE CASCADE,
	PRIMARY KEY (post_id, planter_id)
);

CREATE TABLE IF NOT EXISTS post_reactions (
	post_id TEXT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
	human_id TEXT NOT NULL REFERENCES human_accounts(id) ON DELETE CASCADE,
	emoji TEXT NOT NULL,
	created_at TEXT NOT NULL,
	PRIMARY KEY (post_id, human_id, emoji)
);

CREATE TABLE IF NOT EXISTS post_comments (
	id TEXT PRIMARY KEY,
	post_id TEXT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
	human_id TEXT NOT NULL REFERENCES human_accounts(id) ON DELETE CASCADE,
	body TEXT NOT NULL,
	created_at TEXT NOT NULL,
	updated_at TEXT NOT NULL,
	deleted_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_household_members_human ON household_members(human_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_human_apple_user_id ON human_accounts(apple_user_id);
CREATE INDEX IF NOT EXISTS idx_plants_household ON plant_accounts(household_id);
CREATE INDEX IF NOT EXISTS idx_planters_household ON planters(household_id);
CREATE INDEX IF NOT EXISTS idx_posts_feed ON posts(household_id, occurred_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_post_plant_tags_plant ON post_plant_tags(plant_id, post_id);
CREATE INDEX IF NOT EXISTS idx_post_planter_tags_planter ON post_planter_tags(planter_id, post_id);
CREATE INDEX IF NOT EXISTS idx_comments_post ON post_comments(post_id, created_at);
`

func migrate(ctx context.Context, db *sql.DB) error {
	for _, stmt := range strings.Split(schema, ";") {
		stmt = strings.TrimSpace(stmt)
		if stmt == "" {
			continue
		}
		if _, err := db.ExecContext(ctx, stmt); err != nil {
			return err
		}
	}
	if err := migrateHumanAccountsToAppleOnly(ctx, db); err != nil {
		return err
	}
	return nil
}

func migrateHumanAccountsToAppleOnly(ctx context.Context, db *sql.DB) error {
	columns, err := tableColumns(ctx, db, "human_accounts")
	if err != nil {
		return err
	}
	if !columns["apple_user_id"] {
		if _, err := db.ExecContext(ctx, `ALTER TABLE human_accounts ADD COLUMN apple_user_id TEXT`); err != nil {
			return err
		}
	}
	for _, column := range []string{"password_hash", "auth_provider"} {
		if !columns[column] {
			continue
		}
		if _, err := db.ExecContext(ctx, `ALTER TABLE human_accounts DROP COLUMN `+column); err != nil {
			return err
		}
	}
	_, err = db.ExecContext(ctx, `CREATE UNIQUE INDEX IF NOT EXISTS idx_human_apple_user_id ON human_accounts(apple_user_id)`)
	return err
}

func tableColumns(ctx context.Context, db *sql.DB, table string) (map[string]bool, error) {
	rows, err := db.QueryContext(ctx, `PRAGMA table_info(`+table+`)`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	columns := map[string]bool{}
	for rows.Next() {
		var cid int
		var name, typ string
		var notNull int
		var defaultValue sql.NullString
		var pk int
		if err := rows.Scan(&cid, &name, &typ, &notNull, &defaultValue, &pk); err != nil {
			return nil, err
		}
		columns[name] = true
	}
	return columns, rows.Err()
}
