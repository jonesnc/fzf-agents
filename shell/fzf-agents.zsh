# fzf-agents: Ctrl+Alt+C searches Claude Code / Codex sessions.
# Source from ~/.zshrc:  eval "$(fzf-agents init zsh)"
_fzf_agents_widget() {
    fzf-agents index 2>/dev/null
    local pick src id cwd
    pick=$(true | fzf --ansi --disabled --delimiter '\t' --with-nth 5 \
        --prompt 'Agents> ' \
        --bind 'start,change:reload:fzf-agents search {q}' \
        --preview 'fzf-agents preview {3} {q}' --preview-window 'right,55%,wrap')
    if [[ -n $pick ]]; then
        IFS=$'\t' read -r src id _ cwd _ <<<"$pick"
        if [[ $src == claude ]]; then
            BUFFER="cd ${(q)cwd} && claude --resume $id"
        else
            BUFFER="cd ${(q)cwd} && codex resume $id"
        fi
        CURSOR=${#BUFFER}
    fi
    zle reset-prompt
}
zle -N _fzf_agents_widget
bindkey '^[^C' _fzf_agents_widget
