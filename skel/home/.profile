# shellcheck shell=sh
if [ -n "${BASH_VERSION:-}" ] && [ -f "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi

case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) [ -d "$HOME/.local/bin" ] && PATH="$HOME/.local/bin:$PATH" ;;
esac
export PATH
