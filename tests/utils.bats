#!/usr/bin/env bats
# Test suite for utils.sh

setup() {
    load test_helper
}

@test "count_items counts files correctly" {
    mkdir -p "$TEST_TEMP_DIR/test_folder"
    touch "$TEST_TEMP_DIR/test_folder/file1.md"
    touch "$TEST_TEMP_DIR/test_folder/file2.md"
    touch "$TEST_TEMP_DIR/test_folder/file3.md"

    result=$(count_items "$TEST_TEMP_DIR/test_folder")
    [ "$result" -eq 3 ]
}

@test "count_items returns 0 for empty folder" {
    mkdir -p "$TEST_TEMP_DIR/empty_folder"

    result=$(count_items "$TEST_TEMP_DIR/empty_folder")
    [ "$result" -eq 0 ]
}

@test "count_items returns 0 for non-existent folder" {
    result=$(count_items "$TEST_TEMP_DIR/nonexistent")
    [ "$result" -eq 0 ]
}

@test "get_home_dir returns home directory" {
    result=$(get_home_dir)
    [ "$result" = "$HOME" ]
}

@test "log_success formats output correctly" {
    run log_success "test message"
    [ "$status" -eq 0 ]
}

@test "log_error formats output correctly" {
    run log_error "test error"
    [ "$status" -eq 1 ]
}

@test "ensure_dir creates directory" {
    local new_dir="$TEST_TEMP_DIR/new_subdir/nested"
    ensure_dir "$new_dir"
    [ -d "$new_dir" ]
}

@test "ensure_dir does not fail on existing directory" {
    ensure_dir "$TEST_TEMP_DIR"
    [ -d "$TEST_TEMP_DIR" ]
}
