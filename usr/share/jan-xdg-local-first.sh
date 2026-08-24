# Administrator KConfig defaults under /usr/local must override distribution
# defaults under /etc/xdg while retaining every other configured search path.
jan_xdg_config_dirs=/usr/local/etc/xdg
jan_xdg_config_dirs_old=${XDG_CONFIG_DIRS:-/etc/xdg}
jan_xdg_old_ifs=$IFS
IFS=:
for jan_xdg_config_dir in $jan_xdg_config_dirs_old; do
    if [ -n "$jan_xdg_config_dir" ] && \
        [ "$jan_xdg_config_dir" != /usr/local/etc/xdg ]; then
        jan_xdg_config_dirs=$jan_xdg_config_dirs:$jan_xdg_config_dir
    fi
done
IFS=$jan_xdg_old_ifs
export XDG_CONFIG_DIRS="$jan_xdg_config_dirs"
unset jan_xdg_config_dir jan_xdg_config_dirs jan_xdg_config_dirs_old \
    jan_xdg_old_ifs
