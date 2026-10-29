#!/usr/bin/env bats

load ../helpers

@test "new-user skeleton and installer are present" {
    assert_executable "$OPT_JAN/skel/install"
    assert_dir "$OPT_JAN/skel/home"
    assert_file "$OPT_JAN/skel/home/.config/git/config"
    assert_executable "$OPT_JAN/skel/home/.local/bin/autostart.sh"
    local dir
    for dir in \
        skel/home/.agents/skills \
        skel/home/.claude/skills \
        skel/home/.grok/skills \
        skel/home/.pi/agent/skills; do
        [[ -d $OPT_JAN/$dir && ! -L $OPT_JAN/$dir ]]
        [[ $(readlink -- "$OPT_JAN/$dir/host-lab-vm-cli") == /opt/jan/agent/skills/host-lab-vm-cli ]]
        [[ $(readlink -- "$OPT_JAN/$dir/host-lab-vm-gui") == /opt/jan/agent/skills/host-lab-vm-gui ]]
    done
}

@test "curated defaults use safe paths and desktop scoping" {
    assert_file_contains \
        "$OPT_JAN/skel/home/.config/user-dirs.dirs" \
        'XDG_PUBLICSHARE_DIR="\$HOME/media/share"'
    assert_file_contains \
        "$OPT_JAN/skel/home/.config/zim/preferences.conf" \
        '^file_templates_folder=~/doc/templates$'
    if grep -q '^[[:space:]]*export GTK_THEME=' \
        "$OPT_JAN/skel/home/.profile"; then
        return 1
    fi

    HOME="$OPT_JAN/skel/home" bash -c '
        source "$HOME/.bashrc"
        ! alias cp >/dev/null 2>&1
    '
}

@test "bashrc keeps stock commands and builds PATH once" {
    [[ ! -e $OPT_JAN/skel/home/.config/fish/config.fish ]]
    local home
    home=$(mktemp -d)
    cp "$OPT_JAN/skel/home/.bashrc" "$OPT_JAN/skel/home/.profile" "$home/"
    mkdir -p "$home/.local/bin"
    run env -i HOME="$home" PATH=/usr/bin:/bin TERM=screen-256color bash -i -c '
        source "$HOME/.profile"
        source "$HOME/.bashrc"
        alias stat >/dev/null 2>&1 && exit 1
        printf "%s\n" "$TERM" "$PATH" > "$HOME/result"
    ' 2>/dev/null
    [[ $status -eq 0 ]]
    mapfile -t lines < "$home/result"
    rm -rf "$home"
    [[ ${lines[0]} == screen-256color ]]
    [[ $(tr ':' '\n' <<<"${lines[1]}" | grep -cx "$home/.local/bin") -eq 1 ]]
}

@test "bash keeps a large, immediately saved history" {
    local home
    home=$(mktemp -d)
    cp "$OPT_JAN/skel/home/.bashrc" "$home/"
    run env -i HOME="$home" PATH=/usr/bin:/bin TERM=xterm bash -i -c '
        printf "%s\n" "$HISTSIZE" "$HISTFILESIZE" "$HISTCONTROL" > "$HOME/result"
        history -s "saved-before-shell-exit"
        eval "$PROMPT_COMMAND"
        grep -qx "saved-before-shell-exit" "$HISTFILE"
    ' 2>/dev/null
    local -a result
    mapfile -t result < "$home/result"
    rm -rf "$home"
    [[ $status -eq 0 ]]
    [[ ${result[0]} == 1000000 && ${result[1]} == 1000000 ]]
    [[ ${result[2]} == ignoreboth:erasedups ]]
}

@test "Ctrl-R opens fzf history search and leaves Ctrl-T and Alt-C alone" {
    command -v fzf >/dev/null || skip "fzf not installed"
    fzf --bash >/dev/null 2>&1 \
        || [[ -r /usr/share/fzf/shell/key-bindings.bash ]] \
        || [[ -r /usr/share/doc/fzf/examples/key-bindings.bash ]] \
        || skip "fzf has no bash key bindings"
    local home
    home=$(mktemp -d)
    cp "$OPT_JAN/skel/home/.bashrc" "$home/"
    run env -i HOME="$home" PATH="$PATH" TERM=xterm bash -i -c '
        { bind -X; bind -p; } > "$HOME/bindings"
        [ -z "${FZF_CTRL_T_COMMAND+x}" ]
    ' 2>/dev/null
    local bindings
    bindings=$(cat "$home/bindings")
    rm -rf "$home"
    [[ $status -eq 0 ]]
    [[ $bindings =~ \"\\C-r\"[:\ ]+[^$'\n']*fzf ]]
    [[ $bindings == *'"\C-t": transpose-chars'* ]]
    [[ $bindings == *'"\M-c": capitalize-word'* || $bindings == *'"\ec": capitalize-word'* ]]
}

@test "Starship config parses and uses only characters common fonts have" {
    python3 - "$OPT_JAN/skel/home/.config/starship.toml" <<'PY'
import sys, tomllib
text = open(sys.argv[1], encoding="utf-8").read()
config = tomllib.loads(text)
assert config["palette"] in config["palettes"]
# No Nerd Font is installed: allow ASCII plus characters every common font
# has, so the prompt never shows boxes.
allowed = set("…›‹↑↓")
bad = {f"U+{ord(c):04X} {c}" for c in text if ord(c) > 0x7E and c not in allowed}
assert not bad, bad
# Shown git states whose Starship defaults use other characters.
for key in ("ahead", "behind", "diverged", "renamed", "deleted"):
    assert key in config["git_status"], key
PY
}

@test "prompt shows day-month 24-hour clock on the right without growing" {
    local home
    home=$(mktemp -d)
    mkdir "$home/bin"
    cp "$OPT_JAN/skel/home/.bashrc" "$home/"
    # Minimal stand-in for `starship init bash`: rebuild PS1 on every prompt.
    cat > "$home/bin/starship" <<'STUB'
#!/bin/sh
echo 'starship_precmd() { PS1="> "; }; PROMPT_COMMAND=starship_precmd'
STUB
    chmod +x "$home/bin/starship"
    run env -i HOME="$home" PATH="$home/bin:/usr/bin:/bin" TERM=xterm COLUMNS=40 bash -i -c '
        eval "$PROMPT_COMMAND"
        eval "$PROMPT_COMMAND"
        printf "%s" "$PS1" > "$HOME/ps1"
    ' 2>/dev/null
    local ps1
    ps1=$(cat "$home/ps1")
    rm -rf "$home"
    [[ $status -eq 0 ]]
    # One clock, placed so 11 characters end one column before the edge.
    [[ $ps1 =~ ^'> \[\e7\e[29G'.*'m'[0-3][0-9]-[01][0-9]' '[0-2][0-9]:[0-5][0-9]'\e[0m\e8\]'$ ]]
}

@test "right prompt shows run time and load from 5 s, and a failed exit code" {
    local home
    home=$(mktemp -d)
    mkdir "$home/bin"
    cp "$OPT_JAN/skel/home/.bashrc" "$home/"
    # Stand-in for `starship init bash` that reports what Starship would.
    cat > "$home/bin/starship" <<'STUB'
#!/bin/sh
echo 'starship_precmd() { PS1="> "; }; PROMPT_COMMAND=starship_precmd'
STUB
    chmod +x "$home/bin/starship"
    run env -i HOME="$home" PATH="$home/bin:/usr/bin:/bin" TERM=xterm COLUMNS=60 bash -i -c '
        strip() { sed "s/\\\\e\[[0-9;]*m//g; s/\\\\[][]//g; s/\\\\e[78]//g"; }
        eval "$PROMPT_COMMAND"; strip <<<"$PS1" > "$HOME/p1"
        STARSHIP_END_TIME=1 STARSHIP_DURATION=6500 STARSHIP_CMD_STATUS=3
        eval "$PROMPT_COMMAND"; strip <<<"$PS1" > "$HOME/p2"
        STARSHIP_DURATION=4999 STARSHIP_CMD_STATUS=0 STARSHIP_END_TIME=2
        eval "$PROMPT_COMMAND"; strip <<<"$PS1" > "$HOME/p3"
        eval "$PROMPT_COMMAND"; strip <<<"$PS1" > "$HOME/p4"
        STARSHIP_DURATION=42 STARSHIP_CMD_STATUS=1 STARSHIP_END_TIME=3
        eval "$PROMPT_COMMAND"; strip <<<"$PS1" > "$HOME/p5"
    ' 2>/dev/null
    local p1 p2 p3 p4 p5
    p1=$(cat "$home/p1") p2=$(cat "$home/p2") p3=$(cat "$home/p3")
    p4=$(cat "$home/p4") p5=$(cat "$home/p5")
    rm -rf "$home"
    [[ $status -eq 0 ]]
    local clock='[0-3][0-9]-[01][0-9] [0-2][0-9]:[0-5][0-9]'
    # Each right prompt ends one column before the 60-column edge.
    local p
    for p in "$p1" "$p2" "$p3" "$p4" "$p5"; do
        [[ $p =~ ^'> \e['([0-9]+)'G'(.*)$ ]]
        (( BASH_REMATCH[1] + ${#BASH_REMATCH[2]} == 60 ))
    done
    # First prompt: only the clock.
    [[ $p1 =~ G$clock$ ]]
    # 6.5 s: run time, the 1-minute load average, and exit 3.
    [[ $p2 =~ G'6.5s  load '[0-9]+'.'[0-9][0-9]'  exit 3  '$clock$ ]]
    # Under 5 s and successful: only the clock.
    [[ $p3 =~ G$clock$ ]]
    # A quick failure still shows its exit code.
    [[ $p5 =~ G'exit 1  '$clock$ ]]
    # An empty line shows only the clock again.
    [[ $p4 =~ G$clock$ ]]
}

@test "ex extracts archives with spaces and tar.zst" {
    command -v zstd >/dev/null || skip "zstd not installed"
    local work
    work=$(mktemp -d)
    mkdir "$work/src"
    echo hi > "$work/src/a file"
    tar -C "$work/src" --zstd -cf "$work/my archive.tar.zst" "a file"
    mkdir "$work/out"
    run bash -c '
        eval "$(sed -n "/^ex ()/,/^}/p" "$1")"
        cd "$2/out" && ex "../my archive.tar.zst"
    ' _ "$OPT_JAN/skel/home/.bashrc" "$work"
    [[ $status -eq 0 && -f "$work/out/a file" ]]
    rm -rf "$work"
}

@test "Plasma defaults match the XFCE Sweet appearance" {
    local kdeglobals="$OPT_JAN/skel/home/.config/kdeglobals"
    assert_file_contains "$kdeglobals" '^ColorScheme=Sweet-dark$'
    assert_file_contains "$kdeglobals" '^Theme=Sweet-Purple$'
    if grep -q '^\[Colors:' "$kdeglobals"; then
        return 1
    fi
}

@test "Konsole uses global profiles and defaults to pure black" {
    assert_file_contains \
        "$OPT_JAN/skel/home/.config/konsolerc" \
        '^DefaultProfile=dark.profile$'
    assert_file_contains \
        "$OPT_JAN/usr/share/konsole/dark.profile" \
        '^ColorScheme=WhiteOnBlack$'
    assert_file_contains \
        "$OPT_JAN/usr/share/konsole/white.profile" \
        '^ColorScheme=BlackOnWhite$'
    assert_file_contains \
        "$OPT_JAN/usr/share/konsole/dark.profile" \
        '^Font=JetBrains Mono,10,'
    assert_file_contains \
        "$OPT_JAN/usr/share/konsole/dark.profile" \
        '^WordModeAscii=true$'
    local profile
    for profile in dark white; do
        [[ ! -e $OPT_JAN/skel/home/.local/share/konsole/$profile.profile ]]
        assert_file_contains \
            "$OPT_JAN/usr/share/konsole/$profile.profile" \
            '^Command=/bin/bash$'
        assert_file_contains \
            "$OPT_JAN/usr/share/konsole/$profile.profile" \
            '^HistorySize=1000000$'
    done
}

@test "MC desktop shortcuts use the packaged icon name" {
    assert_file_contains \
        "$OPT_JAN/skel/home/desk/mc.desktop" \
        '^Icon=mc$'
}

@test "monospace defaults use JetBrains Mono 10" {
    assert_file_contains \
        "$OPT_JAN/usr/share/color-schemes/Sweet-dark.colors" \
        '^fixed=JetBrains Mono,10,'
    assert_file_contains \
        "$OPT_JAN/usr/etc/xdg/katerc" \
        '^Text Font Features=liga=1,calt=1$'
    assert_file_contains \
        "$OPT_JAN/usr/etc/xdg/kwriterc" \
        '^Text Font Features=liga=1,calt=1$'
    assert_file_contains \
        "$OPT_JAN/skel/home/.config/dconf-import.ini" \
        "monospace-font-name='JetBrains Mono 10'"
    assert_file \
        "$OPT_JAN/usr/share/fontconfig/conf.avail/60-jan-jetbrains-mono.conf"
}

@test "Plasma panel defaults reproduce the curated VM layout" {
    local layout="$OPT_JAN/skel/home/.local/share/plasma/layout-templates/org.opensuse.desktop.defaultPanel/contents/layout.js"
    local metadata="$OPT_JAN/skel/home/.local/share/plasma/layout-templates/org.opensuse.desktop.defaultPanel/metadata.json"
    assert_file "$layout"
    assert_file "$metadata"
    assert_file_contains "$layout" '^panel.location = "top"$'
    assert_file_contains "$layout" '^panel.height = 32$'
    assert_file_contains "$layout" \
        'addWidget("org.kde.plasma.taskmanager")'
    assert_file_contains "$layout" \
        'preferred://filemanager,applications:org.kde.konsole.desktop'
    assert_file_contains "$layout" \
        'clock.writeConfig("customDateFormat", "MM-dd ddd")'
    assert_file_contains "$layout" \
        'clock.writeConfig("use24hFormat", 2)'
    # The desktop background is named here rather than inherited from the
    # distribution look-and-feel, whose wallpaper package may not be installed.
    assert_file_contains "$layout" \
        'writeConfig("Image", wallpaper)'
    assert_file_contains "$layout" \
        'wallpaper = "/usr/local/share/jan-wallpaper.jpg"'
    assert_file_contains "$layout" \
        'writeConfig("Color", "0,0,0")'
}

@test "skeleton has no account-specific path or generated desktop state" {
    if grep -R -F /home/jan "$OPT_JAN/skel/home"; then
        return 1
    fi
    local forbidden generated
    for forbidden in \
        .cache \
        .config/kwinoutputconfig.json \
        .config/klipperrc \
        .config/kactivitymanagerdrc \
        .config/libvirt \
        .local/share/klipper \
        .local/share/kactivitymanagerd \
        .local/share/libvirt; do
        [[ ! -e "$OPT_JAN/skel/home/$forbidden" ]] || return 1
    done
    generated=$(find "$OPT_JAN/skel/home" -mindepth 1 \
        \( -type d -name .cache \
        -o -iname 'kwinoutputconfig*' \
        -o -iname '*klipper*' \
        -o -iname '*kactivitymanager*' \
        -o -type d -name libvirt \) \
        -print -quit)
    [[ -z $generated ]]
}

@test "VM display resize is a separate XFCE-only autostart" {
    local entry="$OPT_JAN/skel/home/.config/autostart/vm-resize-display.desktop"
    assert_file_contains "$entry" '^OnlyShowIn=XFCE;$'
    if grep -F vm-resize-display-loop \
        "$OPT_JAN/skel/home/.local/bin/autostart.sh" \
        "$OPT_JAN/skel/home/.xsessionrc"; then
        return 1
    fi
}

@test "installer preserves unmanaged paths and converges managed ownership" {
    if (( EUID != 0 )); then
        skip "ownership convergence requires root"
    fi

    local destination source relative installed
    destination=$(mktemp -d \
        -p "${BATS_TEST_TMPDIR:-/tmp}" jan-skel-install.XXXXXX)
    printf 'administrator sentinel\n' > "$destination/admin-sentinel"
    install -d "$destination/.config"
    printf 'unsafe old content\n' > "$destination/.bashrc"
    chown 65534:65534 "$destination/.bashrc" "$destination/.config"

    "$OPT_JAN/skel/install" "$destination"
    "$OPT_JAN/skel/install" "$destination"

    [[ $(<"$destination/admin-sentinel") == "administrator sentinel" ]]
    while IFS= read -r -d '' source; do
        relative=${source#"$OPT_JAN/skel/home/"}
        installed=$destination/$relative
        [[ -e $installed || -L $installed ]]
        [[ $(stat -c %U:%G "$installed") == root:root ]]
        if [[ -L $source ]]; then
            [[ -L $installed ]]
            [[ $(readlink -- "$source") == "$(readlink -- "$installed")" ]]
        elif [[ -f $source ]]; then
            cmp "$source" "$installed"
            [[ $(stat -c %a "$source") == "$(stat -c %a "$installed")" ]]
        fi
    done < <(find "$OPT_JAN/skel/home" -mindepth 1 -print0)
}
