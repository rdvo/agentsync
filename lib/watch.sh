#!/usr/bin/env bash
# watch.sh - Auto-sync daemon for agentsync

set -eo pipefail

# Get script directory for relative imports
if [[ -n "${BASH_SOURCE[0]}" ]]; then
    _WATCH_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    _WATCH_SCRIPT_DIR="$(pwd)"
fi

# Source dependencies
source "$_WATCH_SCRIPT_DIR/utils.sh"
source "$_WATCH_SCRIPT_DIR/detect.sh"
source "$_WATCH_SCRIPT_DIR/config.sh"
source "$_WATCH_SCRIPT_DIR/link.sh"
source "$_WATCH_SCRIPT_DIR/sync.sh"

# Daemon PID file
DAEMON_PID_FILE="${AGENTSYNC_PID_DIR:-$HOME/.config/agentsync}/watch.pid"
DAEMON_LOG_FILE="${AGENTSYNC_LOG_DIR:-$HOME/.local/share/agentsync}/watch.log"

# Debounce time (seconds)
DEBOUNCE_SECONDS=2

# Get available file watcher
get_file_watcher() {
    if command_exists fswatch; then
        echo "fswatch"
    elif command_exists inotifywait; then
        echo "inotify"
    else
        echo ""
    fi
}

# Check if daemon is running
watch_is_running() {
    if [[ -f "$DAEMON_PID_FILE" ]]; then
        local pid=$(cat "$DAEMON_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "true"
            return 0
        else
            rm -f "$DAEMON_PID_FILE"
        fi
    fi
    echo "false"
    return 1
}

# Get daemon PID
watch_get_pid() {
    if [[ -f "$DAEMON_PID_FILE" ]]; then
        cat "$DAEMON_PID_FILE"
    else
        echo ""
    fi
}

# Start daemon
watch_start() {
    local source_dir="${1:-$DEFAULT_SOURCE}"
    local interval="${2:-}"

    if [[ "$(watch_is_running)" == "true" ]]; then
        log_warning "Daemon already running (PID: $(watch_get_pid))"
        return 1
    fi

    ensure_dir "$(dirname "$DAEMON_PID_FILE")"
    ensure_dir "$(dirname "$DAEMON_LOG_FILE")"

    if [[ -z "$source_dir" ]] && config_exists; then
        source_dir=$(config_get_source)
    fi

    if [[ -z "$source_dir" ]]; then
        source_dir="$DEFAULT_SOURCE"
    fi

    if [[ ! -d "$source_dir" ]]; then
        log_error "Source directory not found: $source_dir"
        return 1
    fi

    local watcher=$(get_file_watcher)

    if [[ -z "$watcher" ]]; then
        log_error "No file watcher available."
        log_info "Install fswatch (macOS: brew install fswatch, Linux: apt install inotify-tools)"
        return 1
    fi

    log_info "Starting daemon..."
    log_info "Source: $source_dir"
    log_info "Watcher: $watcher"

    (
        exec "$0" watch-daemon "$source_dir" "$watcher" >> "$DAEMON_LOG_FILE" 2>&1
    ) &

    local pid=$!
    echo "$pid" > "$DAEMON_PID_FILE"

    sleep 1

    if kill -0 "$pid" 2>/dev/null; then
        log_success "Daemon started (PID: $pid)"
        log_info "Log: $DAEMON_LOG_FILE"
        return 0
    else
        log_error "Failed to start daemon"
        return 1
    fi
}

# Stop daemon
watch_stop() {
    if [[ "$(watch_is_running)" != "true" ]]; then
        log_info "Daemon not running"
        return 0
    fi

    local pid=$(watch_get_pid)

    log_info "Stopping daemon (PID: $pid)..."

    kill "$pid" 2>/dev/null

    local count=0
    while kill -0 "$pid" 2>/dev/null && [[ $count -lt 10 ]]; do
        sleep 1
        ((count++))
    done

    if kill -0 "$pid" 2>/dev/null; then
        log_warning "Force killing daemon..."
        kill -9 "$pid" 2>/dev/null
    fi

    rm -f "$DAEMON_PID_FILE"
    log_success "Daemon stopped"
}

# Watch daemon (internal)
watch_daemon() {
    local source_dir="$1"
    local watcher="$2"

    log_info "Watch daemon started"
    log_info "Watching: $source_dir"

    sync_quick "$source_dir"

    local last_event=0

    case "$watcher" in
        fswatch)
            while true; do
                local events=$(fswatch -r "$source_dir" 2>/dev/null)

                if [[ -n "$events" ]]; then
                    local now=$(date +%s)
                    if [[ $((now - last_event)) -ge $DEBOUNCE_SECONDS ]]; then
                        log_info "Change detected, syncing..."
                        sync_quick "$source_dir"
                        last_event=$now
                    fi
                fi
            done
            ;;
        inotify)
            while true; do
                inotifywait -r -e create -e mkdir -e moved_to "$source_dir" 2>/dev/null | head -n 1

                local now=$(date +%s)
                if [[ $((now - last_event)) -ge $DEBOUNCE_SECONDS ]]; then
                    log_info "Change detected, syncing..."
                    sync_quick "$source_dir"
                    last_event=$now
                fi
            done
            ;;
    esac
}

# Watch with periodic polling (fallback)
watch_poll() {
    local source_dir="$1"
    local interval="${2:-30}"

    log_info "Watch poll started (interval: ${interval}s)"
    log_info "Watching: $source_dir"

    sync_quick "$source_dir"

    local known_skills=$(get_skills_list "$source_dir")

    while true; do
        sleep "$interval"

        local current_skills=$(get_skills_list "$source_dir")

        for skill in $current_skills; do
            local found=false
            for known in $known_skills; do
                if [[ "$skill" == "$known" ]]; then
                    found=true
                    break
                fi
            done

            if [[ "$found" == "false" ]]; then
                log_info "New skill detected: $skill"
                sync_quick "$source_dir"
                known_skills=$current_skills
                break
            fi
        done
    done
}

# Show daemon status
watch_status() {
    if [[ "$(watch_is_running)" == "true" ]]; then
        local pid=$(watch_get_pid)
        echo ""
        log_success "Daemon running (PID: $pid)"
        echo "  Source: $(config_get_source 2>/dev/null || echo 'unknown')"
        echo "  Log: $DAEMON_LOG_FILE"
    else
        echo ""
        log_info "Daemon not running"
    fi
}

# Toggle daemon
watch_toggle() {
    if [[ "$(watch_is_running)" == "true" ]]; then
        watch_stop
    else
        watch_start
    fi
}

# Install git hooks
install_git_hooks() {
    local hooks_dir=".git/hooks"
    local post_checkout="$hooks_dir/post-checkout"

    ensure_dir "$hooks_dir"

    cat > "$post_checkout" << 'HOOK'
#!/bin/bash
# agentsync post-checkout hook
# Auto-syncs skills when switching branches/checking out

previous_head="$1"
new_head="$2"
flag="$3"

if [[ "$flag" == "1" ]]; then
    if [[ -f ".agentsyncrc" ]] || [[ -d ".claude/skills" ]]; then
        agentsync --quiet 2>/dev/null &
    fi
fi
HOOK

    chmod +x "$post_checkout"

    log_success "Installed git hook: $post_checkout"
    log_info "Skills will auto-sync on git checkout/switch"
}

# Uninstall git hooks
uninstall_git_hooks() {
    local post_checkout=".git/hooks/post-checkout"

    if [[ -f "$post_checkout" ]]; then
        rm "$post_checkout"
        log_success "Removed git hook: $post_checkout"
    else
        log_info "No git hook found"
    fi
}

# Export for subshells
export -f get_file_watcher watch_is_running watch_get_pid
export -f watch_start watch_stop watch_daemon watch_poll watch_status
export -f watch_toggle install_git_hooks uninstall_git_hooks
