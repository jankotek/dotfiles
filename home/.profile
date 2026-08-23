# shellcheck shell=sh
if [ -n "${BASH_VERSION:-}" ] && [ -f "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi

if [ -d "$HOME/.local/bin" ]; then
    PATH="$HOME/.local/bin:$PATH"
fi
export PATH
