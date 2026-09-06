# Shared helpers for bats tests

# Root of the opt-jan repo
OPT_JAN="${OPT_JAN:-/opt/jan}"

# User home — defaults to /home/jan in VM, current user's home on host
if systemd-detect-virt -q -v 2>/dev/null; then
    JAN_HOME="${JAN_HOME:-/home/jan}"
else
    JAN_HOME="${JAN_HOME:-$HOME}"
fi

# Assert file exists
assert_file() {
    local f="$1"
    if [[ ! -f "$f" ]]; then
        echo "expected file: $f" >&2
        return 1
    fi
}

# Assert file is executable
assert_executable() {
    local f="$1"
    if [[ ! -x "$f" ]]; then
        echo "expected executable: $f" >&2
        return 1
    fi
}

# Assert directory exists
assert_dir() {
    local d="$1"
    if [[ ! -d "$d" ]]; then
        echo "expected directory: $d" >&2
        return 1
    fi
}

# Assert symlink exists and points to expected target
assert_symlink() {
    local link="$1" target="$2"
    if [[ ! -L "$link" ]]; then
        echo "expected symlink: $link" >&2
        return 1
    fi
    local actual
    actual="$(readlink -f "$link")"
    local expected
    expected="$(readlink -f "$target")"
    if [[ "$actual" != "$expected" ]]; then
        echo "symlink $link -> $actual, expected -> $expected" >&2
        return 1
    fi
}

# Assert a command is available in PATH
assert_command() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        echo "command not found: $cmd" >&2
        return 1
    fi
}

# Assert a command is not in PATH. Must not use a bare `! command` in callers:
# bash set -e does not abort when a negated command returns non-zero.
assert_command_absent() {
    local cmd="$1"
    if command -v "$cmd" >/dev/null; then
        echo "unexpected command: $cmd" >&2
        return 1
    fi
}

# Assert string is found in file
assert_file_contains() {
    local file="$1" pattern="$2"
    if ! grep -q -e "$pattern" -- "$file"; then
        echo "expected '$pattern' in $file" >&2
        return 1
    fi
}

# Assert pattern is absent. Must not use a bare `! grep` in callers: bash
# set -e does not abort when a negated command returns non-zero.
# grep exit 1 is "no match" (success here); any other non-zero is an error.
assert_file_not_contains() {
    local file="$1" pattern="$2" status=0
    grep -Eq -e "$pattern" -- "$file" || status=$?
    if (( status == 0 )); then
        echo "unexpected '$pattern' in $file" >&2
        return 1
    fi
    if (( status != 1 )); then
        echo "grep failed ($status) for '$pattern' in $file" >&2
        return 1
    fi
}

# Reject markdown links whose destinations are not absolute paths or URIs.
assert_no_relative_markdown_links() {
    local file="$1"
    local link dest
    local links=()
    mapfile -t links < <(grep -oE '\[[^]]+\]\([^)]+\)' -- "$file" || true)
    for link in "${links[@]}"; do
        dest=${link#*']('}
        dest=${dest%')'}
        dest=${dest%%[[:space:]]*}
        [[ -n $dest ]] || continue
        [[ $dest == /* ]] && continue
        [[ $dest == *://* ]] && continue
        echo "relative markdown link '$dest' in $file" >&2
        return 1
    done
}
