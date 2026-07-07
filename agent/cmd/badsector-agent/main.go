package main

import (
	"log"
	"net/http"
	"os"
)

// badsector-agent is an optional node agent for distributed deployments.
// It syncs runtime config and reports health metrics to the control plane.
func main() {
	apiURL := env("BADSECTOR_API_URL", "http://localhost:8080")
	runtimePath := env("BADSECTOR_RUNTIME", "/etc/badsector/runtime")

	log.Printf("badsector-agent starting (api=%s, runtime=%s)", apiURL, runtimePath)

	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	})

	addr := env("BADSECTOR_AGENT_ADDR", ":9090")
	log.Printf("listening on %s", addr)
	log.Fatal(http.ListenAndServe(addr, nil))
}

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
