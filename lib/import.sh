#!/usr/bin/env bash
# import.sh - Logic for connecting existing skills (No moving, just linking)

cmd_import() {
    log_header "🔗 Connect Existing Skills"

    # 1. Resolve Source of Truth
    local source_dir=""
    if config_exists; then
        source_dir=$(config_get_source)
    else
        log_error "No configuration found. Run 'agentsync init' first."
        return 1
    fi

    log_info "Central Hub: $source_dir"
    echo ""

    local linked_count=0
    local skipped_count=0

    # 2. Define known locations to scan
    # Format: "Tool Name:Path:TargetSubdir"
    local locations=(
        "Claude Agents:.claude/agents:agents"
        "Cursor Rules:.cursor/rules:agents"
        "Windsurf Workflows:.windsurf/workflows:agents"
        "OpenCode Agents:.config/opencode/agent:agents"
        "OpenCode Agents (Legacy):.opencode/agent:agents"
        "Aider Skills:.aider/skills:skills"
    )
    
    # Global expansion
    local home_locations=()
    for loc in "${locations[@]}"; do
        local name="${loc%%:*}"
        local remainder="${loc#*:}"
        local path="${remainder%%:*}"
        local subdir="${remainder#*:}"
        
        # Check Project local
        if [[ -d "$path" ]]; then
            home_locations+=("$name (Project):$path:$subdir")
        fi
        
        # Check Global
        if [[ -d "$HOME/$path" ]]; then
            home_locations+=("$name (Global):$HOME/$path:$subdir")
        fi
    done
    
    for loc in "${home_locations[@]}"; do
        local name="${loc%%:*}"
        local remainder="${loc#*:}"
        local path="${remainder%%:*}"
        local subdir="${remainder#*:}"

        if [[ -d "$path" ]]; then
            # 1. Find flat files (originals)
            local files=$(find "$path" -mindepth 1 -maxdepth 1 -type f ! -name ".*" 2>/dev/null)
            
            # 2. Find nested agents (folders with AGENT.md/RULE.md)
            local folders=$(find "$path" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
            
            if [[ -z "$files" ]] && [[ -z "$folders" ]]; then
                continue
            fi
            
            log_header "Found items in $name ($path)"
            
            # Process Flat Files
            for file in $files; do
                local filename=$(basename "$file")
                local target_path="$source_dir/$subdir/$filename"

                # Check if it's AGENTS.md (special)
                if [[ "$filename" == "AGENTS.md" ]] || [[ "$filename" == "CLAUDE.md" ]]; then
                    continue
                fi

                # If the file is already in our source dir, skip it (loop prevention)
                if [[ "$(abs_path "$file")" == "$(abs_path "$target_path")" ]]; then
                    continue
                fi

                echo "  Found file: $filename"
                
                # Check collision in the Hub
                if [[ -e "$target_path" ]]; then
                    log_warning "    Skipping (Hub already has a file with this name)"
                    skipped_count=$((skipped_count + 1))
                    continue
                fi

                # Prompt user
                if prompt_yes_no "    Link to Hub ($subdir)? (y/n)" "y"; then
                    ensure_dir "$(dirname "$target_path")"
                    link_create "$file" "$target_path" "true"
                    
                    log_success "    Linked to Hub"
                    linked_count=$((linked_count + 1))
                else
                    echo "    Skipped"
                    skipped_count=$((skipped_count + 1))
                fi
            done

            # Process Nested Folders (e.g. Claude agents)
            for folder in $folders; do
                local dirname=$(basename "$folder")
                local source_file=""
                
                # Check for agent definition inside
                if [[ -f "$folder/AGENT.md" ]]; then source_file="$folder/AGENT.md"; fi
                if [[ -f "$folder/RULE.md" ]]; then source_file="$folder/RULE.md"; fi
                if [[ -f "$folder/$dirname.md" ]]; then source_file="$folder/$dirname.md"; fi
                
                if [[ -n "$source_file" ]]; then
                    # We flatten it into the Hub: Hub/agents/dirname.md
                    local target_path="$source_dir/$subdir/$dirname.md"
                    
                    # Loop prevention
                    if [[ "$(abs_path "$source_file")" == "$(abs_path "$target_path")" ]]; then
                        continue
                    fi
                    
                    echo "  Found nested agent: $dirname"
                    
                    if [[ -e "$target_path" ]]; then
                        log_warning "    Skipping (Hub already has '$dirname.md')"
                        skipped_count=$((skipped_count + 1))
                        continue
                    fi
                    
                    if prompt_yes_no "    Link to Hub ($subdir)? (y/n)" "y"; then
                        ensure_dir "$(dirname "$target_path")"
                        link_create "$source_file" "$target_path" "true"
                        
                        log_success "    Linked to Hub (Flattened)"
                        linked_count=$((linked_count + 1))
                    else
                        echo "    Skipped"
                        skipped_count=$((skipped_count + 1))
                    fi
                fi
            done
        fi
    done

    echo ""
    if [[ "$linked_count" -gt 0 ]]; then
        log_success "Connection complete! $linked_count files linked to Hub."
        log_info "Run 'agentsync sync' to broadcast them to all other tools."
    elif [[ "$skipped_count" -gt 0 ]]; then
        log_info "No files linked."
    else
        log_info "No new original files found."
    fi
}

export -f cmd_import
