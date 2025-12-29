#!/usr/bin/env bash
# config.sh - Configuration file reading and writing

set -eo pipefail

# Source utils
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# Default config file name
CONFIG_FILE=".agentsyncrc"
CONFIG_FILE_ALT=".agentsync.yaml"

# Default configuration
DEFAULT_SOURCE=".shared"
DEFAULT_GLOBAL_SOURCE="$HOME/.shared"

# Default targets
DEFAULT_TARGETS=(
    "cursor:.cursor/rules:true"
    "windsurf:.windsurf/workflows:true"
)

# Check if config file exists
config_exists() {
    [[ -f "$CONFIG_FILE" ]] || [[ -f "$CONFIG_FILE_ALT" ]]
}

# Get config file path
get_config_path() {
    if [[ -f "$CONFIG_FILE" ]]; then
        echo "$CONFIG_FILE"
    elif [[ -f "$CONFIG_FILE_ALT" ]]; then
        echo "$CONFIG_FILE_ALT"
    else
        echo ""
    fi
}

# Read source from config
config_get_source() {
    local config_path="${1:-$CONFIG_FILE}"

    if [[ ! -f "$config_path" ]]; then
        echo ""
        return 1
    fi

    # Try YAML format first
    local source=$(grep -E "^source:" "$config_path" 2>/dev/null | sed 's/source: *//' | tr -d ' ')
    if [[ -n "$source" ]]; then
        echo "$source"
        return 0
    fi

    # Try key=value format
    source=$(grep -E "^SOURCE_DIR=" "$config_path" 2>/dev/null | sed 's/SOURCE_DIR=//' | tr -d '"')
    if [[ -n "$source" ]]; then
        echo "$source"
        return 0
    fi

    echo ""
    return 1
}

# Read global source from config
config_get_global_source() {
    local config_path="${1:-$CONFIG_FILE}"

    if [[ ! -f "$config_path" ]]; then
        echo ""
        return 1
    fi

    local global=$(grep -E "^global_source:" "$config_path" 2>/dev/null | sed 's/global_source: *//' | tr -d ' ')
    if [[ -n "$global" ]]; then
        echo "$global"
        return 0
    fi

    echo ""
    return 1
}

# Read targets from config
config_get_targets() {
    local config_path="${1:-$CONFIG_FILE}"

    if [[ ! -f "$config_path" ]]; then
        echo ""
        return 1
    fi

    # Look for targets section
    local in_targets=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^targets: ]]; then
            in_targets=true
            continue
        fi
        if [[ "$in_targets" == "true" ]]; then
            # Stop at next section or empty line
            [[ -z "$line" ]] && break
            [[ ! "$line" =~ ^[[:space:]] ]] && break
            echo "$line"
        fi
    done < "$config_path"
}

# Get all targets as an array
config_get_targets_array() {
    local config_path="${1:-$CONFIG_FILE}"
    local targets=()

    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            # Parse YAML target entry
            local tool=$(echo "$line" | sed -n 's/.*tool:[[:space:]]*\([^[:space:]]*\).*/\1/p')
            local path=$(echo "$line" | sed -n 's/.*path:[[:space:]]*\([^[:space:]]*\).*/\1/p')
            local enabled=$(echo "$line" | sed -n 's/.*enabled:[[:space:]]*\([^[:space:]]*\).*/\1/p')

            if [[ -n "$tool" ]] && [[ -n "$path" ]]; then
                targets+=("${tool}:${path}:${enabled:-true}")
            fi
        fi
    done < <(config_get_targets "$config_path")

    echo "${targets[@]}"
}

# Check if a target is enabled
config_is_target_enabled() {
    local target="$1"
    local config_path="${2:-$CONFIG_FILE}"

    if [[ ! -f "$config_path" ]]; then
        # Default to enabled if no config
        echo "true"
        return 0
    fi

    # Check in targets array
    while IFS= read -r line; do
        local tool=$(echo "$line" | sed -n 's/.*tool:[[:space:]]*\([^[:space:]]*\).*/\1/p')
        local enabled=$(echo "$line" | sed -n 's/.*enabled:[[:space:]]*\([^[:space:]]*\).*/\1/p')
        if [[ "$tool" == "$target" ]]; then
            echo "${enabled:-true}"
            return 0
        fi
    done < <(config_get_targets "$config_path")

    echo "true"
}

# Read exclusions from config
config_get_exclusions() {
    local config_path="${1:-$CONFIG_FILE}"

    if [[ ! -f "$config_path" ]]; then
        echo ""
        return 1
    fi

    grep -E "^\s*- " "$config_path" 2>/dev/null | sed 's/^\s*- //' | tr -d '\r'
}

# Check if a skill should be excluded
config_should_exclude() {
    local skill_name="$1"
    local config_path="${2:-$CONFIG_FILE}"

    if [[ ! -f "$config_path" ]]; then
        return 1
    fi

    while IFS= read -r pattern; do
        if [[ "$skill_name" == $pattern ]]; then
            return 0
        fi
    done < <(config_get_exclusions "$config_path")

    return 1
}

# Get watch setting
config_get_watch() {
    local config_path="${1:-$CONFIG_FILE}"

    if [[ ! -f "$config_path" ]]; then
        echo "false"
        return 0
    fi

    local watch=$(grep -E "^watch:" "$config_path" 2>/dev/null | sed 's/watch: *//' | tr -d ' ')
    echo "${watch:-false}"
}

# Get git hooks setting
config_get_git_hooks() {
    local config_path="${1:-$CONFIG_FILE}"

    if [[ ! -f "$config_path" ]]; then
        echo "false"
        return 0
    fi

    local hooks=$(grep -E "^git_hooks:" "$config_path" 2>/dev/null | sed 's/git_hooks: *//' | tr -d ' ')
    echo "${hooks:-false}"
}

# Write configuration
config_write() {
    local source="$1"
    local targets="$2"
    local global_source="$3"
    local watch_enabled="$4"
    local git_hooks_enabled="$5"

    cat > "$CONFIG_FILE" << EOF
# agentsync configuration
# Generated by 'agentsync init'

source: $source

$(if [[ -n "$global_source" ]]; then
echo "global_source: $global_source"
fi)

targets:
$(for target in "${targets[@]}"; do
    IFS=':' read -r tool path enabled <<< "$target"
    echo "  - tool: $tool"
    echo "    path: $path"
    echo "    enabled: $enabled"
    echo ""
done)

# Auto-sync daemon (true/false)
watch: $watch_enabled

# Git hooks (true/false)
git_hooks: $git_hooks_enabled
EOF

    log_success "Created $CONFIG_FILE"
}

# Update a single config value
config_update() {
    local key="$1"
    local value="$2"
    local config_path="${3:-$CONFIG_FILE}"

    if [[ ! -f "$config_path" ]]; then
        log_error "Config file not found: $config_path"
        return 1
    fi

    # Create temp file
    local temp_file=$(mktemp)

    # Replace the line
    sed "s/^${key}:.*/${key}: ${value}/" "$config_path" > "$temp_file"

    # Backup and replace
    cp "$config_path" "${config_path}.bak"
    mv "$temp_file" "$config_path"

    log_success "Updated $key to $value"
}

# Add target to config
config_add_target() {
    local tool="$1"
    local path="$2"
    local config_path="${3:-$CONFIG_FILE}"

    if [[ ! -f "$config_path" ]]; then
        log_error "Config file not found: $config_path"
        return 1
    fi

    # Insert before targets section or at end
    local temp_file=$(mktemp)

    local in_targets=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^targets: ]]; then
            in_targets=true
            echo "$line" >> "$temp_file"
            echo "  - tool: $tool" >> "$temp_file"
            echo "    path: $path" >> "$temp_file"
            echo "    enabled: true" >> "$temp_file"
            continue
        fi
        if [[ "$in_targets" == "true" ]] && [[ -z "$line" ]]; then
            in_targets=false
        fi
        echo "$line" >> "$temp_file"
    done < "$config_path"

    mv "$temp_file" "$config_path"
    log_success "Added target: $tool -> $path"
}

# Remove target from config
config_remove_target() {
    local tool="$1"
    local config_path="${2:-$CONFIG_FILE}"

    if [[ ! -f "$config_path" ]]; then
        log_error "Config file not found: $config_path"
        return 1
    fi

    local temp_file=$(mktemp)
    local skip_block=false

    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]tool:[[:space:]]${tool} ]]; then
            skip_block=true
            continue
        fi
        if [[ "$skip_block" == "true" ]]; then
            # Skip until we hit the next target or empty line
            [[ "$line" =~ ^[[:space:]]*-[[:space:]]tool: ]] && skip_block=false
            [[ "$skip_block" == "true" ]] && continue
        fi
        echo "$line" >> "$temp_file"
    done < "$config_path"

    mv "$temp_file" "$config_path"
    log_success "Removed target: $tool"
}

# Display current config
config_display() {
    local config_path="${1:-$CONFIG_FILE}"

    if [[ ! -f "$config_path" ]]; then
        log_info "No config file found. Using defaults:"
        echo "  source: $DEFAULT_SOURCE"
        echo "  global_source: $DEFAULT_GLOBAL_SOURCE"
        echo ""
        echo "  Run 'agentsync init' to create a config file."
        return 0
    fi

    echo ""
    log_header "Configuration: $config_path"
    echo ""

    local source=$(config_get_source "$config_path")
    local global=$(config_get_global_source "$config_path")
    local watch=$(config_get_watch "$config_path")
    local hooks=$(config_get_git_hooks "$config_path")

    echo "Source:         ${source:-<not set>}"
    echo "Global source:  ${global:-<not set>}"
    echo "Watch daemon:   ${watch}"
    echo "Git hooks:      ${hooks}"
    echo ""
    echo "Targets:"
    local targets=$(config_get_targets_array "$config_path")
    for target in $targets; do
        IFS=':' read -r tool path enabled <<< "$target"
        local status=$([ "$enabled" == "true" ] && echo "✓" || echo "✗")
        echo "  $status $tool: $path"
    done
    echo ""
}

# Validate config
config_validate() {
    local config_path="${1:-$CONFIG_FILE}"

    if [[ ! -f "$config_path" ]]; then
        return 1
    fi

    local source=$(config_get_source "$config_path")
    if [[ -z "$source" ]]; then
        log_error "Config missing 'source' field"
        return 1
    fi

    if [[ ! -d "$source" ]]; then
        log_warning "Source directory does not exist: $source"
        return 1
    fi

    return 0
}

# Export for subshells
export -f config_exists get_config_path config_get_source config_get_global_source
export -f config_get_targets config_get_targets_array config_is_target_enabled
export -f config_get_exclusions config_should_exclude config_get_watch
export -f config_get_git_hooks config_write config_update config_add_target
export -f config_remove_target config_display config_validate
