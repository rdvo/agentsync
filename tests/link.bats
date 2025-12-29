#!/usr/bin/env bats
# Test suite for link.sh

setup() {
    load test_helper
}

@test "link_create creates symlink successfully" {
    mkdir -p "$TEST_TEMP_DIR/source"
    mkdir -p "$TEST_TEMP_DIR/target"

    echo "test content" > "$TEST_TEMP_DIR/source/file.md"
    touch "$TEST_TEMP_DIR/target/file.md"

    load_lib "link.sh"
    link_create "$TEST_TEMP_DIR/source/file.md" "$TEST_TEMP_DIR/target/file.md" "false"

    [ -L "$TEST_TEMP_DIR/target/file.md" ]
}

@test "link_create fails if target file exists and not overwrite" {
    mkdir -p "$TEST_TEMP_DIR/source"
    mkdir -p "$TEST_TEMP_DIR/target"

    echo "source content" > "$TEST_TEMP_DIR/source/file.md"
    echo "existing content" > "$TEST_TEMP_DIR/target/file.md"

    load_lib "link.sh"
    run link_create "$TEST_TEMP_DIR/source/file.md" "$TEST_TEMP_DIR/target/file.md" "false"

    [ "$status" -ne 0 ]
}

@test "link_create overwrites when allowed" {
    mkdir -p "$TEST_TEMP_DIR/source"
    mkdir -p "$TEST_TEMP_DIR/target"

    echo "source content" > "$TEST_TEMP_DIR/source/file.md"
    echo "existing content" > "$TEST_TEMP_DIR/target/file.md"

    load_lib "link.sh"
    link_create "$TEST_TEMP_DIR/source/file.md" "$TEST_TEMP_DIR/target/file.md" "true"

    [ -L "$TEST_TEMP_DIR/target/file.md" ]
}

@test "link_create creates parent directories" {
    mkdir -p "$TEST_TEMP_DIR/source"
    echo "content" > "$TEST_TEMP_DIR/source/file.md"

    load_lib "link.sh"
    link_create "$TEST_TEMP_DIR/source/file.md" "$TEST_TEMP_DIR/target/nested/dir/file.md" "false"

    [ -L "$TEST_TEMP_DIR/target/nested/dir/file.md" ]
}

@test "link_remove removes symlink" {
    mkdir -p "$TEST_TEMP_DIR/source"
    mkdir -p "$TEST_TEMP_DIR/target"

    echo "content" > "$TEST_TEMP_DIR/source/file.md"
    ln -s "$TEST_TEMP_DIR/source/file.md" "$TEST_TEMP_DIR/target/file.md"

    load_lib "link.sh"
    link_remove "$TEST_TEMP_DIR/target/file.md"

    [ ! -e "$TEST_TEMP_DIR/target/file.md" ]
}

@test "link_is_valid returns true for valid symlink" {
    mkdir -p "$TEST_TEMP_DIR/source"
    mkdir -p "$TEST_TEMP_DIR/target"

    echo "content" > "$TEST_TEMP_DIR/source/file.md"
    ln -s "$TEST_TEMP_DIR/source/file.md" "$TEST_TEMP_DIR/target/file.md"

    load_lib "link.sh"
    run link_is_valid "$TEST_TEMP_DIR/target/file.md"

    [ "$status" -eq 0 ]
}

@test "link_is_valid returns false for broken symlink" {
    mkdir -p "$TEST_TEMP_DIR/target"
    ln -s "$TEST_TEMP_DIR/source/nonexistent.md" "$TEST_TEMP_DIR/target/file.md"

    load_lib "link.sh"
    run link_is_valid "$TEST_TEMP_DIR/target/file.md"

    [ "$status" -ne 0 ]
}
