#!/usr/bin/env bash
# init.sh - Initialization logic for agentsync

cmd_init() {
    log_header "🔧 agentsync Setup"

    local workspace_root=$(find_workspace_root)
    local home_dir=$(get_home_dir)
    local cwd=$(pwd)

    # --- 1. Context Detection ---
    local is_project=false
    local context_msg="🏠 Global Context"
    
    # Check for project signals (git, package managers, existing AI tools)
    if [[ -d ".git" ]] || [[ -f "package.json" ]] || [[ -f "Cargo.toml" ]] || [[ -f "requirements.txt" ]] || [[ -d ".claude" ]] || [[ -d ".cursor" ]]; then
        is_project=true
        context_msg="📦 Project Context: $(basename "$workspace_root")"
    fi

    log_info "$context_msg"

    # --- 2. Determine Scope ---
    echo ""
    log_header "Step 1: Choose Scope"
    echo "Who is this configuration for?"
    echo ""

    local scope="project"
    local default_source=".shared"
    local default_global=""

    if [[ "$is_project" == "true" ]]; then
        local scope_choice=$(prompt_select "Choose Scope:" "Project (.shared/)" "My Machine (Global: ~/.shared/)")
        if [[ "$scope_choice" == "My Machine (Global: ~/.shared/)" ]]; then
            scope="global"
            default_source="$home_dir/.shared"
        fi
    else
        local scope_choice=$(prompt_select "Choose Scope:" "My Machine (Global: ~/.shared/)" "New Project (Current Folder)")
        if [[ "$scope_choice" == "New Project (Current Folder)" ]]; then
            scope="project"
            default_source=".shared"
        else
            scope="global"
            default_source="$home_dir/.shared"
        fi
    fi

    # --- 3. Source Directory (Smart Detection) ---
    echo ""
    log_header "Step 2: Source of Truth"
    
    # Check for existing tool folders to suggest
    local suggested_source="$default_source"
    local found_existing=false
    
    if [[ -d ".cursor/rules" ]] && has_skills ".cursor/rules"; then
        suggested_source=".cursor/rules"
        found_existing=true
    elif [[ -d ".claude/agents" ]] && has_skills ".claude/agents"; then
        suggested_source=".claude/agents"
        found_existing=true
    elif [[ -d ".windsurf/workflows" ]] && has_skills ".windsurf/workflows"; then
        suggested_source=".windsurf/workflows"
        found_existing=true
    fi

    echo "Where should we store your master copy of agents & skills?"
    
    if [[ "$found_existing" == "true" ]]; then
        echo "💡 We found existing agents in: $suggested_source"
        if prompt_yes_no "Use $suggested_source as the Source of Truth? (Y/n)" "y"; then
             default_source="$suggested_source"
        else
             echo "Okay, you can pick a different folder."
        fi
    else
        echo "You will add your markdown/yaml files here."
    fi

    local source_dir=""
    echo -n "Enter folder path [${default_source}]: "
    read -r source_dir
    if [[ -z "$source_dir" ]]; then
        source_dir="$default_source"
    fi

    # Create structure
    if [[ "$source_dir" == *".shared"* ]]; then
        mkdir -p "$source_dir/agents"
        mkdir -p "$source_dir/commands"
        mkdir -p "$source_dir/skills"
    else
        # Flat structure for existing tool folders
        mkdir -p "$source_dir"
    fi
    log_success "Folder ready: $source_dir"

    # --- 4. Hybrid Config (Project + Global) ---
    if [[ "$scope" == "project" ]]; then
        echo ""
        log_header "Step 3: Inheritance"
        echo "Do you want to include your Global skills (~/.shared) in this project?"
        echo "This overlays personal skills on top of project skills."
        echo ""
        
        if prompt_yes_no "Include global skills? (Y/n)" "y" | grep -qi "yes\|y"; then
            default_global="$home_dir/.shared"
            # Ensure global exists if we are going to use it
            if [[ ! -d "$default_global" ]]; then
                mkdir -p "$default_global/agents"
                mkdir -p "$default_global/commands"
                mkdir -p "$default_global/skills"
                log_info "Created global folder: $default_global"
            fi
            log_success "Global inheritance enabled"
        else
            default_global=""
            log_info "Project isolated (no global inheritance)"
        fi
    fi

    # --- 5. Tool Selection (Context-Aware) ---
    echo ""
    log_header "Step 4: Target Tools"
    echo "Which tools should we sync to?"
    echo ""

    local target_options=()
    local detected_msg="Detected:"

    # Helper to add target options
    add_target() {
        target_options+=("$1" "$2" "$3" "$4")
    }

    local tool_prefix=""
    if [[ "$scope" == "global" ]]; then
        tool_prefix="$home_dir/"
    else
        tool_prefix=""
    fi

    # Detect & Add Claude
    if [[ -d "${tool_prefix}.claude" ]] || [[ -d "$home_dir/.claude" ]]; then
        detected_msg="$detected_msg Claude,"
        local claude_path="${tool_prefix}.claude"
        [[ "$scope" == "global" ]] && claude_path="$home_dir/.claude"
        
        add_target "claude-agents" "Claude Agents" "$claude_path/agents" "true"
        add_target "claude-commands" "Claude Commands" "$claude_path/commands" "false"
        add_target "claude-skills" "Claude Skills" "$claude_path/skills" "true"
    fi

    # Detect & Add OpenCode
    if [[ -d "${tool_prefix}.opencode" ]] || [[ -d "$home_dir/.config/opencode" ]]; then
        detected_msg="$detected_msg OpenCode,"
        local opencode_path="${tool_prefix}.opencode"
        [[ "$scope" == "global" ]] && opencode_path="$home_dir/.config/opencode"
        
        add_target "opencode-agent" "OpenCode Agent" "$opencode_path/agent" "true"
        add_target "opencode-command" "OpenCode Command" "$opencode_path/command" "false"
        add_target "opencode-skill" "OpenCode Skill" "$opencode_path/skill" "true"
    fi

    # Detect & Add Cursor
    if [[ -d "${tool_prefix}.cursor" ]] || [[ -d "$home_dir/.cursor" ]]; then
        detected_msg="$detected_msg Cursor,"
        local cursor_path="${tool_prefix}.cursor"
        # Note: Cursor global rules are often handled via UI, but some CLI tools use ~/.cursor
        [[ "$scope" == "global" ]] && cursor_path="$home_dir/.cursor"
        
        add_target "cursor" "Cursor Rules" "$cursor_path/rules" "true"
    fi

    # Detect & Add Windsurf
    if [[ -d "${tool_prefix}.windsurf" ]] || [[ -d "$home_dir/.windsurf" ]]; then
        detected_msg="$detected_msg Windsurf,"
        local windsurf_path="${tool_prefix}.windsurf"
        [[ "$scope" == "global" ]] && windsurf_path="$home_dir/.windsurf"
        add_target "windsurf" "Windsurf Workflows" "$windsurf_path/workflows" "true"
    fi

    # Detect & Add Codex
    if [[ -d "${tool_prefix}.codex" ]] || [[ -d "$home_dir/.codex" ]]; then
        detected_msg="$detected_msg Codex,"
        local codex_path="${tool_prefix}.codex"
        [[ "$scope" == "global" ]] && codex_path="$home_dir/.codex"
        add_target "codex" "Codex Skills" "$codex_path/skills" "true"
    fi



    # Fallback if nothing detected
    if [[ "$detected_msg" == "Detected:" ]]; then
        log_warning "No tools detected. Adding defaults."
        add_target "claude-agents" "Claude Agents" ".claude/agents" "true"
        add_target "opencode-agent" "OpenCode Agent" ".opencode/agent" "true"
    fi

    # Interactive Selection
    local selected_targets=()
    local i=0
    while [[ $i -lt ${#target_options[@]} ]]; do
        local key="${target_options[$i]}"
        local name="${target_options[$((i+1))]}"
        local path="${target_options[$((i+2))]}"
        local default="${target_options[$((i+3))]}"
        
        # Don't sync TO the source directory (avoid loop)
        if [[ "$path" == "$source_dir" ]] || [[ "$path" == "$source_dir/"* ]]; then
             i=$((i + 4))
             continue
        fi

        local prompt_str="  Sync to $name ($path)?"
        local answer="n"
        
        if [[ "$default" == "true" ]]; then
            answer=$(prompt_yes_no "$prompt_str (Y/n)" "y" || echo "n")
        else
            answer=$(prompt_yes_no "$prompt_str (y/N)" "n" || echo "n")
        fi

        if echo "$answer" | grep -qi "yes\|y"; then
            selected_targets+=("${key}:${path}:true")
        else
            selected_targets+=("${key}:${path}:false")
        fi

        i=$((i + 4))
    done

    # --- 6. Daemon & Hooks ---
    local enable_daemon="false"
    local enable_hooks="false"

    echo ""
    log_header "Step 5: Automation"
    
    if prompt_yes_no "Enable auto-sync daemon? (Y/n)" "y" | grep -qi "yes\|y"; then
        enable_daemon="true"
    fi

    if [[ "$scope" == "project" ]] && [[ -d ".git" ]]; then
        if prompt_yes_no "Install git hooks (sync on checkout)? (Y/n)" "y" | grep -qi "yes\|y"; then
            enable_hooks="true"
            install_git_hooks
        fi
    fi

    # --- 7. Execution ---
    echo ""
    log_header "🚀 Initializing..."

    config_write "$source_dir" "${selected_targets[@]}" "$default_global" "$enable_daemon" "$enable_hooks"
    
    # Run first sync
    echo ""
    sync_all "$source_dir"

    # --- 8. Adoption (Import) ---
    echo ""
    log_header "Step 6: Adoption"
    if prompt_yes_no "Search for existing agents in Claude/Cursor/etc. to import? (Y/n)" "y" | grep -qi "yes\|y"; then
        cmd_import
    fi

    # --- 9. Summary ---
    echo ""
    log_success "✅ Setup Complete!"
    echo ""
    echo "Summary:"
    echo "  • Scope:  $scope"
    echo "  • Source: $source_dir"
    [[ -n "$default_global" ]] && echo "  • Global: $default_global (Inherited)"
    echo "  • Tools:  ${#selected_targets[@]} configured"
    
    echo ""
    echo "Next Steps:"
    echo "  1. Add agents to: $source_dir/agents/"
    echo "  2. Add skills to: $source_dir/skills/"
    
    if [[ "$enable_daemon" == "true" ]]; then
        echo ""
        log_info "Starting auto-sync daemon..."
        watch_start "$source_dir"
    else
        echo "  • Run 'agentsync sync' to update tools manually"
    fi
}

export -f cmd_init
