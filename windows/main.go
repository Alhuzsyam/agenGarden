// AgentGarden cross-platform server (Windows + Linux + macOS). A single binary
// that mirrors the macOS GardenServer: the same HTTP endpoints, agent store,
// model-spend scanner, and /new-project spawn, serving the same dashboard — so
// the existing webapp and Garmin app work unchanged. No dependencies.
package main

import (
	"bufio"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"math"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
	"time"

	_ "embed"
)

//go:embed dashboard.html
var dashboardHTML string

func serverPort() int {
	if v := os.Getenv("GARDEN_PORT"); v != "" {
		var p int
		if _, err := fmt.Sscanf(v, "%d", &p); err == nil && p > 0 {
			return p
		}
	}
	return 4141
}

// ---------- token ----------

func homeDir() string { h, _ := os.UserHomeDir(); return h }

func tokenPath() string { return filepath.Join(homeDir(), ".agent-garden-token") }

func loadToken() string {
	if b, err := os.ReadFile(tokenPath()); err == nil {
		if t := strings.TrimSpace(string(b)); t != "" {
			return t
		}
	}
	buf := make([]byte, 24)
	_, _ = rand.Read(buf)
	t := hex.EncodeToString(buf)
	_ = os.WriteFile(tokenPath(), []byte(t), 0o600)
	return t
}

func dailyBudget() float64 {
	if v := os.Getenv("GARDEN_BUDGET"); v != "" {
		var f float64
		if _, err := fmt.Sscanf(v, "%f", &f); err == nil && f > 0 {
			return f
		}
	}
	if b, err := os.ReadFile(filepath.Join(homeDir(), ".agent-garden-budget")); err == nil {
		var f float64
		if _, err := fmt.Sscanf(strings.TrimSpace(string(b)), "%f", &f); err == nil && f > 0 {
			return f
		}
	}
	return 6
}

// ---------- models ----------

type Agent struct {
	ID             string    `json:"id"`
	Task           *string   `json:"task"`
	LastTool       *string   `json:"lastTool"`
	Growth         int       `json:"growth"`
	IsDone         bool      `json:"isDone"`
	IsError        bool      `json:"isError"`
	NeedsAttention bool      `json:"needsAttention"`
	StartedAt      time.Time `json:"startedAt"`
	UpdatedAt      time.Time `json:"updatedAt"`
}

type Approval struct {
	ID        string    `json:"id"`
	Agent     string    `json:"agent"`
	Tool      string    `json:"tool"`
	Detail    string    `json:"detail"`
	CreatedAt time.Time `json:"createdAt"`
	Decision  *string   `json:"decision,omitempty"`
}

type Event struct {
	Agent string  `json:"agent"`
	Event string  `json:"event"`
	Task  *string `json:"task"`
	Tool  *string `json:"tool"`
}

// ---------- store ----------

type Store struct {
	mu            sync.Mutex
	agents        map[string]*Agent
	agentOrder    []string
	approvals     map[string]*Approval
	approvalOrder []string
	prompts       map[string][]string
	terminals     map[string]string
	keys          map[string][]string
}

func newStore() *Store {
	return &Store{
		agents:    map[string]*Agent{},
		approvals: map[string]*Approval{},
		prompts:   map[string][]string{},
		terminals: map[string]string{},
		keys:      map[string][]string{},
	}
}

func (s *Store) ensure(id string) *Agent {
	a := s.agents[id]
	if a == nil {
		now := time.Now()
		a = &Agent{ID: id, StartedAt: now, UpdatedAt: now}
		s.agents[id] = a
		s.agentOrder = append(s.agentOrder, id)
	}
	return a
}

// apply mirrors AgentStore.apply — isDone and needsAttention stay mutually
// exclusive so every surface (webapp/watch/Mac) agrees.
func (s *Store) apply(e Event) {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := time.Now()
	a := s.ensure(e.Agent)
	switch e.Event {
	case "start":
		*a = Agent{ID: e.Agent, Task: e.Task, StartedAt: now, UpdatedAt: now}
	case "tool":
		a.Growth++
		a.LastTool = e.Tool
		a.IsDone = false
		a.NeedsAttention = false
	case "attention":
		a.NeedsAttention = true
		a.IsDone = false
	case "resume":
		a.NeedsAttention = false
		a.IsDone = false
	case "done":
		a.IsDone = true
		a.NeedsAttention = false
	case "error":
		a.IsError = true
	}
	if e.Task != nil {
		a.Task = e.Task
	}
	a.UpdatedAt = now
}

func (s *Store) requestApproval(id, agent, tool, detail string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := time.Now()
	s.approvals[id] = &Approval{ID: id, Agent: agent, Tool: tool, Detail: detail, CreatedAt: now}
	s.approvalOrder = append(s.approvalOrder, id)
	a := s.ensure(agent)
	a.NeedsAttention = true
	a.IsDone = false
	a.UpdatedAt = now
}

func (s *Store) decide(id, decision string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	ap := s.approvals[id]
	if ap == nil {
		return
	}
	ap.Decision = &decision
	stillPending := false
	for _, o := range s.approvals {
		if o.Agent == ap.Agent && o.Decision == nil {
			stillPending = true
		}
	}
	if !stillPending {
		if a := s.agents[ap.Agent]; a != nil {
			a.NeedsAttention = false
		}
	}
}

func (s *Store) decisionOf(id string) *string {
	s.mu.Lock()
	defer s.mu.Unlock()
	if ap := s.approvals[id]; ap != nil {
		return ap.Decision
	}
	return nil
}

func (s *Store) agentList() []*Agent {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := []*Agent{}
	for _, id := range s.agentOrder {
		if a := s.agents[id]; a != nil {
			out = append(out, a)
		}
	}
	return out
}

func (s *Store) pendingApprovals() []*Approval {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := []*Approval{}
	for _, id := range s.approvalOrder {
		if ap := s.approvals[id]; ap != nil && ap.Decision == nil {
			out = append(out, ap)
		}
	}
	return out
}

func (s *Store) enqueuePrompt(agent, text string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.prompts[agent] = append(s.prompts[agent], text)
	if a := s.agents[agent]; a != nil {
		a.IsDone = false
		a.NeedsAttention = false
	}
}

func (s *Store) dequeuePrompt(agent string) *string {
	s.mu.Lock()
	defer s.mu.Unlock()
	q := s.prompts[agent]
	if len(q) == 0 {
		return nil
	}
	t := q[0]
	s.prompts[agent] = q[1:]
	return &t
}

func (s *Store) setTerminal(agent, screen string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.terminals[agent] = screen
}

func (s *Store) terminal(agent string) *string {
	s.mu.Lock()
	defer s.mu.Unlock()
	if v, ok := s.terminals[agent]; ok {
		return &v
	}
	return nil
}

func (s *Store) enqueueKeys(agent string, keys []string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.keys[agent] = append(s.keys[agent], keys...)
}

func (s *Store) dequeueKeys(agent string) []string {
	s.mu.Lock()
	defer s.mu.Unlock()
	k := s.keys[agent]
	s.keys[agent] = nil
	if k == nil {
		return []string{}
	}
	return k
}

func (s *Store) cleanup() {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := time.Now()
	kept := s.agentOrder[:0:0]
	for _, id := range s.agentOrder {
		a := s.agents[id]
		if a == nil {
			continue
		}
		age := now.Sub(a.UpdatedAt)
		if (a.IsDone || a.IsError) && age > 5*time.Minute {
			delete(s.agents, id)
			continue
		}
		if age > 30*time.Minute {
			delete(s.agents, id)
			continue
		}
		kept = append(kept, id)
	}
	s.agentOrder = kept
	akept := s.approvalOrder[:0:0]
	for _, id := range s.approvalOrder {
		ap := s.approvals[id]
		if ap == nil {
			continue
		}
		age := now.Sub(ap.CreatedAt)
		if ap.Decision != nil && age > 2*time.Minute {
			delete(s.approvals, id)
			continue
		}
		if ap.Decision == nil && age > 30*time.Minute {
			delete(s.approvals, id)
			continue
		}
		akept = append(akept, id)
	}
	s.approvalOrder = akept
}

// ---------- usage (model spend) ----------

type price struct{ in, out, cw, cr float64 }

var prices = map[string]price{
	"claude-opus-4-8":   {5, 25, 6.25, 0.50},
	"claude-opus-4-7":   {5, 25, 6.25, 0.50},
	"claude-opus-4-6":   {5, 25, 6.25, 0.50},
	"claude-fable-5":    {10, 50, 12.50, 1.00},
	"claude-mythos-5":   {10, 50, 12.50, 1.00},
	"claude-sonnet-5":   {3, 15, 3.75, 0.30},
	"claude-sonnet-4-6": {3, 15, 3.75, 0.30},
	"claude-haiku-4-5":  {1, 5, 1.25, 0.10},
}

var fallbackPrice = price{5, 25, 6.25, 0.50}

var usageJSON = `{"today":0,"budget":6,"pct":0,"byModel":[],"days":[]}`
var usageMu sync.RWMutex

func dayKey(t time.Time) string { return t.Local().Format("2006-01-02") }

func scanUsage() {
	root := filepath.Join(homeDir(), ".claude", "projects")
	dayKeys := make([]string, 7)
	todayStart := time.Now()
	for i := 0; i < 7; i++ {
		dayKeys[6-i] = dayKey(todayStart.AddDate(0, 0, -i))
	}
	todayK := dayKeys[6]
	perDay := map[string]float64{}
	todayModel := map[string]float64{}

	_ = filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() || !strings.HasSuffix(path, ".jsonl") {
			return nil
		}
		f, err := os.Open(path)
		if err != nil {
			return nil
		}
		defer f.Close()
		sc := bufio.NewScanner(f)
		sc.Buffer(make([]byte, 1024*1024), 8*1024*1024)
		for sc.Scan() {
			line := sc.Bytes()
			if len(line) == 0 || line[0] != '{' {
				continue
			}
			var rec map[string]json.RawMessage
			if json.Unmarshal(line, &rec) != nil {
				continue
			}
			var ts string
			if json.Unmarshal(rec["timestamp"], &ts) != nil || ts == "" {
				continue
			}
			t, err := time.Parse(time.RFC3339, ts)
			if err != nil {
				continue
			}
			k := dayKey(t)
			if _, ok := perDay[k]; !ok {
				inRange := false
				for _, dk := range dayKeys {
					if dk == k {
						inRange = true
						break
					}
				}
				if !inRange {
					continue
				}
			}
			var msg struct {
				Model string `json:"model"`
				Usage struct {
					In float64 `json:"input_tokens"`
					Out float64 `json:"output_tokens"`
					CW float64 `json:"cache_creation_input_tokens"`
					CR float64 `json:"cache_read_input_tokens"`
				} `json:"usage"`
			}
			if json.Unmarshal(rec["message"], &msg) != nil || msg.Model == "" {
				continue
			}
			p, ok := prices[msg.Model]
			if !ok {
				p = fallbackPrice
			}
			cost := (msg.Usage.In*p.in + msg.Usage.Out*p.out + msg.Usage.CW*p.cw + msg.Usage.CR*p.cr) / 1_000_000
			perDay[k] += cost
			if k == todayK {
				todayModel[msg.Model] += cost
			}
		}
		return nil
	})

	today := perDay[todayK]
	budget := dailyBudget()
	pct := 0.0
	if budget > 0 {
		pct = math.Min(today/budget, 9.99)
	}
	type kv struct {
		Model string  `json:"model"`
		Cost  float64 `json:"cost"`
	}
	byModel := []kv{}
	for m, c := range todayModel {
		byModel = append(byModel, kv{m, c})
	}
	sort.Slice(byModel, func(i, j int) bool { return byModel[i].Cost > byModel[j].Cost })
	type dc struct {
		Date string  `json:"date"`
		Cost float64 `json:"cost"`
	}
	days := []dc{}
	spark := []float64{}
	for _, k := range dayKeys {
		days = append(days, dc{k, perDay[k]})
		spark = append(spark, perDay[k])
	}
	top := ""
	if len(byModel) > 0 {
		top = byModel[0].Model
	}
	out, _ := json.Marshal(map[string]any{
		"today": today, "budget": budget, "pct": pct,
		"byModel": byModel, "days": days, "spark": spark, "topModel": top,
	})
	usageMu.Lock()
	usageJSON = string(out)
	usageMu.Unlock()
}

// ---------- new-project spawn ----------

func sanitize(name string) string {
	var b strings.Builder
	for _, r := range name {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '_' {
			b.WriteRune(r)
		} else {
			b.WriteRune('_')
		}
	}
	return b.String()
}

// spawnProject opens a real terminal running `claude` in the project dir. On
// Windows it uses cmd/Windows Terminal; elsewhere tmux (detached) or an xterm.
func spawnProject(name, dir string) bool {
	if dir == "" {
		dir = filepath.Join(homeDir(), name)
	}
	_ = os.MkdirAll(dir, 0o755)
	session := "garden_" + sanitize(name)

	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "windows":
		// prefer Windows Terminal if present, else a plain console
		inner := fmt.Sprintf(`cd /d "%s" && claude`, dir)
		cmd = exec.Command("cmd", "/c", "start", "", "cmd", "/k", inner)
	default:
		// Linux/macOS: detached tmux session running claude
		script := fmt.Sprintf(`tmux new-session -d -s %q -c %q claude 2>/dev/null || (cd %q && claude)`, session, dir, dir)
		cmd = exec.Command("sh", "-lc", script)
	}
	if err := cmd.Start(); err != nil {
		return false
	}
	return true
}

// ---------- HTTP ----------

var store = newStore()
var token string

func isPublic(r *http.Request) bool {
	if r.Method != http.MethodGet {
		return false
	}
	p := r.URL.Path
	return p == "/" || p == "/favicon.ico" || strings.HasPrefix(p, "/icon") || strings.HasPrefix(p, "/apple-touch")
}

func authOK(r *http.Request) bool {
	if h := r.Header.Get("Authorization"); strings.HasPrefix(h, "Bearer ") {
		if strings.TrimPrefix(h, "Bearer ") == token {
			return true
		}
	}
	return r.URL.Query().Get("token") == token
}

func writeJSON(w http.ResponseWriter, status int, body string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	fmt.Fprint(w, body)
}

func readJSON(r *http.Request, v any) bool {
	return json.NewDecoder(r.Body).Decode(v) == nil
}

func handler(w http.ResponseWriter, r *http.Request) {
	if !isPublic(r) && !authOK(r) {
		writeJSON(w, 401, `{"error":"unauthorized"}`)
		return
	}
	p := r.URL.Path

	switch {
	case r.Method == "GET" && p == "/":
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		fmt.Fprint(w, dashboardHTML)

	case r.Method == "GET" && p == "/agents":
		b, _ := json.Marshal(store.agentList())
		writeJSON(w, 200, string(b))

	case r.Method == "POST" && p == "/event":
		var e Event
		if readJSON(r, &e) && e.Agent != "" {
			store.apply(e)
			writeJSON(w, 200, `{"ok":true}`)
		} else {
			writeJSON(w, 400, `{"error":"bad event"}`)
		}

	case r.Method == "GET" && p == "/approvals":
		b, _ := json.Marshal(store.pendingApprovals())
		writeJSON(w, 200, string(b))

	case r.Method == "POST" && p == "/approval/request":
		var a Approval
		if readJSON(r, &a) && a.ID != "" && a.Agent != "" {
			store.requestApproval(a.ID, a.Agent, a.Tool, a.Detail)
			writeJSON(w, 200, `{"ok":true}`)
		} else {
			writeJSON(w, 400, `{"error":"bad approval"}`)
		}

	case r.Method == "POST" && strings.HasPrefix(p, "/approval/") && strings.HasSuffix(p, "/decide"):
		id := strings.TrimSuffix(strings.TrimPrefix(p, "/approval/"), "/decide")
		var body struct {
			Decision string `json:"decision"`
		}
		if readJSON(r, &body) && (body.Decision == "allow" || body.Decision == "deny") {
			store.decide(id, body.Decision)
			writeJSON(w, 200, `{"ok":true}`)
		} else {
			writeJSON(w, 400, `{"error":"bad decision"}`)
		}

	case r.Method == "GET" && strings.HasPrefix(p, "/approval/"):
		id := strings.TrimPrefix(p, "/approval/")
		d := store.decisionOf(id)
		if d == nil {
			writeJSON(w, 200, `{"decision":null}`)
		} else {
			writeJSON(w, 200, fmt.Sprintf(`{"decision":%q}`, *d))
		}

	case r.Method == "POST" && p == "/prompt":
		var body struct{ Agent, Text string }
		if readJSON(r, &body) && body.Agent != "" {
			store.enqueuePrompt(body.Agent, body.Text)
			writeJSON(w, 200, `{"ok":true}`)
		} else {
			writeJSON(w, 400, `{"error":"bad prompt"}`)
		}

	case r.Method == "GET" && strings.HasPrefix(p, "/prompt/"):
		agent := decodePath(strings.TrimPrefix(p, "/prompt/"))
		if t := store.dequeuePrompt(agent); t != nil {
			writeJSON(w, 200, fmt.Sprintf(`{"prompt":%q}`, *t))
		} else {
			writeJSON(w, 200, `{"prompt":null}`)
		}

	case r.Method == "POST" && p == "/terminal":
		var body struct{ Agent, Screen string }
		if readJSON(r, &body) && body.Agent != "" {
			store.setTerminal(body.Agent, body.Screen)
			writeJSON(w, 200, `{"ok":true}`)
		} else {
			writeJSON(w, 400, `{"error":"bad terminal"}`)
		}

	case r.Method == "GET" && strings.HasPrefix(p, "/terminal/"):
		agent := decodePath(strings.TrimPrefix(p, "/terminal/"))
		if s := store.terminal(agent); s != nil {
			b, _ := json.Marshal(map[string]string{"screen": *s})
			writeJSON(w, 200, string(b))
		} else {
			writeJSON(w, 200, `{"screen":null}`)
		}

	case r.Method == "POST" && p == "/keys":
		var body struct {
			Agent string   `json:"agent"`
			Keys  []string `json:"keys"`
		}
		if readJSON(r, &body) && body.Agent != "" {
			store.enqueueKeys(body.Agent, body.Keys)
			writeJSON(w, 200, `{"ok":true}`)
		} else {
			writeJSON(w, 400, `{"error":"bad keys"}`)
		}

	case r.Method == "GET" && strings.HasPrefix(p, "/keys/"):
		agent := decodePath(strings.TrimPrefix(p, "/keys/"))
		b, _ := json.Marshal(map[string][]string{"keys": store.dequeueKeys(agent)})
		writeJSON(w, 200, string(b))

	case r.Method == "POST" && p == "/new-project":
		var body struct {
			Name string  `json:"name"`
			Dir  *string `json:"dir"`
		}
		name := ""
		if readJSON(r, &body) {
			name = strings.TrimSpace(body.Name)
		}
		if name == "" {
			writeJSON(w, 400, `{"error":"need a project name"}`)
			return
		}
		dir := ""
		if body.Dir != nil {
			dir = *body.Dir
		}
		if spawnProject(name, dir) {
			task := dir
			store.apply(Event{Agent: name, Event: "start", Task: &task})
			writeJSON(w, 200, fmt.Sprintf(`{"ok":true,"agent":%q}`, name))
		} else {
			writeJSON(w, 500, `{"error":"spawn failed — cek claude di PATH"}`)
		}

	case r.Method == "GET" && p == "/usage":
		usageMu.RLock()
		body := usageJSON
		usageMu.RUnlock()
		writeJSON(w, 200, body)

	default:
		writeJSON(w, 404, `{"error":"not found"}`)
	}
}

func decodePath(s string) string {
	if d, err := decodeURI(s); err == nil {
		return d
	}
	return s
}

func decodeURI(s string) (string, error) {
	// minimal percent-decode (agent ids are simple; this covers %20 etc.)
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		if s[i] == '%' && i+2 < len(s) {
			var v int
			if _, err := fmt.Sscanf(s[i+1:i+3], "%02x", &v); err == nil {
				b.WriteByte(byte(v))
				i += 2
				continue
			}
		}
		b.WriteByte(s[i])
	}
	return b.String(), nil
}

func main() {
	token = loadToken()
	port := serverPort()

	go func() {
		for {
			scanUsage()
			time.Sleep(60 * time.Second)
		}
	}()
	go func() {
		for {
			time.Sleep(30 * time.Second)
			store.cleanup()
		}
	}()

	addr := fmt.Sprintf("0.0.0.0:%d", port)
	fmt.Printf("AgentGarden server on http://localhost:%d\n", port)
	fmt.Printf("token: %s\n", token)
	fmt.Printf("dashboard: http://localhost:%d/?token=%s\n", port, token)
	if err := http.ListenAndServe(addr, http.HandlerFunc(handler)); err != nil {
		fmt.Fprintln(os.Stderr, "listen error:", err)
		os.Exit(1)
	}
}
