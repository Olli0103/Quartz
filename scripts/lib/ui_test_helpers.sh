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

run_xcodebuild_to_log() {
    local log_path="$1"
    shift

    if "$@" >"$log_path" 2>&1; then
        tail -n 20 "$log_path"
        return 0
    fi

    tail -n 40 "$log_path"
    return 1
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
