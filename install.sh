#!/bin/sh
# Install the latest fzf-agents release into ~/.local/bin (or $BIN_DIR).
set -eu
repo=jonesnc/fzf-agents
bin_dir=${BIN_DIR:-$HOME/.local/bin}

case "$(uname -s)-$(uname -m)" in
    Linux-x86_64) target=linux-amd64 ;;
    Linux-aarch64 | Linux-arm64) target=linux-arm64 ;;
    Darwin-arm64) target=macos-arm64 ;;
    *) echo "fzf-agents: no prebuilt binary for $(uname -sm); build from source" >&2; exit 1 ;;
esac

url="https://github.com/$repo/releases/latest/download/fzf-agents-$target.tar.gz"
mkdir -p "$bin_dir"
curl -fsSL "$url" | tar xz -C "$bin_dir" fzf-agents
echo "installed $bin_dir/fzf-agents"
command -v fzf >/dev/null || echo "note: fzf not found; install it first (https://github.com/junegunn/fzf)"

case ":$PATH:" in
    *":$bin_dir:"*) ;;
    *) echo "note: $bin_dir is not on your PATH; add it so the widget can find fzf-agents" ;;
esac

# Wire the Ctrl+Alt+C widget into every installed shell. Idempotent; set
# FZF_AGENTS_NO_SHELL=1 to skip.
add_line() { # file line
    mkdir -p "$(dirname "$1")"
    if ! grep -qsF "$2" "$1"; then
        printf '\n%s\n' "$2" >>"$1"
        echo "added widget to $1"
    fi
}
if [ -z "${FZF_AGENTS_NO_SHELL:-}" ]; then
    if command -v fish >/dev/null; then
        conf="${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d/fzf-agents.fish"
        mkdir -p "$(dirname "$conf")"
        printf '%s\n' 'status is-interactive; and fzf-agents init fish | source' >"$conf"
        echo "added widget to $conf"
    fi
    command -v bash >/dev/null && add_line "$HOME/.bashrc" 'eval "$(fzf-agents init bash)"'
    command -v zsh >/dev/null && add_line "${ZDOTDIR:-$HOME}/.zshrc" 'eval "$(fzf-agents init zsh)"'
    echo "open a new shell and press Ctrl+Alt+C"
fi
