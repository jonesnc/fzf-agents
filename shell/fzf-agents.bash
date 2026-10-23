# fzf-agents: Ctrl+Alt+C searches Claude Code / Codex sessions.
# Source from ~/.bashrc:  eval "$(fzf-agents init bash)"
_fzf_agents_widget() {
    fzf-agents index 2>/dev/null
    local pick src id cwd
    pick=$(true | fzf --ansi --disabled --delimiter '\t' --with-nth 5 \
        --prompt 'Agents> ' \
        --bind 'start,change:reload:fzf-agents search {q}' \
        --preview 'fzf-agents preview {3} {q}' --preview-window 'right,55%,wrap') || return
    IFS=$'\t' read -r src id _ cwd _ <<<"$pick"
    if [[ $src == claude ]]; then
        READLINE_LINE="cd $(printf '%q' "$cwd") && claude --resume $id"
    else
        READLINE_LINE="cd $(printf '%q' "$cwd") && codex resume $id"
    fi
    READLINE_POINT=${#READLINE_LINE}
}
bind -x '"\e\C-c": _fzf_agents_widget'
