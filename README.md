# fzf-agents

Fuzzy-find your coding-agent sessions. Press **Ctrl+Alt+C**, type any text, and see every Claude Code and Codex session that contains it, newest first, with the matching messages previewed on the right. Press Enter to get a ready-to-run resume command (`cd <dir> && claude --resume <id>` or `codex resume <id>`).

Inspired by the Ctrl+Alt+F directory search in [fzf.fish](https://github.com/PatrickF1/fzf.fish).

## Install

Requires [fzf](https://github.com/junegunn/fzf) 0.45+.

```sh
curl -fsSL https://github.com/jonesnc/fzf-agents/releases/latest/download/install.sh | sh
```

Prebuilt binaries: Linux amd64/arm64, macOS arm64. The installer also adds the Ctrl+Alt+C widget to every shell it finds (fish, bash, zsh); it is safe to rerun. Set `FZF_AGENTS_NO_SHELL=1` to skip that and wire it up by hand:

| Shell | Add to config |
|---|---|
| fish | `fzf-agents init fish \| source` in `~/.config/fish/config.fish` |
| bash | `eval "$(fzf-agents init bash)"` in `~/.bashrc` |
| zsh | `eval "$(fzf-agents init zsh)"` in `~/.zshrc` |

### Build from source

```sh
odin build . -o:speed -out:fzf-agents
```

Needs [Odin](https://odin-lang.org) dev-2026-10 or newer.

## How it works

- `fzf-agents index` extracts user and assistant text from session logs into a plain-text cache. It is incremental (by file mtime), so it runs on every widget open in a few milliseconds.
- `fzf-agents search QUERY` does a case-insensitive substring scan of the cache and prints one line per matching session with a hit count and snippet.
- `fzf-agents preview CACHE QUERY` prints the matching messages with hits highlighted.

| Source | Default location | Override |
|---|---|---|
| Claude Code | `~/.claude/projects/*/*.jsonl` | `CLAUDE_CONFIG_DIR` |
| Codex | `~/.codex/sessions/**/*.jsonl` | `CODEX_HOME` |
| Cache | `~/.cache/fzf-agents/` | `XDG_CACHE_HOME` |

Timestamps are shown in UTC.

## License

MIT
