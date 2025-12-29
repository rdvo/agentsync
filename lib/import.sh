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
        "OpenCode Agents:.opencode/agent:agents"
        "Aider Skills:.aider/skills:skills"
    )

    for loc in "${locations[@]}"; do
        local name="${loc%%:*}"
        local remainder="${loc#*:}"
        local path="${remainder%%:*}"
        local subdir="${remainder#*:}"

        if [[ -d "$path" ]]; then
            # Find files that are NOT symlinks (Originals)
            local files=$(find "$path" -mindepth 1 -maxdepth 1 -type f ! -name ".*" 2>/dev/null)
            
            if [[ -z "$files" ]]; then
                continue
            fi
            
            log_header "Found original files in $name ($path)"
            
            for file in $files; do
                local filename=$(basename "$file")
                local target_path="$source_dir/$subdir/$filename"

                # If the file is already in our source dir, skip it (loop prevention)
                if [[ "$(abs_path "$file")" == "$(abs_path "$target_path")" ]]; then
                    continue
                fi

                echo "  Found: $filename"
                
                # Check collision in the Hub
                if [[ -e "$target_path" ]]; then
                    log_warning "    Skipping (Hub already has a file with this name)"
                    skipped_count=$((skipped_count + 1))
                    continue
                fi

                # Prompt user
                if prompt_yes_no "    Link to Hub ($subdir)? (y/n)" "y"; then
                    # INSTEAD OF MOVING: Link the Original -> Hub
                    # This makes the Hub aware of the file, so it can sync it to OTHER tools
                    ensure_dir "$(dirname "$target_path")"
                    link_create "$file" "$target_path" "true"
                    
                    log_success "    Linked to Hub"
                    linked_count=$((linked_count + 1))
                else
                    echo "    Skipped"
                    skipped_count=$((skipped_count + 1))
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
