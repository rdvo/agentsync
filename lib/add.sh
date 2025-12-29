#!/usr/bin/env bash
# add.sh - Package manager logic for agentsync

cmd_add() {
    local skill_uri="$1"

    if [[ -z "$skill_uri" ]]; then
        log_error "Usage: agentsync add <user/repo> or <user/repo/path>"
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
        mkdir -p "$source_dir/agent" "$source_dir/command" "$source_dir/skill"
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
    local target_subdir="skill"
    local skill_name=""
    
    if [[ -f "$install_src" ]]; then
        # If it's a file, try to guess by name or content
        if [[ "$install_src" == *.md ]] || [[ "$install_src" == *.yaml ]]; then
            target_subdir="agent"
        else
            target_subdir="command"
        fi
        
        local filename=$(basename "$install_src")
        skill_name="${filename%.*}"
        # Create a directory for the skill to follow the structure if needed, or just copy file
        # Standard: agents are single files, skills/commands can be folders
        
        if [[ "$target_subdir" == "agent" ]] || [[ "$target_subdir" == "command" ]]; then
            cp "$install_src" "$source_dir/$target_subdir/"
        else
             mkdir -p "$source_dir/$target_subdir/$skill_name"
             cp "$install_src" "$source_dir/$target_subdir/$skill_name/"
        fi

    else
        # If it's a directory
        skill_name=$(basename "$install_src")
        # Check if it looks like an agent (has .md or .yaml)
        if ls "$install_src"/*.md >/dev/null 2>&1 || ls "$install_src"/*.yaml >/dev/null 2>&1; then
            # If directory contains markdowns, it might be a 'skill' containing multiple agents or docs
             target_subdir="skill"
        fi
        
        # Override: if the user explicitly asked for a folder that maps to our structure
        if [[ "$skill_name" == "agent" ]] || [[ "$skill_name" == "command" ]] || [[ "$skill_name" == "skill" ]]; then
             cp -r "$install_src"/* "$source_dir/$skill_name/"
             target_subdir="$skill_name (merged)"
        else
             mkdir -p "$source_dir/$target_subdir"
             cp -r "$install_src" "$source_dir/$target_subdir/"
        fi
    fi

    log_success "Installed $skill_name to $source_dir/$target_subdir"
    rm -rf "$temp_dir"

    # 4. Sync
    sync_all "$source_dir"
}

export -f cmd_add
