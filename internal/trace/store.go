package trace

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/redis/go-redis/v9"
)

type Step struct {
	Module   string                 `json:"module"`
	Decision string                 `json:"decision"`
	Ms       float64                `json:"ms"`
	Detail   string                 `json:"detail,omitempty"`
	Extra    map[string]interface{} `json:"-"`
}

type RequestTrace struct {
	ID          string                 `json:"id"`
	Ts          int64                  `json:"ts"`
	Method      string                 `json:"method"`
	Path        string                 `json:"path"`
	Host        string                 `json:"host"`
	RemoteAddr  string                 `json:"remote_addr"`
	UserAgent   string                 `json:"user_agent,omitempty"`
	Decision    string                 `json:"decision"`
	Status      int                    `json:"status,omitempty"`
	DurationMs  int                    `json:"duration_ms"`
	Steps       []Step                 `json:"steps"`
}

type Store struct {
	client *redis.Client
}

func NewStore(redisURL string) (*Store, error) {
	opts, err := redis.ParseURL(redisURL)
	if err != nil {
		return nil, err
	}
	return &Store{client: redis.NewClient(opts)}, nil
}

func traceKey(siteID string) string {
	return fmt.Sprintf("badsector:trace:%s", siteID)
}

func (s *Store) List(siteID string, limit int) ([]RequestTrace, error) {
	if limit <= 0 {
		limit = 50
	}
	if limit > 200 {
		limit = 200
	}

	ctx := context.Background()
	values, err := s.client.LRange(ctx, traceKey(siteID), 0, int64(limit-1)).Result()
	if err != nil {
		return nil, err
	}

	traces := make([]RequestTrace, 0, len(values))
	for _, raw := range values {
		var t RequestTrace
		if err := json.Unmarshal([]byte(raw), &t); err != nil {
			continue
		}
		traces = append(traces, t)
	}
	return traces, nil
}

func (s *Store) Ping(ctx context.Context) error {
	return s.client.Ping(ctx).Err()
}
