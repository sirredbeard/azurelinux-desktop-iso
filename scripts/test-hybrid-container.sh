#!/usr/bin/env bash
# Exercise the published hybrid container as a package-source canary.
set -euo pipefail

LOG_DIR="${AZL_HYBRID_TEST_LOG_DIR:-/logs}"
mkdir -p "$LOG_DIR"
exec > >(tee "$LOG_DIR/test-hybrid-container.log") 2>&1

run_dnf() {
    local name="$1"
    shift
    dnf5 "$@" | tee "$LOG_DIR/$name.log"
}

assert_rpm_source() {
    local package="$1"
    local expected_release="$2"
    local release
    release="$(rpm -q --qf '%{RELEASE}\n' "$package")"
    printf '%s %s\n' "$package" "$release" | tee -a "$LOG_DIR/package-origins.log"
    [[ "$release" == *"$expected_release"* ]] || {
        echo "error: $package has release $release, expected $expected_release" >&2
        exit 1
    }
}

dnf5 repolist --enabled | tee "$LOG_DIR/enabled-repositories.log"
run_dnf dnf-update update --refresh -y
run_dnf dnf-upgrade upgrade -y
run_dnf dnf-install-samples install -y \
    ovfenv telegraf \
    dconf-editor gnome-sudoku idle3

: > "$LOG_DIR/package-origins.log"
assert_rpm_source ovfenv '.azl4'
assert_rpm_source telegraf '.azl4'
assert_rpm_source dconf-editor '.fc43'
assert_rpm_source gnome-sudoku '.fc43'
assert_rpm_source python3-idle '.fc43'

{
    echo '=== RPM versions ==='
    rpm -q \
        ovfenv telegraf dconf-editor gnome-sudoku python3-idle \
        microsoft-edge-canary code-insiders gh github-desktop github \
        powershell dotnet-sdk-11.0 dotnet-runtime-11.0 dnf5 flatpak
    echo
    echo '=== Side-loaded command versions ==='
    copilot --version
    edit --version
} | tee "$LOG_DIR/software-versions.log"

flatpak remote-add --system --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --system -y --noninteractive flathub \
    org.mozilla.firefox com.github.tchx84.Flatseal org.gnome.Polari \
    | tee "$LOG_DIR/flatpak-install.log"
flatpak list --system --app --columns=application,version,origin \
    | tee "$LOG_DIR/flatpak-versions.log"
