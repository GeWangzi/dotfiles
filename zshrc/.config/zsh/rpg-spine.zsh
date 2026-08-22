# rpg-spine.zsh -- the W4 command block's gutter spine and result row.
#
# From the "W4 -- spine + full greeting" handoff (Retro RPG launcher concepts
# #5). Each command in that design is a block: a 4px spine down the left, the
# command at the top, its output beneath, and the exit status carried by the
# spine's colour -- green for success, red for failure.
#
# A shell cannot draw that ideal, and the handoff says so itself:
#
#     the spine needs the exit status of a command *before* its output prints,
#     which a prompt cannot do retroactively [...] the pragmatic version is a
#     neutral gutter with a status-coloured first line.
#
# Prefixing every output line would mean intercepting each command's stdout.
# Two other routes were tried and rejected as well:
#
#   * making stdout a pipe kills isatty, so every program drops its colour and
#     its pager, and full-screen ones break outright;
#   * painting column 1 afterwards -- ask the terminal for the cursor row
#     before and after the command, then go back and draw -- overwrites the
#     first character of every output line, because output starts in column 1;
#   * DECSLRM left/right margins would move output out of column 1 and fix
#     that, and kitty does not implement them. With `\033[?69h\033[5;40s` set,
#     text still starts in column 1 and still runs the full width.
#
# So the spine renders on the lines the shell itself owns, and the status row
# closes the block instead of opening it -- the one reordering the shell
# forces. Everything else is the handoff: spine in column 1, exit code as a
# Silkscreen mark, the dim context string right-aligned, duration only above
# 100ms, counters only when real.
#
#     ▌ …/dotfiles ⑂ master !2 ?1 cargo build --release   <- starship, live
#     error[E0308]: mismatched types                       <- raw output
#     ▌              101  …/dotfiles ⑂ master  12.8s       <- this file
#
# The context string is read straight out of .git/HEAD rather than by running
# git, so the row costs no forks at all: starship is already paying for a full
# `git status` one line above and there is no reason to pay twice.

zmodload zsh/datetime

# Handoff design tokens. Literal truecolor rather than ANSI slots, for the same
# reason rpg-greet and starship.toml use literals: skinctl repaints the ANSI
# palette per skin, but the creature's colours are fixed by the design.
typeset -g _rpg_ok=$'\e[38;2;61;220;132m'      # HP ok        #3DDC84
typeset -g _rpg_crit=$'\e[38;2;255;74;31m'     # critical     #FF4A1F
typeset -g _rpg_dimmest=$'\e[38;2;106;90;140m' # dimmest      #6A5A8C
typeset -g _rpg_bold=$'\e[1m'                  # -> Silkscreen, see kitty.conf
typeset -g _rpg_reset=$'\e[0m'

typeset -g _rpg_started=0
typeset -g _rpg_ran=0

# The branch, without forking git. A .git file rather than a directory means a
# worktree or a submodule; that indirection is not worth parsing here, so the
# row simply shows no branch in one.
_rpg_branch() {
    local dir=$PWD head
    while [[ -n $dir && $dir != / ]]; do
        if [[ -f $dir/.git/HEAD ]]; then
            read -r head < $dir/.git/HEAD
            [[ $head == ref:* ]] && print -r -- "${head##*/}" || print -r -- "${head[1,7]}"
            return
        fi
        [[ -e $dir/.git ]] && return
        dir=${dir:h}
    done
}

# The handoff writes durations as 0.4s and 12.8s -- one decimal under a minute,
# which is finer than starship's own cmd_duration can render.
_rpg_duration() {
    local -F e=$1
    if (( e < 60 )); then
        printf '%.1fs' $e
    elif (( e < 3600 )); then
        printf '%dm %02ds' $(( e / 60 )) $(( e % 60 ))
    else
        printf '%dh %02dm' $(( e / 3600 )) $(( e % 3600 / 60 ))
    fi
}

_rpg_preexec() {
    _rpg_ran=1
    _rpg_started=$EPOCHREALTIME
}

# $? has to be read on the very first line or the local declarations clobber it.
_rpg_precmd() {
    local st=$?

    # Bare Enter runs precmd without preexec. No command, no block, no row.
    (( _rpg_ran )) || return 0
    _rpg_ran=0

    local -F elapsed=$(( EPOCHREALTIME - _rpg_started ))
    local duration=""
    (( elapsed >= 0.1 )) && duration=$(_rpg_duration $elapsed)

    local spine right plain
    if (( st == 0 )); then
        # Success is "one dim string" in the handoff -- the whole thing in
        # #6A5A8C, not the prompt's per-segment colours:
        #     …/dotfiles ⑂ master · 0.4s
        local dir branch
        if [[ $PWD == $HOME ]]; then
            dir='~'
        else
            dir="…/${PWD:t}"
        fi
        branch=$(_rpg_branch)
        [[ -n $branch ]] && plain="$dir ⑂ $branch" || plain="$dir"
        [[ -n $duration ]] && plain+=" · $duration"

        spine=$_rpg_ok
        right="${_rpg_dimmest}${plain}${_rpg_reset}"
    else
        # Failure carries no context in the handoff, only the exit code as a
        # Silkscreen mark and then the duration:
        #     101  12.8s
        spine=$_rpg_crit
        plain="$st"
        right="${_rpg_bold}${_rpg_crit}${st}${_rpg_reset}"
        if [[ -n $duration ]]; then
            plain+="  $duration"
            right+="  ${_rpg_dimmest}${duration}${_rpg_reset}"
        fi
    fi

    # Spine in column 1, everything else hard against the right edge. The 2 is
    # the spine and the space after it.
    local -i pad=$(( COLUMNS - 2 - ${#plain} ))
    (( pad < 0 )) && pad=0
    print -r -- "${spine}▌${_rpg_reset}$(printf '%*s' $pad '')${right}"
}

autoload -Uz add-zsh-hook
add-zsh-hook preexec _rpg_preexec
add-zsh-hook precmd _rpg_precmd
