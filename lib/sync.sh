#!/usr/bin/env bash
# sync.sh - Main sync logic for agentsync

set -eo pipefail

# Get script directory for relative imports
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source dependencies
source "$_SCRIPT_DIR/utils.sh"
source "$_SCRIPT_DIR/detect.sh"
source "$_SCRIPT_DIR/config.sh"
source "$_SCRIPT_DIR/link.sh"

# Get default targets
get_default_targets() {
    echo "cursor:.cursor/agents:true"
    echo "cursor:.cursor/rules:true"
    echo "windsurf:.windsurf/workflows:true"
    echo "claude:.claude/agents:true"
    echo "claude:.claude/commands:true"
    echo "claude:.claude/skills:true"
    echo "codex:.codex/skills:true"
    echo "opencode:.opencode/agent:true"
    echo "opencode:.opencode/command:true"
    echo "opencode:.opencode/skill:true"
}

# Sync AGENTS.md to project root and tool-specific global roots
sync_root_files() {
    local source_dir="$1"
    local synced_roots=0
    local home_dir=$(get_home_dir)

    # Check for AGENTS.md
    if [[ -f "$source_dir/AGENTS.md" ]]; then
        log_info "Found AGENTS.md (linking to roots)"
        
        # 1. Project Root (Universal)
        if [[ ! -e "AGENTS.md" ]]; then
            link_create "$source_dir/AGENTS.md" "./AGENTS.md" "false"
            synced_roots=$((synced_roots + 1))
        fi

        # 2. Claude Global Root (~/.claude/CLAUDE.md)
        if [[ -d "$home_dir/.claude" ]]; then
            if [[ ! -e "$home_dir/.claude/CLAUDE.md" ]]; then
                link_create "$source_dir/AGENTS.md" "$home_dir/.claude/CLAUDE.md" "false"
                synced_roots=$((synced_roots + 1))
            fi
        fi

        # 3. Codex Global Root (~/.codex/AGENTS.md)
        if [[ -d "$home_dir/.codex" ]]; then
            if [[ ! -e "$home_dir/.codex/AGENTS.md" ]]; then
                link_create "$source_dir/AGENTS.md" "$home_dir/.codex/AGENTS.md" "false"
                synced_roots=$((synced_roots + 1))
            fi
        fi

        # 4. Aider Root (.aider/CONVENTIONS.md)
        if [[ -d ".aider" ]]; then
            if [[ ! -e ".aider/CONVENTIONS.md" ]]; then
                link_create "$source_dir/AGENTS.md" ".aider/CONVENTIONS.md" "false"
                synced_roots=$((synced_roots + 1))
            fi
        fi
    fi

    echo "$synced_roots"
}

# Sync nested skills (SKILL.md in folders)
sync_skills_nested() {
    local source_skill_dir="$1"
    local target_skill_dir="$2"
    local synced_count=0

    if [[ ! -d "$source_skill_dir" ]]; then
        echo 0
        return
    fi

    ensure_dir "$target_skill_dir"

    # Find all skill folders (directories containing SKILL.md)
    for skill_folder in "$source_skill_dir"/*/; do
        [[ -d "$skill_folder" ]] || continue
        
        local skill_name=$(basename "$skill_folder")
        local skill_file="$skill_folder/SKILL.md"
        
        if [[ -f "$skill_file" ]]; then
            local target_folder="$target_skill_dir/$skill_name"
            local target_file="$target_folder/SKILL.md"
            
            # Create target folder if needed
            ensure_dir "$target_folder"
            
            # Link the SKILL.md file
            if [[ ! -e "$target_file" ]]; then
                if link_create "$skill_file" "$target_file" "false"; then
                    log_info "Linked skill: $skill_name"
                    synced_count=$((synced_count + 1))
                fi
            fi
            
            # Also link any other files in the skill folder (resources, scripts, etc.)
            for resource in "$skill_folder"/*; do
                [[ -f "$resource" ]] || continue
                [[ "$(basename "$resource")" == "SKILL.md" ]] && continue
                
                local resource_name=$(basename "$resource")
                local target_resource="$target_folder/$resource_name"
                
                if [[ ! -e "$target_resource" ]]; then
                    link_create "$resource" "$target_resource" "false"
                    synced_count=$((synced_count + 1))
                fi
            done
        fi
    done

    echo "$synced_count"
}

# Sync Cursor rules (folders with RULE.md inside)
sync_cursor_rules() {
    local source_dir="$1"
    local target_dir="$2"
    local synced_count=0

    if [[ ! -d "$source_dir" ]]; then
        echo 0
        return
    fi

    ensure_dir "$target_dir"

    # Find all .md files in source
    for agent_file in "$source_dir"/*.md; do
        [[ -f "$agent_file" ]] || continue
        
        local agent_name=$(basename "$agent_file" .md)
        local target_folder="$target_dir/$agent_name"
        local target_file="$target_folder/RULE.md"
        
        # Create folder
        ensure_dir "$target_folder"
        
        # Link as RULE.md inside the folder
        if [[ ! -e "$target_file" ]]; then
            if link_create "$agent_file" "$target_file" "false"; then
                log_info "Linked Cursor rule: $agent_name"
                synced_count=$((synced_count + 1))
            fi
        fi
    done

    echo "$synced_count"
}

# Sync flat files (agents, commands)
sync_files_flat() {
    local source_dir="$1"
    local target_dir="$2"
    local synced_count=0

    if [[ ! -d "$source_dir" ]]; then
        echo 0
        return
    fi

    ensure_dir "$target_dir"

    for item in "$source_dir"/*; do
        [[ -e "$item" ]] || continue
        [[ -d "$item" ]] && continue  # Skip directories for flat sync
        
        local item_name=$(basename "$item")
        
        # Skip special files
        if [[ "$item_name" == "AGENTS.md" ]]; then
            continue
        fi

        local target_path="$target_dir/$item_name"
        
        # Avoid recursive linking
        local abs_source=$(abs_path "$item")
        local abs_target=$(abs_path "$target_dir")
        if [[ "$(dirname "$abs_source")" == "$abs_target" ]]; then
            continue
        fi

        if [[ ! -e "$target_path" ]]; then
            if link_create "$item" "$target_path" "false"; then
                synced_count=$((synced_count + 1))
            fi
        fi
    done

    echo "$synced_count"
}

# Main sync function
sync_all() {
    local source_dir="${1:-$DEFAULT_SOURCE}"
    local config_path="${2:-$CONFIG_FILE}"

    if [[ -z "$source_dir" ]] && config_exists; then
        source_dir=$(config_get_source "$config_path")
    fi

    if [[ -z "$source_dir" ]]; then
        source_dir="$DEFAULT_SOURCE"
    fi

    if [[ ! -d "$source_dir" ]]; then
        log_error "Source directory not found: $source_dir"
        log_info "Run 'agentsync init' to set up agentsync"
        return 1
    fi

    log_header "Syncing from: $source_dir"

    # 1. Sync root-level files first (AGENTS.md, etc.)
    local root_synced=$(sync_root_files "$source_dir")
    local total_synced=$root_synced

    # Detect structure
    local is_structured=false
    if [[ -d "$source_dir/agents" ]] || [[ -d "$source_dir/commands" ]] || [[ -d "$source_dir/skills" ]]; then
        is_structured=true
    fi

    # 3. Get targets
    local targets=""
    if config_exists; then
        targets=$(config_get_targets_array "$config_path")
    fi

    if [[ -z "$targets" ]]; then
        targets=$(get_default_targets)
    fi

    # 4. Filter enabled targets
    local enabled_targets=""
    for target in $targets; do
        local enabled=$(echo "$target" | cut -d':' -f3)
        if [[ "$enabled" == "true" ]]; then
            local path=$(echo "$target" | cut -d':' -f2)
            enabled_targets="$enabled_targets $path"
        fi
    done

    local global_source=""
    if config_exists; then
        global_source=$(config_get_global_source "$config_path")
    fi

    log_info "Syncing project skills..."

    # 5. Sync Project Source to Targets
    for target_dir in $enabled_targets; do
        if [[ -d "$target_dir" ]] || [[ -d "$(dirname "$target_dir")" ]]; then
            # Determine target type
            local target_type="agents"
            local is_nested=false
            local is_cursor_rules=false
            
            if [[ "$target_dir" == *"/commands"* ]] || [[ "$target_dir" == *"/command"* ]]; then
                target_type="commands"
            elif [[ "$target_dir" == *"/skills"* ]] || [[ "$target_dir" == *"/skill"* ]]; then
                target_type="skills"
                is_nested=true
            elif [[ "$target_dir" == *"/rules"* ]]; then
                # Cursor rules need special handling (folders with RULE.md)
                target_type="rule"
                is_cursor_rules=true
            fi

            local specific_source="$source_dir"
            
            if [[ "$is_structured" == "true" ]]; then
                specific_source="$source_dir/$target_type"
            else
                specific_source="$source_dir"
            fi

            if [[ -d "$specific_source" ]]; then
                if [[ "$is_cursor_rules" == "true" ]]; then
                    # Special handling for Cursor rules
                    local synced=$(sync_cursor_rules "$specific_source" "$target_dir")
                    total_synced=$((total_synced + synced))
                elif [[ "$is_nested" == "true" ]]; then
                    # Skills need nested folder structure
                    local synced=$(sync_skills_nested "$specific_source" "$target_dir")
                    total_synced=$((total_synced + synced))
                else
                    # Agents and commands are flat files
                    local synced=$(sync_files_flat "$specific_source" "$target_dir")
                    total_synced=$((total_synced + synced))
                fi
            fi
        else
            log_debug "Target directory not found, skipping: $target_dir"
        fi
    done

    # 6. Sync Global Source to Targets (Inheritance)
    if [[ -n "$global_source" ]] && [[ -d "$global_source" ]]; then
        log_info "Syncing global skills..."
        
        local global_is_structured=false
        if [[ -d "$global_source/agents" ]] || [[ -d "$global_source/commands" ]] || [[ -d "$global_source/skills" ]]; then
            global_is_structured=true
        fi

        for target_dir in $enabled_targets; do
            if [[ -d "$target_dir" ]] || [[ -d "$(dirname "$target_dir")" ]]; then
                ensure_dir "$target_dir"
                
                local target_type="agents"
                local is_nested=false
                local is_cursor_rules=false
                
                if [[ "$target_dir" == *"/commands"* ]] || [[ "$target_dir" == *"/command"* ]]; then
                    target_type="commands"
                elif [[ "$target_dir" == *"/skills"* ]] || [[ "$target_dir" == *"/skill"* ]]; then
                    target_type="skills"
                    is_nested=true
                elif [[ "$target_dir" == *"/rules"* ]]; then
                    target_type="rule"
                    is_cursor_rules=true
                fi

                local specific_global_source="$global_source"
                if [[ "$global_is_structured" == "true" ]]; then
                    specific_global_source="$global_source/$target_type"
                fi
                
                if [[ -d "$specific_global_source" ]]; then
                    if [[ "$is_cursor_rules" == "true" ]]; then
                        local synced=$(sync_cursor_rules "$specific_global_source" "$target_dir")
                        total_synced=$((total_synced + synced))
                    elif [[ "$is_nested" == "true" ]]; then
                        local synced=$(sync_skills_nested "$specific_global_source" "$target_dir")
                        total_synced=$((total_synced + synced))
                    else
                        local synced=$(sync_files_flat "$specific_global_source" "$target_dir")
                        total_synced=$((total_synced + synced))
                    fi
                fi
            fi
        done
    fi

    echo ""
    log_success "Sync complete: $total_synced items synced"
}

# Sync status
sync_status() {
    local source_dir="${1:-$DEFAULT_SOURCE}"
    local config_path="${2:-$CONFIG_FILE}"

    if [[ -z "$source_dir" ]] && config_exists; then
        source_dir=$(config_get_source "$config_path")
    fi

    if [[ -z "$source_dir" ]]; then
        source_dir="$DEFAULT_SOURCE"
    fi

    echo ""
    log_header "Source: $source_dir"

    if [[ -d "$source_dir" ]]; then
        local skill_count=$(count_items "$source_dir")
        log_info "Skills: $skill_count"
        
        # Check for root-level files
        if [[ -f "$source_dir/AGENTS.md" ]]; then
            echo "  ✓ AGENTS.md (root)"
        fi
        
        # Count nested skills
        if [[ -d "$source_dir/skills" ]]; then
            local nested_count=$(find "$source_dir/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
            if [[ "$nested_count" -gt 0 ]]; then
                echo "  ✓ $nested_count nested skills"
            fi
        fi
    else
        log_warning "Source directory not found"
    fi

    echo ""

    local targets=""
    if config_exists; then
        targets=$(config_get_targets_array "$config_path")
    fi

    if [[ -z "$targets" ]]; then
        targets=$(get_default_targets)
    fi

    log_header "Targets"

    for target in $targets; do
        local tool=$(echo "$target" | cut -d':' -f1)
        local path=$(echo "$target" | cut -d':' -f2)
        local enabled=$(echo "$target" | cut -d':' -f3)

        if [[ "$enabled" != "true" ]]; then
            continue
        fi

        echo ""
        echo "  $tool: $path"

        if [[ -d "$path" ]]; then
            local link_count=$(find "$path" -mindepth 1 -maxdepth 1 -type l 2>/dev/null | wc -l)
            local folder_count=$(find "$path" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
            local broken_count=$(find "$path" -mindepth 1 -maxdepth 1 -type l ! -exec test -e {} \; -print 2>/dev/null | wc -l)

            if [[ "$link_count" -gt 0 ]]; then
                echo "    ✓ $link_count linked files"
            fi
            if [[ "$folder_count" -gt 0 ]]; then
                echo "    ✓ $folder_count linked folders"
            fi
            if [[ "$broken_count" -gt 0 ]]; then
                echo "    ✗ $broken_count broken symlinks"
            fi
        else
            echo "    (directory not found)"
        fi
    done

    echo ""
}

# Unlink all symlinks
unlink_all() {
    local target_dir="$1"
    local remove_all="${2:-false}"

    if [[ ! -d "$target_dir" ]]; then
        log_warning "Directory not found: $target_dir"
        return 1
    fi

    local unlinked=0

    for item in $(find "$target_dir" -mindepth 1 -maxdepth 1 2>/dev/null); do
        if [[ -L "$item" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would unlink: $item"
            else
                rm "$item"
                unlinked=$((unlinked + 1))
            fi
        elif [[ -d "$item" ]] && [[ "$remove_all" == "true" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would remove: $item"
            else
                rm -rf "$item"
                unlinked=$((unlinked + 1))
            fi
        fi
    done

    echo "$unlinked"
}

# Quick sync (skip validation)
sync_quick() {
    sync_all
}

# Export for subshells
export -f get_default_targets sync_all sync_status unlink_all sync_quick
