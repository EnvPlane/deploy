package main

import (
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestGenerateAndSignCreatesBoundedEphemeralMaterial(t *testing.T) {
	dir := t.TempDir()
	privatePath := filepath.Join(dir, "private")
	publicPath := filepath.Join(dir, "public.json")
	generate([]string{"--private-key-output", privatePath, "--public-keys-output", publicPath})
	privateInfo, err := os.Stat(privatePath)
	if err != nil || privateInfo.Mode().Perm() != 0o600 {
		t.Fatalf("private key permissions = %v, err=%v", privateInfo.Mode(), err)
	}
	var keys []verificationKey
	publicRaw, err := os.ReadFile(publicPath)
	if err != nil || json.Unmarshal(publicRaw, &keys) != nil || len(keys) != 1 || keys[0].KeyID != keyID {
		t.Fatalf("invalid public fixture: %s err=%v", publicRaw, err)
	}
	codePath := filepath.Join(dir, "code")
	sign([]string{"--private-key", privatePath, "--output", codePath, "--installation-id", "installation", "--tenant-id", "tenant", "--expires-in", "1m"})
	codeRaw, err := os.ReadFile(codePath)
	if err != nil {
		t.Fatal(err)
	}
	parts := strings.Split(string(codeRaw), ".")
	if len(parts) != 3 || parts[0] != "v1" {
		t.Fatalf("activation code envelope is invalid")
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		t.Fatal(err)
	}
	signature, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil {
		t.Fatal(err)
	}
	public, err := base64.RawStdEncoding.DecodeString(keys[0].PublicKey)
	if err != nil || !ed25519.Verify(ed25519.PublicKey(public), payload, signature) {
		t.Fatalf("ephemeral activation code signature rejected: %v", err)
	}
	var parsed envelope
	if err := json.Unmarshal(payload, &parsed); err != nil {
		t.Fatal(err)
	}
	if parsed.Grant.InstallationID != "installation" || parsed.Grant.TenantID != "tenant" || !parsed.Grant.ExpiresAt.After(time.Now().UTC()) {
		t.Fatalf("activation grant binding=%+v", parsed.Grant)
	}
}

func TestSignAcceptsRequestedLimits(t *testing.T) {
	dir := t.TempDir()
	privatePath := filepath.Join(dir, "private")
	publicPath := filepath.Join(dir, "public.json")
	codePath := filepath.Join(dir, "code")
	generate([]string{"--private-key-output", privatePath, "--public-keys-output", publicPath})
	sign([]string{"--private-key", privatePath, "--output", codePath, "--installation-id", "installation", "--tenant-id", "tenant", "--projects-max", "5", "--environments-active-max", "20", "--expires-in", "1h"})
	raw, err := os.ReadFile(codePath)
	if err != nil {
		t.Fatal(err)
	}
	parts := strings.Split(string(raw), ".")
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		t.Fatal(err)
	}
	var parsed envelope
	if err := json.Unmarshal(payload, &parsed); err != nil {
		t.Fatal(err)
	}
	if parsed.Grant.Limits["projects.max"] != 5 || parsed.Grant.Limits["environments.active.max"] != 20 {
		t.Fatalf("limits = %#v", parsed.Grant.Limits)
	}
}
