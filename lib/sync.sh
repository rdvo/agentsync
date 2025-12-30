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
        log_info "Found AGENTS.md (linking to roots)" >&2
        
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

    # 1. Handle flat files (source/skill.md -> target/skill/SKILL.md)
    # log_debug "Scanning for flat skills in $source_skill_dir"
    for skill_file in "$source_skill_dir"/*.md; do
        [[ -f "$skill_file" ]] || continue
        [[ "$(basename "$skill_file")" == "AGENTS.md" ]] && continue
        
        # log_debug "Found flat skill: $skill_file"
        local skill_name=$(basename "$skill_file" .md)
        local target_folder="$target_skill_dir/$skill_name"
        local target_file="$target_folder/SKILL.md"
        
        ensure_dir "$target_folder" >&2
        
        if [[ ! -e "$target_file" ]]; then
            if link_create "$skill_file" "$target_file" "false"; then
                log_info "Linked skill (from file): $skill_name" >&2
                synced_count=$((synced_count + 1))
            fi
        fi
    done

    # 2. Handle folders (source/skill/SKILL.md)
    for skill_folder in "$source_skill_dir"/*/; do
        [[ -d "$skill_folder" ]] || continue
        
        local skill_name=$(basename "$skill_folder")
        local skill_file="$skill_folder/SKILL.md"
        
        if [[ -f "$skill_file" ]]; then
            local target_folder="$target_skill_dir/$skill_name"
            local target_file="$target_folder/SKILL.md"
            
            # Create target folder if needed
            ensure_dir "$target_folder" >&2
            
            # Link the SKILL.md file
            if [[ ! -e "$target_file" ]]; then
                if link_create "$skill_file" "$target_file" "false"; then
                    log_info "Linked skill: $skill_name" >&2
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

# Sync Nested Agents (folders with AGENT.md or RULE.md)
sync_nested_agents() {
    local source_dir="$1"
    local target_dir="$2"
    local agent_filename="${3:-AGENT.md}"
    local synced_count=0

    if [[ ! -d "$source_dir" ]]; then
        echo 0
        return
    fi

    ensure_dir "$target_dir" >&2

    # 1. Handle flat files (source/*.md)
    for agent_file in "$source_dir"/*.md; do
        [[ -f "$agent_file" ]] || continue
        [[ "$(basename "$agent_file")" == "AGENTS.md" ]] && continue
        
        local agent_name=$(basename "$agent_file" .md)
        local target_folder="$target_dir/$agent_name"
        local target_file="$target_folder/$agent_filename"
        
        ensure_dir "$target_folder" >&2
        
        if [[ ! -e "$target_file" ]]; then
            if link_create "$agent_file" "$target_file" "false"; then
                log_info "Linked agent: $agent_name ($agent_filename)" >&2
                synced_count=$((synced_count + 1))
            fi
        fi
    done

    # 2. Handle folders (source/agent/AGENT.md)
    for agent_folder in "$source_dir"/*/; do
        [[ -d "$agent_folder" ]] || continue
        
        local agent_name=$(basename "$agent_folder")
        local source_file=""
        
        # Find the agent definition inside
        if [[ -f "$agent_folder/AGENT.md" ]]; then source_file="$agent_folder/AGENT.md"; fi
        if [[ -f "$agent_folder/RULE.md" ]]; then source_file="$agent_folder/RULE.md"; fi
        if [[ -f "$agent_folder/$agent_name.md" ]]; then source_file="$agent_folder/$agent_name.md"; fi
        
        if [[ -n "$source_file" ]]; then
            local target_folder="$target_dir/$agent_name"
            local target_file="$target_folder/$agent_filename"
            
            ensure_dir "$target_folder" >&2
            
            if [[ ! -e "$target_file" ]]; then
                if link_create "$source_file" "$target_file" "false"; then
                    log_info "Linked agent (from folder): $agent_name" >&2
                    synced_count=$((synced_count + 1))
                fi
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

    ensure_dir "$target_dir" >&2

    for item in "$source_dir"/*; do
        [[ -e "$item" ]] || continue
        
        local item_name=$(basename "$item")
        local target_path="$target_dir/$item_name"
        
        # Skip special files
        if [[ "$item_name" == "AGENTS.md" ]]; then
            continue
        fi

        # Avoid recursive linking
        local abs_source=$(abs_path "$item")
        local abs_target=$(abs_path "$target_dir")
        if [[ "$(dirname "$abs_source")" == "$abs_target" ]]; then
            continue
        fi

        # Case 1: Item is a directory (e.g. from .claude/agents/foo/)
        if [[ -d "$item" ]]; then
            # Check for AGENT.md or similar inside
            local agent_file=""
            if [[ -f "$item/AGENT.md" ]]; then
                agent_file="$item/AGENT.md"
            elif [[ -f "$item/agent.md" ]]; then
                agent_file="$item/agent.md"
            elif [[ -f "$item/$item_name.md" ]]; then
                agent_file="$item/$item_name.md"
            elif [[ -f "$item/RULE.md" ]]; then
                agent_file="$item/RULE.md"
            fi
            
            # If we found an agent file inside the folder, link THAT file to the target name
            if [[ -n "$agent_file" ]]; then
                # Target should be flat: target_dir/foo.md
                local flat_target="$target_dir/$item_name.md"
                if [[ ! -e "$flat_target" ]]; then
                    if link_create "$agent_file" "$flat_target" "false"; then
                        log_info "Linked flat agent (from folder): $item_name" >&2
                        synced_count=$((synced_count + 1))
                    fi
                fi
            fi
            continue
        fi

        # Case 2: Item is a flat file
        if [[ ! -e "$target_path" ]]; then
            if link_create "$item" "$target_path" "false"; then
                log_info "Linked flat file: $item_name" >&2
                synced_count=$((synced_count + 1))
            fi
        fi
    done

    echo "$synced_count"
}

# Main sync function
sync_all() {
    local source_dir=""
    local config_path="${2:-$CONFIG_FILE}"

    # 1. Prefer explicit CLI argument
    if [[ -n "$1" ]]; then
        source_dir="$1"
    
    # 2. Then try config file
    elif config_exists; then
        source_dir=$(config_get_source "$config_path")
    fi

    # 3. Fallback to default
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
            local is_nested_agent=false
            local nested_filename="AGENT.md"
            
            if [[ "$target_dir" == *"/commands"* ]] || [[ "$target_dir" == *"/command"* ]]; then
                target_type="commands"
            elif [[ "$target_dir" == *"/skills"* ]] || [[ "$target_dir" == *"/skill"* ]]; then
                target_type="skills"
                is_nested=true
            elif [[ "$target_dir" == *"/rules"* ]]; then
                target_type="rule"
                is_nested_agent=true
                nested_filename="RULE.md"
            elif [[ "$target_dir" == *"/agents"* ]]; then
                target_type="agents"
                # Claude agents are FLAT files (according to official docs)
                # So we treat them just like OpenCode agents
            fi

            local specific_source="$source_dir"
            
            if [[ "$is_structured" == "true" ]]; then
                # Map target type to potential source folders
                if [[ "$target_type" == "agents" ]] || [[ "$target_type" == "rule" ]]; then
                    # Agents can be in agents/ or rules/
                    if [[ -d "$source_dir/agents" ]]; then
                        specific_source="$source_dir/agents"
                    elif [[ -d "$source_dir/rules" ]]; then
                        specific_source="$source_dir/rules"
                    else
                        specific_source="$source_dir/$target_type"
                    fi
                else
                    # Skills/Commands usually match
                    specific_source="$source_dir/$target_type"
                fi
            else
                specific_source="$source_dir"
            fi

            if [[ -d "$specific_source" ]]; then
                if [[ "$is_nested_agent" == "true" ]]; then
                    # Nested agents (Cursor Rules / Claude Agents)
                    local synced=$(sync_nested_agents "$specific_source" "$target_dir" "$nested_filename")
                    total_synced=$((total_synced + synced))
                elif [[ "$is_nested" == "true" ]]; then
                    # Skills need nested folder structure
                    local synced=$(sync_skills_nested "$specific_source" "$target_dir")
                    total_synced=$((total_synced + synced))
                else
                    # Flat agents (OpenCode) and commands
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
                local is_nested_agent=false
                local nested_filename="AGENT.md"
                
                if [[ "$target_dir" == *"/commands"* ]] || [[ "$target_dir" == *"/command"* ]]; then
                    target_type="commands"
                elif [[ "$target_dir" == *"/skills"* ]] || [[ "$target_dir" == *"/skill"* ]]; then
                    target_type="skills"
                    is_nested=true
                elif [[ "$target_dir" == *"/rules"* ]]; then
                    target_type="rule"
                    is_nested_agent=true
                    nested_filename="RULE.md"
                elif [[ "$target_dir" == *"/agents"* ]]; then
                    target_type="agents"
                    if [[ "$target_dir" == *".claude"* ]]; then
                        is_nested_agent=true
                        nested_filename="AGENT.md"
                    fi
                fi

                local specific_global_source="$global_source"
                if [[ "$global_is_structured" == "true" ]]; then
                    # Map target type to potential source folders
                    if [[ "$target_type" == "agents" ]] || [[ "$target_type" == "rule" ]]; then
                        if [[ -d "$global_source/agents" ]]; then
                            specific_global_source="$global_source/agents"
                        elif [[ -d "$global_source/rules" ]]; then
                            specific_global_source="$global_source/rules"
                        else
                            specific_global_source="$global_source/$target_type"
                        fi
                    else
                        specific_global_source="$global_source/$target_type"
                    fi
                fi
                
                if [[ -d "$specific_global_source" ]]; then
                    if [[ "$is_nested_agent" == "true" ]]; then
                        local synced=$(sync_nested_agents "$specific_global_source" "$target_dir" "$nested_filename")
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
