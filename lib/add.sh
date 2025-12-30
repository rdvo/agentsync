#!/usr/bin/env bash
# add.sh - Package manager logic for agentsync

cmd_add() {
    local type_flag=""
    local skill_uri=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type)
                type_flag="$2"
                shift 2
                ;;
            *)
                skill_uri="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$skill_uri" ]]; then
        log_error "Usage: agentsync add <user/repo> [options]"
        log_error "Options: --type <agent|skill|command>"
        return 1
    fi

    # 1. Resolve Source of Truth
    local source_dir=""
    if config_exists; then
        source_dir=$(config_get_source)
    fi

    if [[ -z "$source_dir" ]]; then
        log_warning "No configuration found. Run 'agentsync init' first or choose where to install:"
        local choice=$(prompt_select "Install to:" "Project (.shared/)" "Global (~/.shared/)")
        if [[ "$choice" == "Project (.shared/)" ]]; then
            source_dir=".shared"
        else
            source_dir="$HOME/.shared"
        fi
        mkdir -p "$source_dir/agents" "$source_dir/commands" "$source_dir/skills"
    fi

    log_info "Installing to: $source_dir"

    # 2. Fetch Content
    local temp_dir=$(mktemp -d)
    local repo=""
    local subpath=""

    if [[ "$skill_uri" =~ ^([^/]+/[^/]+)(/.*)?$ ]]; then
        repo="${BASH_REMATCH[1]}"
        subpath="${BASH_REMATCH[2]}"
    else
        log_error "Invalid skill URI: $skill_uri. Expected format: user/repo or user/repo/path"
        return 1
    fi

    log_info "Fetching from GitHub: $repo$subpath"

    if command_exists gh; then
        log_debug "Using gh CLI to fetch"
        if [[ -n "$subpath" ]]; then
            # gh doesn't easily download just a subfolder, so we clone it shallowly
            git clone --depth 1 --filter=blob:none --sparse "https://github.com/$repo.git" "$temp_dir" >/dev/null 2>&1
            if [[ $? -ne 0 ]]; then
                 log_error "Failed to clone repository: $repo"
                 rm -rf "$temp_dir"
                 return 1
            fi
            cd "$temp_dir"
            git sparse-checkout set "${subpath#/}" >/dev/null 2>&1
            cd - >/dev/null
        else
            gh repo clone "$repo" "$temp_dir" -- --depth 1 >/dev/null 2>&1
             if [[ $? -ne 0 ]]; then
                 log_error "Failed to clone repository: $repo"
                 rm -rf "$temp_dir"
                 return 1
            fi
        fi
    else
        log_debug "Using curl + tar to fetch"
        local tarball_url="https://github.com/$repo/tarball/main"
        curl -sL "$tarball_url" | tar -xz -C "$temp_dir" --strip-components=1 >/dev/null 2>&1
        if [[ $? -ne 0 ]]; then
            log_error "Failed to download tarball from $tarball_url. Check your internet connection or if the repo exists."
            rm -rf "$temp_dir"
            return 1
        fi
    fi

    # 3. Install
    local install_src="$temp_dir${subpath}"
    if [[ ! -d "$install_src" ]] && [[ ! -f "$install_src" ]]; then
        log_error "Failed to find content at $skill_uri"
        rm -rf "$temp_dir"
        return 1
    fi

    # Determine type (agent, command, skill)
    local target_subdir=""
    local skill_name=""
    
    if [[ -n "$type_flag" ]]; then
        case "$type_flag" in
            agent|agents) target_subdir="agents" ;;
            skill|skills) target_subdir="skills" ;;
            command|commands) target_subdir="commands" ;;
            *)
                log_error "Invalid type: $type_flag. Must be agent, skill, or command."
                rm -rf "$temp_dir"
                return 1
                ;;
        esac
    else
        # Auto-detection
        if [[ -f "$install_src" ]]; then
            if [[ "$install_src" == *.md ]] || [[ "$install_src" == *.yaml ]] || [[ "$install_src" == *.yml ]]; then
                target_subdir="agents"
            elif [[ "$install_src" == *.sh ]] || [[ "$install_src" == *.py ]] || [[ "$install_src" == *.js ]]; then
                target_subdir="commands"
            else
                target_subdir="agents"
            fi
        else
            # Directory detection
            local dir_name=$(basename "$install_src")
            
            # 1. Check for explicit folder names
            if [[ "$dir_name" == "agents" ]] || [[ "$dir_name" == "personas" ]]; then
                target_subdir="agents"
            elif [[ "$dir_name" == "commands" ]] || [[ "$dir_name" == "scripts" ]]; then
                target_subdir="commands"
            elif [[ "$dir_name" == "skills" ]]; then
                target_subdir="skills"
            # 2. Check for skill structure (SKILL.md)
            elif [[ -f "$install_src/SKILL.md" ]]; then
                target_subdir="skills"
            # 3. Fallback: If it contains loose markdown files, it could be agents, 
            #    but if it's a specific named folder (e.g. "git-tool"), it's likely a skill.
            #    We default to 'skills' for folders unless they look exactly like a collection of agents.
            else
                target_subdir="skills"
            fi
        fi
        log_info "Auto-detected type: $target_subdir (use --type to override)"
    fi
    
    local filename=$(basename "$install_src")
    skill_name="${filename%.*}"
    
    # Ensure source directory exists
    mkdir -p "$source_dir/$target_subdir"
    
    if [[ -f "$install_src" ]]; then
        if [[ "$target_subdir" == "skills" ]]; then
            # Skills usually need a folder
            mkdir -p "$source_dir/$target_subdir/$skill_name"
            cp "$install_src" "$source_dir/$target_subdir/$skill_name/"
        else
            cp "$install_src" "$source_dir/$target_subdir/"
        fi
    else
        # Directory copy
        if [[ "$target_subdir" == "skills" ]]; then
             # If target is skills, we copy the folder AS a skill
             # e.g. adding 'git-tool' -> .shared/skills/git-tool/
             cp -r "$install_src" "$source_dir/$target_subdir/"
        elif [[ "$target_subdir" == "agents" ]] || [[ "$target_subdir" == "commands" ]]; then
             # If target is agents/commands, we likely want the CONTENTS of the folder
             # e.g. adding 'agents/' -> .shared/agents/*
             # But if the user added 'my-agent-pack/', maybe they want files?
             # Let's flatten: copy contents to target dir
             log_info "Flattening folder contents into $source_dir/$target_subdir/"
             cp -r "$install_src"/* "$source_dir/$target_subdir/"
        else
             cp -r "$install_src" "$source_dir/$target_subdir/"
        fi
    fi

    log_success "Installed $skill_name to $source_dir/$target_subdir"
    rm -rf "$temp_dir"

    # 4. Sync
    sync_all "$source_dir"
}

export -f cmd_add
