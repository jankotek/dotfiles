#!/bin/sh

inifile2="$HOME/.config/dconf-import.ini"
if [ -f "$inifile2" ]; then
    dconf load / < "$inifile2"
    rm -- "$inifile2"
fi



xfconf-query -c xfce4-session -np '/shutdown/ShowSuspend' -t 'bool' -s 'false'
xfconf-query -c xfce4-session -np '/shutdown/ShowHibernate' -t 'bool' -s 'false'
xfconf-query -c xfce4-session -np '/shutdown/ShowHybridSleep' -t 'bool' -s 'false'


xfconf-query -c xfce4-session -np '/backdrop/screen0/xinerama-stretch' -t 'bool' -s 'true'



# Trust desktop shortcuts (prevents XFCE "untrusted launcher" dialog)
for f in ~/desk/*.desktop; do
    [ -f "$f" ] || continue
    chmod +x "$f"
    checksum=$(sha256sum "$f" | cut -d' ' -f1)
    gio set "$f" metadata::xfce-exe-checksum "$checksum" 2>/dev/null || true
done

# Only the empty legacy directory; ~/desk is the XDG desktop.
rmdir -- "$HOME/Desktop" 2>/dev/null || true
