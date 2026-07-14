// Package bots, dogrulanmis arama motoru botlarinin (Googlebot, Bingbot vb.)
// resmi yayinladigi IP aralik listelerini gunluk indirip engine'in okuyacagi
// tek bir bot-ranges.json dosyasina yazar. GeoIP senkronizasyonuyla ayni
// desende calisir: worker acilista + periyodik olarak Sync() cagirir, sonra
// engine'e reload sinyali gonderir.
package bots

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

const rangesFile = "bot-ranges.json"

// srcFormat, bir kaynak URL'sinin JSON semasini belirtir.
type srcFormat int

const (
	// formatGooglePrefixes: {"prefixes":[{"ipv4Prefix":".."},{"ipv6Prefix":".."}]}
	// Hem Google (googlebot/special-crawlers/user-triggered-fetchers) hem de
	// Bing (bingbot.json) bu semayi kullanir.
	formatGooglePrefixes srcFormat = iota
)

type source struct {
	bot    string
	url    string
	format srcFormat
}

// defaultSources: resmi, makine-okunabilir aralik listeleri. Yandex ve
// DuckDuckBot kararli bir JSON yayinlamadigi icin engine'de statik prefix +
// rDNS ile dogrulanmaya devam eder (buraya eklenmez).
var defaultSources = []source{
	{bot: "Googlebot", url: "https://developers.google.com/static/search/apis/ipranges/googlebot.json", format: formatGooglePrefixes},
	{bot: "Googlebot", url: "https://developers.google.com/static/search/apis/ipranges/special-crawlers.json", format: formatGooglePrefixes},
	{bot: "Googlebot", url: "https://developers.google.com/static/search/apis/ipranges/user-triggered-fetchers.json", format: formatGooglePrefixes},
	{bot: "Bingbot", url: "https://www.bing.com/toolbox/bingbot.json", format: formatGooglePrefixes},
}

// Syncer, bot IP araliklarini indirir ve DataDir/bot-ranges.json'a yazar.
type Syncer struct {
	DataDir string
	Client  *http.Client
	Sources []source
}

func NewSyncer(dataDir string) *Syncer {
	return &Syncer{
		DataDir: dataDir,
		Client:  &http.Client{Timeout: 30 * time.Second},
		Sources: defaultSources,
	}
}

// Ranges, diske yazilan konsolide dosyanin semasidir.
type Ranges struct {
	Generated string              `json:"generated"`
	Sources   map[string]string   `json:"sources"` // bot -> "ok" | "error: .."
	Bots      map[string][]string `json:"bots"`    // bot -> ["66.249.64.0/27", "2001:..::/64"]
}

// Status, /bots/status ucu icin ozet durum.
type Status struct {
	Path      string            `json:"path"`
	OK        bool              `json:"ok"`
	Generated string            `json:"generated,omitempty"`
	Sources   map[string]string `json:"sources,omitempty"`
	Counts    map[string]int    `json:"counts,omitempty"`
}

func (s *Syncer) path() string {
	return filepath.Join(s.DataDir, rangesFile)
}

// Load, mevcut bot-ranges.json'u okur (yoksa bos Ranges + hata).
func (s *Syncer) Load() (Ranges, error) {
	var r Ranges
	b, err := os.ReadFile(s.path())
	if err != nil {
		return Ranges{Bots: map[string][]string{}, Sources: map[string]string{}}, err
	}
	if err := json.Unmarshal(b, &r); err != nil {
		return Ranges{Bots: map[string][]string{}, Sources: map[string]string{}}, err
	}
	if r.Bots == nil {
		r.Bots = map[string][]string{}
	}
	if r.Sources == nil {
		r.Sources = map[string]string{}
	}
	return r, nil
}

// Status, dosyayi okuyup ozet dondurur.
func (s *Syncer) Status() Status {
	st := Status{Path: s.path()}
	r, err := s.Load()
	if err != nil {
		return st
	}
	st.OK = true
	st.Generated = r.Generated
	st.Sources = r.Sources
	st.Counts = make(map[string]int, len(r.Bots))
	for bot, list := range r.Bots {
		st.Counts[bot] = len(list)
	}
	return st
}

// Sync, tum kaynaklari indirir ve dosyayi gunceller. Bir bot'un kaynaklarindan
// en az biri basariliysa o bot icin liste TAZE olarak yeniden kurulur; hepsi
// basarisizsa mevcut (son bilinen) liste korunur. Boylece gecici bir ag hatasi
// dogrulama verisini silmez.
func (s *Syncer) Sync(ctx context.Context) error {
	if err := os.MkdirAll(s.DataDir, 0o755); err != nil {
		return err
	}

	existing, _ := s.Load()

	// Kaynaklari bota gore grupla (Googlebot'un 3 kaynagi var), sirayi koru.
	byBot := map[string][]source{}
	var order []string
	for _, src := range s.Sources {
		if _, ok := byBot[src.bot]; !ok {
			order = append(order, src.bot)
		}
		byBot[src.bot] = append(byBot[src.bot], src)
	}

	out := Ranges{
		Generated: time.Now().UTC().Format(time.RFC3339),
		Sources:   map[string]string{},
		Bots:      map[string][]string{},
	}

	var firstErr error
	for _, bot := range order {
		set := map[string]struct{}{}
		gotAny := false
		var lastErr error

		for _, src := range byBot[bot] {
			cidrs, err := s.fetch(ctx, src)
			if err != nil {
				lastErr = err
				continue
			}
			gotAny = true
			for _, c := range cidrs {
				set[c] = struct{}{}
			}
		}

		if gotAny {
			out.Bots[bot] = sortedKeys(set)
			out.Sources[bot] = "ok"
		} else {
			out.Bots[bot] = existing.Bots[bot] // son bilinen listeyi koru
			if lastErr != nil {
				out.Sources[bot] = "error: " + lastErr.Error()
				if firstErr == nil {
					firstErr = lastErr
				}
			}
		}
	}

	if err := s.write(out); err != nil {
		return err
	}
	return firstErr
}

func (s *Syncer) write(r Ranges) error {
	b, err := json.MarshalIndent(r, "", "  ")
	if err != nil {
		return err
	}
	tmp := s.path() + ".tmp"
	if err := os.WriteFile(tmp, b, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, s.path())
}

func (s *Syncer) fetch(ctx context.Context, src source) ([]string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, src.url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "BadSector-Worker/1.0 (+bot-range-sync)")

	resp, err := s.Client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 300 {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return nil, fmt.Errorf("HTTP %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}

	body, err := io.ReadAll(io.LimitReader(resp.Body, 8<<20)) // 8 MB tavan
	if err != nil {
		return nil, err
	}

	switch src.format {
	case formatGooglePrefixes:
		return parseGooglePrefixes(body)
	default:
		return nil, fmt.Errorf("unknown source format")
	}
}

func parseGooglePrefixes(body []byte) ([]string, error) {
	var doc struct {
		Prefixes []struct {
			IPv4 string `json:"ipv4Prefix"`
			IPv6 string `json:"ipv6Prefix"`
		} `json:"prefixes"`
	}
	if err := json.Unmarshal(body, &doc); err != nil {
		return nil, err
	}
	var out []string
	for _, p := range doc.Prefixes {
		if c := normalizeCIDR(p.IPv4); c != "" {
			out = append(out, c)
		}
		if c := normalizeCIDR(p.IPv6); c != "" {
			out = append(out, c)
		}
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("no prefixes in response")
	}
	return out, nil
}

// normalizeCIDR, bir CIDR (veya tek bir IP) girdisini gecerliyse kanonik
// bicimde dondurur, degilse "".
func normalizeCIDR(v string) string {
	v = strings.TrimSpace(v)
	if v == "" {
		return ""
	}
	if strings.Contains(v, "/") {
		_, ipnet, err := net.ParseCIDR(v)
		if err != nil {
			return ""
		}
		return ipnet.String()
	}
	ip := net.ParseIP(v)
	if ip == nil {
		return ""
	}
	if ip.To4() != nil {
		return ip.String() + "/32"
	}
	return ip.String() + "/128"
}

func sortedKeys(set map[string]struct{}) []string {
	out := make([]string, 0, len(set))
	for k := range set {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}
