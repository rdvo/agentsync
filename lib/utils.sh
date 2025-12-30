#!/usr/bin/env bash
# utils.sh - Helper functions for agentsync

set -eo pipefail

# Colors
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export BOLD='\033[1m'
export NC='\033[0m'

# Logging functions
log_info() {
    echo -e "info $1"
}

log_success() {
    echo -e "[OK] $1"
}

log_warning() {
    echo -e "[!] $1" >&2
}

log_error() {
    echo -e "[ERROR] $1" >&2
}

log_header() {
    echo -e "\n$1"
}

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "debug $1" >&2
    fi
}

# Check if we're on Windows
is_windows() {
    [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ -n "${WINDIR:-}" ]]
}

# Get OS type
get_os() {
    case "$OSTYPE" in
        darwin*) echo "macos" ;;
        linux*) echo "linux" ;;
        msys*|cygwin*) echo "windows" ;;
        *) echo "unknown" ;;
    esac
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Get relative path from target to source
get_relative_path() {
    local source="$1"
    local target="$2"

    # Expand ~ to home directory
    source="${source/#\~/$HOME}"
    target="${target/#\~/$HOME}"

    # Get absolute paths
    local source_abs=$(abs_path "$source" 2>/dev/null || echo "$source")
    local target_abs=$(abs_path "$target" 2>/dev/null || echo "$target")

    # Handle case where target is in current directory
    local target_dir=$(dirname "$target_abs")

    if [[ "$target_dir" == "." ]]; then
        echo "$source_abs"
        return
    fi

    # Calculate relative path using a more robust method
    local rel_path=""

    # Get the directory parts
    local source_parts=()
    local target_parts=()

    IFS='/' read -ra SOURCE_PARTS <<< "$source_abs"
    IFS='/' read -ra TARGET_PARTS <<< "$target_dir"

    # Skip empty parts
    local source_len=0
    local target_len=0

    for part in "${SOURCE_PARTS[@]}"; do
        if [[ -n "$part" ]]; then
            source_parts+=("$part")
            ((source_len++))
        fi
    done

    for part in "${TARGET_PARTS[@]}"; do
        if [[ -n "$part" ]]; then
            target_parts+=("$part")
            ((target_len++))
        fi
    done

    # Find common prefix
    local common=0
    local min_len=$source_len
    if [[ $target_len -lt $min_len ]]; then
        min_len=$target_len
    fi

    while [[ $common -lt $min_len ]]; do
        if [[ "${source_parts[$common]}" == "${target_parts[$common]}" ]]; then
            ((common++))
        else
            break
        fi
    done

    # Add .. for each part in target that's not in common
    local i=0
    for ((i = common; i < target_len; i++)); do
        rel_path="${rel_path}../"
    done

    # Add remaining parts from source
    for ((i = common; i < source_len; i++)); do
        rel_path="${rel_path}${source_parts[$i]}/"
    done

    # Remove trailing slash
    rel_path="${rel_path%/}"

    echo "$rel_path"
}

# Get absolute path
abs_path() {
    local path="$1"
    if [[ -d "$path" ]]; then
        (cd "$path" && pwd)
    else
        local dir=$(dirname "$path")
        local base=$(basename "$path")
        (cd "$dir" && echo "$(pwd)/$base")
    fi
}

# Count items in directory
count_items() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        find "$dir" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' '
    else
        echo "0"
    fi
}

# Check if directory has skills
has_skills() {
    local dir="$1"
    [[ -d "$dir" ]] && [[ $(count_items "$dir") -gt 0 ]]
}

# Find the workspace root (parent of .claude/.cursor/.windsurf)
find_workspace_root() {
    local start_dir="${1:-$(pwd)}"
    local dir="$start_dir"
    local home=$(get_home_dir)

    while [[ "$dir" != "/" ]]; do
        if [[ "$dir" == "$home" ]]; then
            break # Stop at home directory
        fi
        
        if [[ -d "$dir/.claude" ]] || [[ -d "$dir/.cursor" ]] || [[ -d "$dir/.windsurf" ]] || [[ -d "$dir/.git" ]]; then
            echo "$dir"
            return 0
        fi
        dir=$(dirname "$dir")
    done

    # If not found, return the start directory
    echo "$start_dir"
    return 1
}

# Prompt yes/no
prompt_yes_no() {
    local prompt="$1"
    local default="${2:-y}"

    while true; do
        echo -n "$prompt " >&2
        read -r answer

        case "$answer" in
            [Yy]*|"") 
                if [[ "$answer" == "" ]]; then
                    answer="$default"
                fi
                if [[ "$answer" =~ ^[Yy] ]] || [[ "$answer" == "1" ]]; then
                    echo "Yes"
                    return 0
                fi
                echo "No"
                return 1
                ;;
            [Nn]*|"2")
                echo "No"
                return 1
                ;;
        esac
    done
}

# Prompt for selection
prompt_select() {
    local prompt="$1"
    shift
    local options=("$@")

    local n=${#options[@]}
    echo "$prompt" >&2
    for ((i=1; i<=n; i++)); do
        echo "  [$i] ${options[$i-1]}" >&2
    done

    while true; do
        echo -n "> " >&2
        read -r answer
        if [[ "$answer" =~ ^[0-9]+$ ]] && [[ "$answer" -ge 1 ]] && [[ "$answer" -le $n ]]; then
            echo "${options[$answer-1]}"
            return 0
        fi
    done
}

# Create directory if not exists
ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        log_debug "Created directory: $dir"
    fi
}

# Remove directory safely
safe_remove() {
    local path="$1"
    if [[ -L "$path" ]]; then
        rm "$path"
    elif [[ -d "$path" ]]; then
        rm -rf "$path"
    elif [[ -f "$path" ]]; then
        rm "$path"
    fi
}

# Check if running as root (for Windows junction support)
is_root() {
    [[ "$(id -u)" == "0" ]]
}

# Get home directory (cross-platform)
get_home_dir() {
    if is_windows && [[ -n "$HOME" ]]; then
        echo "$HOME"
    elif [[ -n "$USERPROFILE" ]]; then
        echo "$USERPROFILE"
    else
        echo "$HOME"
    fi
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                ;;
            --force)
                FORCE=true
                ;;
            --verbose|-v)
                VERBOSE=true
                ;;
            --quiet|-q)
                QUIET=true
                ;;
            --fix)
                FIX=true
                ;;
            --help|-h)
                if [[ -n "$CMD" ]]; then
                    # Pass help flag to subcommand
                    ARGS+=("--help")
                else
                    CMD="help"
                fi
                ;;
            --version)
                CMD="version"
                ;;
            --agents|-a|--skills|-s|--commands|-c|--global|-g|--project|-p|--stale|--json|--type)
                # Flags for list/add command - pass through
                if [[ -z "$CMD" ]]; then
                    if [[ "$1" == "--type" ]]; then
                        CMD="add"
                    else
                        CMD="list"
                    fi
                fi
                ARGS+=("$1")
                ;;
            --*)
                log_error "Unknown option: $1"
                exit 1
                ;;
            *)
                # Assume it's a command or path
                if [[ -z "$CMD" ]]; then
                    CMD="$1"
                else
                    ARGS+=("$1")
                fi
                ;;
        esac
        shift
    done
}

# Export functions for subshells
export -f log_info log_success log_warning log_error log_header log_debug
export -f is_windows get_os command_exists get_relative_path abs_path
export -f count_items has_skills find_workspace_root
export -f prompt_yes_no prompt_select ensure_dir safe_remove
export -f is_root get_home_dir
