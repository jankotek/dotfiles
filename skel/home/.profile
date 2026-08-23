if [ -n "${BASH_VERSION:-}" ] && [ -f "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi

if [ -d "$HOME/.local/bin" ]; then
    PATH="$HOME/.local/bin:$PATH"
fi
export PATH

export GTK_THEME=Sweet-Dark-v40
#export QT_STYLE_OVERRIDE=Adwaita-Dark
