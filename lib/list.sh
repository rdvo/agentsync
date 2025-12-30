#!/usr/bin/env bash
# list.sh - List installed agents, skills, and commands

# Get sync targets for a specific item type
get_item_targets() {
    local item_type="$1"
    local config_file=".agentsyncrc"
    local targets=""
    
    if [[ -f "$config_file" ]]; then
        # Read targets from config (simple parsing)
        local parsing_targets=false
        while IFS= read -r line; do
            if [[ "$line" =~ ^targets: ]]; then
                parsing_targets=true
                continue
            fi
            if [[ "$parsing_targets" == "true" ]]; then
                [[ -z "$line" ]] && break
                [[ "$line" =~ ^[[:alpha:]] ]] && break
                
                if [[ "$line" =~ -[[:space:]]tool:[[:space:]]*(.*) ]]; then
                    local tool="${BASH_REMATCH[1]}"
                    # Read next line for path
                    read -r path_line
                    if [[ "$path_line" =~ path:[[:space:]]*(.*) ]]; then
                        local path="${BASH_REMATCH[1]}"
                        
                        # Check if matches type
                        local matches=false
                        case "$item_type" in
                            "agent") [[ "$path" == *"/agents"* ]] || [[ "$path" == *"/rules"* ]] && matches=true ;;
                            "skill") [[ "$path" == *"/skills"* ]] || [[ "$path" == *"/skill"* ]] && matches=true ;;
                            "command") [[ "$path" == *"/commands"* ]] || [[ "$path" == *"/command"* ]] && matches=true ;;
                        esac
                        
                        if [[ "$matches" == "true" ]]; then
                            # Add if not present
                            if [[ ! "$targets" == *"$tool"* ]]; then
                                if [[ -z "$targets" ]]; then
                                    targets="$tool"
                                else
                                    targets="$targets, $tool"
                                fi
                            fi
                        fi
                    fi
                fi
            fi
        done < "$config_file"
    else
        # Default targets
        targets="cursor, claude, opencode"
    fi
    
    echo "$targets"
}

cmd_list() {
    local filter_type=""
    local filter_scope=""
    local output_json="false"
    
    # Parse flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a|--agents) filter_type="agent" ;;
            -s|--skills) filter_type="skill" ;;
            -c|--commands) filter_type="command" ;;
            -g|--global) filter_scope="global" ;;
            -p|--project) filter_scope="project" ;;
            --json) output_json="true" ;;
            --help|-h)
                cat << 'EOF'
Usage: agentsync list [options]

List installed agents, skills, and commands.

OPTIONS:
  -a, --agents     Show only agents
  -s, --skills     Show only skills
  -c, --commands   Show only commands
  -g, --global     Show only global items
  -p, --project    Show only project items
  --json           Output as JSON
EOF
                return 0
                ;;
        esac
        shift
    done
    
    # Get sources
    local project_source=".shared"
    local global_source="$HOME/.shared"
    
    if [[ -f ".agentsyncrc" ]]; then
        project_source=$(grep "^source:" .agentsyncrc 2>/dev/null | sed 's/source: *//' | tr -d ' ') || project_source=".shared"
        global_source=$(grep "^global_source:" .agentsyncrc 2>/dev/null | sed 's/global_source: *//' | tr -d ' ') || global_source="$HOME/.shared"
    fi
    
    local sources=()
    local scopes=()
    local src_labels=()
    
    if [[ "$filter_scope" != "global" ]] && [[ -d "$project_source" ]]; then
        sources+=("$project_source")
        scopes+=("project")
        src_labels+=("$project_source")
    fi
    
    if [[ "$filter_scope" != "project" ]] && [[ -d "$global_source" ]]; then
        sources+=("$global_source")
        scopes+=("global")
        src_labels+=("$global_source")
    fi
    
    if [[ ${#sources[@]} -eq 0 ]]; then
        echo "  No source directories found. Run 'agentsync init' first."
        return 0
    fi
    
    local total_items=0
    
    # Process each type
    for type_idx in 0 1 2; do
        case "$type_idx" in
            0) type_name="AGENTS"; type_dir="agents"; singular="agent" ;;
            1) type_name="SKILLS"; type_dir="skills"; singular="skill" ;;
            2) type_name="COMMANDS"; type_dir="commands"; singular="command" ;;
        esac
        
        # Skip if filtered
        if [[ -n "$filter_type" ]]; then
            case "$filter_type" in
                agent) [[ $type_idx -ne 0 ]] && continue ;;
                skill) [[ $type_idx -ne 1 ]] && continue ;;
                command) [[ $type_idx -ne 2 ]] && continue ;;
            esac
        fi
        
        local items_found=()
        local sync_targets=$(get_item_targets "$singular")
        
        # Scan each source
        for src_idx in "${!sources[@]}"; do
            local source="${sources[$src_idx]}"
            local scope="${scopes[$src_idx]}"
            local src_path="${src_labels[$src_idx]}"
            local full_dir="$source/$type_dir"
            
            if [[ -d "$full_dir" ]]; then
                for item in "$full_dir"/*; do
                    [[ -e "$item" ]] || continue
                    local item_name=$(basename "$item")
                    [[ "$item_name" == .* ]] && continue
                    item_name="${item_name%.*}"
                    
                    # Display scope logic:
                    # Show explicit [global] or [project] tag + folder
                    local display_scope=""
                    if [[ "$scope" == "project" ]]; then
                        display_scope="[project] $src_path"
                    else
                        display_scope="[global]  ~/${src_path##*/}"
                    fi
                    
                    items_found+=("$item_name|$display_scope|$sync_targets")
                done
            fi
        done
        
        if [[ ${#items_found[@]} -gt 0 ]]; then
            if [[ "$output_json" == "true" ]]; then
                echo "  \"$type_name\": ["
                local first=true
                for item_info in "${items_found[@]}"; do
                    [[ "$first" == "false" ]] && echo ","
                    first=false
                    IFS='|' read -r name scope targets <<< "$item_info"
                    echo "    {\"name\": \"$name\", \"scope\": \"$scope\", \"syncs_to\": \"$targets\"}"
                done
                echo "  ]"
            else
                echo ""
                echo "  $type_name"
                printf "  %-15s %-15s %-8s %s\n" "NAME" "SOURCE" "STATUS" "SYNCS TO"
                echo ""
                for item_info in "${items_found[@]}"; do
                    IFS='|' read -r name scope targets <<< "$item_info"
                    printf "  %-15s %-15s %-8s %s\n" "$name" "$scope" "~" "$targets"
                done
                total_items=$((total_items + ${#items_found[@]}))
            fi
        fi
    done
    
    if [[ "$output_json" == "true" ]]; then
        echo "}"
    else
        echo ""
        echo "  $total_items items"
    fi
}

export -f cmd_list
