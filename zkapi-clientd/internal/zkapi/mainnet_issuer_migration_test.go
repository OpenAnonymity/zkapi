package zkapi

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestMainnetIssuerMigrationPreservesDeploymentAndWallet(t *testing.T) {
	_, packaged, err := pinnedDeployment("mainnet")
	if err != nil {
		t.Fatal(err)
	}
	previous := bytes.Replace(packaged, []byte("https://org-live.openanonymity.ai"), []byte("https://org-staging.openanonymity.ai"), 1)
	previous = bytes.Replace(previous, []byte("https://verifier-production-20260917.openanonymity.ai"), []byte("https://verifier2.openanonymity.ai"), 1)
	for _, pair := range []struct {
		raw  []byte
		want string
	}{{previous, previousMainnetManifestSHA256}, {packaged, productionMainnetManifestSHA256}} {
		digest := sha256.Sum256(pair.raw)
		if hex.EncodeToString(digest[:]) != pair.want {
			t.Fatal("Mainnet manifest pair changed; review the complete migration before updating pins")
		}
	}
	var oldManifest, newManifest map[string]any
	if json.Unmarshal(previous, &oldManifest) != nil || json.Unmarshal(packaged, &newManifest) != nil {
		t.Fatal("invalid manifest")
	}
	oldPrivacy := oldManifest["privacy_mode"].(map[string]any)
	newPrivacy := newManifest["privacy_mode"].(map[string]any)
	for _, key := range []string{"issuer_url", "verifier_url"} {
		delete(oldPrivacy, key)
		delete(newPrivacy, key)
	}
	if !reflect.DeepEqual(oldManifest, newManifest) {
		t.Fatal("issuer migration changed other deployment bindings")
	}
	dir := t.TempDir()
	path := filepath.Join(dir, "deployment-manifest.json")
	if err := os.WriteFile(path, previous, 0600); err != nil {
		t.Fatal(err)
	}
	wallet := filepath.Join(dir, "wallet.json")
	const sentinel = "synthetic private note and pending request"
	if err := os.WriteFile(wallet, []byte(sentinel), 0600); err != nil {
		t.Fatal(err)
	}
	for range 2 {
		if _, err := writeDeploymentManifest(dir, packaged); err != nil {
			t.Fatal("reviewed migration or subsequent restart failed", err)
		}
	}
	got, _ := os.ReadFile(path)
	info, statErr := os.Stat(path)
	state, stateErr := os.ReadFile(wallet)
	if !bytes.Equal(got, packaged) || statErr != nil || info.Mode().Perm() != 0600 || stateErr != nil || string(state) != sentinel {
		t.Fatal("migration failed to preserve wallet contents or private manifest")
	}

	for _, change := range []struct{ name, before, after string }{
		{"vault", "0x4386FDbdA35D995beB3BF8625118Ec5982ec81fe", "0x1111111111111111111111111111111111111111"},
		{"deployment", "fresh-20260930", "fresh-20260928"},
		{"signer", "0x2094c5f9e183a8aef5be682556a17aa4dbafdb03fd6e6a97d75a03efed2fe5a4", "0x1"},
		{"proof", "c894b261a13f571d0df36be29734aabf2a8cd7162baddc5e08a50341aa076584", strings.Repeat("a", 64)},
		{"protocol origin", "https://zkapi-mainnet.openanonymity.ai", "https://untrusted.example"},
		{"extra field", "{\n", "{\n  \"unreviewed\": true,\n"},
		{"formatting", "{\n", "{\n\n"},
	} {
		t.Run(change.name, func(t *testing.T) {
			changedSource := bytes.Replace(previous, []byte(change.before), []byte(change.after), 1)
			changedTarget := bytes.Replace(packaged, []byte(change.before), []byte(change.after), 1)
			if bytes.Equal(changedSource, previous) || bytes.Equal(changedTarget, packaged) {
				t.Fatal("test did not mutate both manifests")
			}
			if isMainnetIssuerMigration(changedSource, packaged) || isMainnetIssuerMigration(previous, changedTarget) {
				t.Fatal("changed source or target accepted")
			}
			if err := os.WriteFile(path, changedSource, 0600); err != nil {
				t.Fatal(err)
			}
			if _, err := writeDeploymentManifest(dir, packaged); err == nil {
				t.Fatal("unreviewed saved manifest migrated")
			}
			got, _ := os.ReadFile(path)
			if !bytes.Equal(got, changedSource) {
				t.Fatal("refusal changed the saved manifest")
			}
		})
	}
	partial := bytes.Replace(previous, []byte("https://org-staging.openanonymity.ai"), []byte("https://org-live.openanonymity.ai"), 1)
	unknown := bytes.Replace(previous, []byte("https://verifier2.openanonymity.ai"), []byte("https://untrusted.example"), 1)
	_, sepolia, _ := pinnedDeployment("sepolia")
	for _, candidate := range [][]byte{partial, unknown, sepolia, packaged, nil} {
		if isMainnetIssuerMigration(candidate, packaged) {
			t.Fatal("unexpected migration source accepted")
		}
	}
	if isMainnetIssuerMigration(previous, sepolia) || isMainnetIssuerMigration(packaged, previous) || isMainnetIssuerMigration(previous, nil) {
		t.Fatal("unrelated or reversed replacement accepted")
	}
}
