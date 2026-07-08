package db

import (
	"os"
	"testing"
)

func TestDefaultBackendURL(t *testing.T) {
	t.Setenv("BADSECTOR_DEFAULT_BACKEND_URL", "")
	if got := DefaultBackendURL(); got != localBackendURL {
		t.Fatalf("expected %q, got %q", localBackendURL, got)
	}

	t.Setenv("BADSECTOR_DEFAULT_BACKEND_URL", DockerBackendURL())
	if got := DefaultBackendURL(); got != DockerBackendURL() {
		t.Fatalf("expected %q, got %q", DockerBackendURL(), got)
	}
}

func TestGetBackendURL(t *testing.T) {
	os.Unsetenv("BADSECTOR_DEFAULT_BACKEND_URL")

	cfg := `{"backend_url":"http://backend:80","upstream":"backend"}`
	if got := GetBackendURL(cfg); got != "http://backend:80" {
		t.Fatalf("expected backend_url, got %q", got)
	}

	if got := GetBackendURL(`{"upstream":"origin"}`); got != "http://origin" {
		t.Fatalf("expected upstream fallback, got %q", got)
	}
}

func TestDefaultPipelineHasEarlyFilters(t *testing.T) {
	stages := DefaultPipelineStages("test-site")
	if len(stages) < 7 {
		t.Fatalf("expected full pipeline, got %d stages", len(stages))
	}

	modules := []string{stages[0].Module, stages[1].Module, stages[2].Module}
	want := []string{"access_lists", "trusted_bots", "ip_reputation"}
	for i, m := range want {
		if modules[i] != m {
			t.Fatalf("stage %d: expected %q, got %q", i, m, modules[i])
		}
	}

	proxy := stages[len(stages)-1]
	if proxy.Module != reverseProxyModule {
		t.Fatalf("last stage should be reverse_proxy, got %q", proxy.Module)
	}

	prev := stages[len(stages)-2]
	if prev.Module != "custom_rules" {
		t.Fatalf("stage before reverse_proxy should be custom_rules, got %q", prev.Module)
	}
}
