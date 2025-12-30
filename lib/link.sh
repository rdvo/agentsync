#!/usr/bin/env bash
# link.sh - Cross-platform symlink creation

set -eo pipefail

# Source utils
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# Create symlink (cross-platform)
link_create() {
    local source="$1"
    local target="$2"
    local force="${3:-false}"

    log_debug "Creating link: $target -> $source"

    # Ensure source exists
    if [[ ! -e "$source" ]]; then
        log_error "Source does not exist: $source"
        return 1
    fi

    # Ensure target parent directory exists
    local target_parent=$(dirname "$target")
    ensure_dir "$target_parent"

    # Check if target already exists
    if [[ -e "$target" ]] || [[ -L "$target" ]]; then
        if [[ "$force" == "true" ]]; then
            log_debug "Removing existing: $target"
            safe_remove "$target"
        else
            log_warning "Skipping $target (exists, use --force to overwrite)"
            return 1
        fi
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create: $target -> $source"
        return 0
    fi

    # Create symlink based on OS
    if is_windows; then
        link_create_windows "$source" "$target"
    else
        link_create_unix "$source" "$target"
    fi

    if [[ $? -eq 0 ]]; then
        log_debug "Created link: $target -> $source"
        return 0
    else
        log_error "Failed to create link: $target"
        return 1
    fi
}

# Create symlink on Unix/Linux/macOS
link_create_unix() {
    local source="$1"
    local target="$2"

    # Use relative path for better portability
    local rel_path=$(get_relative_path "$source" "$target")

    ln -s "$rel_path" "$target"
}

# Create junction on Windows
link_create_windows() {
    local source="$1"
    local target="$2"

    # Try junction first (works without admin)
    if command_exists cmd; then
        local source_win=$(cygpath -w "$source")
        local target_win=$(cygpath -w "$target")

        # Try using cmd.exe
        if cmd //c "mklink /J \"$target_win\" \"$source_win\"" 2>/dev/null; then
            return 0
        fi
    fi

    # Fallback to ln -s
    ln -s "$source" "$target"
}

# Remove symlink
link_remove() {
    local target="$1"

    if [[ ! -L "$target" ]]; then
        log_debug "Not a symlink: $target"
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would remove: $target"
        return 0
    fi

    rm "$target"
    log_debug "Removed link: $target"
    return 0
}

# Check if symlink is valid
link_is_valid() {
    local link="$1"

    if [[ ! -L "$link" ]]; then
        echo "false"
        return 1
    fi

    if [[ -e "$link" ]]; then
        echo "true"
        return 0
    else
        echo "false"
        return 1
    fi
}

# Get symlink target
link_get_target() {
    local link="$1"

    if [[ -L "$link" ]]; then
        local target=$(readlink "$link")
        if [[ "$target" == /* ]]; then
            echo "$target"
        else
            local dir=$(dirname "$link")
            abs_path "$dir/$target"
        fi
    else
        echo ""
    fi
}

# Check if symlink points to expected source
link_points_to() {
    local link="$1"
    local expected_source="$2"

    if [[ ! -L "$link" ]]; then
        echo "false"
        return 1
    fi

    local actual_source=$(link_get_target "$link")
    local expected_abs=$(abs_path "$expected_source")

    if [[ "$actual_source" == "$expected_abs" ]]; then
        echo "true"
        return 0
    else
        echo "false"
        return 1
    fi
}

# Create symlink for a skill
link_skill() {
    local skill_name="$1"
    local source_dir="$2"
    local target_dir="$3"
    local force="${4:-false}"

    local source_path="$source_dir/$skill_name"
    local target_path="$target_dir/$skill_name"

    if [[ ! -d "$source_path" ]]; then
        log_warning "Source not found: $source_path"
        return 1
    fi

    link_create "$source_path" "$target_path" "$force"
}

# Remove symlink for a skill
unlink_skill() {
    local skill_name="$1"
    local target_dir="$2"

    local target_path="$target_dir/$skill_name"

    link_remove "$target_path"
}

# Sync all skills from source to target
link_sync_all() {
    local source_dir="$1"
    local target_dir="$2"
    local force="${3:-false}"

    if [[ ! -d "$source_dir" ]]; then
        log_warning "Source directory not found: $source_dir"
        return 1
    fi

    local synced=0
    local skipped=0
    local failed=0

    # Create target directory
    ensure_dir "$target_dir"

    # Link each skill
    while IFS= read -r -d '' skill; do
        local skill_name=$(basename "$skill")
        local target_path="$target_dir/$skill_name"

        if link_create "$skill" "$target_path" "$force"; then
            ((synced++))
        else
            ((skipped++))
        fi
    done < <(find "$source_dir" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

    echo "synced=$skipped failed=$failed"
}

# Create parent directories for target
link_ensure_parents() {
    local target="$1"

    local parent=$(dirname "$target")
    ensure_dir "$parent"
}

# Batch create links
link_batch() {
    local source_dir="$1"
    local targets=("$2")
    local force="${3:-false}"

    local total=0
    local success=0
    local skipped=0

    for target in "${targets[@]}"; do
        local result=$(link_sync_all "$source_dir" "$target" "$force")
        IFS=' ' read -r s sk f <<< "$result"
        total=$((total + s + sk + f))
        success=$((success + s))
        skipped=$((skipped + sk))
    done

    echo "total=$total success=$success skipped=$skipped"
}

# Find broken symlinks in a directory
link_find_broken() {
    local dir="$1"
    local broken=()

    if [[ ! -d "$dir" ]]; then
        echo ""
        return 1
    fi

    while IFS= read -r -d '' link; do
        if [[ -L "$link" ]] && [[ ! -e "$link" ]]; then
            broken+=("$link")
        fi
    done < <(find "$dir" -mindepth 1 -maxdepth 1 -type l -print0 2>/dev/null)

    echo "${broken[@]}"
}

# Repair broken symlinks
link_repair() {
    local dir="$1"
    local source_dir="$2"
    local force="${3:-false}"

    local broken=$(link_find_broken "$dir")

    if [[ -z "$broken" ]]; then
        log_success "No broken symlinks found"
        return 0
    fi

    log_info "Repairing broken symlinks..."

    for link in $broken; do
        local skill_name=$(basename "$link")
        local source_path="$source_dir/$skill_name"

        if [[ -d "$source_path" ]]; then
            log_info "Repairing: $link"
            link_create "$source_path" "$link" "true"
        else
            log_warning "Source missing for: $skill_name"
        fi
    done
}

# Export for subshells
export -f link_create link_create_unix link_create_windows
export -f link_remove link_is_valid link_get_target link_points_to
export -f link_skill unlink_skill link_sync_all link_ensure_parents
export -f link_batch link_find_broken link_repair
