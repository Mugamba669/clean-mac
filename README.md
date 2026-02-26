# clean-mac

A comprehensive Bash script that safely reduces macOS **System Data** storage by cleaning caches, logs, Time Machine snapshots, old backups, and developer tool bloat.

Healthy System Data sits at 12-25 GB. If yours has ballooned to 50-100 GB+, this script brings it back down.

## What it cleans

| # | Section | Targets | Typical savings |
|---|---------|---------|-----------------|
| 1 | **User & System Caches** | `~/Library/Caches`, `/Library/Caches`, `~/.cache`, `/tmp`, font caches | 2-10 GB |
| 2 | **Logs & Diagnostics** | User/system logs, crash reports, ASL logs, old unified log traces | 1-5 GB |
| 3 | **Xcode & Dev Tools** | DerivedData, Archives, iOS DeviceSupport, simulators, InstallerSandbox leftovers | 10-60 GB |
| 4 | **iOS Device Backups** | Old iPhone/iPad local backups in `MobileSync/Backup` | 5-50 GB |
| 5 | **Time Machine Snapshots** | Local APFS snapshots created by Time Machine | 5-50 GB |
| 6 | **macOS Updates** | Downloaded update files, installer leftovers, SoftwareUpdate cache | 2-15 GB |
| 7 | **App Caches** | VS Code, Chrome, Safari, Spotify, Slack, Discord, Teams, Mail downloads, screensaver videos | 2-10 GB |
| 8 | **Developer Caches** | Gradle, Dart/Flutter, CocoaPods, Carthage, Go, Rust/Cargo, Maven, Android, Composer, Ruby | 1-10 GB |
| 9 | **Package Managers** | npm, yarn, pnpm, bun, Homebrew, pip | 1-5 GB |
| 10 | **Docker** | Unused images, volumes, containers, build cache | 5-30 GB |
| 11 | **Trash & Misc** | Trash, DNS cache, purgeable space, Spotlight index data | 1-10 GB |

## What it does NOT touch

- System frameworks and OS files
- Application binaries
- User documents, photos, music, and videos
- Browser bookmarks, passwords, or history
- Any data that is not regenerable (unless you confirm deletion, e.g. iOS backups)

## Usage

```bash
# Download
git clone https://github.com/Mugamba669/clean-mac.git
cd clean-mac

# Make executable (already set, but just in case)
chmod +x clean_mac.sh

# Run (sudo needed for system caches, logs, and snapshots)
sudo ./clean_mac.sh
```

## How it works

1. **Pre-flight scan** — Shows current disk usage and estimates cleanable space per category
2. **Confirmation prompt** — Nothing is deleted until you confirm
3. **11 cleanup passes** — Each section reports what it freed in real time
4. **Interactive prompts** — Destructive items (iOS backups, TM snapshots) ask for separate confirmation
5. **Summary report** — Shows estimated vs actual disk space reclaimed, with final disk usage

## Features

- **Size tracking** — Every cleaned directory reports bytes freed
- **Before/after comparison** — Actual disk space gained measured via `df`
- **Safe defaults** — Uses `${path:?}` guards to prevent accidental root deletion
- **Color-coded output** — Green for success, yellow for warnings, cyan for headers
- **Skip detection** — Gracefully skips tools/folders that don't exist on your system
- **`set -euo pipefail`** — Fails fast on errors instead of silently continuing

## Example output

```
  ╔══════════════════════════════════════════════════════╗
  ║       macOS System Data Deep Cleaner                ║
  ║       Safely reduce System Data to ~10GB            ║
  ╚══════════════════════════════════════════════════════╝

══════════════════════════════════════════════════════════
  CURRENT DISK USAGE
══════════════════════════════════════════════════════════
  Disk: 228Gi total, 210Gi used, 18Gi free (92% capacity)

  Estimated cleanable sizes:
    User Caches                    4.2GB
    Xcode DerivedData              12.8GB
    Xcode DeviceSupport            8.3GB
    iOS Backups                    22.1GB
    Docker Data                    15.6GB
    Time Machine Snapshots         3 snapshots (can be multi-GB each)

  Estimated total cleanable: 63.0GB (+ snapshots)
```

## Tips

- **Restart after cleaning** — macOS reclaims purgeable space on reboot
- **Storage display lag** — System Settings may take a few minutes to reflect changes
- **Run periodically** — Caches rebuild over time; run monthly for best results
- **Close apps first** — Some caches are locked by running applications

## Requirements

- macOS 12 (Monterey) or later
- Bash 3.2+ (ships with macOS)
- `sudo` access for system-level cleanup

## License

MIT
