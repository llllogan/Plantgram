package plantgram

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
)

type nullableString struct {
	sql.NullString
}

func (s nullableString) MarshalJSON() ([]byte, error) {
	if !s.Valid {
		return []byte("null"), nil
	}
	return json.Marshal(s.String)
}

type humanAccount struct {
	ID             string         `json:"id"`
	Email          string         `json:"email"`
	DisplayName    string         `json:"display_name"`
	ProfileMediaID nullableString `json:"profile_media_id"`
	CreatedAt      string         `json:"created_at"`
}

type plant struct {
	ID             string         `json:"id"`
	ActorID        string         `json:"actor_id"`
	Name           string         `json:"name"`
	Species        string         `json:"species"`
	Notes          string         `json:"notes"`
	ProfileMediaID nullableString `json:"profile_media_id"`
	CreatedAt      string         `json:"created_at"`
}

type planter struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	Location  string `json:"location"`
	Notes     string `json:"notes"`
	CreatedAt string `json:"created_at"`
}

type actor struct {
	ID             string         `json:"id"`
	Type           string         `json:"type"`
	DisplayName    string         `json:"display_name"`
	ProfileMediaID nullableString `json:"profile_media_id"`
}

type post struct {
	ID               string         `json:"id"`
	HouseholdID      string         `json:"household_id"`
	Author           actor          `json:"author"`
	CreatedByHumanID string         `json:"created_by_human_id"`
	PostType         string         `json:"post_type"`
	Caption          string         `json:"caption"`
	ImageMediaID     nullableString `json:"image_media_id"`
	ImageURL         nullableString `json:"image_url"`
	OccurredAt       string         `json:"occurred_at"`
	CreatedAt        string         `json:"created_at"`
	UpdatedAt        string         `json:"updated_at"`
	PlantIDs         []string       `json:"plant_ids"`
	PlanterIDs       []string       `json:"planter_ids"`
	Reactions        []reaction     `json:"reactions"`
	CommentCount     int            `json:"comment_count"`
}

type reaction struct {
	Emoji string `json:"emoji"`
	Count int    `json:"count"`
	Mine  bool   `json:"mine"`
}

type comment struct {
	ID        string `json:"id"`
	PostID    string `json:"post_id"`
	HumanID   string `json:"human_id"`
	Body      string `json:"body"`
	CreatedAt string `json:"created_at"`
	UpdatedAt string `json:"updated_at"`
}

func (a *App) isHouseholdMember(ctx context.Context, householdID, humanID string) (bool, error) {
	var count int
	err := a.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM household_members WHERE household_id = ? AND human_id = ?`, householdID, humanID).Scan(&count)
	return count > 0, err
}

func (a *App) plantInHousehold(ctx context.Context, plantID, householdID string) bool {
	var count int
	_ = a.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM plant_accounts WHERE id = ? AND household_id = ?`, plantID, householdID).Scan(&count)
	return count > 0
}

func (a *App) planterInHousehold(ctx context.Context, planterID, householdID string) bool {
	var count int
	_ = a.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM planters WHERE id = ? AND household_id = ?`, planterID, householdID).Scan(&count)
	return count > 0
}

func (a *App) actorInHousehold(ctx context.Context, actorID, householdID string) bool {
	var count int
	_ = a.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM actors WHERE id = ? AND household_id = ?`, actorID, householdID).Scan(&count)
	return count > 0
}

func (a *App) mediaInHousehold(ctx context.Context, mediaID, householdID string) bool {
	var count int
	_ = a.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM media_assets WHERE id = ? AND household_id = ?`, mediaID, householdID).Scan(&count)
	return count > 0
}

func (a *App) postInHousehold(ctx context.Context, postID, householdID string) bool {
	var count int
	_ = a.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM posts WHERE id = ? AND household_id = ?`, postID, householdID).Scan(&count)
	return count > 0
}

func (a *App) humanActorID(ctx context.Context, humanID, householdID string) (string, error) {
	var id string
	err := a.db.QueryRowContext(ctx, `SELECT id FROM actors WHERE actor_type = 'human' AND human_id = ? AND household_id = ?`, humanID, householdID).Scan(&id)
	if err == nil {
		return id, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return "", err
	}
	var displayName string
	if err = a.db.QueryRowContext(ctx, `SELECT display_name FROM human_accounts WHERE id = ?`, humanID).Scan(&displayName); err != nil {
		return "", err
	}
	id = newID("act")
	_, err = a.db.ExecContext(ctx, `INSERT INTO actors (id, household_id, actor_type, human_id, display_name, created_at) VALUES (?, ?, 'human', ?, ?, ?)`, id, householdID, humanID, displayName, nowString())
	return id, err
}

func (a *App) getPlant(ctx context.Context, id, householdID string) (plant, bool) {
	var p plant
	err := a.db.QueryRowContext(ctx, `SELECT id, actor_id, name, species, notes, profile_media_id, created_at FROM plant_accounts WHERE id = ? AND household_id = ?`, id, householdID).Scan(&p.ID, &p.ActorID, &p.Name, &p.Species, &p.Notes, &p.ProfileMediaID, &p.CreatedAt)
	return p, err == nil
}

func (a *App) loadPost(ctx context.Context, id, householdID, humanID string) (post, error) {
	var p post
	var authorID string
	err := a.db.QueryRowContext(ctx, `
SELECT p.id, p.household_id, p.author_actor_id, p.created_by_human_id, p.post_type, p.caption, p.image_media_id, p.occurred_at, p.created_at, p.updated_at,
       a.id, a.actor_type, a.display_name, a.profile_media_id
FROM posts p
JOIN actors a ON a.id = p.author_actor_id
WHERE p.id = ? AND p.household_id = ?`, id, householdID).Scan(&p.ID, &p.HouseholdID, &authorID, &p.CreatedByHumanID, &p.PostType, &p.Caption, &p.ImageMediaID, &p.OccurredAt, &p.CreatedAt, &p.UpdatedAt, &p.Author.ID, &p.Author.Type, &p.Author.DisplayName, &p.Author.ProfileMediaID)
	if err != nil {
		return p, err
	}
	if p.ImageMediaID.Valid {
		p.ImageURL = nullableString{sql.NullString{String: "/media/" + p.ImageMediaID.String, Valid: true}}
	}
	p.PlantIDs, err = a.loadStringList(ctx, `SELECT plant_id FROM post_plant_tags WHERE post_id = ? ORDER BY plant_id`, p.ID)
	if err != nil {
		return p, err
	}
	p.PlanterIDs, err = a.loadStringList(ctx, `SELECT planter_id FROM post_planter_tags WHERE post_id = ? ORDER BY planter_id`, p.ID)
	if err != nil {
		return p, err
	}
	p.Reactions, err = a.loadReactions(ctx, p.ID, humanID)
	if err != nil {
		return p, err
	}
	_ = a.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM post_comments WHERE post_id = ? AND deleted_at IS NULL`, p.ID).Scan(&p.CommentCount)
	return p, nil
}

func (a *App) loadStringList(ctx context.Context, query string, args ...any) ([]string, error) {
	rows, err := a.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []string{}
	for rows.Next() {
		var v string
		if err := rows.Scan(&v); err != nil {
			return nil, err
		}
		out = append(out, v)
	}
	return out, rows.Err()
}

func (a *App) loadReactions(ctx context.Context, postID, humanID string) ([]reaction, error) {
	rows, err := a.db.QueryContext(ctx, `
SELECT emoji, COUNT(*), MAX(CASE WHEN human_id = ? THEN 1 ELSE 0 END)
FROM post_reactions
WHERE post_id = ?
GROUP BY emoji
ORDER BY emoji`, humanID, postID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []reaction{}
	for rows.Next() {
		var r reaction
		var mine int
		if err := rows.Scan(&r.Emoji, &r.Count, &mine); err != nil {
			return nil, err
		}
		r.Mine = mine == 1
		out = append(out, r)
	}
	return out, rows.Err()
}
