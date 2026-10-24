# shellcheck shell=bash
# based on Derek Taylor (DistroTube)

# Bash may read ~/.bashrc for a noninteractive command started by sshd. Keep
# aliases, prompt hooks, shopt changes, and application initialization out of
# provisioning and file-transfer commands.
case $- in
    *i*) ;;
    *) return ;;
esac

export EDITOR="mcedit"
export VISUAL="mousepad"

### PROMPT
# This is commented out if using starship prompt
# PS1='[\u@\h \W]\$ '

### PATH
# ~/.profile sources this file for login shells; skip directories already on
# PATH so login and nested shells do not repeat them.
for dir in "$HOME/.bin" "$HOME/.local/bin"; do
  case ":$PATH:" in
    *":$dir:"*) ;;
    *) [ -d "$dir" ] && PATH="$dir:$PATH" ;;
  esac
done
unset dir

### CHANGE TITLE OF TERMINALS
case ${TERM} in
  xterm*|rxvt*|Eterm*|aterm|kterm|gnome*|alacritty|st|konsole*)
    PROMPT_COMMAND='echo -ne "\033]0;${USER}@${HOSTNAME%%.*}:${PWD/#$HOME/\~}\007"'
        ;;
  screen*)
    PROMPT_COMMAND='echo -ne "\033_${USER}@${HOSTNAME%%.*}:${PWD/#$HOME/\~}\033\\"'
    ;;
esac

### HISTORY
# Keep a large history, drop duplicates and commands typed with a leading
# space, and record when each command ran. `history -a` writes every command
# as soon as it finishes, so other terminals and crashes do not lose it.
HISTSIZE=1000000
HISTFILESIZE=1000000
HISTCONTROL=ignoreboth:erasedups
HISTTIMEFORMAT='%F %T  '
PROMPT_COMMAND="history -a${PROMPT_COMMAND:+; $PROMPT_COMMAND}"

### SHOPT
shopt -s autocd # change to named directory
shopt -s cdspell # autocorrects cd misspellings
shopt -s cmdhist # save multi-line commands in history as single line
shopt -s dotglob
shopt -s histappend # do not overwrite history
shopt -s expand_aliases # expand aliases
shopt -s checkwinsize # checks term size when bash regains control


### COUNTDOWN   

cdown () {
    N=$1
  while (( --N > 0 ))
    do
        echo "$N" |  figlet -c | lolcat &&  sleep 1
    done
}

### ARCHIVE EXTRACTION
# usage: ex <file>
ex ()
{
  if [ -f "$1" ] ; then
    case $1 in
      *.tar.bz2)   tar xjf "$1"   ;;
      *.tar.gz)    tar xzf "$1"   ;;
      *.bz2)       bunzip2 "$1"   ;;
      *.rar)       unrar x "$1"   ;;
      *.gz)        gunzip "$1"    ;;
      *.tar)       tar xf "$1"    ;;
      *.tbz2)      tar xjf "$1"   ;;
      *.tgz)       tar xzf "$1"   ;;
      *.zip)       unzip "$1"     ;;
      *.Z)         uncompress "$1";;
      *.7z)        7z x "$1"      ;;
      *.deb)       ar x "$1"      ;;
      *.tar.xz)    tar xJf "$1"   ;;
      *.tar.zst)   tar --zstd -xf "$1" ;;
      *)           echo "'$1' cannot be extracted via ex()" ;;
    esac
  else
    echo "'$1' is not a valid file"
  fi
}

### ALIASES ###

# root privileges
alias doas="doas --"



# Colorize grep output (good for log files)
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'

# confirm before overwriting something
alias cp="cp -i"
alias mv='mv -i'
alias rm='rm -i'

# adding flags
alias df='df -h'                          # human-readable sizes
alias free='free -m'                      # show sizes in MB


# git
alias addup='git add -u'
alias addall='git add .'
alias branch='git branch'
alias checkout='git checkout'
alias clone='git clone'
alias commit='git commit -m'
alias fetch='git fetch'
alias pull='git pull origin'
alias push='git push origin'
alias tag='git tag'
alias newtag='git tag -a'

# get error messages from journalctl
alias jctl="journalctl -p 3 -xb"

### FZF HISTORY SEARCH ###
# Ctrl-R opens a fuzzy search over history. Only Ctrl-R is taken: the empty
# commands stop fzf from binding Ctrl-T and Alt-C. Packages older than fzf
# 0.48 have no --bash and ship the script instead, which binds all three, so
# readline's defaults for those two keys are put back.
if command -v fzf >/dev/null 2>&1; then
  # shellcheck disable=SC2034 # read by the fzf script evaluated below
  FZF_CTRL_T_COMMAND='' FZF_ALT_C_COMMAND=''
  if fzf_init=$(fzf --bash 2>/dev/null); then
    eval "$fzf_init"
  else
    for fzf_init in /usr/share/fzf/shell/key-bindings.bash \
                    /usr/share/doc/fzf/examples/key-bindings.bash; do
      if [ -r "$fzf_init" ]; then
        # shellcheck source=/dev/null
        . "$fzf_init"
        bind '"\C-t": transpose-chars'
        bind '"\ec": capitalize-word'
        break
      fi
    done
  fi
  unset fzf_init FZF_CTRL_T_COMMAND FZF_ALT_C_COMMAND
fi

### SETTING THE STARSHIP PROMPT ###
if command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"

    # Bash has no right-hand prompt, so draw one at the right edge of the
    # input line without moving the cursor. It stays beside every command in
    # the scrollback: for commands that ran 5 s or longer, their run time and
    # the system load (1-minute load average); a non-zero exit code; and the
    # day-month 24-hour clock.
    # Colours are sand, mist, coral, and clock from the palette in
    # ~/.config/starship.toml.
    __prompt_right() {
        local plain='' text='' part ms=${STARSHIP_DURATION:-0} load _ clock
        # Starship updates STARSHIP_END_TIME only when a command ran, not for
        # an empty line. The first prompt has only the clock.
        if [[ -n ${__prompt_last_end+set} && -n ${STARSHIP_END_TIME-} \
            && $STARSHIP_END_TIME != "$__prompt_last_end" ]]; then
            if (( ms >= 5000 )); then
                if (( ms < 60000 )); then
                    part="$(( ms / 1000 )).$(( ms % 1000 / 100 ))s"
                elif (( ms < 3600000 )); then
                    printf -v part '%dm%02ds' $(( ms / 60000 )) $(( ms % 60000 / 1000 ))
                else
                    printf -v part '%dh%02dm' $(( ms / 3600000 )) $(( ms % 3600000 / 60000 ))
                fi
                plain+="$part  "
                text+="\e[38;2;201;169;106m$part\e[0m  "
                if read -r load _ < /proc/loadavg; then
                    part="load $load"
                    plain+="$part  "
                    text+="\e[38;2;143;179;191m$part\e[0m  "
                fi
            fi
            if (( ${STARSHIP_CMD_STATUS:-0} != 0 )); then
                part="exit $STARSHIP_CMD_STATUS"
                plain+="$part  "
                text+="\e[38;2;201;113;106m$part\e[0m  "
            fi
        fi
        __prompt_last_end=${STARSHIP_END_TIME-}
        printf -v clock '%(%d-%m %H:%M)T' -1
        plain+=$clock
        text+="\e[38;2;127;156;168m$clock\e[0m"
        PS1+="\[\e7\e[$(( ${COLUMNS:-80} - ${#plain} ))G$text\e8\]"
    }
    # Run after starship_precmd, which rebuilds PS1 on every prompt.
    PROMPT_COMMAND+="; __prompt_right"
fi
