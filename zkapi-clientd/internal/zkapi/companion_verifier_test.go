package zkapi

import (
	"testing"

	"github.com/ethereum/zkapi/zkapi-clientd/internal/config"
)

func TestProfileVerifierDefaultsMatchCompanionDeploymentPins(t *testing.T) {
	for _, network := range []string{"mainnet", "sepolia"} {
		deployment, _, err := pinnedDeployment(network)
		if err != nil {
			t.Fatal(err)
		}
		profile, err := config.Default()
		if err != nil {
			t.Fatal(err)
		}
		profile = config.SelectNetwork(profile, network)
		if deployment.Privacy.VerifierURL == "" || profile.VerifierURL != deployment.Privacy.VerifierURL {
			t.Fatalf("%s profile verifier disagrees with the companion manifest pin", network)
		}
	}
}
