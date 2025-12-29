#!/usr/bin/env bats
# Test suite for detect.sh

setup() {
    load test_helper
}

@test "detect_tools finds Claude directory" {
    mkdir -p "$TEST_TEMP_DIR/.claude"

    # Need to be in a directory with the .claude folder
    cd "$TEST_TEMP_DIR"

    # Source detect and call detect_tools
    load_lib "detect.sh"
    result=$(detect_tools)

    [[ "$result" == *"claude"* ]]
}

@test "detect_tools finds Cursor directory" {
    mkdir -p "$TEST_TEMP_DIR/.cursor"

    cd "$TEST_TEMP_DIR"
    load_lib "detect.sh"
    result=$(detect_tools)

    [[ "$result" == *"cursor"* ]]
}

@test "get_tool_display_name returns correct names" {
    load_lib "detect.sh"

    result=$(get_tool_display_name "claude")
    [[ "$result" == "Claude Code" ]]

    result=$(get_tool_display_name "cursor")
    [[ "$result" == "Cursor" ]]

    result=$(get_tool_display_name "windsurf")
    [[ "$result" == "Windsurf" ]]
}

@test "find_skill_folders finds skills directory" {
    mkdir -p "$TEST_TEMP_DIR/.claude/skills"
    touch "$TEST_TEMP_DIR/.claude/skills/test.md"

    cd "$TEST_TEMP_DIR"
    load_lib "detect.sh"
    result=$(find_skill_folders ".")

    [[ "$result" == *"skills"* ]]
}

@test "scan_directory counts skills correctly" {
    mkdir -p "$TEST_TEMP_DIR/.claude/skills"
    mkdir -p "$TEST_TEMP_DIR/.claude/agents"
    touch "$TEST_TEMP_DIR/.claude/skills/skill1.md"
    touch "$TEST_TEMP_DIR/.claude/skills/skill2.md"
    touch "$TEST_TEMP_DIR/.claude/agents/agent1.md"

    cd "$TEST_TEMP_DIR"
    load_lib "detect.sh"
    result=$(scan_directory ".")

    echo "$result" | grep -q "skills:2"
    echo "$result" | grep -q "agents:1"
}
