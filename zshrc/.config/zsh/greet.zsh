# greet.zsh -- the shell greeting, rebuilt small after the creature era.
#
# Everything here is fork-free: colours and identity come from skinctl's
# skin.sh, the art is a $(<file) read, battery and uptime are plain file reads
# from sysfs and /proc. Sourced once per interactive shell from ~/.zshrc;
# SKIN_GREET=0 skips it there. skin.sh is read once at shell start, so the
# greeting also says which skin this shell's colours belong to when an old
# shell survives a `skinctl set`.
#
# The art is per-skin by file name -- ~/.config/skins/art/<slug>.txt, drawn in
# the skin's art colour. No file, no art: the greeting is then the name and
# status lines plus one dim notice naming the missing file, so a skin added to
# skins.toml without a drawing is visible rather than silently bare. The art
# belongs to the skin, not to this file; the braille drawings themselves are
# the ones from the old notes.txt (git history).

() {
    local f=${XDG_STATE_HOME:-$HOME/.local/state}/skins/skin.sh
    [[ -r $f ]] || return 0
    source $f
    local e=$'\e' reset=$'\e[0m'

    # The art, if this skin ships one. Star glyphs (✦ ✧ ⋆) anywhere in the
    # art are background scenery, so they render in the dimmest colour while
    # the subject keeps the art colour -- a plain substitution, still no forks.
    local art=~/.config/skins/art/${RPG_SKIN}.txt
    if [[ -r $art ]]; then
        local a=$(<$art) artcol="${e}[38;2;${RPG_C_ART}m" g
        for g in ✦ ✧ ⋆; do a=${a//$g/${e}[38;2;${RPG_C_DIMMEST}m${g}${artcol}}; done
        print -r -- "${artcol}${a}${reset}"
    else
        print -r -- "${e}[38;2;${RPG_C_DIMMEST}m(no art: ${art/#$HOME/~})${reset}"
    fi

    # The name, with type badges when the skin is a creature.
    local line="${e}[38;2;${RPG_C_ART}m▌${reset} ${e}[1;38;2;${RPG_C_NAME}m${RPG_SPECIES}${reset}"
    [[ -n $RPG_TYPE1 ]] && line+="  ${e}[48;2;${RPG_C_TYPE1};38;2;${RPG_C_BADGE_FG}m ${RPG_TYPE1} ${reset}"
    [[ -n $RPG_TYPE2 ]] && line+=" ${e}[48;2;${RPG_C_TYPE2};38;2;${RPG_C_BADGE_FG}m ${RPG_TYPE2} ${reset}"
    print -r -- $line

    # One dim status line. Only the battery number carries colour, on the same
    # fixed thresholds as everything else (warn 30, crit 15), so the line
    # stays quiet when nothing is wrong.
    local up d h m
    read -r up _ < /proc/uptime
    up=${up%.*}; d=$(( up / 86400 )); h=$(( up % 86400 / 3600 )); m=$(( up % 3600 / 60 ))
    local upstr="up "
    (( d )) && upstr+="${d}d "
    (( h )) && upstr+="${h}h "
    upstr+="${m}m"

    local cap="" c
    for c in /sys/class/power_supply/BAT*/capacity(N); do read -r cap < $c; break; done

    local dim="${e}[38;2;${RPG_C_DIM}m"
    local info="${dim}  ${USER}@${HOST} · zsh ${ZSH_VERSION} · ${upstr}"
    if [[ -n $cap ]]; then
        local bcol=$RPG_C_OK
        (( cap <= 30 )) && bcol=$RPG_C_WARN
        (( cap <= 15 )) && bcol=$RPG_C_CRIT
        info+=" · bat ${e}[38;2;${bcol}m${cap}%${dim}"
    fi
    print -r -- "${info}${reset}"

    unset -m 'RPG_*'
}
