# dotfiles

my config files

To install on new system:
```
wget -O- https://github.com/jankotek/dotfiles/archive/refs/heads/main.tar.gz | tar -xz -C /tmp && bash /tmp/dotfiles-main/install-dotfiles.sh dotfiles
```
Or just download to temp folder without running installation:
```
wget -O- https://github.com/jankotek/dotfiles/archive/refs/heads/main.tar.gz | tar -xz -C /tmp && cd /tmp/dotfiles-main/
```

To install on new system, and WIPE home dirs and make all sorts of changes:
```
wget -O- https://github.com/jankotek/dotfiles/archive/refs/heads/main.tar.gz | tar -xz -C /tmp && bash /tmp/dotfiles-main/install-wipe.sh dotfiles