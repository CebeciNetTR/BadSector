package metrics

import (
	"context"
	"strconv"

	"github.com/badsector/badsector/api/internal/db"
	"github.com/redis/go-redis/v9"
	"gorm.io/gorm"
)

const (
	globalKey     = "badsector:metrics:global"
	decisionsKey  = "badsector:metrics:decisions"
)

type Dashboard struct {
	RequestsTotal int            `json:"requests_total"`
	Blocked       int            `json:"blocked"`
	Challenged    int            `json:"challenged"`
	RateLimited   int            `json:"rate_limited"`
	Allowed       int            `json:"allowed"`
	ActiveSites   int64          `json:"active_sites"`
	Decisions     map[string]int `json:"decisions"`
	Edge          EdgeStatus     `json:"edge"`
}

type EdgeStatus struct {
	API    string `json:"api"`
	Engine string `json:"engine"`
	Redis  string `json:"redis"`
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

func (s *Store) Dashboard(ctx context.Context, database *gorm.DB) (Dashboard, error) {
	out := Dashboard{
		Decisions: make(map[string]int),
		Edge: EdgeStatus{
			API:    "unknown",
			Engine: "unknown",
			Redis:  "unknown",
		},
	}

	if err := s.client.Ping(ctx).Err(); err == nil {
		out.Edge.Redis = "ok"
	} else {
		out.Edge.Redis = "down"
	}

	var siteCount int64
	if database != nil {
		_ = database.Model(&db.Site{}).Where("enabled = ?", true).Count(&siteCount).Error
	}
	out.ActiveSites = siteCount

	if s.client == nil {
		return out, nil
	}

	out.RequestsTotal = hashInt(ctx, s.client, globalKey, "requests")
	out.Blocked = hashInt(ctx, s.client, decisionsKey, "BLOCK")
	out.Challenged = hashInt(ctx, s.client, decisionsKey, "CHALLENGE")
	out.RateLimited = hashInt(ctx, s.client, decisionsKey, "RATE_LIMIT")
	out.Allowed = hashInt(ctx, s.client, decisionsKey, "ALLOW")

	keys, err := s.client.HGetAll(ctx, decisionsKey).Result()
	if err == nil {
		for k, v := range keys {
			n, _ := strconv.Atoi(v)
			out.Decisions[k] = n
		}
	}

	return out, nil
}

func hashInt(ctx context.Context, client *redis.Client, key, field string) int {
	val, err := client.HGet(ctx, key, field).Result()
	if err != nil {
		return 0
	}
	n, _ := strconv.Atoi(val)
	return n
}
