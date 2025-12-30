#!/usr/bin/env bash
# detect.sh - Smart detection of skill folders across AI tools

set -eo pipefail

# Source utils
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# Known skills/agents/rule folder names
SKILL_FOLDERS="skills agents rules prompts commands context skill agent rule command"
SPECIAL_FILES="AGENTS.md CLAUDE.md AGENTS.override.md"

# Known AI tool directories
TOOL_DIRS=".claude .cursor .windsurf .codeium .aider .github Copilot"

# Known AI tool configurations (tool:dir format)
TOOL_CONFIGS="claude:.claude cursor:.cursor windsurf:.windsurf codeium:.codeium aider:.aider copilot:.Copilot opencode:.config/opencode opencode:.opencode"

# Target mappings (source_folder:tool:target_path format, separated by spaces)
# Note: Claude Code uses plural (agents, commands) OpenCode uses singular (agent, command)
TARGET_MAP="skills:cursor:.cursor/rules skills:windsurf:.windsurf/workflows skills:opencode:.opencode/skill skills:claude:.claude/skills skills:codex:.codex/skills agents:cursor:.cursor/rules agents:claude:.claude/agents agents:opencode:.opencode/agent agents:windsurf:.windsurf/workflows rules:cursor:.cursor/rules rules:windsurf:.windsurf/workflows prompts:claude:.claude/prompts commands:claude:.claude/commands commands:cursor:.cursor/commands commands:opencode:.opencode/command workflows:windsurf:.windsurf/workflows"

# Detect installed AI tools
detect_tools() {
    local tools=""
    for pair in $TOOL_CONFIGS; do
        local tool="${pair%%:*}"
        local dir="${pair#*:}"
        if [[ -d "$dir" ]] || [[ -d "$HOME/$dir" ]]; then
            tools="$tools $tool"
        fi
    done
    echo "$tools"
}

# Get tool display name
get_tool_display_name() {
    local tool="$1"
    case "$tool" in
        claude) echo "Claude Code" ;;
        cursor) echo "Cursor" ;;
        windsurf) echo "Windsurf" ;;
        codeium) echo "Codeium" ;;
        aider) echo "Aider" ;;
        copilot) echo "Copilot" ;;
        *) echo "$tool" ;;
    esac
}

# Find all skill folders in a directory
find_skill_folders() {
    local base_dir="$1"
    local folders=""

    for sf in $SKILL_FOLDERS; do
        local path="$base_dir/$sf"
        if [[ -d "$path" ]]; then
            folders="$folders $sf"
        fi
    done

    echo "$folders"
}

# Scan a directory for all skills/agents/rule folders
scan_directory() {
    local dir="$1"

    if [[ ! -d "$dir" ]]; then
        return 1
    fi

    local result=""
    local has_any=false

    for sf in $SKILL_FOLDERS; do
        local path="$dir/$sf"
        if [[ -d "$path" ]]; then
            local count=$(count_items "$path")
            if [[ "$count" -gt 0 ]]; then
                has_any=true
                if [[ -n "$result" ]]; then
                    result="${result}|"
                fi
                result="${result}${sf}:${count}"
            fi
        fi
    done

    if [[ "$has_any" == "true" ]]; then
        echo "$result"
        return 0
    fi
    return 1
}

# Detect all skill folders (project + global)
detect_all_skill_folders() {
    local workspace_root="${1:-$(pwd)}"
    local home_dir=$(get_home_dir)

    local project_folders=""
    local global_folders=""

    for tool_dir in $TOOL_DIRS; do
        local tool_path="$workspace_root/$tool_dir"
        local result=$(scan_directory "$tool_path")
        if [[ -n "$result" ]]; then
            project_folders="${project_folders}${tool_dir}:${result} "
        fi
    done

    for tool_dir in ".claude" ".cursor" ".codeium" ".config/opencode" ".codex"; do
        global_path="$home_dir/$tool_dir"
        local result=$(scan_directory "$global_path")
        if [[ -n "$result" ]]; then
            global_folders="${global_folders}${tool_dir}:${result} "
        fi
    done

    echo "PROJECT:$project_folders"
    echo "GLOBAL:$global_folders"
}

# Get list of available skills from a source folder
get_skills_list() {
    local source_dir="$1"
    local skills=""

    if [[ -d "$source_dir" ]]; then
        for skill in $(find "$source_dir" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null); do
            skills="$skills $skill"
        done
    fi

    echo "$skills"
}

# Count total skills in a source directory
count_total_skills() {
    local source_dir="$1"
    local count=0

    if [[ -d "$source_dir" ]]; then
        count=$(find "$source_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
    fi

    echo "$count"
}

# Check if a tool is installed
is_tool_installed() {
    local tool="$1"

    for pair in $TOOL_CONFIGS; do
        local t="${pair%%:*}"
        local dir="${pair#*:}"
        if [[ "$t" == "$tool" ]]; then
            [[ -d "$dir" ]] || [[ -d "$HOME/$dir" ]]
            return $?
        fi
    done

    return 1
}

# Get tool installation directory
get_tool_dir() {
    local tool="$1"

    for pair in $TOOL_CONFIGS; do
        local t="${pair%%:*}"
        local dir="${pair#*:}"
        if [[ "$t" == "$tool" ]]; then
            if [[ -d "$dir" ]]; then
                echo "$dir"
                return 0
            elif [[ -d "$HOME/$dir" ]]; then
                echo "$HOME/$dir"
                return 0
            fi
        fi
    done

    return 1
}

# Check and report tool availability
check_tool_status() {
    local tool="$1"
    local display_name=$(get_tool_display_name "$tool")
    local tool_dir=$(get_tool_dir "$tool")
    local installed=false
    local status_msg=""

    # 1. Check if Config Folder exists and has content
    if [[ -n "$tool_dir" ]] && [[ -d "$tool_dir" ]]; then
        local has_content=false
        for item in "$tool_dir"/*; do
            [[ -e "$item" ]] && { has_content=true; break; }
        done
        
        if [[ "$has_content" == "true" ]]; then
            status_msg="$tool_dir"
            installed=true
        else
            status_msg="$tool_dir (Empty)"
            # Even if empty, if it exists, count it? 
            # Let's verify binary first.
        fi
    fi

    # 2. If folder check didn't confirm valid installation, check for Binary
    if [[ "$installed" == "false" ]]; then
        local binary_name="$tool"
        # Map tool names to binary names if different
        case "$tool" in
            claude) binary_name="claude" ;;
            opencode) binary_name="opencode" ;;
            cursor) binary_name="cursor" ;;
            windsurf) binary_name="windsurf" ;;
            codeium) binary_name="codeium" ;;
            codex) binary_name="codex" ;;
        esac

        if command -v "$binary_name" >/dev/null 2>&1; then
            if [[ -n "$tool_dir" ]]; then
                status_msg="$tool_dir (Not initialized)"
            else
                status_msg="Binary found, config missing"
            fi
            installed=true
        fi
    fi

    if [[ "$installed" == "true" ]]; then
        echo "  ✓ $display_name ($status_msg)"
        return 0
    fi
    
    return 1
}

# Check all known tools
check_all_tools() {
    log_header "Installed AI Tools"

    local installed=0
    local seen_tools=""

    for pair in $TOOL_CONFIGS; do
        local tool="${pair%%:*}"
        
        # Skip duplicate tool entries
        if [[ "$seen_tools" == *",$tool,"* ]]; then
            continue
        fi
        seen_tools="$seen_tools$tool,"
        
        if check_tool_status "$tool" >/dev/null 2>&1; then
            check_tool_status "$tool"
            ((installed++))
        fi
    done

    echo ""
    echo "Summary: $installed installed"
}

# Get all targets for a skill type
get_targets_for_skill() {
    local skill_type="$1"
    local targets=""

    for mapping in $TARGET_MAP; do
        local st="${mapping%%:*}"
        if [[ "$st" == "$skill_type" ]]; then
            local rest="${mapping#*:}"
            targets="$targets ${rest%%:*}:${rest#*:}"
        fi
    done

    echo "$targets"
}

# Get skills count for display
get_skills_summary() {
    local dir="$1"
    local count=$(count_items "$dir")
    echo "$count skill(s)"
}

# Check for broken symlinks
find_broken_symlinks() {
    local dir="$1"
    local broken=""

    if [[ -d "$dir" ]]; then
        for link in $(find "$dir" -mindepth 1 -maxdepth 1 -type l 2>/dev/null); do
            if [[ -L "$link" ]] && [[ ! -e "$link" ]]; then
                broken="$broken $link"
            fi
        done
    fi

    echo "$broken"
}

# Detect the best source folder (with most skills)
detect_best_source() {
    local workspace_root="${1:-$(pwd)}"
    local home_dir=$(get_home_dir)

    local best_source=""
    local best_count=0

    for sf in $SKILL_FOLDERS; do
        local path="$workspace_root/.claude/$sf"
        if [[ -d "$path" ]]; then
            local count=$(count_items "$path")
            if [[ "$count" -gt "$best_count" ]]; then
                best_count=$count
                best_source="$path"
            fi
        fi
    done

    if [[ "$best_count" -eq 0 ]]; then
        for sf in $SKILL_FOLDERS; do
            local path="$home_dir/.claude/$sf"
            if [[ -d "$path" ]]; then
                local count=$(count_items "$path")
                if [[ "$count" -gt "$best_count" ]]; then
                    best_count=$count
                    best_source="$path"
                fi
            fi
        done
    fi

    echo "$best_source"
}

# Print detected folders in a nice format
print_detected_folders() {
    local workspace_root="${1:-$(pwd)}"
    local home_dir=$(get_home_dir)

    echo ""
    log_header "📁 Project: $workspace_root"

    local found_any=false

    for tool_dir in $TOOL_DIRS; do
        local tool_path="$workspace_root/$tool_dir"
        if [[ -d "$tool_path" ]]; then
            for sf in $SKILL_FOLDERS; do
                local sf_path="$tool_path/$sf"
                if [[ -d "$sf_path" ]]; then
                    local count=$(count_items "$sf_path")
                    if [[ "$count" -gt 0 ]]; then
                        found_any=true
                        echo "   • $tool_dir/$sf/ ($count items)"
                    fi
                fi
            done
        fi
    done

    if [[ "$found_any" == "false" ]]; then
        echo "   No skill folders found"
    fi

    echo ""
    log_header "🌐 Global: $home_dir"

    local global_found=false
    for tool_dir in ".claude" ".cursor" ".codeium"; do
        local global_path="$home_dir/$tool_dir"
        if [[ -d "$global_path" ]]; then
            for sf in $SKILL_FOLDERS; do
                local sf_path="$global_path/$sf"
                if [[ -d "$sf_path" ]]; then
                    local count=$(count_items "$sf_path")
                    if [[ "$count" -gt 0 ]]; then
                        global_found=true
                        echo "   • ~/$tool_dir/$sf/ ($count items)"
                    fi
                fi
            done
        fi
    done

    if [[ "$global_found" == "false" ]]; then
        echo "   No global skill folders found"
    fi

    echo ""
}

# Export for subshells
export -f detect_tools get_tool_display_name find_skill_folders
export -f scan_directory detect_all_skill_folders get_skills_list
export -f count_total_skills is_tool_installed get_targets_for_skill
export -f get_skills_summary find_broken_symlinks
export -f detect_best_source print_detected_folders
export -f get_tool_dir check_tool_status check_all_tools
