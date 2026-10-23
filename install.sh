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

cat <<'MSG'

Add the Ctrl+Alt+C widget to your shell:
  fish:  echo 'fzf-agents init fish | source' >> ~/.config/fish/config.fish
  bash:  echo 'eval "$(fzf-agents init bash)"' >> ~/.bashrc
  zsh:   echo 'eval "$(fzf-agents init zsh)"' >> ~/.zshrc
MSG
