# fzf-agents: Ctrl+Alt+C searches Claude Code / Codex sessions.
# Source from config.fish:  fzf-agents init fish | source
function _fzf_agents_widget --description "Search agent sessions; insert a resume command"
    fzf-agents index 2>/dev/null
    set -l pick (true | fzf --ansi --disabled --delimiter '\t' --with-nth 5 \
        --prompt 'Agents> ' --query (commandline --current-token) \
        --bind 'start,change:reload:fzf-agents search {q}' \
        --preview 'fzf-agents preview {3} {q}' --preview-window 'right,55%,wrap')
    if test -n "$pick"
        set -l f (string split \t -- $pick)
        set -l resume (test $f[1] = claude; and echo "claude --resume $f[2]"; or echo "codex resume $f[2]")
        commandline --replace -- "cd "(string escape -- $f[4])"; and $resume"
    end
    commandline --function repaint
end

for mode in default insert
    bind --mode $mode ctrl-alt-c _fzf_agents_widget
end
