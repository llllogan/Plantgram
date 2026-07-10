package plantgram

import (
	"context"
	"crypto"
	"crypto/rsa"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"math/big"
	"net/http"
	"strings"
	"time"
)

const appleKeysURL = "https://appleid.apple.com/auth/keys"

type appleSignInRequest struct {
	IdentityToken     string `json:"identity_token"`
	AuthorizationCode string `json:"authorization_code"`
	RawNonce          string `json:"raw_nonce"`
	UserIdentifier    string `json:"user_identifier"`
	Email             string `json:"email"`
	FullName          string `json:"full_name"`
}

type appleClaims struct {
	Issuer   string `json:"iss"`
	Audience string `json:"aud"`
	Subject  string `json:"sub"`
	Email    string `json:"email"`
	Expires  int64  `json:"exp"`
	Nonce    string `json:"nonce"`
}

type appleJWKSet struct {
	Keys []appleJWK `json:"keys"`
}

type appleJWK struct {
	KeyType string `json:"kty"`
	KeyID   string `json:"kid"`
	Use     string `json:"use"`
	Alg     string `json:"alg"`
	N       string `json:"n"`
	E       string `json:"e"`
}

func (a *App) handleAppleSignIn(w http.ResponseWriter, r *http.Request) {
	var req appleSignInRequest
	if !readJSON(w, r, &req) {
		return
	}
	req.Email = strings.ToLower(strings.TrimSpace(req.Email))
	req.FullName = strings.TrimSpace(req.FullName)
	if req.IdentityToken == "" || req.RawNonce == "" {
		writeError(w, http.StatusBadRequest, "identity_token and raw_nonce are required")
		return
	}

	claims, err := a.verifyAppleIdentityToken(r.Context(), req.IdentityToken, req.RawNonce)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "invalid apple identity token")
		return
	}
	if req.UserIdentifier != "" && req.UserIdentifier != claims.Subject {
		writeError(w, http.StatusUnauthorized, "apple user mismatch")
		return
	}

	email := claims.Email
	if email == "" {
		email = req.Email
	}
	if email == "" {
		email = "apple+" + claims.Subject + "@plantgram.local"
	}
	displayName := req.FullName
	if displayName == "" {
		displayName = "Plantgram User"
	}

	humanID, err := a.findOrCreateAppleHuman(r.Context(), claims.Subject, strings.ToLower(email), displayName)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "apple sign in failed")
		return
	}
	a.writeAuthResponse(w, r, humanID, "")
}

func (a *App) findOrCreateAppleHuman(ctx context.Context, appleUserID, email, displayName string) (string, error) {
	var humanID string
	err := a.db.QueryRowContext(ctx, `SELECT id FROM human_accounts WHERE apple_user_id = ?`, appleUserID).Scan(&humanID)
	if err == nil {
		return humanID, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return "", err
	}

	now := nowString()
	humanID = newID("hum")
	_, err = a.db.ExecContext(ctx, `INSERT INTO human_accounts (id, email, apple_user_id, display_name, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)`, humanID, email, appleUserID, displayName, now, now)
	if err == nil {
		return humanID, nil
	}

	err = a.db.QueryRowContext(ctx, `SELECT id FROM human_accounts WHERE email = ?`, email).Scan(&humanID)
	if err != nil {
		return "", err
	}
	_, err = a.db.ExecContext(ctx, `UPDATE human_accounts SET apple_user_id = ?, updated_at = ? WHERE id = ?`, appleUserID, now, humanID)
	return humanID, err
}

func (a *App) verifyAppleIdentityToken(ctx context.Context, token, rawNonce string) (appleClaims, error) {
	var claims appleClaims
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return claims, errors.New("invalid token")
	}

	var header struct {
		Algorithm string `json:"alg"`
		KeyID     string `json:"kid"`
	}
	headerBytes, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return claims, err
	}
	if err := json.Unmarshal(headerBytes, &header); err != nil {
		return claims, err
	}
	if header.Algorithm != "RS256" || header.KeyID == "" {
		return claims, errors.New("unsupported apple token header")
	}

	key, err := applePublicKey(ctx, header.KeyID)
	if err != nil {
		return claims, err
	}
	signed := []byte(parts[0] + "." + parts[1])
	signature, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil {
		return claims, err
	}
	digest := sha256.Sum256(signed)
	if err := rsa.VerifyPKCS1v15(key, crypto.SHA256, digest[:], signature); err != nil {
		return claims, err
	}

	claimsBytes, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return claims, err
	}
	if err := json.Unmarshal(claimsBytes, &claims); err != nil {
		return claims, err
	}
	if claims.Issuer != "https://appleid.apple.com" || claims.Audience != a.cfg.AppleClientID || claims.Subject == "" || time.Now().Unix() >= claims.Expires {
		return claims, errors.New("invalid apple claims")
	}
	expectedNonce := sha256Hex(rawNonce)
	if claims.Nonce != "" && claims.Nonce != expectedNonce {
		return claims, errors.New("invalid nonce")
	}
	return claims, nil
}

func applePublicKey(ctx context.Context, keyID string) (*rsa.PublicKey, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, appleKeysURL, nil)
	if err != nil {
		return nil, err
	}
	client := http.Client{Timeout: 5 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, errors.New("apple keys request failed")
	}

	var set appleJWKSet
	if err := json.NewDecoder(resp.Body).Decode(&set); err != nil {
		return nil, err
	}
	for _, key := range set.Keys {
		if key.KeyID == keyID && key.KeyType == "RSA" {
			return rsaPublicKeyFromJWK(key)
		}
	}
	return nil, errors.New("apple key not found")
}

func rsaPublicKeyFromJWK(key appleJWK) (*rsa.PublicKey, error) {
	nBytes, err := base64.RawURLEncoding.DecodeString(key.N)
	if err != nil {
		return nil, err
	}
	eBytes, err := base64.RawURLEncoding.DecodeString(key.E)
	if err != nil {
		return nil, err
	}
	e := 0
	for _, b := range eBytes {
		e = e<<8 + int(b)
	}
	if e == 0 {
		return nil, errors.New("invalid exponent")
	}
	return &rsa.PublicKey{N: new(big.Int).SetBytes(nBytes), E: e}, nil
}

func sha256Hex(value string) string {
	sum := sha256.Sum256([]byte(value))
	return hex.EncodeToString(sum[:])
}
