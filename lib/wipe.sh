#!/usr/bin/env bash
# wipe.sh - Wipe AI tool folders (with safety warnings)

cmd_wipe() {
    local force=false
    local dry_run=true
    local targets=()
    
    # Parse flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--force)
                force=true
                dry_run=false
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --help|-h)
                cat << 'EOF'
Usage: agentsync wipe [options] [tools...]

Wipe AI tool sync folders (agents, skills, commands, rules).

OPTIONS:
  -f, --force    Skip confirmation (DANGEROUS!)
  --dry-run      Show what would be deleted without deleting (default)

TOOLS:
  claude    Wipe ~/.claude/agents, ~/.claude/skills, ~/.claude/commands
  cursor    Wipe ~/.cursor/rules
  windsurf  Wipe ~/.windsurf/workflows
  codeium   Wipe ~/.codeium/agents
  codex     Wipe ~/.codex
  opencode  Wipe ~/.config/opencode/agent, ~/.config/opencode/skill, ~/.config/opencode/command
  all       Wipe all supported tools

EXAMPLES:
  agentsync wipe                    # Preview what would be wiped
  agentsync wipe --dry-run          # Same as above
  agentsync wipe -f claude cursor   # Actually wipe Claude and Cursor folders
  agentsync wipe -f all             # Wipe everything!

WARNING: This deletes your synced AI configurations!
    Your source of truth (~/.shared or .shared) is NOT affected.
EOF
                return 0
                ;;
            claude|cursor|windsurf|codeium|opencode|codex)
                targets+=("$1")
                shift
                ;;
            all)
                targets=("claude" "cursor" "windsurf" "codeium" "opencode" "codex")
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Default to all if no targets specified
    if [[ ${#targets[@]} -eq 0 ]]; then
        targets=("claude" "cursor" "windsurf" "codeium" "opencode")
    fi
    
    local home_dir=$(get_home_dir)
    local to_delete=()
    
    # Collect files to delete for each tool
    for tool in "${targets[@]}"; do
        case "$tool" in
            claude)
                for folder in ".claude/agents" ".claude/skills" ".claude/commands"; do
                    local full_path="$home_dir/$folder"
                    if [[ -d "$full_path" ]]; then
                        while IFS= read -r item; do
                            [[ -n "$item" ]] && to_delete+=("$item")
                        done < <(find "$full_path" -mindepth 1 2>/dev/null)
                        to_delete+=("$full_path")
                    fi
                done
                ;;
            cursor)
                for folder in ".cursor/rules"; do
                    local full_path="$home_dir/$folder"
                    if [[ -d "$full_path" ]]; then
                        while IFS= read -r item; do
                            [[ -n "$item" ]] && to_delete+=("$item")
                        done < <(find "$full_path" -mindepth 1 2>/dev/null)
                        to_delete+=("$full_path")
                    fi
                done
                ;;
            windsurf)
                # Wipe entire .windsurf folder
                local full_path="$home_dir/.windsurf"
                if [[ -d "$full_path" ]]; then
                    while IFS= read -r item; do
                        [[ -n "$item" ]] && to_delete+=("$item")
                    done < <(find "$full_path" -mindepth 1 2>/dev/null)
                    to_delete+=("$full_path")
                fi
                ;;
            codeium)
                # Wipe entire .codeium folder (contains windsurf subfolder)
                local full_path="$home_dir/.codeium"
                if [[ -d "$full_path" ]]; then
                    while IFS= read -r item; do
                        [[ -n "$item" ]] && to_delete+=("$item")
                    done < <(find "$full_path" -mindepth 1 2>/dev/null)
                    to_delete+=("$full_path")
                fi
                ;;
            codex)
                # Wipe entire .codex folder
                local full_path="$home_dir/.codex"
                if [[ -d "$full_path" ]]; then
                    while IFS= read -r item; do
                        [[ -n "$item" ]] && to_delete+=("$item")
                    done < <(find "$full_path" -mindepth 1 2>/dev/null)
                    to_delete+=("$full_path")
                fi
                ;;
            opencode)
                for folder in ".config/opencode/agent" ".config/opencode/skill" ".config/opencode/command"; do
                    local full_path="$home_dir/$folder"
                    if [[ -d "$full_path" ]]; then
                        while IFS= read -r item; do
                            [[ -n "$item" ]] && to_delete+=("$item")
                        done < <(find "$full_path" -mindepth 1 2>/dev/null)
                        to_delete+=("$full_path")
                    fi
                done
                ;;
        esac
    done
    
    if [[ ${#to_delete[@]} -eq 0 ]]; then
        echo ""
        echo "  ✓ Nothing to wipe - no matching folders found"
        echo ""
        return 0
    fi
    
    echo ""
    echo "  ⚠️  WARNING: WIPING AI TOOL FOLDERS  ⚠️"
    echo ""
    echo "  The following will be DELETED:"
    echo ""
    
    # Show what will be deleted (unique, sorted)
    printf '%s\n' "${to_delete[@]}" | sort -u | while read -r item; do
        echo "    • $item"
    done
    
    echo ""
    echo "  Your source of truth (~/.shared or .shared) is SAFE."
    echo ""
    
    if [[ "$dry_run" == "true" ]]; then
        echo "  [DRY RUN] Run with --force to actually delete."
        echo ""
        return 0
    fi

    # Double confirmation (skip if --force used)
    if [[ "$force" != "true" ]]; then
        echo "  ⚠️  THIS CANNOT BE UNDONE! ⚠️"
        echo ""
        echo -n "  Type 'yes' to confirm: "
        read -r confirm
        echo ""
        
        if [[ "$confirm" != "yes" ]]; then
            echo "  Cancelled."
            return 0
        fi
    fi
    
    # Execute deletion
    local deleted=0
    for item in "${to_delete[@]}"; do
        if [[ -e "$item" ]]; then
            rm -rf "$item" 2>/dev/null && ((deleted++))
        fi
    done
    
    echo "  ✓ Wiped $deleted items"
    echo ""
}

export -f cmd_wipe
