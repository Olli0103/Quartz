#!/usr/bin/env bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
RESET='\033[0m'

pass() { echo -e "${GREEN}${BOLD}✓ $1${RESET}"; }
step() { echo -e "\n${BOLD}→ $1${RESET}"; }
fail() {
    echo -e "${RED}${BOLD}✗ $1${RESET}"
    exit 1
}

reset_result_bundle() {
    local bundle_path="$1"
    if [ -e "$bundle_path" ]; then
        rm -rf "$bundle_path"
    fi
}

automation_mode_status() {
    automationmodetool help 2>&1 || true
}

macos_ui_automation_requires_authentication() {
    automation_mode_status | grep -q "requires user authentication to enable Automation Mode"
}

ensure_macos_ui_automation_available() {
    local log_path="${1:-}"

    if ! command -v automationmodetool >/dev/null 2>&1; then
        return 0
    fi

    if macos_ui_automation_requires_authentication; then
        local message="macOS UI automation is disabled on this host and requires local user authentication: run 'sudo automationmodetool enable-automationmode-without-authentication' once in an unlocked session."
        if [ -n "$log_path" ]; then
            printf '%s\n' "$message" >"$log_path"
            printf '%s\n' "$(automation_mode_status)" >>"$log_path"
        else
            printf '%s\n' "$message"
            automation_mode_status
        fi
        return 1
    fi

    return 0
}

run_xcodebuild_to_log() {
    local log_path="$1"
    shift
    local attempt=1
    local max_attempts=2

    while [ "$attempt" -le "$max_attempts" ]; do
        if "$@" >"$log_path" 2>&1; then
            tail -n 20 "$log_path"
            return 0
        fi

        if [ "$attempt" -lt "$max_attempts" ] && result_bundle_exists_error_in_log "$log_path"; then
            reset_result_bundle_from_log "$log_path"
            attempt=$((attempt + 1))
            continue
        fi

        if [ "$attempt" -lt "$max_attempts" ] && ui_automation_timeout_in_log "$log_path"; then
            echo "UI automation mode timed out; healing and retrying once..." >>"$log_path"
            heal_ui_automation_timeout
            attempt=$((attempt + 1))
            continue
        fi

        tail -n 40 "$log_path"
        return 1
    done
}

extract_simulator_id() {
    local line="$1"
    echo "$line" | sed -nE 's/.*\(([A-F0-9-]+)\) \((Booted|Shutdown)\)[[:space:]]*$/\1/p' | head -1 | xargs
}

stable_simulator_lines() {
    local family="$1"
    xcrun simctl list devices available 2>/dev/null | grep -F "$family" | grep -E '\((Booted|Shutdown)\)[[:space:]]*$' || true
}

available_simulator_id() {
    local preferred="$1"
    local family="$2"
    local line=""

    if [ -n "$preferred" ]; then
        line=$(xcrun simctl list devices available 2>/dev/null | grep -F "$preferred (" | grep -E '\((Booted|Shutdown)\)[[:space:]]*$' | head -1 || true)
    fi
    if [ -z "$line" ] && [ -n "$family" ]; then
        line=$(stable_simulator_lines "$family" | grep -E '\(Booted\)[[:space:]]*$' | head -1 || true)
    fi
    if [ -z "$line" ] && [ -n "$family" ]; then
        line=$(stable_simulator_lines "$family" | grep -E '\(Shutdown\)[[:space:]]*$' | head -1 || true)
    fi
    if [ -n "$line" ]; then
        extract_simulator_id "$line"
    fi
}

prepare_simulator() {
    local sim_id="$1"
    local bundle_id="${2:-olli.QuartzNotes}"

    xcrun simctl boot "$sim_id" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$sim_id" -b >/dev/null 2>&1 || return 1
    xcrun simctl terminate "$sim_id" "$bundle_id" >/dev/null 2>&1 || true
    xcrun simctl uninstall "$sim_id" "$bundle_id" >/dev/null 2>&1 || true
}

prepared_simulator_id() {
    local preferred="$1"
    local family="$2"
    local primary_id=""
    local candidate_line=""
    local candidate_id=""

    primary_id=$(available_simulator_id "$preferred" "$family")
    if [ -n "$primary_id" ] && prepare_simulator "$primary_id"; then
        echo "$primary_id"
        return 0
    fi

    while IFS= read -r candidate_line; do
        candidate_id=$(extract_simulator_id "$candidate_line")
        if [ -z "$candidate_id" ] || [ "$candidate_id" = "$primary_id" ]; then
            continue
        fi
        if prepare_simulator "$candidate_id"; then
            echo "$candidate_id"
            return 0
        fi
    done < <(stable_simulator_lines "$family")

    return 1
}

terminate_conflicting_macos_app_processes() {
    local pid=""

    while IFS= read -r pid; do
        [ -z "$pid" ] && continue
        kill "$pid" >/dev/null 2>&1 || true
        sleep 1
        if ps -p "$pid" >/dev/null 2>&1; then
            kill -9 "$pid" >/dev/null 2>&1 || true
        fi
    done < <(ps -ax -o pid=,command= | grep '/Quartz.app/Contents/MacOS/Quartz' | awk '{print $1}' || true)
}

ui_automation_timeout_in_log() {
    local log_path="$1"
    grep -q "Timed out while enabling automation mode" "$log_path"
}

ui_automation_disabled_in_log() {
    local log_path="$1"
    grep -q "requires local user authentication" "$log_path"
}

result_bundle_exists_error_in_log() {
    local log_path="$1"
    grep -q 'Existing file at -resultBundlePath "' "$log_path"
}

reset_result_bundle_from_log() {
    local log_path="$1"
    local bundle_path=""
    bundle_path="$(sed -nE 's/.*Existing file at -resultBundlePath "([^"]+)".*/\1/p' "$log_path" | tail -1)"
    if [ -n "$bundle_path" ] && [ -e "$bundle_path" ]; then
        rm -rf "$bundle_path"
    fi
}

heal_ui_automation_timeout() {
    pkill -f "QuartzUITests-Runner" >/dev/null 2>&1 || true
    pkill -f "/Quartz.app/Contents/MacOS/Quartz" >/dev/null 2>&1 || true
    pkill -f "xcodebuild test -scheme Quartz" >/dev/null 2>&1 || true
    rm -rf /tmp/QuartzEditorShell_*.xcresult /tmp/QuartzUITests_*.xcresult >/dev/null 2>&1 || true
    sleep 2
}
