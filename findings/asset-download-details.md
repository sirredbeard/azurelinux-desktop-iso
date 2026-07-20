# Release asset download details

The README's "How do I use this" section keeps a short quickstart for
`scripts/Get-AzureLinuxDesktop.ps1`. This is the fuller version of
that same material - how the split/manifest/7z packaging actually
works, the full flag reference, and more example invocations - for
anyone who wants the details instead of just the one-liner.

## Why assets are split and 7z-compressed

Every asset here runs well over GitHub's 2 GiB per-asset cap on
releases, so each one ships as a handful of split parts
(`<name>.split.00.part`, `.01.part`, ...) plus a `<name>.sha256`
manifest instead of one file. VHDX, VDI, and VMDK also ship
7z-compressed on top of that - `qemu-img` only supports real
compression for qcow2 (`-c`/`--compress`, zstd here), so the other
three get 7z instead, otherwise VHDX/VDI/VMDK's coarser sparse-block
granularity would make them noticeably bigger downloads for the same
guest data than the split-part count already suggests.

## What the PowerShell script does for you

[`scripts/Get-AzureLinuxDesktop.ps1`](../scripts/Get-AzureLinuxDesktop.ps1)
downloads every part for whichever asset you ask for from the latest
release, reassembles them, checks the result against the manifest, and
- for VHDX/VDI/VMDK - decompresses the reassembled `.7z` into the
actual disk image and deletes the `.7z` once that succeeds. It
downloads with [`aria2c`](https://aria2.github.io/) (15 connections per
file) if it finds it on PATH (`winget install aria2.aria2`, or the
choco/scoop equivalent) - noticeably faster on files this size. If it
doesn't find `aria2c`, it falls back to PowerShell's own
`Invoke-WebRequest` instead of failing outright, and prints a note
telling you it did that and recommending you install `aria2c`. For the
7z step, it looks for a native `7z`/`7zz`/`7za` binary first (on PATH,
or - Windows only - the registry/Program Files locations the official
7-Zip installer doesn't add to PATH by default), and only falls back to
installing the [7Zip4Powershell](https://github.com/thoemmi/7Zip4Powershell)
module from the PowerShell Gallery on Windows if none is found - that
module is a Windows-only wrapper around native 7-Zip DLLs, so on
Linux/macOS with no native `7z` on PATH the script fails outright with
install instructions instead of pretending that module is an option.

## Full flag reference

Flags, all mutually exclusive with each other except
`-OutputDirectory`/`-KeepParts` which combine with any of them:

| Flag | Downloads | Notes |
| --- | --- | --- |
| *(none)* / `-Live` | `azurelinux-desktop-live.iso` | Default if no flag is given |
| `-Install` (alias `-Installer`) | `azurelinux-desktop-install.iso` | Can't combine with `-Kvm`/`-Hyperv`/`-VirtualBox`/`-VMWare` - the installer doesn't ship as a pre-built disk image |
| `-Kvm` | `azurelinux-desktop-live.qcow2` | Bootable live desktop, no install step. Implies the live image |
| `-Hyperv` | `azurelinux-desktop-live.vhdx` | Bootable live desktop, no install step. Implies the live image. Ships 7z-compressed; the script decompresses it for you |
| `-VirtualBox` | `azurelinux-desktop-live.vdi` | Bootable live desktop, no install step. Implies the live image. Converted from the same qcow2 as the others but not boot-tested here - no VirtualBox in this dev environment. Ships 7z-compressed; the script decompresses it for you |
| `-VMWare` | `azurelinux-desktop-live.vmdk` | Bootable live desktop, no install step. Implies the live image. Converted from the same qcow2 as the others but not boot-tested here - no VMware in this dev environment. Ships 7z-compressed; the script decompresses it for you |
| `-OutputDirectory <path>` | - | Where parts and the reassembled file land. Defaults to the current directory |
| `-KeepParts` | - | Keep the downloaded `.part` files instead of deleting them after reassembly. The intermediate `.7z` for VHDX/VDI/VMDK is always deleted once decompression succeeds, regardless of this flag |

## More example invocations

```powershell
.\scripts\Get-AzureLinuxDesktop.ps1               # live ISO (default)
.\scripts\Get-AzureLinuxDesktop.ps1 -Install       # installer ISO (alias: -Installer)
.\scripts\Get-AzureLinuxDesktop.ps1 -Kvm           # live desktop as a bootable qcow2 disk image
.\scripts\Get-AzureLinuxDesktop.ps1 -Hyperv        # live desktop as a bootable VHDX disk image
.\scripts\Get-AzureLinuxDesktop.ps1 -VirtualBox    # live desktop as a bootable VDI disk image
.\scripts\Get-AzureLinuxDesktop.ps1 -VMWare        # live desktop as a bootable VMDK disk image
.\scripts\Get-AzureLinuxDesktop.ps1 -Kvm -OutputDirectory C:\vms
.\scripts\Get-AzureLinuxDesktop.ps1 -Hyperv -KeepParts
```
