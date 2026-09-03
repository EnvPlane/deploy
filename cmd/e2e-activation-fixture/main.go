// e2e-activation-fixture creates disposable activation material for release
// tests. It is never part of a chart image and deliberately writes codes and
// private keys only to caller-selected 0600 files.
package main

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const keyID = "clean-cluster-e2e"

type grant struct {
	SchemaVersion  string           `json:"schemaVersion"`
	InstallationID string           `json:"installationId"`
	TenantID       string           `json:"tenantId"`
	SKU            string           `json:"sku"`
	PlanID         string           `json:"planId"`
	PlanVersion    string           `json:"planVersion"`
	Features       map[string]bool  `json:"features"`
	Limits         map[string]int64 `json:"limits"`
	IssuedAt       time.Time        `json:"issuedAt"`
	NotBefore      time.Time        `json:"notBefore"`
	ExpiresAt      time.Time        `json:"expiresAt"`
	LicenseID      string           `json:"licenseId"`
	Nonce          string           `json:"nonce"`
	Commercial     commercial       `json:"commercial"`
}

type commercial struct {
	Currency        string `json:"currency"`
	AmountMinor     int64  `json:"amountMinor"`
	BillingInterval string `json:"billingInterval"`
	TaxMode         string `json:"taxMode"`
}

type envelope struct {
	Version   string `json:"v"`
	KeyID     string `json:"kid"`
	Algorithm string `json:"alg"`
	Grant     grant  `json:"grant"`
}

type verificationKey struct {
	KeyID     string `json:"keyId"`
	Algorithm string `json:"algorithm"`
	PublicKey string `json:"publicKey"`
	Status    string `json:"status"`
}

func main() {
	if len(os.Args) < 2 {
		fatal(errors.New("expected generate or sign command"))
	}
	switch os.Args[1] {
	case "generate":
		generate(os.Args[2:])
	case "sign":
		sign(os.Args[2:])
	default:
		fatal(fmt.Errorf("unknown command %q", os.Args[1]))
	}
}

func generate(args []string) {
	flags := flag.NewFlagSet("generate", flag.ExitOnError)
	privatePath := flags.String("private-key-output", "", "0600 private key output")
	publicPath := flags.String("public-keys-output", "", "public verification key output")
	_ = flags.Parse(args)
	if *privatePath == "" || *publicPath == "" {
		fatal(errors.New("private-key-output and public-keys-output are required"))
	}
	public, private, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		fatal(err)
	}
	privateSeed := private.Seed()
	keys, err := json.Marshal([]verificationKey{{KeyID: keyID, Algorithm: "Ed25519", PublicKey: base64.RawStdEncoding.EncodeToString(public), Status: "active"}})
	if err != nil {
		fatal(err)
	}
	if err := writePrivate(*privatePath, []byte(base64.RawStdEncoding.EncodeToString(privateSeed))); err != nil {
		fatal(err)
	}
	if err := writePrivate(*publicPath, keys); err != nil {
		fatal(err)
	}
}

func sign(args []string) {
	flags := flag.NewFlagSet("sign", flag.ExitOnError)
	privatePath := flags.String("private-key", "", "private key from generate")
	outputPath := flags.String("output", "", "0600 activation code output")
	installationID := flags.String("installation-id", "", "safe installation identifier")
	tenantID := flags.String("tenant-id", "", "safe tenant identifier")
	projectsMax := flags.Int64("projects-max", 5, "maximum projects")
	environmentsMax := flags.Int64("environments-active-max", 5, "maximum active environments")
	expiresIn := flags.Duration("expires-in", 15*time.Second, "positive lifetime")
	_ = flags.Parse(args)
	if *privatePath == "" || *outputPath == "" || strings.TrimSpace(*installationID) == "" || strings.TrimSpace(*tenantID) == "" || *projectsMax < 0 || *environmentsMax < 0 || *expiresIn <= 0 {
		fatal(errors.New("private-key, output, installation-id, tenant-id, and a positive expires-in are required"))
	}
	seed, err := os.ReadFile(*privatePath)
	if err != nil {
		fatal(err)
	}
	decoded, err := base64.RawStdEncoding.DecodeString(strings.TrimSpace(string(seed)))
	if err != nil || len(decoded) != ed25519.SeedSize {
		fatal(errors.New("invalid ephemeral activation private key"))
	}
	now := time.Now().UTC().Truncate(time.Second)
	nonce := make([]byte, 24)
	if _, err := rand.Read(nonce); err != nil {
		fatal(err)
	}
	payload, err := json.Marshal(envelope{
		Version: "v1", KeyID: keyID, Algorithm: "Ed25519",
		Grant: grant{
			SchemaVersion: "v1", InstallationID: *installationID, TenantID: *tenantID,
			SKU: "e2e", PlanID: "e2e", PlanVersion: "1", Features: map[string]bool{"e2e": true},
			Limits:   map[string]int64{"projects.max": *projectsMax, "environments.active.max": *environmentsMax},
			IssuedAt: now, NotBefore: now, ExpiresAt: now.Add(*expiresIn), LicenseID: "clean-cluster-e2e",
			Nonce:      base64.RawURLEncoding.EncodeToString(nonce),
			Commercial: commercial{Currency: "EUR", AmountMinor: 0, BillingInterval: "test", TaxMode: "exclusive"},
		},
	})
	if err != nil {
		fatal(err)
	}
	private := ed25519.NewKeyFromSeed(decoded)
	code := "v1." + base64.RawURLEncoding.EncodeToString(payload) + "." + base64.RawURLEncoding.EncodeToString(ed25519.Sign(private, payload))
	if err := writePrivate(*outputPath, []byte(code)); err != nil {
		fatal(err)
	}
}

func writePrivate(path string, value []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	return os.WriteFile(path, value, 0o600)
}

func fatal(err error) {
	fmt.Fprintln(os.Stderr, "e2e activation fixture:", err)
	os.Exit(2)
}
