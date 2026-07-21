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

func (s *Store) GetAttackMode() (bool, error) {
	ctx := context.Background()
	val, err := s.client.Get(ctx, "bs:attack_mode").Result()
	if err == redis.Nil {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return val == "1", nil
}

func (s *Store) SetAttackMode(enabled bool) error {
	ctx := context.Background()
	if enabled {
		return s.client.Set(ctx, "bs:attack_mode", "1", 0).Err()
	}
	return s.client.Del(ctx, "bs:attack_mode").Err()
}

// SetAttackKernelPolicy writes watcher keys for kernel-level attack blocks (iptables/ipset).
// countries = explicit block list only (attack_block_countries + block_countries); allow_only is NOT used.
func (s *Store) SetAttackKernelPolicy(countries, asns, exemptCountries string) error {
	ctx := context.Background()
	pipe := s.client.Pipeline()
	setOrDel := func(key, val string) {
		if val == "" {
			pipe.Del(ctx, key)
		} else {
			pipe.Set(ctx, key, val, 0)
		}
	}
	setOrDel("bs:attack_kernel_countries", countries)
	setOrDel("bs:attack_kernel_asns", asns)
	setOrDel("bs:attack_kernel_exempt_countries", exemptCountries)
	pipe.Del(ctx, "bs:attack_kernel_allow_only")
	pipe.Del(ctx, "bs:attack_kernel_allow_countries")
	_, err := pipe.Exec(ctx)
	return err
}

func (s *Store) GetAttackKernelPolicy() (countries, asns, exemptCountries string, err error) {
	ctx := context.Background()
	countries, err = s.client.Get(ctx, "bs:attack_kernel_countries").Result()
	if err == redis.Nil {
		countries = ""
		err = nil
	} else if err != nil {
		return
	}
	asns, err = s.client.Get(ctx, "bs:attack_kernel_asns").Result()
	if err == redis.Nil {
		asns = ""
		err = nil
	} else if err != nil {
		return
	}
	exemptCountries, err = s.client.Get(ctx, "bs:attack_kernel_exempt_countries").Result()
	if err == redis.Nil {
		exemptCountries = ""
		err = nil
	}
	return
}
