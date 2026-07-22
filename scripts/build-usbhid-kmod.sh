#!/usr/bin/env bash
# Build an Azure Linux usbhid module RPM for one exact Azure kernel release.
set -euo pipefail

AZL_BASE_URL="${AZL_BASE_URL:-https://packages.microsoft.com/azurelinux/4.0/beta/base/x86_64}"
OUTPUT_DIR="${1:?usage: $0 OUTPUT_DIR [kernel-nevra]}"
REQUESTED_KERNEL="${2:-}"

mkdir -p "$OUTPUT_DIR"

if [[ -n "$REQUESTED_KERNEL" ]]; then
    KERNEL_QUERY=("$REQUESTED_KERNEL")
else
    KERNEL_QUERY=(--latest-limit=1 kernel)
fi

read -r _ KERNEL_VERSION KERNEL_RELEASE KERNEL_ARCH < <(
    dnf5 repoquery --setopt=reposdir=/dev/null \
        --repofrompath=azl-base,"$AZL_BASE_URL" --repo=azl-base \
        --available \
        --qf '%{name}-%{version}-%{release}.%{arch} %{version} %{release} %{arch}' \
        "${KERNEL_QUERY[@]}"
    printf '\n'
)
KERNEL_EVR="${KERNEL_VERSION}-${KERNEL_RELEASE}"
KERNEL_DEVEL_NEVRA="kernel-devel-${KERNEL_EVR}.${KERNEL_ARCH}"

rpm -q "$KERNEL_DEVEL_NEVRA" >/dev/null 2>&1 || dnf5 install -y \
    --setopt=reposdir=/dev/null --setopt=azl-base.gpgcheck=0 \
    --repofrompath=azl-base,"$AZL_BASE_URL" --repo=azl-base \
    "$KERNEL_DEVEL_NEVRA" \
    bc gcc make perl python3 openssl-devel elfutils-devel elfutils-libelf-devel rpm-build kmod git curl

KVERREL="${KERNEL_EVR}.${KERNEL_ARCH}"
BUILD_DIR="/usr/src/kernels/$KVERREL"

test -f "$BUILD_DIR/.config"
test -f "$BUILD_DIR/Module.symvers"

# Azure's kernel component carries its source fourth-version component as
# the first RPM release component (for example, 6.18.31-1.6.azl4 uses the
# rolling-lts/azl4/6.18.31.1 source).
SOURCE_REF="${KERNEL_VERSION}.${KERNEL_RELEASE%%.*}"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
COMPONENT_TOML="$WORKDIR/kernel.comp.toml"
curl --fail --location --retry 3 \
    https://raw.githubusercontent.com/microsoft/azurelinux/4.0/base/comps/kernel/kernel.comp.toml \
    -o "$COMPONENT_TOML"
read -r SOURCE_URL SOURCE_SHA512 < <(
    python3 - "$COMPONENT_TOML" "$SOURCE_REF" <<'PY'
import sys
import tomllib

component_path, source_ref = sys.argv[1:]
with open(component_path, "rb") as component_file:
    component = tomllib.load(component_file)

expected_filename = f"kernel-{source_ref}.tar.gz"
for source in component["components"]["kernel"]["source-files"]:
    if source["filename"] == expected_filename:
        print(source["origin"]["uri"], source["hash"])
        break
else:
    raise SystemExit(f"Azure Linux 4.0 does not define {expected_filename}")
PY
)
test -n "$SOURCE_URL"
test -n "$SOURCE_SHA512"
curl --fail --location --retry 3 "$SOURCE_URL" -o "$WORKDIR/kernel.tar.gz"
printf '%s  %s\n' "$SOURCE_SHA512" "$WORKDIR/kernel.tar.gz" | sha512sum --check
tar -xzf "$WORKDIR/kernel.tar.gz" -C "$WORKDIR"
SOURCE_DIR="$(find "$WORKDIR" -mindepth 1 -maxdepth 1 -type d -name 'CBL-Mariner-Linux-Kernel-*' -print -quit)"
test -n "$SOURCE_DIR"

MODULE_DIR="$WORKDIR/usbhid"
mkdir -p "$MODULE_DIR"
cp "$SOURCE_DIR/drivers/hid/usbhid/hid-core.c" "$MODULE_DIR/"
cp "$SOURCE_DIR/drivers/hid/usbhid/"*.h "$MODULE_DIR/"
cat > "$MODULE_DIR/Makefile" <<'EOF'
obj-m += usbhid.o
usbhid-y := hid-core.o
EOF
make -C "$BUILD_DIR" M="$MODULE_DIR" modules

MODULE="$MODULE_DIR/usbhid.ko"
test -f "$MODULE"
test "$(modinfo -F vermagic "$MODULE" | awk '{print $1}')" = "$KVERREL"

RPMBUILD="$WORKDIR/rpmbuild"
mkdir -p "$RPMBUILD"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
cp "$MODULE" "$RPMBUILD/SOURCES/usbhid.ko"
cat > "$RPMBUILD/SPECS/azurelinux-desktop-usbhid-kmod.spec" <<EOF
Name:           azurelinux-desktop-policy
Version:        ${KERNEL_VERSION}
Release:        ${KERNEL_RELEASE}
Summary:        Exact Azure Linux kernel and USB HID module update policy
License:        GPL-2.0-only
BuildArch:      ${KERNEL_ARCH}
Requires:       kernel-core-uname-r = ${KVERREL}
Requires:       azurelinux-desktop-usbhid-kmod = %{version}-%{release}

%description
Keeps Azure Linux kernel updates paired with their matching USB HID module.

%package -n azurelinux-desktop-usbhid-kmod
Summary:        USB HID transport module for Azure Linux ${KVERREL}
Requires:       kernel-core-uname-r = ${KVERREL}

%description -n azurelinux-desktop-usbhid-kmod
The usbhid module built for Azure Linux kernel ${KVERREL}.

%install
install -Dpm 0644 %{_sourcedir}/usbhid.ko \
  %{buildroot}%{_usr}/lib/modules/${KVERREL}/extra/azurelinux-desktop/usbhid.ko
install -Dpm 0644 /dev/stdin \
  %{buildroot}%{_sysconfdir}/dracut.conf.d/90-azurelinux-desktop-usbhid.conf <<'DRACUT'
add_drivers+=" usbhid "
DRACUT

%post -n azurelinux-desktop-usbhid-kmod
/usr/sbin/depmod -a ${KVERREL} || :
if [ -x /usr/bin/dracut ] && [ -e /boot/initramfs-${KVERREL}.img ]; then
  /usr/bin/dracut --force --kver ${KVERREL} || :
fi

%postun -n azurelinux-desktop-usbhid-kmod
/usr/sbin/depmod -a ${KVERREL} || :

%files

%files -n azurelinux-desktop-usbhid-kmod
%{_usr}/lib/modules/${KVERREL}/extra/azurelinux-desktop/usbhid.ko
%config(noreplace) %{_sysconfdir}/dracut.conf.d/90-azurelinux-desktop-usbhid.conf
EOF

rpmbuild --define "_topdir $RPMBUILD" -bb \
    "$RPMBUILD/SPECS/azurelinux-desktop-usbhid-kmod.spec"
find "$RPMBUILD/RPMS" -type f -name '*.rpm' -exec cp -v {} "$OUTPUT_DIR/" \;
