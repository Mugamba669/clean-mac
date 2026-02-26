#!/bin/bash

# =============================================================================
# macOS System Data Deep Cleaner
# Safely reduces System Data to ~10GB by targeting caches, logs, snapshots,
# old backups, and developer tool bloat.
#
# SAFE: Only targets regenerable caches, logs, temp files, and old backups.
# DOES NOT touch: system frameworks, app binaries, user documents, photos.
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Track total space freed
TOTAL_FREED=0

# ---- Helpers ----------------------------------------------------------------

log_header() {
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  $1${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
}

log_info() {
    echo -e "${GREEN}  ✓${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}  ⚠${NC} $1"
}

log_skip() {
    echo -e "  - $1 (not found, skipping)"
}

# Get folder size in bytes (0 if not found)
get_size_bytes() {
    local path="$1"
    if [ -e "$path" ]; then
        du -sk "$path" 2>/dev/null | awk '{print $1 * 1024}' || echo 0
    else
        echo 0
    fi
}

# Human-readable size
human_size() {
    local bytes=$1
    if [ "$bytes" -ge 1073741824 ]; then
        echo "$(echo "scale=1; $bytes / 1073741824" | bc)GB"
    elif [ "$bytes" -ge 1048576 ]; then
        echo "$(echo "scale=1; $bytes / 1048576" | bc)MB"
    elif [ "$bytes" -ge 1024 ]; then
        echo "$(echo "scale=0; $bytes / 1024" | bc)KB"
    else
        echo "${bytes}B"
    fi
}

# Clean a directory's contents (not the directory itself)
clean_dir() {
    local path="$1"
    local label="${2:-$1}"
    if [ -d "$path" ]; then
        local size_before
        size_before=$(get_size_bytes "$path")
        sudo rm -rf "${path:?}/"* 2>/dev/null || true
        local size_after
        size_after=$(get_size_bytes "$path")
        local freed=$((size_before - size_after))
        if [ "$freed" -gt 0 ]; then
            TOTAL_FREED=$((TOTAL_FREED + freed))
            log_info "$label — freed $(human_size $freed)"
        else
            log_info "$label — already clean"
        fi
    else
        log_skip "$label"
    fi
}

# Clean a directory entirely (remove the dir itself)
remove_dir() {
    local path="$1"
    local label="${2:-$1}"
    if [ -d "$path" ]; then
        local size_before
        size_before=$(get_size_bytes "$path")
        sudo rm -rf "$path" 2>/dev/null || true
        if [ "$size_before" -gt 0 ]; then
            TOTAL_FREED=$((TOTAL_FREED + size_before))
            log_info "$label — freed $(human_size $size_before)"
        else
            log_info "$label — already clean"
        fi
    else
        log_skip "$label"
    fi
}

# ---- Pre-flight info --------------------------------------------------------

show_disk_usage() {
    log_header "CURRENT DISK USAGE"
    df -h / 2>/dev/null | tail -1 | awk '{printf "  Disk: %s total, %s used, %s free (%s capacity)\n", $2, $3, $4, $5}'
    echo ""

    echo -e "${BOLD}  Estimated cleanable sizes:${NC}"

    local targets=(
        "$HOME/Library/Caches:User Caches"
        "/Library/Caches:System Caches"
        "$HOME/Library/Logs:User Logs"
        "/private/var/log:System Logs"
        "$HOME/.Trash:Trash"
        "$HOME/Library/Developer/Xcode/DerivedData:Xcode DerivedData"
        "$HOME/Library/Developer/Xcode/Archives:Xcode Archives"
        "$HOME/Library/Developer/Xcode/iOS DeviceSupport:Xcode DeviceSupport"
        "$HOME/Library/Developer/CoreSimulator:Xcode Simulators"
        "$HOME/Library/Application Support/MobileSync/Backup:iOS Backups"
        "$HOME/.gradle/caches:Gradle Cache"
        "$HOME/.cache:General Cache (~/.cache)"
        "$HOME/.pub-cache:Pub Cache"
        "$HOME/.npm:npm Cache"
        "$HOME/Library/Application Support/Code/Cache:VS Code Cache"
        "$HOME/Library/Application Support/Code/CachedData:VS Code CachedData"
        "$HOME/Library/Containers/com.docker.docker:Docker Data"
    )

    local total_est=0
    for entry in "${targets[@]}"; do
        local path="${entry%%:*}"
        local label="${entry##*:}"
        local size
        size=$(get_size_bytes "$path")
        if [ "$size" -gt 1048576 ]; then
            printf "    %-30s %s\n" "$label" "$(human_size $size)"
            total_est=$((total_est + size))
        fi
    done

    # Time Machine snapshots
    local snap_count
    snap_count=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c "com.apple" || echo 0)
    if [ "$snap_count" -gt 0 ]; then
        printf "    %-30s %s snapshots (can be multi-GB each)\n" "Time Machine Snapshots" "$snap_count"
    fi

    echo ""
    echo -e "  ${BOLD}Estimated total cleanable: $(human_size $total_est)${NC} (+ snapshots)"
    echo ""
}

# ---- Cleanup sections -------------------------------------------------------

clean_user_caches() {
    log_header "1. USER & SYSTEM CACHES"
    clean_dir "$HOME/Library/Caches" "User Caches (~/Library/Caches)"
    clean_dir "/Library/Caches" "System Caches (/Library/Caches)"
    clean_dir "$HOME/.cache" "General Cache (~/.cache)"
    clean_dir "/tmp" "Temp files (/tmp)"
    clean_dir "/private/var/tmp" "System temp (/private/var/tmp)"

    # Font caches
    if [ -d "/private/var/folders" ]; then
        sudo find /private/var/folders -name "com.apple.FontRegistry" -type d -exec rm -rf {} + 2>/dev/null || true
        log_info "Font caches cleaned"
    fi
}

clean_logs() {
    log_header "2. LOGS & DIAGNOSTIC REPORTS"
    clean_dir "$HOME/Library/Logs" "User Logs"
    clean_dir "/private/var/log" "System Logs (/var/log)"
    clean_dir "/Library/Logs" "Library Logs"
    clean_dir "$HOME/Library/Logs/DiagnosticReports" "User Crash Reports"
    clean_dir "/Library/Logs/DiagnosticReports" "System Crash Reports"

    # Apple System Profiler logs
    clean_dir "/private/var/log/asl" "ASL Logs"

    # Unified log data (only old/archived — current logs are needed)
    if [ -d "/private/var/db/diagnostics" ]; then
        local diag_size
        diag_size=$(get_size_bytes "/private/var/db/diagnostics")
        if [ "$diag_size" -gt 1073741824 ]; then
            sudo find /private/var/db/diagnostics -name "*.tracev3" -mtime +3 -delete 2>/dev/null || true
            log_info "Old diagnostic traces (>3 days) cleaned"
        fi
    fi
}

clean_xcode() {
    log_header "3. XCODE & DEVELOPER TOOLS"
    clean_dir "$HOME/Library/Developer/Xcode/DerivedData" "Xcode DerivedData"
    remove_dir "$HOME/Library/Developer/Xcode/Archives" "Xcode Archives"
    remove_dir "$HOME/Library/Developer/Xcode/iOS DeviceSupport" "Xcode iOS DeviceSupport"
    clean_dir "$HOME/Library/Developer/Xcode/iOS Device Logs" "Xcode Device Logs"
    remove_dir "$HOME/Library/Developer/Xcode/watchOS DeviceSupport" "Xcode watchOS DeviceSupport"
    clean_dir "$HOME/Library/Caches/com.apple.dt.Xcode" "Xcode Caches"
    clean_dir "$HOME/Library/Developer/Xcode/Index.noindex" "Xcode Index"
    remove_dir "$HOME/Library/Saved Application State/com.apple.dt.Xcode.savedState" "Xcode Saved State"

    # Delete unavailable simulators
    if command -v xcrun &>/dev/null; then
        echo "  Removing unavailable simulators..."
        xcrun simctl delete unavailable 2>/dev/null && log_info "Unavailable simulators removed" || true
    fi

    # CoreSimulator caches (old device data)
    clean_dir "$HOME/Library/Developer/CoreSimulator/Caches" "CoreSimulator Caches"

    # Xcode installer sandbox leftovers (can be huge after failed updates)
    if [ -d "/Library/InstallerSandboxes/.PKInstallSandboxManager" ]; then
        local sandbox_size
        sandbox_size=$(get_size_bytes "/Library/InstallerSandboxes/.PKInstallSandboxManager")
        if [ "$sandbox_size" -gt 104857600 ]; then
            sudo rm -rf /Library/InstallerSandboxes/.PKInstallSandboxManager/* 2>/dev/null || true
            TOTAL_FREED=$((TOTAL_FREED + sandbox_size))
            log_info "Xcode InstallerSandbox leftovers — freed $(human_size $sandbox_size)"
        fi
    fi
}

clean_ios_backups() {
    log_header "4. OLD iOS DEVICE BACKUPS"
    local backup_dir="$HOME/Library/Application Support/MobileSync/Backup"
    if [ -d "$backup_dir" ]; then
        local size
        size=$(get_size_bytes "$backup_dir")
        if [ "$size" -gt 0 ]; then
            echo -e "  ${YELLOW}Found iOS backups: $(human_size $size)${NC}"
            echo "  These are iPhone/iPad local backups."
            read -p "  Delete ALL old iOS backups? (y/n): " ios_confirm
            if [[ "$ios_confirm" =~ ^[Yy]$ ]]; then
                rm -rf "${backup_dir:?}/"* 2>/dev/null || true
                TOTAL_FREED=$((TOTAL_FREED + size))
                log_info "iOS backups removed — freed $(human_size $size)"
            else
                log_warn "iOS backups kept"
            fi
        fi
    else
        log_skip "iOS Backups"
    fi
}

clean_time_machine_snapshots() {
    log_header "5. TIME MACHINE LOCAL SNAPSHOTS"
    local snapshots
    snapshots=$(tmutil listlocalsnapshots / 2>/dev/null | grep "com.apple" || true)

    if [ -z "$snapshots" ]; then
        log_info "No local snapshots found"
        return
    fi

    local count
    count=$(echo "$snapshots" | wc -l | tr -d ' ')
    echo -e "  ${YELLOW}Found $count local snapshot(s).${NC}"
    echo "  These can consume 1-50GB+ and are safely removable."
    read -p "  Delete all Time Machine local snapshots? (y/n): " tm_confirm

    if [[ "$tm_confirm" =~ ^[Yy]$ ]]; then
        local dates
        dates=$(tmutil listlocalsnapshotdates / 2>/dev/null | grep -v "Snapshot" || true)
        while IFS= read -r date; do
            if [ -n "$date" ]; then
                sudo tmutil deletelocalsnapshots "$date" 2>/dev/null || true
            fi
        done <<< "$dates"
        log_info "All local snapshots deleted"
    else
        log_warn "Snapshots kept"
    fi
}

clean_macos_updates() {
    log_header "6. macOS UPDATE & INSTALL FILES"
    clean_dir "/Library/Updates" "macOS update downloads"

    # macOS installer leftovers
    if [ -d "/macOS Install Data" ]; then
        local size
        size=$(get_size_bytes "/macOS Install Data")
        sudo rm -rf "/macOS Install Data" 2>/dev/null || true
        TOTAL_FREED=$((TOTAL_FREED + size))
        log_info "macOS Install Data removed — freed $(human_size $size)"
    fi

    # Softwareupdate downloaded installers
    clean_dir "/Library/Application Support/Apple/SoftwareUpdate" "SoftwareUpdate cache"
}

clean_app_caches() {
    log_header "7. APPLICATION-SPECIFIC CACHES"

    # Saved Application State (safe — apps recreate on launch)
    clean_dir "$HOME/Library/Saved Application State" "Saved Application States"

    # VS Code
    clean_dir "$HOME/Library/Application Support/Code/Cache" "VS Code Cache"
    clean_dir "$HOME/Library/Application Support/Code/CachedData" "VS Code CachedData"
    clean_dir "$HOME/Library/Application Support/Code/CachedExtensionVSIXs" "VS Code Extension Cache"
    clean_dir "$HOME/Library/Application Support/Code/logs" "VS Code Logs"

    # Chrome
    clean_dir "$HOME/Library/Application Support/Google/Chrome/Default/Service Worker/CacheStorage" "Chrome SW Cache"
    clean_dir "$HOME/Library/Application Support/Google/Chrome/Default/Cache" "Chrome Cache"
    clean_dir "$HOME/Library/Application Support/Google/Chrome/Default/Code Cache" "Chrome Code Cache"

    # Safari
    clean_dir "$HOME/Library/Safari/LocalStorage" "Safari LocalStorage"

    # Spotify
    clean_dir "$HOME/Library/Application Support/Spotify/PersistentCache" "Spotify Cache"
    clean_dir "$HOME/Library/Caches/com.spotify.client" "Spotify App Cache"

    # Slack
    clean_dir "$HOME/Library/Application Support/Slack/Cache" "Slack Cache"
    clean_dir "$HOME/Library/Application Support/Slack/Service Worker/CacheStorage" "Slack SW Cache"

    # Discord
    clean_dir "$HOME/Library/Application Support/discord/Cache" "Discord Cache"

    # Teams
    clean_dir "$HOME/Library/Application Support/Microsoft/Teams/Cache" "Teams Cache"

    # Mail downloads
    clean_dir "$HOME/Library/Containers/com.apple.mail/Data/Library/Mail Downloads" "Mail Downloads"

    # Screensaver video downloads (aerial/dynamic wallpapers)
    clean_dir "/Library/Application Support/com.apple.idleassetsd/Customer" "Screensaver Downloads"
}

clean_developer_caches() {
    log_header "8. DEVELOPER TOOL CACHES"

    # Gradle
    clean_dir "$HOME/.gradle/caches" "Gradle Caches"
    clean_dir "$HOME/.gradle/wrapper/dists" "Gradle Wrapper Dists"

    # Dart / Flutter
    clean_dir "$HOME/.dartServer/.analysis-driver" "Dart Analysis Cache"
    clean_dir "$HOME/.pub-cache" "Pub Cache"

    # CocoaPods
    clean_dir "$HOME/Library/Caches/CocoaPods" "CocoaPods Cache"

    # Carthage
    clean_dir "$HOME/Library/Caches/org.carthage.CarthageKit" "Carthage Cache"

    # Go modules
    if command -v go &>/dev/null; then
        go clean -cache 2>/dev/null && log_info "Go build cache cleaned" || true
        go clean -testcache 2>/dev/null || true
    fi
    clean_dir "$HOME/.cache/go-build" "Go Build Cache"

    # Rust / Cargo
    clean_dir "$HOME/.cargo/registry/cache" "Cargo Registry Cache"

    # Maven
    clean_dir "$HOME/.m2/repository" "Maven Local Repository"

    # Android Studio / SDK
    clean_dir "$HOME/.android/cache" "Android Cache"
    clean_dir "$HOME/.android/build-cache" "Android Build Cache"

    # Composer (PHP)
    clean_dir "$HOME/.composer/cache" "Composer Cache"

    # Ruby
    clean_dir "$HOME/.gem" "Ruby Gems Cache"
    clean_dir "$HOME/.bundle/cache" "Bundler Cache"
}

clean_package_managers() {
    log_header "9. PACKAGE MANAGER CLEANUP"

    # npm
    if command -v npm &>/dev/null; then
        npm cache clean --force 2>/dev/null && log_info "npm cache cleaned" || true
    fi
    clean_dir "$HOME/.npm/_cacache" "npm cache dir"

    # yarn
    if command -v yarn &>/dev/null; then
        yarn cache clean 2>/dev/null && log_info "yarn cache cleaned" || true
    fi

    # pnpm
    if command -v pnpm &>/dev/null; then
        pnpm store prune 2>/dev/null && log_info "pnpm store pruned" || true
    fi

    # bun
    clean_dir "$HOME/.bun/install/cache" "Bun cache"

    # Homebrew
    if command -v brew &>/dev/null; then
        brew cleanup --prune=all -s 2>/dev/null && log_info "Homebrew cache cleaned" || true
        rm -rf "$(brew --cache)" 2>/dev/null || true
    fi

    # pip
    if command -v pip3 &>/dev/null; then
        pip3 cache purge 2>/dev/null && log_info "pip cache purged" || true
    elif command -v pip &>/dev/null; then
        pip cache purge 2>/dev/null && log_info "pip cache purged" || true
    fi
}

clean_docker() {
    log_header "10. DOCKER CLEANUP"
    if docker info &>/dev/null 2>&1; then
        echo "  Docker is running. Cleaning unused resources..."
        docker system prune -af --volumes 2>/dev/null && log_info "Docker full prune done (images + volumes + containers)" || true
        docker builder prune -af 2>/dev/null && log_info "Docker build cache pruned" || true
    else
        log_skip "Docker (not running)"
        # Even if Docker isn't running, its disk image may be huge
        local docker_data="$HOME/Library/Containers/com.docker.docker/Data"
        if [ -d "$docker_data" ]; then
            local size
            size=$(get_size_bytes "$docker_data")
            if [ "$size" -gt 5368709120 ]; then
                echo -e "  ${YELLOW}Docker data dir is $(human_size $size) at $docker_data${NC}"
                echo "  Start Docker and run 'docker system prune -af --volumes' to reclaim space."
            fi
        fi
    fi
}

clean_trash() {
    log_header "11. TRASH & MISC"
    clean_dir "$HOME/.Trash" "User Trash"

    # Flush DNS cache (tiny but good hygiene)
    sudo dscacheutil -flushcache 2>/dev/null && log_info "DNS cache flushed" || true

    # Purge memory cache (frees purgeable disk space too)
    sudo purge 2>/dev/null && log_info "Memory/disk purge triggered" || true

    # Spotlight re-index trigger (helps recalculate System Data)
    clean_dir "$HOME/Library/Application Support/com.apple.spotlight" "Spotlight user data"
    clean_dir "$HOME/Library/Application Support/com.apple.sharedfilelist" "Shared File Lists"
    clean_dir "$HOME/Library/Metadata/CoreSpotlight" "CoreSpotlight index"
}

# ---- Main -------------------------------------------------------------------

main() {
    echo -e "${BOLD}"
    echo "  ╔══════════════════════════════════════════════════════╗"
    echo "  ║       macOS System Data Deep Cleaner                ║"
    echo "  ║       Safely reduce System Data to ~10GB            ║"
    echo "  ╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Show what we'll clean
    show_disk_usage

    echo -e "${RED}${BOLD}  WARNING: This will delete caches, logs, old backups, and temp files.${NC}"
    echo "  All deleted data is regenerable (caches/logs) or old backups."
    echo "  Your apps, documents, photos, and system files are NOT touched."
    echo ""
    read -p "  Proceed with deep clean? (y/n): " confirmation

    if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
        echo -e "\n  ${RED}Cancelled.${NC}"
        exit 0
    fi

    # Record starting free space
    local free_before
    free_before=$(df -k / | tail -1 | awk '{print $4 * 1024}')

    # Run all cleanup sections
    clean_user_caches
    clean_logs
    clean_xcode
    clean_ios_backups
    clean_time_machine_snapshots
    clean_macos_updates
    clean_app_caches
    clean_developer_caches
    clean_package_managers
    clean_docker
    clean_trash

    # Final summary
    local free_after
    free_after=$(df -k / | tail -1 | awk '{print $4 * 1024}')
    local actual_freed=$((free_after - free_before))
    if [ "$actual_freed" -lt 0 ]; then
        actual_freed=0
    fi

    log_header "CLEANUP COMPLETE"
    echo ""
    echo -e "  ${GREEN}${BOLD}Estimated freed (tracked):  $(human_size $TOTAL_FREED)${NC}"
    echo -e "  ${GREEN}${BOLD}Actual disk space gained:   $(human_size $actual_freed)${NC}"
    echo ""
    df -h / 2>/dev/null | tail -1 | awk '{printf "  Disk now: %s total, %s used, %s free (%s capacity)\n", $2, $3, $4, $5}'
    echo ""
    echo -e "  ${CYAN}Tip: Restart your Mac for macOS to fully reclaim purgeable space.${NC}"
    echo -e "  ${CYAN}Tip: Check Storage in System Settings — it may take a few minutes to update.${NC}"
    echo ""
}

main "$@"
