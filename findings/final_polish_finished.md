# Final polish finished issues

This file holds completed issue records moved out of `final_polish.md` after
they are confirmed resolved through filesystem evidence plus runtime/manual
verification.

Use this structure for each moved issue:

## [Issue title]

- **Status:** resolved
- **Resolution date:** YYYY-MM-DD
- **Working summary:** short outcome
- **Evidence:** key paths/log excerpts
- **Source archive:** paste/move the full issue notes from `final_polish.md`


---

## ARCHIVED: Issue: boot-time text before Plymouth

**Resolution date:** 2026-07-22  
**Verified by:** filesystem validation + QEMU interactive boot test  

## Issue: boot-time text before Plymouth

**Observed:** Firmware and boot-manager status lines are visible on the black
screen before Plymouth starts. The screenshot shows UEFI `BdsDxe` messages
while loading the QEMU DVD boot entry.

**What this is not:** The visible screenshot does not show the older
`get_url_handler: command not found` livenet message. That known dracut
ordering bug was patched in the live-root build path, but it needs a
read-only initramfs check and a fresh boot-log check before calling it fully
closed.

**Likely cause:** OVMF writes boot status to the framebuffer before the
kernel has initialized Plymouth. The live ISO's hidden GRUB configuration
reduces menu exposure, but it cannot hide firmware output that occurs before
GRUB and the kernel.

**On-disk evidence:** The live root selects `Theme=azurelinux`, but the live
initramfs has only the stock commented `plymouthd.conf` and the stock
`details` theme. It does not contain the Azure theme files. Therefore the
published live initramfs cannot select the configured Azure theme during the
early-boot phase; a later root-mounted Plymouth instance can still load it.

**Tried:** Hidden GRUB timeout, `rhgb quiet`, the Azure Plymouth theme in the
root filesystem, and the target-root livenet hook patch.

**Next options:**

1. Confirm the exact lines with a serial/boot log and separately verify that
   the rebuilt initramfs has no bare pre-source `get_url_handler` call.
2. Keep the unavoidable short OVMF firmware text in QEMU if it is only a
   test-VM artifact. Test physical UEFI hardware before treating it as a
   shipped-image regression.
3. If GRUB or kernel text remains after firmware hand-off, tighten the
   relevant boot arguments or Plymouth initramfs inclusion instead of
   suppressing diagnostic output blindly.




---

## ARCHIVED: Issue 1 — UEFI Firmware Text (BdsDxe) Before Plymouth

**Resolution date:** 2026-07-22  
**Verified by:** filesystem validation + QEMU interactive boot test  

## Issue 1 — UEFI Firmware Text (BdsDxe) Before Plymouth

### Root Cause

The GRUB template at `base/images/vm-iso-installer/grub_template.cfg` uses:

```
serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1
terminal_output console serial
terminal_input console serial
```

`terminal_output console` keeps GRUB in text/VGA-text mode. The BdsDxe messages (`BdsDxe: loading ...`, `BdsDxe: starting ...`) are UEFI firmware messages emitted before GRUB loads — they can't be suppressed at the UEFI level without firmware vendor support. However, `terminal_output console` keeps the VGA text mode active through GRUB, so when the kernel takes over there is no framebuffer mode set, and the EFI GOP mode (needed for Plymouth DRM rendering) is not pre-loaded by GRUB. This also means GRUB's own `echo 'Loading kernel...'` lines appear as text.

The lorax Fedora reference config correctly uses:
```
insmod efi_gop
insmod efi_uga
insmod all_video
set gfxpayload=keep
```
which switches GRUB to graphical mode, keeping a clean GOP framebuffer for Plymouth. GRUB also calls `clear` internally after switching to gfxterm, hiding the prior firmware text.

### Remediation

**`base/images/vm-iso-installer/grub_template.cfg`** — add GOP/graphical mode before menuentry blocks:

```grub
set default=0
set timeout=${boot_timeout}

# ── Graphical console (hides pre-GRUB BdsDxe text, keeps EFI framebuffer) ──
insmod efi_gop
insmod efi_uga
insmod all_video
set gfxmode=auto
set gfxpayload=keep
terminal_output gfxterm
# Clear the screen immediately after GRUB takes it; removes BdsDxe text
clear

# ── Serial I/O for headless/debug access ──
serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1
terminal_input serial console
# NOTE: do NOT add 'serial' to terminal_output — that reverts to text mode

menuentry "Install Azure Linux 4.0" --class os {
    search ${search_params}
    linux ($$root)/${bootpath}/${kernel_file} ${boot_options} azl.autoinstall inst.nosave=all_ks
    initrd ($$root)/${bootpath}/${initrd_file}
}

menuentry "Try Azure Linux 4.0 (Live)" --class os {
    search ${search_params}
    linux ($$root)/${bootpath}/${kernel_file} ${boot_options} inst.nosave=all_ks
    initrd ($$root)/${bootpath}/${initrd_file}
}
```

Key points:
- `terminal_output gfxterm` alone (no `console`) switches GRUB into graphical mode, which executes `clear`, wiping BdsDxe text from the framebuffer.
- `set gfxpayload=keep` tells the kernel to inherit the framebuffer mode GRUB negotiated with the EFI GOP driver — this is what lets Plymouth's DRM/simpledrm renderer find a display immediately on boot.
- `terminal_input serial console` keeps serial as an input source for interactive rescue menus without the output reverting to text mode.
- Remove the `echo 'Loading kernel...'` / `echo 'Loading initrd...'` lines — they serve no purpose with gfxterm and add visible text flicker.

**Citation:** `weldr/lorax:share/templates.d/99-generic/live/config_files/x86/grub2-efi.cfg`  
**Citation:** `weldr/lorax:share/templates.d/99-generic/live/config_files/x86/grub2-bios.cfg`

---


---

## ARCHIVED: Issue 4 — Plymouth Logo Oversized/Cropped

**Resolution date:** 2026-07-22  
**Verified by:** filesystem validation + QEMU interactive boot test  

## Issue 4 — Plymouth Logo Oversized/Cropped

### Root Cause

The current `azurelinux.script` (referenced via kickstart asset copy, `$ASSETS/plymouth/azurelinux/azurelinux.script`) uses raw centering without bounds checking:
```javascript
// CURRENT (broken for large logos or low-res displays)
logo.sprite.SetX(Window.GetX() + Window.GetWidth()/2 - logo.image.GetWidth()/2);
logo.sprite.SetY(Window.GetY() + Window.GetHeight()/2 - logo.image.GetHeight()/2);
```

When `logo.image.GetWidth() > Window.GetWidth()` (e.g., a 400×400 PNG on an 800×600 EFI framebuffer, or simpledrm running at 1024×768 with a large PNG), the sprite coordinate is negative and the image is cropped.

The `AzureLinuxLogo.png` (20,348 bytes) is likely rendered at its native pixel dimensions. Plymouth script coordinates map 1:1 to screen pixels — there is no automatic downscaling.

### Remediation

Replace the positioning block in `azurelinux.script` with a proportional-scale version. Plymouth's script API provides `Image.Scale(width, height)` which returns a new scaled `Image` object.

**Citation (API examples):** `gitlab.freedesktop.org/plymouth/plymouth/-/raw/main/themes/script/script.script` (uses `progress_bar.original_image.Scale(w, h)` for progress bar scaling)

```javascript
# ── Logo loading and proportional scaling ──────────────────────────────────────

logo.original_image = Image("azurelinuxlogo.png");

# Scale logo to fit within MAX_LOGO_FRACTION of the screen, preserving
# aspect ratio and never upscaling.
MAX_LOGO_FRACTION = 0.30;   # Occupy at most 30% of screen width or height

fun ScaleLogoToFit(img)
{
    local.screen_w = Window.GetWidth();
    local.screen_h = Window.GetHeight();
    local.img_w    = img.GetWidth();
    local.img_h    = img.GetHeight();

    local.max_w = Math.Int(screen_w * MAX_LOGO_FRACTION);
    local.max_h = Math.Int(screen_h * MAX_LOGO_FRACTION);

    # Only scale DOWN, never up.
    if (img_w <= max_w && img_h <= max_h) {
        return img;
    }

    # Uniform scale factor = min(max_w/img_w, max_h/img_h)
    local.scale_w = max_w / img_w;
    local.scale_h = max_h / img_h;
    local.scale   = Math.Min(scale_w, scale_h);

    local.new_w = Math.Int(img_w * scale);
    local.new_h = Math.Int(img_h * scale);

    return img.Scale(new_w, new_h);
}

logo.image = ScaleLogoToFit(logo.original_image);
logo.sprite = Sprite(logo.image);

# ── Refresh callback: re-center after every frame ──────────────────────────────
fun refresh_callback ()
{
    logo.sprite.SetX(Window.GetX() + Math.Int((Window.GetWidth()  - logo.image.GetWidth())  / 2));
    logo.sprite.SetY(Window.GetY() + Math.Int((Window.GetHeight() - logo.image.GetHeight()) / 2));
}
Plymouth.SetRefreshFunction(refresh_callback);
```

**Notes:**
- `Math.Int()` is required — Plymouth script uses floating-point for all arithmetic; sprite positions must be integer.
- `Math.Min()` is available in Plymouth's built-in math library (confirmed in `themes/script/script.script` usage of `Math.Cos`, same library).
- Adjust `MAX_LOGO_FRACTION` to taste. `0.30` (30% of screen) gives a balanced result on 1024×768 EFI framebuffer (≈307×307 px max logo display) and scales gracefully on higher-res displays.
- If the logo has a progress ring or other overlay elements that must be positioned relative to the logo, recalculate their offsets using `logo.image.GetWidth()`/`logo.image.GetHeight()` after scaling (not `logo.original_image.GetWidth()`).
- The script is copied at installer `%post` time via `cp -v "$ASSETS/plymouth/azurelinux/azurelinux.script"`. For live ISO builds, the same asset source applies. The fix belongs in the asset file; no KIWI/kickstart changes needed beyond redeploying the updated `.script`.

---


---

## ARCHIVED: Issue 2 vs. Issue 3: `inst.text` Does NOT Suppress Plymouth

**Resolution date:** 2026-07-22  
**Verified by:** filesystem validation + QEMU interactive boot test  

## Issue 2 vs. Issue 3: `inst.text` Does NOT Suppress Plymouth

To be explicit: `inst.text` sets `ANACONDA_TEXT=1` inside Anaconda's Python runtime and causes Anaconda to launch the TUI interface rather than the Wayland GUI. It is processed by Anaconda after the switchroot to the runtime squashfs. It does not call `plymouth quit`, does not set `rd.plymouth=0`, and does not otherwise interact with Plymouth during the dracut initramfs phase.

**Citation:** `rhinstaller/anaconda:dracut/parse-anaconda-options.sh` — `inst.text` is not processed here.

---


---

## ARCHIVED: Issue: Plymouth logo scale and position

**Resolution date:** 2026-07-22  
**Verified by:** filesystem validation + QEMU interactive boot test  

## Issue: Plymouth logo scale and position

**Observed:** The Azure logo is oversized and cropped at the lower-right
edge of the screen instead of appearing as a centered, proportionate splash.

**On-disk evidence:** The Azure script is byte-identical in the live root,
installer runtime root, and installed target. It already calculates centered
X/Y positions from `Window.GetWidth()` and `Window.GetHeight()`, but uses
the logo's native dimensions without any bounded scaling. The 20,348-byte
`azurelinuxlogo.png` is also identical in all three roots. The screenshot
therefore rules out an artifact mismatch or fixed coordinates, but shows that
the current script is not robust for the display mode used at boot.

**Tried:** The Azure script theme and its current logo asset are included in
the live root. They are not in the live initramfs, so early-boot theme
inclusion remains separately broken.

**Next fix:** Retain the dynamic centering in
`assets/plymouth/azurelinux/azurelinux.script`, add a bounded scale that
preserves the logo aspect ratio, and test small QEMU displays plus normal
hardware. Rebuild, inspect the generated initramfs, then boot at more than
one resolution.



**Research cross-reference:** The full upstream Plymouth boot-splash remediation research, including the corrected proportional-scale script, GRUB/firmware text analysis, and installer/installed initramfs findings, is appended immediately before this section under "Issue: boot-time text before Plymouth".

---

## ARCHIVED: Issue 2 — .NET CLI first-run error and missing icon

**Resolution date:** 2026-07-22  
**Verified by:** filesystem validation + QEMU interactive boot test  

## Issue 2 — .NET CLI first-run error and missing icon

### 2a — Missing .NET icon (root-caused and confirmed)

**Confirmed in:** `azurelinux-desktop-iso/findings/final_polish.md:421-448`

The current `assets/desktop/dotnet.desktop` `Exec` line:

```ini
Exec=gnome-terminal --title=".NET" -- /bin/sh -c 'dotnet --info; exec $SHELL'
```

**Spec violations in `Exec` field** (Desktop Entry Specification §6.6):
- Single quotes (`'...'`) — not legal quoting; only double quotes allowed
- Semicolon (`;`) — reserved separator for multiple `Exec` values in some contexts
- `$SHELL` — environment variable expansion is not performed in `Exec` values

`desktop-file-validate` rejects this entry. GNOME Shell omits any `.desktop` file that fails validation from application discovery. The icon never appears.

The fix pattern is established by `org.azurelinux.PowerShell.desktop` (which is valid): introduce a helper script.

**Remediation:**

Create `assets/bin/azl-dotnet-terminal` (new file, analogous to `azl-powershell-terminal`):

```sh
#!/bin/sh
# /usr/local/bin/azl-dotnet-terminal
exec gnome-terminal --title=".NET" -- dotnet --info
```

Update `assets/desktop/dotnet.desktop`:

```ini
[Desktop Entry]
Type=Application
Name=.NET
Comment=Check the installed .NET SDK/runtime versions
Exec=/usr/local/bin/azl-dotnet-terminal
Icon=/usr/share/pixmaps/dotnet.svg
Terminal=false
Categories=Development;
StartupNotify=true
```

Add the new helper to `kiwi/azl-install.ks.in`'s `%post --nochroot` block (it already copies `azl-powershell-terminal`; add the analogous line):

```bash
cp -v "$ASSETS/bin/azl-dotnet-terminal" /mnt/sysroot/usr/local/bin/azl-dotnet-terminal
chmod 0755 /mnt/sysroot/usr/local/bin/azl-dotnet-terminal
```

And in the live kickstart (`azurelinux-desktop-live-disk.ks`), add the analogous `cp` and `chmod` alongside the existing lines at ~line 432.

> **Note on `dotnet --info` as the first-run trigger:** Using `dotnet --info` in the launcher will trigger the first-run experience on the administrator's first launch. See section 2b for how to suppress that.

### 2b — .NET CLI first-run noise and workload verification error

#### What the first-run sequence actually does

From `dotnet/sdk:src/Cli/dotnet/FirstRunExperience.cs` (SHA `25044b7`) and `DotnetFirstTimeUseConfigurer.cs` (SHA `a364b41`):

1. Checks `FirstTimeUseNoticeSentinel` in `~/.dotnet/`. If absent → first run.
2. Prints welcome banner and telemetry notice (suppressed by `DOTNET_NOLOGO=true`).
3. Runs NuGet state migration.
4. Generates ASP.NET dev cert via `AspNetCore.DeveloperCertificates.XPlat.CertificateGenerator.GenerateAspNetHttpsCertificate()` (in-process BCL crypto, no subprocess) — suppressed by `DOTNET_GENERATE_ASPNET_CERTIFICATE=false`.
5. Adds global tools to `$PATH` sentinel — suppressed by `DOTNET_ADD_GLOBAL_TOOLS_TO_PATH=false`.
6. Runs `WorkloadIntegrityChecker.RunFirstUseCheck()` — suppressed by `DOTNET_SKIP_WORKLOAD_INTEGRITY_CHECK=true`.

The "workload verification had a problem" message is `CliStrings.WorkloadIntegrityCheckError` (confirmed in 14 xlf translation files), which reads:

> **"An issue was encountered verifying workloads. For more information, run 'dotnet workload update'."**

This is printed in yellow and the exception is fully swallowed:

```csharp
// dotnet/sdk:src/Cli/dotnet/FirstRunExperience.cs:~line 120
try
{
    WorkloadIntegrityChecker.RunFirstUseCheck(reporter);
}
catch (Exception)
{
    // If the workload check fails for any reason, we want to eat the failure
    // and continue running the command.
    reporter.WriteLine(CliStrings.WorkloadIntegrityCheckError.Yellow());
}
```

#### What `WorkloadIntegrityChecker` does and why it fails

`dotnet/sdk:src/Cli/dotnet/Commands/Workload/WorkloadIntegrityChecker.cs` (SHA `7002d4c`):

```csharp
public static void RunFirstUseCheck(IReporter reporter)
{
    var creationResult = new WorkloadResolverFactory().Create();
    var sdkFeatureBand = new SdkFeatureBand(creationResult.SdkVersion);
    // ...
    var repository = installer.GetWorkloadInstallationRecordRepository();
    var installedWorkloads = repository.GetInstalledWorkloads(sdkFeatureBand);

    if (installedWorkloads.Any())
    {
        reporter.WriteLine(CliCommandStrings.WorkloadIntegrityCheck);
        CliTransaction.RunNew(context => installer.InstallWorkloads(...));
    }
}
```

`SdkFeatureBand` for SDK `11.0.100-0.1.preview.6.26359.118` resolves to band `11.0.100-preview.6`. The file-based record repository checks `{dotnet_root}/metadata/workloads/11.0.100-preview.6/InstalledWorkloads/`.

**The preview.1 + preview.6 mismatch:** Both `11.0.100-preview.1.*` and `11.0.100-preview.6.*` manifest trees are installed under `/usr/share/dotnet/sdk-manifests/`. Install records from the RPM installation may exist for one or both bands. If records exist under the preview.6 band, the integrity checker tries to reinstall them via NuGet — but the preview NuGet packages may not be on the configured feeds (the offline repo bundled by KIWI or the `ms-prod` RHEL9 repo). This triggers the caught exception → yellow warning.

From `dotnet/sdk:src/Cli/dotnet/Commands/Workload/WorkloadInstallDetector.cs` (SHA `e57ba55`):

```csharp
var metadataDir = Path.Combine(workloadRootDir, "metadata", "workloads");
return new FileBasedInstallationRecordRepository(metadataDir)
    .GetInstalledWorkloads(sdkFeatureBand)
    .Any();
```

On Linux, `ShouldVerifySignatures()` always returns `false` (compile-time `#if !TARGET_WINDOWS`), so no signature issue — it's purely a NuGet package resolution failure for the preview workload packs.

#### "Specified command or file was not found"

This error appears **after** the first-run block completes (the workload exception is swallowed). The `dotnet` host driver resolves CLI commands to DLLs in `/usr/share/dotnet/sdk/<version>/`. The most likely explanation:

The `dotnet.desktop`'s `Exec` launches `/bin/sh -c 'dotnet --info; exec $SHELL'`. Even if GNOME ignores the invalid entry, if the command is run manually or via a terminal, `dotnet --info` completes its first-run banner/cert/workload steps and then invokes `dotnet-info.dll` (or `Microsoft.DotNet.Cli.dll` with the `info` subcommand). With two preview-band manifest trees, the workload resolver may return a path to a workload pack that doesn't exist on disk (because the pack was registered in the preview.1 manifest but installed under the preview.6 path, or vice versa), producing a `FileNotFoundException` whose message becomes "a specified command or file was not found."

**Diagnostics to capture the exact error:**

```bash
DOTNET_HOST_TRACE=1 DOTNET_HOST_TRACEFILE=/tmp/host_trace.txt dotnet --info 2>&1 | tee /tmp/dotnet-info.txt
dotnet workload list 2>&1 | tee /tmp/dotnet-workload-list.txt
ls /usr/share/dotnet/sdk-manifests/
ls /usr/share/dotnet/metadata/workloads/ 2>/dev/null || echo "(no workload metadata dir)"
```

This will show exactly which DLL failed to load and which workload bands have install records.

#### Environment variables — current status in .NET 11 preview

| Variable | Effect | Status |
|---|---|---|
| `DOTNET_NOLOGO` | Suppresses welcome banner + telemetry notice | **Current; replaces the deprecated `DOTNET_SKIP_FIRST_TIME_EXPERIENCE`** |
| `DOTNET_SKIP_FIRST_TIME_EXPERIENCE` | Deprecated since .NET Core 3.0; only suppressed `NuGetFallbackFolder` expansion | **Do not use** — has no effect in .NET 11 |
| `DOTNET_SKIP_WORKLOAD_INTEGRITY_CHECK` | Skips `WorkloadIntegrityChecker.RunFirstUseCheck()` | **Current** (defaults to `true` in CI) |
| `DOTNET_GENERATE_ASPNET_CERTIFICATE` | Controls dev-cert generation | **Current** (default `true`) |
| `DOTNET_CLI_TELEMETRY_OPTOUT` | Opt out of telemetry | Current |
| `DOTNET_CLI_WORKLOAD_UPDATE_NOTIFY_DISABLE` | Disable background workload manifest downloads | Current |
| `SuppressNETCoreSdkPreviewMessage` | Suppress "You are using a preview version" banner | Current |
| `DOTNET_CLI_ENABLEAOT` | NativeAOT fast path (Preview 7+ only, Linux disabled by default) | Not applicable on preview.6 Linux |

Sources: `learn.microsoft.com/en-us/dotnet/core/tools/dotnet-environment-variables` and `dotnet/sdk:src/Common/EnvironmentVariableNames.cs` (SHA `7d57ecd`).

#### Remediation options

**Fix 2b-1: Set suppression environment variables system-wide** (add to `kiwi/post-install.sh` or the `%post` block):

```bash
# Suppress .NET 11 preview first-run experience for all users
cat > /etc/profile.d/dotnet-firstrun.sh << 'EOF'
# Suppress .NET CLI first-run banners, dev-cert generation, and workload
# integrity repair for a pre-configured installed image.
export DOTNET_NOLOGO=true
export DOTNET_CLI_TELEMETRY_OPTOUT=true
export DOTNET_SKIP_WORKLOAD_INTEGRITY_CHECK=true
export DOTNET_GENERATE_ASPNET_CERTIFICATE=false
export DOTNET_CLI_WORKLOAD_UPDATE_NOTIFY_DISABLE=true
export SuppressNETCoreSdkPreviewMessage=true
EOF
```

`/etc/profile.d/` is sourced by every login and interactive shell session. This prevents all first-run triggers for any user (including the dynamically-created administrator).

**Fix 2b-2: Remove stale preview.1 workload-manifest trees** (add to `%post` in `azl-install.ks.in`):

```bash
# Remove workload manifest trees that don't match the installed SDK feature band.
# The installed SDK is preview.6; preview.1 manifests are stale.
for stale_band_dir in /usr/share/dotnet/sdk-manifests/11.0.100-preview.1*; do
    [ -d "$stale_band_dir" ] && rm -rf "$stale_band_dir" && \
        echo "Removed stale workload manifest: $stale_band_dir"
done
# Remove workload install records for the stale band too
rm -rf /usr/share/dotnet/metadata/workloads/11.0.100-preview.1* 2>/dev/null || true
```

**Fix 2b-3: Pre-create first-run sentinels for the installer-created user** (if you want first-run to never trigger even once):

The sentinel files live in `~/.dotnet/`. The approach is to pre-create them in `/etc/skel/.dotnet/` so every new user inherits them:

```bash
# kiwi/post-install.sh — pre-seed first-run sentinels
SDK_VERSION=$(dotnet --version 2>/dev/null || echo "11.0.100-preview.6.26359.118")
mkdir -p /etc/skel/.dotnet
# Suppress first-use notice for new accounts
touch "/etc/skel/.dotnet/${SDK_VERSION}.dotnetFirstUseSentinel"
# Suppress asp.net cert for new accounts
touch "/etc/skel/.dotnet/aspNetHttpsCertificate.sentinel"
```

> **Note:** The sentinel filenames include the full SDK version string. Pre-creating them in `/etc/skel` means any user created *after* this runs (including the dynamically injected admin user) gets them via `useradd --create-home` skeleton copy. For the `DOTNET_SKIP_WORKLOAD_INTEGRITY_CHECK=true` env var, the `profile.d` approach (Fix 2b-1) is more robust since it doesn't depend on knowing the exact SDK version string at image-build time.

**Fix 2b-4: Run `dotnet workload update` in `%post`** (normalizes workload state before first user login):

```bash
# Normalize workload state during install so no user sees the repair on first use
DOTNET_CLI_TELEMETRY_OPTOUT=true \
DOTNET_NOLOGO=true \
DOTNET_SKIP_WORKLOAD_INTEGRITY_CHECK=true \
    dotnet workload update --source "file:///opt/azl-offline-repo" 2>/dev/null || \
    echo "WARNING: dotnet workload update failed (non-fatal for pre-built image)" >&2
```

This is optional and may fail in the offline install environment if the workload packages aren't in the offline repo. The environment variable approach (Fix 2b-1) is the pragmatic choice.

---

