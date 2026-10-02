package zkapi

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"os"
	"strings"
	"testing"
)

// The golden results are produced by executing OA's actual modelTiers.js and
// zkapiModelBudget.mjs, not by deriving expected values from this Go code.
func TestWebModelBudgetParityFixture(t *testing.T) {
	raw, err := os.ReadFile("testdata/web-model-budgets.json")
	if err != nil {
		t.Fatal(err)
	}
	var fixture struct {
		Assignments map[string]uint64 `json:"assignments"`
		Cases       []struct {
			Model     string `json:"model"`
			Reasoning bool   `json:"reasoning"`
			MicroUSD  uint64 `json:"micro_usd"`
			Error     string `json:"error"`
		} `json:"cases"`
	}
	if err := json.Unmarshal(raw, &fixture); err != nil {
		t.Fatal(err)
	}
	if len(fixture.Cases) == 0 {
		t.Fatal("empty web parity fixture")
	}
	models := []map[string]string{}
	for _, test := range fixture.Cases {
		models = append(models, map[string]string{"id": test.Model})
	}
	catalog, _ := json.Marshal(map[string]any{"data": models})
	c := &Client{config: Config{Network: "mainnet", InferenceBaseURL: "https://openrouter.ai/api/v1"}, inference: &http.Client{
		Transport: budgetTransport(func(r *http.Request) (*http.Response, error) {
			if r.URL.String() != "https://openrouter.ai/api/v1/models" {
				t.Errorf("unexpected request %s", r.URL)
			}
			return &http.Response{StatusCode: 200, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(string(catalog))), Request: r}, nil
		}),
	}}
	addTestModelPolicy(c, fixture.Assignments, nil)
	for _, test := range fixture.Cases {
		body, _ := json.Marshal(map[string]any{"model": test.Model, "reasoning": map[string]bool{"enabled": test.Reasoning}})
		got, err := c.requestBudget(context.Background(), body)
		if test.Error != "" {
			failure, ok := err.(*Error)
			if !ok || failure.Code != test.Error {
				t.Errorf("%s reasoning=%v: %d %v", test.Model, test.Reasoning, got, err)
			}
		} else if err != nil || got != test.MicroUSD {
			t.Errorf("%s reasoning=%v: got %d %v; web %d", test.Model, test.Reasoning, got, err, test.MicroUSD)
		}
	}
}
