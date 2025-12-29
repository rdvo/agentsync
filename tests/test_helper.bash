#!/usr/bin/env bats
# Test helper for agentsync

# Set up test environment
export AGENTSYNC_TEST_MODE=true

setup() {
    TEST_TEMP_DIR=$(mktemp -d)
    BATS_TMPDIR="$TEST_TEMP_DIR"

    # Source the utils file
    load_lib "utils.sh"
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
}

# Helper to load library files
load_lib() {
    local lib_file="lib/$1"
    if [[ -f "$lib_file" ]]; then
        source "$lib_file"
    else
        # Try from test directory
        local alt_file="../lib/$1"
        if [[ -f "$alt_file" ]]; then
            source "$alt_file"
        fi
    fi
}

# Helper to create a mock source directory
create_mock_source() {
    local base_dir="$1"
    mkdir -p "$base_dir/agents"
    mkdir -p "$base_dir/skills"
    mkdir -p "$base_dir/commands"

    echo "# Senior Developer" > "$base_dir/agents/senior-dev.md"
    echo "# Git Specialist" > "$base_dir/agents/git-expert.md"

    mkdir -p "$base_dir/skills/git-release"
    echo "# Git Release Skill" > "$base_dir/skills/git-release/SKILL.md"

    echo "#!/bin/bash\necho deploy" > "$base_dir/commands/deploy.sh"
}

# Helper to verify symlink exists
assert_symlink_exists() {
    local link="$1"
    [ -L "$link" ]
}

# Helper to verify symlink points to correct target
assert_symlink_points_to() {
    local link="$1"
    local target="$2"
    local actual=$(readlink "$link")
    [ "$actual" = "$target" ]
}
