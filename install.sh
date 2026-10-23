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

# Wire the Ctrl+Alt+C widget into every installed shell, unless the shell's
# config already runs `fzf-agents init`. Set FZF_AGENTS_NO_SHELL=1 to skip.
add_line() { # shell file line [search-path]
    if grep -rqsF "fzf-agents init $1" "${4:-$2}"; then
        echo "$1: widget already set up"
        return
    fi
    mkdir -p "$(dirname "$2")"
    printf '\n%s\n' "$3" >>"$2"
    echo "$1: added widget to $2"
}
if [ -z "${FZF_AGENTS_NO_SHELL:-}" ]; then
    fish_dir="${XDG_CONFIG_HOME:-$HOME/.config}/fish"
    command -v fish >/dev/null && add_line fish "$fish_dir/conf.d/fzf-agents.fish" \
        'status is-interactive; and fzf-agents init fish | source' "$fish_dir"
    command -v bash >/dev/null && add_line bash "$HOME/.bashrc" 'eval "$(fzf-agents init bash)"'
    command -v zsh >/dev/null && add_line zsh "${ZDOTDIR:-$HOME}/.zshrc" 'eval "$(fzf-agents init zsh)"'
    echo "open a new shell and press Ctrl+Alt+C"
fi
