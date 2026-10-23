// fzf-agents: substring search over Claude Code and Codex session transcripts.
//
//   fzf-agents index              refresh the text cache (incremental, by mtime)
//   fzf-agents search [QUERY]     one line per matching session, newest first
//   fzf-agents preview CACHE [Q]  transcript excerpt with hits highlighted
//   fzf-agents init fish|bash|zsh  print the Ctrl+Alt+C shell widget
//
// Cache: $XDG_CACHE_HOME/fzf-agents/ (default ~/.cache/fzf-agents/)<src>_<id>.txt
//   line 1: src \t id \t cwd \t last_ts \t source_path
//   then per message: RS role \n text \n
package fzf_agents

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:time"
import "core:unicode/utf8"

RS :: "\x1e"
HL_ON :: "\x1b[1;30;43m"
HL_OFF :: "\x1b[0m"
MAX_HITS :: 20

Src :: enum {
	Claude,
	Codex,
}
SRC_TAG := [Src]string {
	.Claude = "claude",
	.Codex  = "codex",
}

Msg :: struct {
	role, text: string,
}

Session :: struct {
	src:                 Src,
	id, cwd, ts, source: string,
	msgs:                [dynamic]Msg,
}

home: string
cache_dir: string
claude_dir: string // $CLAUDE_CONFIG_DIR, default ~/.claude
codex_dir: string  // $CODEX_HOME, default ~/.codex

main :: proc() {
	home = os.get_env("HOME", context.allocator)
	cache_dir = join(env_or("XDG_CACHE_HOME", join(home, ".cache")), "fzf-agents")
	claude_dir = env_or("CLAUDE_CONFIG_DIR", join(home, ".claude"))
	codex_dir = env_or("CODEX_HOME", join(home, ".codex"))
	args := os.args[1:]
	cmd := len(args) > 0 ? args[0] : "search"
	arg :: proc(args: []string, i: int) -> string {return i < len(args) ? args[i] : ""}
	switch cmd {
	case "index":
		index()
	case "search":
		search(arg(args, 1))
	case "preview":
		preview(arg(args, 1), arg(args, 2))
	case "init":
		switch arg(args, 1) {
		case "fish":
			fmt.print(#load("shell/fzf-agents.fish", string))
		case "bash":
			fmt.print(#load("shell/fzf-agents.bash", string))
		case "zsh":
			fmt.print(#load("shell/fzf-agents.zsh", string))
		case:
			fmt.eprintln("usage: fzf-agents init fish|bash|zsh")
			os.exit(2)
		}
	case:
		fmt.eprintln("usage: fzf-agents index | search [QUERY] | preview CACHE [QUERY] | init SHELL")
		os.exit(2)
	}
}

// ---------------------------------------------------------------- index

index :: proc() {
	os.make_directory_all(cache_dir)
	n := 0
	claude_root := join(claude_dir, "projects")
	if dirs, err := os.read_all_directory_by_path(claude_root, context.allocator); err == nil {
		for d in dirs {
			if d.type != .Directory do continue
			files, _ := os.read_all_directory_by_path(d.fullpath, context.allocator)
			for f in files {
				if f.type == .Regular && strings.has_suffix(f.name, ".jsonl") {
					n += index_file(.Claude, f)
				}
			}
		}
	}
	w := os.walker_create(join(codex_dir, "sessions"))
	defer os.walker_destroy(&w)
	for f in os.walker_walk(&w) {
		if f.type == .Regular && strings.has_suffix(f.name, ".jsonl") {
			n += index_file(.Codex, f)
		}
	}
	fmt.eprintfln("fzf-agents: indexed %d changed session(s)", n)
}

index_file :: proc(src: Src, f: os.File_Info) -> int {
	defer free_all(context.temp_allocator)
	context.allocator = context.temp_allocator

	stem := strings.trim_suffix(f.name, ".jsonl")
	out := cache_path(src, stem)
	if st, err := os.stat(out, context.allocator); err == nil {
		if time.diff(f.modification_time, st.modification_time) >= 0 do return 0
	}
	data, err := os.read_entire_file(f.fullpath, context.allocator)
	if err != nil do return 0

	s := Session {
		src    = src,
		id     = stem,
		source = f.fullpath,
	}
	it := string(data)
	for line in strings.split_lines_iterator(&it) {
		switch src {
		case .Claude:
			parse_claude_line(&s, line)
		case .Codex:
			parse_codex_line(&s, line)
		}
	}
	// Still write a stub so unchanged skipped files are not re-parsed next run.
	b := strings.builder_make()
	if len(s.msgs) == 0 {
		_ = os.write_entire_file(out, "skip\n")
		return 0
	}
	fmt.sbprintf(&b, "%s\t%s\t%s\t%s\t%s\n", SRC_TAG[src], s.id, s.cwd, s.ts, s.source)
	for m in s.msgs do fmt.sbprintf(&b, RS + "%s\n%s\n", m.role, m.text)
	_ = os.write_entire_file(out, strings.to_string(b))
	return 1
}

cache_path :: proc(src: Src, id: string) -> string {
	return join(cache_dir, fmt.tprintf("%s_%s.txt", SRC_TAG[src], id))
}

// Most lines are tool output or API blobs; skip them before paying for a parse.
parse_claude_line :: proc(s: ^Session, line: string) {
	if !strings.contains(line, `"type":"user"`) && !strings.contains(line, `"type":"assistant"`) do return
	v, err := json.parse_string(line)
	if err != nil do return
	o, o_ok := v.(json.Object)
	if !o_ok do return
	if b, ok := o["isMeta"].(json.Boolean); ok && b do return
	role := o["type"].(json.String) or_else ""
	if role != "user" && role != "assistant" do return
	if cwd, ok := o["cwd"].(json.String); ok do s.cwd = cwd
	if ts, ok := o["timestamp"].(json.String); ok do s.ts = ts
	msg, msg_ok := o["message"].(json.Object)
	if !msg_ok do return
	add_content(s, role, msg["content"])
}

parse_codex_line :: proc(s: ^Session, line: string) {
	if !strings.contains(line, `"response_item"`) && !strings.contains(line, `"session_meta"`) do return
	v, err := json.parse_string(line)
	if err != nil do return
	o, o_ok := v.(json.Object)
	if !o_ok do return
	if ts, ok := o["timestamp"].(json.String); ok do s.ts = ts
	p, p_ok := o["payload"].(json.Object)
	if !p_ok do return
	switch o["type"].(json.String) or_else "" {
	case "session_meta":
		s.cwd = p["cwd"].(json.String) or_else s.cwd
		s.id = p["id"].(json.String) or_else s.id
	case "response_item":
		if (p["type"].(json.String) or_else "") != "message" do return
		role := p["role"].(json.String) or_else ""
		if role != "user" && role != "assistant" do return
		add_content(s, role, p["content"])
	}
}

// Content is either a bare string or a list of typed parts; keep text parts only.
// Text starting with '<' is harness-injected context, not something anyone typed.
add_content :: proc(s: ^Session, role: string, c: json.Value) {
	add :: proc(s: ^Session, role, t: string) {
		t := strings.trim_space(t)
		if len(t) == 0 || t[0] == '<' do return
		append(&s.msgs, Msg{role, t})
	}
	#partial switch c in c {
	case json.String:
		add(s, role, c)
	case json.Array:
		for part in c {
			po := part.(json.Object) or_continue
			if t, ok := po["text"].(json.String); ok do add(s, role, t)
		}
	}
}

// ---------------------------------------------------------------- search

Hit :: struct {
	line, ts: string,
}

search :: proc(query: string) {
	q := ascii_lower(query)
	files, _ := os.read_all_directory_by_path(cache_dir, context.allocator)
	hits := make([dynamic]Hit)
	for f in files {
		data, err := os.read_entire_file(f.fullpath, context.temp_allocator)
		if err != nil do continue
		text := string(data)
		header, _, body := strings.partition(text, "\n")
		h := strings.split(header, "\t", context.temp_allocator)
		if len(h) < 5 do continue

		count, at := 0, -1
		if len(q) > 0 {
			lower := ascii_lower(body, context.temp_allocator)
			rest := lower
			for {
				i := strings.index(rest, q)
				if i < 0 do break
				if at < 0 do at = len(lower) - len(rest) + i
				count += 1
				rest = rest[i + len(q):]
			}
			if count == 0 {
				free_all(context.temp_allocator)
				continue
			}
		}
		snip := at >= 0 ? snippet(body, at, len(q)) : first_user(body)
		line := fmt.aprintf(
			"%s\t%s\t%s\t%s\t%s %s  %s  %s%s",
			h[0], h[1], f.fullpath, h[2],
			h[0] == "claude" ? "\x1b[35mC\x1b[0m" : "\x1b[36mX\x1b[0m",
			short_ts(h[3]),
			pad(tilde(h[2]), 28),
			count > 0 ? fmt.tprintf("\x1b[33m%d×\x1b[0m ", count) : "",
			snip,
		)
		append(&hits, Hit{line, strings.clone(h[3])})
		free_all(context.temp_allocator)
	}
	slice.sort_by(hits[:], proc(a, b: Hit) -> bool {return a.ts > b.ts})
	for h in hits do fmt.println(h.line)
}

// One-line excerpt around byte offset `at`, cut on rune boundaries.
snippet :: proc(body: string, at, qlen: int) -> string {
	lo := max(0, at - 30)
	hi := min(len(body), at + qlen + 70)
	for lo > 0 && !utf8.rune_start(body[lo]) do lo -= 1
	for hi < len(body) && !utf8.rune_start(body[hi]) do hi += 1
	s := flatten(body[lo:hi])
	return fmt.tprintf("%s%s%s", lo > 0 ? "…" : "", highlight(s, body[at:at + qlen]), hi < len(body) ? "…" : "")
}

first_user :: proc(body: string) -> string {
	for rec in strings.split(body, RS, context.temp_allocator) {
		role, _, text := strings.partition(rec, "\n")
		if role != "user" do continue
		t := flatten(text)
		n := 0
		for _, i in t {
			if n == 100 do return fmt.tprintf("%s…", t[:i])
			n += 1
		}
		return t
	}
	return ""
}

// ---------------------------------------------------------------- preview

preview :: proc(path, query: string) {
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil do return
	header, _, body := strings.partition(string(data), "\n")
	h := strings.split(header, "\t")
	if len(h) < 5 do return
	fmt.printfln("\x1b[1m%s\x1b[0m %s\n%s  %s\n", h[0], h[1], tilde(h[2]), short_ts(h[3]))

	q := ascii_lower(query)
	shown := 0
	for rec in strings.split(body, RS) {
		role, _, text := strings.partition(rec, "\n")
		text = strings.trim_space(text)
		if len(text) == 0 do continue
		if len(q) > 0 {
			i := strings.index(ascii_lower(text), q)
			if i < 0 do continue
			lo := max(0, i - 300)
			hi := min(len(text), i + len(q) + 500)
			for lo > 0 && !utf8.rune_start(text[lo]) do lo -= 1
			for hi < len(text) && !utf8.rune_start(text[hi]) do hi += 1
			text = text[lo:hi]
		} else if len(text) > 800 {
			cut := 800
			for !utf8.rune_start(text[cut]) do cut -= 1
			text = fmt.tprintf("%s…", text[:cut])
		}
		color := role == "user" ? "\x1b[1;32m" : "\x1b[1;34m"
		fmt.printfln("%s── %s\x1b[0m\n%s\n", color, role, len(q) > 0 ? highlight_all(text, q) : text)
		shown += 1
		if shown == MAX_HITS do break
	}
}

// ---------------------------------------------------------------- helpers

// ASCII-only lowering keeps byte offsets identical to the original string.
ascii_lower :: proc(s: string, allocator := context.allocator) -> string {
	b := make([]byte, len(s), allocator)
	for i in 0 ..< len(s) {
		c := s[i]
		b[i] = c >= 'A' && c <= 'Z' ? c + 32 : c
	}
	return string(b)
}

highlight :: proc(s, needle: string) -> string {
	if len(needle) == 0 do return s
	return highlight_all(s, ascii_lower(needle, context.temp_allocator))
}

highlight_all :: proc(s, q: string) -> string {
	lower := ascii_lower(s, context.temp_allocator)
	b := strings.builder_make(context.temp_allocator)
	i := 0
	for {
		j := strings.index(lower[i:], q)
		if j < 0 do break
		strings.write_string(&b, s[i:i + j])
		strings.write_string(&b, HL_ON)
		strings.write_string(&b, s[i + j:i + j + len(q)])
		strings.write_string(&b, HL_OFF)
		i += j + len(q)
	}
	strings.write_string(&b, s[i:])
	return strings.to_string(b)
}

flatten :: proc(s: string) -> string {
	r, _ := strings.replace_all(s, "\n", " ", context.temp_allocator)
	r, _ = strings.replace_all(r, "\t", " ", context.temp_allocator)
	return r
}

tilde :: proc(p: string) -> string {
	if strings.has_prefix(p, home) do return fmt.tprintf("~%s", p[len(home):])
	return p
}

pad :: proc(s: string, w: int) -> string {
	n := utf8.rune_count(s)
	if n >= w do return s
	return fmt.tprintf("%s%s", s, strings.repeat(" ", w - n, context.temp_allocator))
}

// 2026-10-23T18:03:45.164Z -> 2026-10-23 18:03 (UTC, as stored)
short_ts :: proc(ts: string) -> string {
	if len(ts) < 16 do return ts
	return fmt.tprintf("%s %s", ts[:10], ts[11:16])
}

join :: proc(parts: ..string) -> string {
	s, _ := filepath.join(parts)
	return s
}

env_or :: proc(key, fallback: string) -> string {
	v := os.get_env(key, context.allocator)
	return len(v) > 0 ? v : fallback
}
