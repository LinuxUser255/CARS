#!/usr/bin/env bash
# rice-ubuntu.sh — rice an Ubuntu (GNOME) VM
#
#   ./rice-ubuntu.sh                   # run every module
#   ./rice-ubuntu.sh keys fastfetch    # run only these modules
#   DRY_RUN=1 ./rice-ubuntu.sh         # print actions, change nothing
#   DEBUG=1 ./rice-ubuntu.sh           # extra trace output
#   FORCE=1 ./rice-ubuntu.sh nvim      # re-run the nvim installer anyway
#   FASTFETCH_TAG=2.70.0 ./rice-ubuntu.sh fastfetch   # pin a release
#
# Modules, in order: deps zsh fff fastfetch keys nvim
# Run as your normal user, from a terminal inside the desktop session.
# Idempotent: safe to re-run; each module checks state first.

set -Eeuo pipefail
IFS=$'\n\t'
trap 'err "failed in ${FUNCNAME[0]:-main} (line $LINENO): $BASH_COMMAND"' ERR

# Style notes:
#   • No subshells: command output is written to a file in $WORK and read
#     back with builtins (read / mapfile / printf -v) instead of $(...).
#   • Process-level parallelism: downloads and the fastfetch clone run as
#     background jobs while apt works; `wait` collects them.

# ───────────────────────── config ─────────────────────────
ZSHRC_URL="https://raw.githubusercontent.com/LinuxUser255/CARS/main/vm-dot-files/zshrc-ubuntu-hacking"
NVIM_INSTALLER_URL="https://raw.githubusercontent.com/LinuxUser255/nvim/refs/heads/main/install-fast-improved.sh"
FFF_URL="https://raw.githubusercontent.com/LinuxUser255/ShellScripting/refs/heads/main/ShortCuts/fff"
FASTFETCH_REPO="https://github.com/fastfetch-cli/fastfetch.git"
FASTFETCH_TAG="${FASTFETCH_TAG:-latest}"
WM_SCHEMA="org.gnome.desktop.wm.keybindings"
WS_LEFT='<Super><Control>Left'     # Win + Ctrl + ←
WS_RIGHT='<Super><Control>Right'   # Win + Ctrl + →

# what the zshrc expects to exist, plus ripgrep
APT_PKGS=(
  git curl ca-certificates python3
  zsh zsh-syntax-highlighting zsh-autosuggestions command-not-found
  ripgrep fzf bat xclip jq unzip zstd tmux ranger less
  nmap net-tools wireless-tools ufw
)

FASTFETCH_BUILD_PKGS=(build-essential cmake pkg-config git)

# optional: each one enables more fastfetch modules; missing ones are skipped
FASTFETCH_OPT_PKGS=(
  libpci-dev libvulkan-dev libwayland-dev libxrandr-dev libxcb-randr0-dev
  libdconf-dev libdbus-1-dev libmagickcore-dev libsqlite3-dev libegl-dev
  libglx-dev ocl-icd-opencl-dev libnm-dev libpulse-dev libdrm-dev
  libchafa-dev libelf-dev zlib1g-dev
)

MODULES=(deps zsh fff fastfetch keys nvim)

# private scratch dir; mkdir (not -p) fails if the path already exists
printf -v WORK '%s/rice-ubuntu.%s.%s' "${TMPDIR:-/tmp}" "$$" "${SRANDOM:-$RANDOM}"
declare -A BG_PID=()   # name → pid of a background job
APT_READY=0

# ───────────────────────── helpers ─────────────────────────
log() {
        local IFS=' '
        printf '\e[32m[+]\e[0m %s\n' "$*"
}

warn() {
        local IFS=' '
        printf '\e[33m[!]\e[0m %s\n' "$*" >&2
}

err() {
        local IFS=' '
        printf '\e[31m[x]\e[0m %s\n' "$*" >&2
}

die() {
        err "$@"
        exit 1
}

debug() {
        [[ ${DEBUG:-0} == 1 ]] || return 0

        local IFS=' '
        printf '\e[36m[DEBUG]\e[0m %s\n' "$*" >&2
}

run() {  # run <cmd...> — execute, or only print it under DRY_RUN
        local IFS=' '
        if [[ ${DRY_RUN:-0} == 1 ]]; then
            printf '  DRY: %s\n' "$*" >&2
            return 0
        fi
        debug "exec: $*"
        "$@"
}

did() {  # did <msg> — report an action only if it really ran
        [[ ${DRY_RUN:-0} == 1 ]] || log "$@"
        return 0
}

has() {
        command -v "$1" > /dev/null 2>&1
}

stamp() {  # stamp <var> — timestamp via printf's builtin strftime (no date fork)
        printf -v "$1" '%(%F-%H%M%S)T' -1
}

capture() {  # capture <var> <cmd...> — first line of cmd's stdout → var, no subshell
        local -n _cap_out=$1
        shift
        _cap_out=
        "$@" > "$WORK/capture" 2> /dev/null || return 1
        IFS= read -r _cap_out < "$WORK/capture" || :
}

cpus() {  # cpus <var> — CPU count from /sys (no nproc fork); "0-3" → 4
        local -n _cpus=$1
        local online
        IFS= read -r online < /sys/devices/system/cpu/online || online=0-1
        _cpus=$(( ${online##*[-,]} + 1 ))
}

usage() {  # print the header comment block
        local line
        while IFS= read -r line; do
            case $line in
                '#!'*) continue ;;
                '#'*)  line=${line#\#}; printf '%s\n' "${line# }" ;;
                *)     break ;;
            esac
        done < "$0"
}

cleanup() {  # stop unfinished background jobs, remove the scratch dir
        local pid

        for pid in "${BG_PID[@]}"; do
            kill "$pid" 2> /dev/null || :
        done

        [[ -d $WORK ]] && rm -rf -- "$WORK"

        return 0
}

# ── downloads: started early as background jobs, collected on demand ──
prefetch() {  # prefetch <name> <url>
        [[ -n ${BG_PID[$1]:-} || -s $WORK/$1 ]] && return 0

        curl -fsSL --retry 2 -o "$WORK/$1" "$2" &
        BG_PID[$1]=$!
        debug "prefetch $1 (pid ${BG_PID[$1]})"
}

await() {  # await <name> <url> — wait for the download, then sanity-check it
        local name=$1 url=$2 head=
        prefetch "$name" "$url"

        if [[ -n ${BG_PID[$name]:-} ]]; then
            wait "${BG_PID[$name]}" || die "download failed: $url"
            unset 'BG_PID[$name]'
        fi

        [[ -s $WORK/$name ]] || die "empty download: $url"
        IFS= read -r -N 256 head < "$WORK/$name" || :
        head=${head,,}

        if [[ $head == *'<!doctype html'* || $head == *'<html'* ]]; then
            die "got an HTML page, not a file: $url"
        fi
}

# ── apt ──
apt_refresh() {  # apt update once, then cache the archive's package names
        (( APT_READY )) && return 0

        run sudo apt-get update -qq
        apt-cache pkgnames > "$WORK/pkgnames"
        APT_READY=1
}

apt_has() {
        grep -qxF -- "$1" "$WORK/pkgnames"
}

apt_install() {  # apt_install <pkg...> — install what exists, warn about the rest
        local p list
        local -a found=() miss=()
        local -A ok=()
        apt_refresh
        printf '%s\n' "$@" > "$WORK/want"
        grep -xFf "$WORK/want" "$WORK/pkgnames" > "$WORK/found" || :
        mapfile -t found < "$WORK/found"

        for p in "${found[@]}"; do
            ok[$p]=1
        done

        for p in "$@"; do
            [[ -n ${ok[$p]:-} ]] || miss+=("$p")
        done

        # confdef/confold: never stop on a changed /etc config file — keep the existing one
        if (( ${#found[@]} )); then
            run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
                -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "${found[@]}"
        fi

        if (( ${#miss[@]} )); then
            printf -v list '%s ' "${miss[@]}"
            warn "  not in apt, skipped: ${list% }"
        fi

        return 0
}

# ── GNOME keybinding helpers (pure bash, no python) ──
ws_dir() {  # ws_dir <binding> <var> — var=left|right if binding is Super+Ctrl+arrow, else ""
        local -n _dir=$2
        local b=${1,,} m ctrl=0 super=0 other=0 re='^<([a-z0-9_]+)>(.*)$'
        _dir=

        while [[ $b =~ $re ]]; do
            m=${BASH_REMATCH[1]}
            b=${BASH_REMATCH[2]}
            case $m in
                primary|ctrl|control) ctrl=1 ;;
                super)                super=1 ;;
                *)                    other=1 ;;
            esac
        done

        if (( ctrl && super && !other )) && [[ $b == left || $b == right ]]; then
            _dir=$b
        fi

        return 0
}

parse_list() {  # parse_list <gvariant> <array> — "['a', 'b']" → (a b); non-lists → return 1
        local v=$1 sep="', '"
        local -n _items=$2
        _items=()
        v=${v#@as }

        [[ $v == '['*']' ]] || return 1

        v=${v:1:${#v}-2}

        [[ -z $v ]] && return 0

        [[ $v == "'"*"'" && $v != *'"'* ]] || return 1

        v=${v:1:${#v}-2}

        while [[ $v == *"$sep"* ]]; do
            _items+=("${v%%"$sep"*}")
            v=${v#*"$sep"}
        done

        _items+=("$v")
}

fmt_list() {  # fmt_list <var> <items...> — bash args → "['a', 'b']"
        local -n _gv=$1
        local item out=
        shift

        for item in "$@"; do
            out+="${out:+, }'$item'"
        done

        _gv="[$out]"
}

gs_put() {  # gs_put <schema> <key> <items...>
        local schema=$1 key=$2 gv
        shift 2
        fmt_list gv "$@"
        printf '      %s %s = %s\n' "$schema" "$key" "$gv"
        run gsettings set "$schema" "$key" "$gv"
}

# ───────────────────────── modules ─────────────────────────
mod_deps() {
        log "apt packages (incl. ripgrep)"

        if ! grep -rqsw universe /etc/apt/sources.list /etc/apt/sources.list.d/; then
            log "  enabling the universe repository"
            run sudo apt-get install -y -qq software-properties-common
            run sudo add-apt-repository -y universe
            APT_READY=0
        fi

        apt_refresh

        # 7zip on 24.04+, p7zip-full before — `: value` then "$_" picks it
        if apt_has 7zip; then : 7zip; else : p7zip-full; fi
        apt_install "${APT_PKGS[@]}" "$_"
}

mod_zsh() {
        local pwline bak zsh_path=/usr/bin/zsh
        log "zshrc + zsh as login shell"
        has zsh || apt_install zsh
        await zshrc "$ZSHRC_URL"

        if has zsh; then
            zsh -n "$WORK/zshrc" || die "downloaded zshrc has a syntax error — not installing"
        else
            warn "  zsh not installed yet (dry run) — syntax check skipped"
        fi

        if [[ -f $HOME/.zshrc ]] && cmp -s "$WORK/zshrc" "$HOME/.zshrc"; then
            log "  ~/.zshrc already up to date"
        else
            if [[ -f $HOME/.zshrc ]]; then
                stamp bak
                bak="$HOME/.zshrc.bak.$bak"
                run cp -a -- "$HOME/.zshrc" "$bak"
                did "  backed up old ~/.zshrc → $bak"
            fi

            run install -m 0644 -- "$WORK/zshrc" "$HOME/.zshrc"
            did "  installed ~/.zshrc"
        fi

        run mkdir -p -- "$HOME/.cache"                      # zshrc writes compdump here

        [[ -f $HOME/.zshrc.local ]] || run install -m 0600 /dev/null "$HOME/.zshrc.local"
        capture pwline getent passwd "$USER" || die "can't look up user $USER"

        if [[ ${pwline##*:} != */zsh ]]; then
            hash zsh 2> /dev/null && zsh_path=${BASH_CMDS[zsh]}
            run sudo chsh -s "$zsh_path" "$USER"
            did "  login shell → zsh"
        fi

        return 0
}

mod_fff() {
        log "fff → /usr/local/bin/fff"
        await fff "$FFF_URL"
        bash -n "$WORK/fff" || die "downloaded fff has a syntax error — not installing"

        if cmp -s "$WORK/fff" /usr/local/bin/fff; then
            log "  already up to date"
        else
            run sudo install -m 0755 -- "$WORK/fff" /usr/local/bin/fff
            did "  installed"
        fi

        return 0
}

mod_fastfetch() {
        local tag=$FASTFETCH_TAG line have jobs
        local src=$WORK/fastfetch logf=$WORK/fastfetch-build.log
        log "fastfetch (build from source → /usr/local/bin)"
        has git || apt_install git

        if [[ $tag == latest ]]; then
            capture line git ls-remote --tags --refs --sort=-v:refname "$FASTFETCH_REPO" 'refs/tags/[0-9]*' \
                || die "can't reach $FASTFETCH_REPO"
            tag=${line##*refs/tags/}
            [[ -n $tag ]] || die "no fastfetch release tags found"
        fi

        capture have /usr/local/bin/fastfetch --version || :
        if [[ $have == "fastfetch $tag "* ]]; then
            log "  $tag already installed"
            return 0
        fi

        log "  building $tag"
        if [[ ${DRY_RUN:-0} == 1 ]]; then
            apt_install "${FASTFETCH_BUILD_PKGS[@]}" "${FASTFETCH_OPT_PKGS[@]}"
            run git clone --depth 1 --branch "$tag" "$FASTFETCH_REPO" "$src"
            run cmake -S "$src" -B "$src/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local
            run cmake --build "$src/build" --parallel
            run sudo cmake --install "$src/build"
            return 0
        fi

        # clone in the background while apt installs the build dependencies
        git -c advice.detachedHead=false clone -q --depth 1 --branch "$tag" "$FASTFETCH_REPO" "$src" &
        BG_PID[fastfetch-clone]=$!
        apt_install "${FASTFETCH_BUILD_PKGS[@]}" "${FASTFETCH_OPT_PKGS[@]}"
        wait "${BG_PID[fastfetch-clone]}" || die "git clone of fastfetch $tag failed"
        unset 'BG_PID[fastfetch-clone]'
        cpus jobs
        log "  compiling with $jobs jobs"

        if ! cmake -S "$src" -B "$src/build" -DCMAKE_BUILD_TYPE=Release \
                -DCMAKE_INSTALL_PREFIX=/usr/local > "$logf" 2>&1 \
            || ! cmake --build "$src/build" --parallel "$jobs" >> "$logf" 2>&1; then
            tail -n 25 "$logf" >&2
            cp -- "$logf" "$HOME/fastfetch-build.log"
            die "fastfetch build failed — full log: ~/fastfetch-build.log"
        fi

        sudo cmake --install "$src/build" > /dev/null
        capture have /usr/local/bin/fastfetch --version || :
        log "  installed: $have"
}

mod_keys() {
        local line schema key val b dir hit target want
        local -a items keep
        log "workspace keys: Win+Ctrl+← / Win+Ctrl+→"

        if ! has gsettings; then
            warn "  gsettings not found — not a GNOME desktop, skipping"
            return 0
        fi

        gsettings list-schemas > "$WORK/schemas"
        if ! grep -qxF "$WM_SCHEMA" "$WORK/schemas"; then
            warn "  GNOME keybinding schema missing — skipping"
            return 0
        fi

        # gsettings needs the desktop's session bus; without it, changes are silently lost
        if [[ -z ${DBUS_SESSION_BUS_ADDRESS:-} && -S /run/user/$UID/bus ]]; then
            export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$UID/bus"
        fi

        if [[ -z ${DBUS_SESSION_BUS_ADDRESS:-} ]]; then
            warn "  no desktop session bus — log into the desktop and re-run: $0 keys"
            return 0
        fi

        # 1) strip Super+Ctrl+←/→ from any other action that already uses it
        gsettings list-recursively > "$WORK/gsettings"

        while IFS= read -r line; do
            [[ $line == *[Ll]eft* || $line == *[Rr]ight* ]] || continue   # cheap prefilter
            schema=${line%% *}
            line=${line#* }
            key=${line%% *}
            val=${line#* }
            if [[ $schema == "$WM_SCHEMA" ]]; then
                [[ $key == switch-to-workspace-left || $key == switch-to-workspace-right ]] && continue
            fi

            parse_list "$val" items || continue
            keep=()
            hit=0

            for b in "${items[@]}"; do
                ws_dir "$b" dir
                if [[ -n $dir ]]; then
                    hit=1
                else
                    keep+=("$b")
                fi
            done
            (( hit )) || continue
            warn "  conflict: $schema $key also used it — removing"
            gs_put "$schema" "$key" "${keep[@]}"
        done < "$WORK/gsettings"

        # 2) add the combos to workspace left/right, keeping existing bindings
        for target in "left:$WS_LEFT" "right:$WS_RIGHT"; do
            want=${target#*:}
            target=${target%%:*}
            key=switch-to-workspace-$target
            capture val gsettings get "$WM_SCHEMA" "$key" || die "gsettings get $key failed"
            parse_list "$val" items || items=()
            hit=0
            for b in "${items[@]}"; do
                ws_dir "$b" dir
                if [[ $dir == "$target" ]]; then
                    hit=1
                fi
            done

            if (( hit )); then
                printf '      %s: already bound to %s\n' "$key" "$want"
            else
                gs_put "$WM_SCHEMA" "$key" "$want" "${items[@]}"
            fi
        done

        return 0
}

mod_nvim() {
        local cfg=${XDG_CONFIG_HOME:-$HOME/.config}/nvim origin bak
        local installer=$WORK/install-fast-improved.sh
        log "neovim + config (your installer — interactive)"

        if [[ ${FORCE:-0} != 1 ]] && has nvim; then
            capture origin git -C "$cfg" remote get-url origin || :
            if [[ $origin == *LinuxUser255/nvim* ]]; then
                log "  already installed (FORCE=1 to re-run the installer)"
                return 0
            fi
        fi

        if [[ ${DRY_RUN:-0} != 1 ]] && ! { : < /dev/tty; } 2> /dev/null; then
            die "the nvim installer is interactive — run from a terminal (over SSH: ssh -t)"
        fi

        await install-fast-improved.sh "$NVIM_INSTALLER_URL"
        bash -n "$installer" || die "nvim installer has a syntax error"

        # the installer runs: rm -rf ~/.config/nvim ~/.local/share/nvim
        if [[ -e $cfg ]]; then
            stamp bak
            run cp -a -- "$cfg" "$cfg.bak.$bak"
            did "  backed up $cfg → $cfg.bak.$bak"
        fi

        chmod +x "$installer"
        warn "  it will ask: install? → Enter/yes | remove existing nvim? → your choice"
        warn "  it also runs 'apt full-upgrade' and builds Neovim from source (several minutes)"

        if [[ ${DRY_RUN:-0} == 1 ]]; then
            run "$installer"
        else
            "$installer" < /dev/tty      # it cd's into its own build dir; no cd needed here
        fi

        return 0
}

# ───────────────────────── main ─────────────────────────
main() {
        local m list
        local -a sel
        case ${1:-} in
            -h|--help) usage; return 0 ;;
        esac
        (( EUID != 0 )) || die "run as your user, not root (sudo is used where needed)"
        sel=("$@")
        (( ${#sel[@]} )) || sel=("${MODULES[@]}")
        for m in "${sel[@]}"; do
            if ! declare -F "mod_$m" > /dev/null; then
                printf -v list '%s ' "${MODULES[@]}"
                die "unknown module '$m' (modules: ${list% })"
            fi
        done
        grep -qs '^ID=ubuntu' /etc/os-release || warn "this isn't Ubuntu — continuing anyway"
        mkdir -m 0700 -- "$WORK" || die "can't create $WORK"
        trap cleanup EXIT
        [[ -n ${USER:-} ]] || capture USER id -un

        # start downloads now; they finish in the background while apt runs
        for m in "${sel[@]}"; do
            case $m in
                zsh)  prefetch zshrc "$ZSHRC_URL" ;;
                fff)  prefetch fff "$FFF_URL" ;;
                nvim) prefetch install-fast-improved.sh "$NVIM_INSTALLER_URL" ;;
            esac
        done

        [[ ${DRY_RUN:-0} == 1 ]] || sudo -v
        for m in "${sel[@]}"; do
            "mod_$m"
        done

        log "done — log out and back in so zsh becomes your login shell; open nvim once to install plugins"
}

main "$@"
