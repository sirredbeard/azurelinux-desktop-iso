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
dnf5 install -y --refresh \
    kernel azurelinux-desktop-policy \
    | tee "$LOG_DIR/usbhid-kmod-resolve.log"
grep -Fq "azurelinux-desktop-policy" "$LOG_DIR/usbhid-kmod-resolve.log"
grep -Fq "azurelinux-desktop-usbhid-kmod" "$LOG_DIR/usbhid-kmod-resolve.log"
kver="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}' kernel-core)"
test -f "/usr/lib/modules/$kver/extra/azurelinux-desktop/usbhid.ko"
modinfo -F vermagic "/usr/lib/modules/$kver/extra/azurelinux-desktop/usbhid.ko" \
    | grep -Fq "$kver"
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
assert_rpm_source gnome-backgrounds '.fc43'
assert_rpm_source gnome-terminal '.fc43'
test -s /etc/dconf/db/local
DCONF_PROFILE=user dconf read /org/gnome/desktop/background/picture-uri-dark \
    | grep -Fq "file:///usr/share/backgrounds/azurelinux/adwaita-d.jpg"
test -x /usr/local/bin/azl-powershell-terminal
test -f /usr/share/applications/org.azurelinux.PowerShell.desktop
grep -Fxq 'StartupWMClass=org.azurelinux.PowerShell' /usr/share/applications/org.azurelinux.PowerShell.desktop

{
    echo '=== RPM versions ==='
    rpm -q \
        ovfenv telegraf dconf-editor gnome-sudoku python3-idle gnome-backgrounds gnome-terminal \
        microsoft-edge-canary code-insiders gh github-desktop github \
        powershell dotnet-sdk-11.0 dotnet-runtime-11.0 dnf5 flatpak
    echo
    echo '=== Side-loaded command versions ==='
    timeout 20 copilot --version </dev/null || echo 'copilot --version timed out or failed'
    timeout 20 edit --version </dev/null || echo 'edit --version timed out or failed'
} | tee "$LOG_DIR/software-versions.log"

flatpak remote-add --system --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo
if flatpak install --system --noninteractive -y flathub \
    org.mozilla.firefox com.github.tchx84.Flatseal org.gnome.Polari \
    | tee "$LOG_DIR/flatpak-install.log"; then
    flatpak list --system --app --columns=application,version,origin \
        | tee "$LOG_DIR/flatpak-versions.log"
else
    echo "WARN: flatpak install failed in hybrid container test environment; keeping repo-origin checks as authoritative for this run." \
        | tee "$LOG_DIR/flatpak-install-warning.log"
fi
