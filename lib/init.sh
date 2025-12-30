#!/usr/bin/env bash
# init.sh - Initialization logic for agentsync

cmd_init() {
    log_header "🔧 agentsync Setup"

    local workspace_root=""
    local home_dir=$(get_home_dir)
    local cwd=$(pwd)

    # --- 1. Context Detection ---
    local is_project=false
    local context_msg="🏠 Global Context"
    
    # Try to find a valid project root (stopping at home)
    if workspace_root=$(find_workspace_root) && [[ "$workspace_root" != "$home_dir" ]]; then
        is_project=true
        context_msg="📦 Project Context: $(basename "$workspace_root")"
    elif [[ "$cwd" != "$home_dir" ]]; then
        # If we are in a subfolder but not a git repo/tool repo, assume user MIGHT want project
        # But default to Global if no signals.
        # However, user expectation: "if i launched it from a folder it should take my existing folder"
        # So let's allow Project option to appear first if we are NOT in home.
        is_project=true
        context_msg="📂 Folder Context: $(basename "$cwd")"
        workspace_root="$cwd"
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
    local project_label="Project ($(basename "$cwd"))"

    if [[ "$is_project" == "true" ]]; then
        local scope_choice=$(prompt_select "Choose Scope:" "$project_label" "My Machine (Global)")
        if [[ "$scope_choice" == "My Machine (Global)" ]]; then
            scope="global"
            default_source="$home_dir/.shared"
        fi
    else
        local scope_choice=$(prompt_select "Choose Scope:" "My Machine (Global)" "$project_label")
        if [[ "$scope_choice" == "$project_label" ]]; then
            scope="project"
            default_source=".shared"
        else
            scope="global"
            default_source="$home_dir/.shared"
        fi
    fi

    # --- 3. Source Directory (Simplified) ---
    echo ""
    log_header "Step 2: Source of Truth"
    echo ""
    
    local home="$HOME"
    local pwd="$(pwd)"
    local source_dir=""
    local candidates=()
    local candidate_labels=()
    
    # Priority check for existing folders
    if [[ "$scope" == "global" ]]; then
        [[ -d "$home/.claude" ]] && { candidates+=("$home/.claude"); candidate_labels+=("~/.claude (Claude)"); }
        [[ -d "$home/.cursor" ]] && { candidates+=("$home/.cursor"); candidate_labels+=("~/.cursor (Cursor)"); }
        [[ -d "$home/.config/opencode" ]] && { candidates+=("$home/.config/opencode"); candidate_labels+=("~/.config/opencode (OpenCode)"); }
        [[ -d "$home/.shared" ]] && { candidates+=("$home/.shared"); candidate_labels+=("~/.shared (agentsync)"); }
        
        if [[ ${#candidates[@]} -eq 1 ]]; then
            # Single match - Fast path
            if prompt_yes_no "Found existing configuration at ${candidates[0]}. Use as source? (Y/n)" "y"; then
                source_dir="${candidates[0]}"
            fi
        elif [[ ${#candidates[@]} -gt 1 ]]; then
            # Multiple matches - Choice path
            echo "Found multiple potential sources:"
            for i in "${!candidate_labels[@]}"; do
                echo "  [$((i+1))] ${candidate_labels[$i]}"
            done
            echo "  [$(( ${#candidates[@]} + 1 ))] Create new (~/.shared)"
            
            echo -n "Choose source [1]: "
            read -r choice
            if [[ -z "$choice" ]]; then choice=1; fi
            
            if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -le "${#candidates[@]}" ]]; then
                source_dir="${candidates[$((choice-1))]}"
            fi
        fi
        
        if [[ -z "$source_dir" ]]; then
            echo -n "Enter source path [~/.shared]: "
            read -r source_dir
            [[ -z "$source_dir" ]] && source_dir="$home/.shared"
        fi
    else
        # Project scope
        [[ -d ".claude" ]] && { candidates+=(".claude"); candidate_labels+=(".claude (Project)"); }
        [[ -d ".cursor" ]] && { candidates+=(".cursor"); candidate_labels+=(".cursor (Project)"); }
        [[ -d ".shared" ]] && { candidates+=(".shared"); candidate_labels+=(".shared (Project)"); }
        
        if [[ ${#candidates[@]} -eq 1 ]]; then
            if prompt_yes_no "Found existing configuration at ${candidates[0]}. Use as source? (Y/n)" "y"; then
                source_dir="${candidates[0]}"
            fi
        elif [[ ${#candidates[@]} -gt 1 ]]; then
            echo "Found multiple potential sources:"
            for i in "${!candidate_labels[@]}"; do
                echo "  [$((i+1))] ${candidate_labels[$i]}"
            done
            echo "  [$(( ${#candidates[@]} + 1 ))] Create new (.shared)"
            
            echo -n "Choose source [1]: "
            read -r choice
            if [[ -z "$choice" ]]; then choice=1; fi
            
            if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -le "${#candidates[@]}" ]]; then
                source_dir="${candidates[$((choice-1))]}"
            fi
        fi
        
        if [[ -z "$source_dir" ]]; then
            echo -n "Enter source path [.shared]: "
            read -r source_dir
            [[ -z "$source_dir" ]] && source_dir=".shared"
        fi
    fi

    # Ensure source directory exists (if new)
    if [[ ! -d "$source_dir" ]]; then
        mkdir -p "$source_dir"
        log_success "Created folder: $source_dir"
    fi
    
    # Only create subdirs if it's a .shared folder (don't pollute .claude)
    if [[ "$source_dir" == *".shared"* ]]; then
        mkdir -p "$source_dir/agents" "$source_dir/commands" "$source_dir/skills" 2>/dev/null || true
    fi
    
    log_success "Source ready: $source_dir"

    # --- 4. Hybrid Config (Project + Global) ---
    if [[ "$scope" == "project" ]]; then
        echo ""
        log_header "Step 3: Inheritance"
        
        # Detect global source
        local detected_global=""
        
        # 1. Try global config first
        if [[ -f "$home_dir/.agentsyncrc" ]]; then
            local cfg_source=$(config_get_source "$home_dir/.agentsyncrc")
            if [[ -n "$cfg_source" ]]; then
                detected_global="$cfg_source"
            fi
        fi
        
        # 2. If no config, try auto-detection (prioritize tools)
        if [[ -z "$detected_global" ]]; then
            if [[ -d "$home_dir/.claude" ]]; then
                detected_global="$home_dir/.claude"
            elif [[ -d "$home_dir/.cursor" ]]; then
                detected_global="$home_dir/.cursor"
            elif [[ -d "$home_dir/.config/opencode" ]]; then
                detected_global="$home_dir/.config/opencode"
            elif [[ -d "$home_dir/.shared" ]]; then
                detected_global="$home_dir/.shared"
            else
                detected_global="$home_dir/.shared"
            fi
        fi
        
        echo "Do you want to include your Global skills ($detected_global) in this project?"
        echo "This overlays personal skills on top of project skills."
        echo ""
        
        if prompt_yes_no "Include global skills? (Y/n)" "y" | grep -qi "yes\|y"; then
            default_global="$detected_global"
            # Ensure global exists if we are going to use it
            if [[ ! -d "$default_global" ]]; then
                mkdir -p "$default_global"
                if [[ "$default_global" == *".shared"* ]]; then
                    mkdir -p "$default_global/agents" "$default_global/commands" "$default_global/skills"
                fi
                log_info "Created global folder: $default_global"
            fi
            log_success "Global inheritance enabled"
        else
            default_global=""
            log_info "Project isolated (no global inheritance)"
        fi
    fi

    # --- 5. Auto-configure all tools ---
    echo ""
    log_header "Step 4: Sync Targets"
    echo "  Auto-detecting tools to sync to..."
    echo ""

    local selected_targets=()
    local home="$HOME"
    
    if [[ "$scope" == "global" ]]; then
        # GLOBAL SCOPE: Sync to ~/.claude, ~/.cursor, etc.
        
        # Auto-add Claude
        if [[ "$source_dir" != *".claude"* ]]; then
            if [[ -d "$home/.claude" ]]; then
                selected_targets+=("claude-agents:$home/.claude/agents:true")
                selected_targets+=("claude-skills:$home/.claude/skills:true")
                selected_targets+=("claude-commands:$home/.claude/commands:false")
            fi
        fi
        
        # Auto-add OpenCode
        if [[ "$source_dir" != *".opencode"* ]]; then
            local oc_path=""
            if [[ -d "$home/.config/opencode" ]]; then
                oc_path="$home/.config/opencode"
            elif [[ -d "$home/.opencode" ]]; then
                oc_path="$home/.opencode"
            fi

            if [[ -n "$oc_path" ]]; then
                selected_targets+=("opencode-agent:$oc_path/agent:true")
                selected_targets+=("opencode-skill:$oc_path/skill:true")
                selected_targets+=("opencode-command:$oc_path/command:false")
            fi
        fi
        
        # Auto-add Cursor
        if [[ "$source_dir" != *".cursor"* ]]; then
            [[ -d "$home/.cursor" ]] && selected_targets+=("cursor:$home/.cursor/rules:true")
        fi
        
        # Auto-add Codex
        if [[ "$source_dir" != *".codex"* ]]; then
            [[ -d "$home/.codex" ]] && selected_targets+=("codex:$home/.codex/skills:true")
        fi
        
    else
        # PROJECT SCOPE: Sync to .claude, .cursor, etc. in CURRENT directory
        # We assume if you are using agentsync, you want to support these tools in your repo.
        # So we add them by default (relative paths).
        
        # Claude
        if [[ "$source_dir" != *".claude"* ]]; then
            selected_targets+=("claude-agents:.claude/agents:true")
            selected_targets+=("claude-skills:.claude/skills:true")
            selected_targets+=("claude-commands:.claude/commands:false")
        fi
        
        # OpenCode
        if [[ "$source_dir" != *".opencode"* ]]; then
            # Project local opencode is usually .opencode (legacy) or just .opencode? 
            # OpenCode docs say per-project is .opencode/agent/
            selected_targets+=("opencode-agent:.opencode/agent:true")
            selected_targets+=("opencode-skill:.opencode/skill:true")
            selected_targets+=("opencode-command:.opencode/command:false")
        fi
        
        # Cursor
        if [[ "$source_dir" != *".cursor"* ]]; then
            selected_targets+=("cursor:.cursor/rules:true")
        fi
        
        # Windsurf
        if [[ "$source_dir" != *".windsurf"* ]]; then
            selected_targets+=("windsurf:.windsurf/workflows:true")
        fi
    fi
    
    # Show what will be synced
    echo "  We will sync (link) contents to:"
    local seen_tools=""
    
    for target in "${selected_targets[@]}"; do
        local name=$(echo "$target" | cut -d':' -f1)
        local path=$(echo "$target" | cut -d':' -f2)
        
        # Group OpenCode
        if [[ "$name" == "opencode-"* ]]; then
            if [[ "$seen_tools" != *"opencode"* ]]; then
                local parent=$(dirname "$path")
                echo "    -> OpenCode ($parent)"
                seen_tools="$seen_tools,opencode"
            fi
            continue
        fi
        
        # Group Claude
        if [[ "$name" == "claude-"* ]]; then
            if [[ "$seen_tools" != *"claude"* ]]; then
                local parent=$(dirname "$path")
                echo "    -> Claude Code ($parent)"
                seen_tools="$seen_tools,claude"
            fi
            continue
        fi
        
        echo "    -> $name ($path)"
    done
    
    if [[ ${#selected_targets[@]} -eq 0 ]]; then
        echo "  (No tools detected - sync will only work if you install them)"
    else
        echo ""
        if ! prompt_yes_no "Proceed with sync? (Y/n)" "y"; then
             log_info "Init cancelled."
             return 0
        fi
    fi
    
    echo ""
    echo "  Syncing from: $source_dir"
    echo ""

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

    config_write "$source_dir" "$default_global" "$enable_daemon" "$enable_hooks" "${selected_targets[@]}"
    
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
