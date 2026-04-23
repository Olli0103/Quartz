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

xcodebuild_timeout_in_log() {
    local log_path="$1"
    grep -q "\\[ui_test_helpers\\] Command timed out after" "$log_path"
}

xcodebuild_executed_zero_tests_in_log() {
    local log_path="$1"
    grep -q "Executed 0 tests" "$log_path"
}

xctest_runner_bootstrap_failure_in_log() {
    local log_path="$1"
    grep -Eq 'Early unexpected exit, operation never finished bootstrapping|before establishing connection|Unable to monitor event loop' "$log_path"
}

run_command_with_timeout_to_log() {
    local log_path="$1"
    local timeout_seconds="$2"
    local completion_grace_seconds="${UI_TEST_HELPERS_COMPLETION_GRACE_SECONDS:-0}"
    shift 2

    python3 - "$log_path" "$timeout_seconds" "$completion_grace_seconds" "$@" <<'PY'
import os
import re
import signal
import subprocess
import sys
import time

log_path = sys.argv[1]
timeout_seconds = float(sys.argv[2])
completion_grace_seconds = float(sys.argv[3])
command = sys.argv[4:]

suite_success_pattern = re.compile(r"Executed [1-9][0-9]* tests, with 0 failures")
suite_failure_pattern = re.compile(r"Executed [0-9]+ tests, with [1-9][0-9]* failures?")
observer_end_pattern = re.compile(r"IDETestOperationsObserverDebug: .* -- end")
selected_tests_passed_pattern = re.compile(r"Test Suite 'Selected tests' passed at")
selected_tests_failed_pattern = re.compile(r"Test Suite 'Selected tests' failed at")
post_completion_deadline = None
completed_status = None

def xcodebuild_completion_status():
    try:
        with open(log_path, "r", encoding="utf-8", errors="ignore") as reader:
            content = reader.read()
    except OSError:
        return None

    if "** TEST SUCCEEDED **" in content:
        return 0
    if "** TEST FAILED **" in content:
        return 1
    if selected_tests_failed_pattern.search(content) or suite_failure_pattern.search(content):
        return 1
    if selected_tests_passed_pattern.search(content) and suite_success_pattern.search(content):
        return 0
    if suite_success_pattern.search(content) and observer_end_pattern.search(content):
        return 0

    return None

with open(log_path, "w", buffering=1) as log_file:
    process = subprocess.Popen(
        command,
        stdout=log_file,
        stderr=subprocess.STDOUT,
        preexec_fn=os.setsid,
        text=True,
    )

    start = time.monotonic()

    while True:
        return_code = process.poll()
        if return_code is not None:
            sys.exit(return_code)

        if completion_grace_seconds > 0:
            if completed_status is None:
                completed_status = xcodebuild_completion_status()
                if completed_status is not None:
                    post_completion_deadline = time.monotonic() + completion_grace_seconds

            if post_completion_deadline is not None and time.monotonic() >= post_completion_deadline:
                status_label = "successful" if completed_status == 0 else "failing"
                log_file.write(
                    f"\n[ui_test_helpers] XCTest completion markers show a {status_label} run, but the command remained alive for {int(completion_grace_seconds)}s after completion. Terminating the lingering process group and returning the completed test status.\n"
                )
                log_file.flush()
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                time.sleep(2)
                if process.poll() is None:
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                sys.exit(completed_status)

        if time.monotonic() - start >= timeout_seconds:
            log_file.write(
                f"\n[ui_test_helpers] Command timed out after {int(timeout_seconds)}s: {' '.join(command)}\n"
            )
            log_file.flush()
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            time.sleep(5)
            if process.poll() is None:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            sys.exit(124)

        time.sleep(1)
PY
}

run_command_with_timeout() {
    local timeout_seconds="$1"
    shift

    python3 - "$timeout_seconds" "$@" <<'PY'
import os
import signal
import subprocess
import sys
import time

timeout_seconds = float(sys.argv[1])
command = sys.argv[2:]

with open(os.devnull, "w") as devnull:
    process = subprocess.Popen(
        command,
        stdout=devnull,
        stderr=devnull,
        preexec_fn=os.setsid,
        text=True,
    )

    start = time.monotonic()

    while True:
        return_code = process.poll()
        if return_code is not None:
            sys.exit(return_code)

        if time.monotonic() - start >= timeout_seconds:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            time.sleep(1)
            if process.poll() is None:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            sys.exit(124)

        time.sleep(1)
PY
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
    local max_attempts=3
    local timeout_seconds="${XCODEBUILD_TEST_TIMEOUT_SECONDS:-900}"
    local completion_grace_seconds="${XCODEBUILD_COMPLETION_GRACE_SECONDS:-20}"

    while [ "$attempt" -le "$max_attempts" ]; do
        if UI_TEST_HELPERS_COMPLETION_GRACE_SECONDS="$completion_grace_seconds" \
            run_command_with_timeout_to_log "$log_path" "$timeout_seconds" "$@"; then
            if xcodebuild_executed_zero_tests_in_log "$log_path"; then
                echo "[ui_test_helpers] xcodebuild completed but executed 0 tests; treating as a harness failure." >>"$log_path"
                tail -n 40 "$log_path"
                return 1
            fi
            if xcodebuild_targets_macos_destination "$@"; then
                cleanup_macos_ui_test_processes
            fi
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

        if [ "$attempt" -lt "$max_attempts" ] && xcodebuild_timeout_in_log "$log_path"; then
            echo "xcodebuild timed out after ${timeout_seconds}s; resetting simulator/UI harness and retrying once..." >>"$log_path"
            heal_ui_automation_timeout
            attempt=$((attempt + 1))
            continue
        fi

        if [ "$attempt" -lt "$max_attempts" ] && macos_launch_failure_in_log "$log_path"; then
            echo "macOS launch/automation instability detected; cleaning up Quartz UI processes and retrying once..." >>"$log_path"
            heal_macos_launch_failure
            attempt=$((attempt + 1))
            continue
        fi

        if [ "$attempt" -lt "$max_attempts" ] && xctest_runner_bootstrap_failure_in_log "$log_path"; then
            echo "macOS XCTest runner bootstrap failed before establishing a test connection; cleaning up the runner/app state and retrying once..." >>"$log_path"
            heal_macos_launch_failure
            attempt=$((attempt + 1))
            continue
        fi

        tail -n 40 "$log_path"
        return 1
    done
}

xcodebuild_targets_macos_destination() {
    local arg=""
    for arg in "$@"; do
        if [ "$arg" = "platform=macOS" ]; then
            return 0
        fi
    done
    return 1
}

cleanup_macos_ui_test_processes() {
    pkill -f "QuartzUITests-Runner" >/dev/null 2>&1 || true
    terminate_conflicting_macos_app_processes || true
}

run_xcodebuild_in_workdir_to_log() {
    local workdir="$1"
    local log_path="$2"
    shift 2

    local absolute_log_path="$log_path"
    if [[ "$absolute_log_path" != /* ]]; then
        absolute_log_path="$(pwd)/$absolute_log_path"
    fi

    (
        cd "$workdir"
        run_xcodebuild_to_log "$absolute_log_path" "$@"
    )
}

extract_simulator_id() {
    local line="$1"
    echo "$line" | sed -nE 's/.*\(([A-F0-9-]+)\) \((Booted|Shutdown)\)[[:space:]]*$/\1/p' | head -1 | xargs
}

simulator_line_by_id() {
    local sim_id="$1"
    xcrun simctl list devices available 2>/dev/null | grep -F "($sim_id)" | head -1 || true
}

simulator_runtime_id() {
    local sim_id="$1"
    xcrun simctl list devices available 2>/dev/null | awk -v target="($sim_id)" '
        /^-- / && / --$/ {
            current = $0
            sub(/^-- /, "", current)
            sub(/ --$/, "", current)
        }
        index($0, target) {
            print current
            exit
        }
    ' | sed -nE 's/^.* \((com\.apple\.CoreSimulator\.SimRuntime\.[^)]+)\)$/\1/p' | head -1 | xargs
}

simulator_name_by_id() {
    local sim_id="$1"
    simulator_line_by_id "$sim_id" | sed -nE 's/^[[:space:]]*(.*) \(([A-F0-9-]+)\) \((Booted|Shutdown)\)[[:space:]]*$/\1/p' | head -1 | xargs
}

stable_simulator_lines() {
    local family="$1"
    xcrun simctl list devices available 2>/dev/null | grep -F "$family" | grep -E '\((Booted|Shutdown)\)[[:space:]]*$' || true
}

simulator_id_by_name() {
    local simulator_name="$1"
    xcrun simctl list devices available 2>/dev/null | grep -F "$simulator_name (" | grep -E '\((Booted|Shutdown)\)[[:space:]]*$' | head -1 | while IFS= read -r line; do
        extract_simulator_id "$line"
    done
}

preferred_device_type_id() {
    local preferred="$1"
    xcrun simctl list devicetypes 2>/dev/null | grep -F "$preferred (" | sed -nE 's/^[[:space:]]*.*\((com\.apple\.CoreSimulator\.SimDeviceType\.[^)]+)\)[[:space:]]*$/\1/p' | head -1 | xargs
}

latest_ios_runtime_id() {
    xcrun simctl list runtimes available 2>/dev/null | grep -E '^iOS ' | sed -nE 's/^.* - (com\.apple\.CoreSimulator\.SimRuntime\.iOS-[[:alnum:]-]+)$/\1/p' | head -1 | xargs
}

shutdown_simulator() {
    local sim_id="$1"
    run_command_with_timeout 30 xcrun simctl shutdown "$sim_id" || true
}

delete_simulator() {
    local sim_id="$1"
    shutdown_simulator "$sim_id"
    run_command_with_timeout 30 xcrun simctl delete "$sim_id" || true
}

create_simulator() {
    local simulator_name="$1"
    local device_type_id="$2"
    local runtime_id="$3"
    xcrun simctl create "$simulator_name" "$device_type_id" "$runtime_id" 2>/dev/null | tr -d '\n'
}

bootstatus_waiting_on_data_migration_in_log() {
    local log_path="$1"
    grep -Eq 'Waiting on Data Migration|CoreLocationMigrator\.migrator|locationd\.migrator' "$log_path"
}

bootstatus_terminal_failure_in_log() {
    local log_path="$1"
    grep -Eq 'State: Shutdown|Unable to boot device|Invalid device|Failed to open device|Launchd failed to respond' "$log_path"
}

prepare_simulator_with_bootstatus_log() {
    local sim_id="$1"
    local bundle_id="${2:-olli.QuartzNotes}"
    local bootstatus_timeout_seconds="${3:-120}"
    local bootstatus_log_path="$4"

    xcrun simctl boot "$sim_id" >/dev/null 2>&1 || true
    if ! run_command_with_timeout_to_log "$bootstatus_log_path" "$bootstatus_timeout_seconds" xcrun simctl bootstatus "$sim_id" -b; then
        return 1
    fi

    run_command_with_timeout 20 xcrun simctl terminate "$sim_id" "$bundle_id" || true
    run_command_with_timeout 20 xcrun simctl uninstall "$sim_id" "$bundle_id" || true
    return 0
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
    run_command_with_timeout 120 xcrun simctl bootstatus "$sim_id" -b || return 1
    run_command_with_timeout 20 xcrun simctl terminate "$sim_id" "$bundle_id" || true
    run_command_with_timeout 20 xcrun simctl uninstall "$sim_id" "$bundle_id" || true
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

prepared_dedicated_simulator_info() {
    local preferred="$1"
    local family="$2"
    local simulator_name="$3"
    local bundle_id="${4:-olli.QuartzNotes}"
    local bootstatus_timeout_seconds="${5:-150}"
    local device_type_id=""
    local runtime_id=""
    local sim_id=""
    local bootstatus_log_path=""
    local strategy="reused"
    local attempt=1

    device_type_id=$(preferred_device_type_id "$preferred")
    runtime_id=$(latest_ios_runtime_id)

    if [ -z "$device_type_id" ] || [ -z "$runtime_id" ]; then
        return 1
    fi

    xcrun simctl shutdown all >/dev/null 2>&1 || true

    while [ "$attempt" -le 2 ]; do
        sim_id=$(simulator_id_by_name "$simulator_name")
        if [ -z "$sim_id" ]; then
            sim_id=$(create_simulator "$simulator_name" "$device_type_id" "$runtime_id")
            strategy="created"
        elif [ "$attempt" -gt 1 ]; then
            strategy="recreated"
        else
            strategy="reused"
        fi

        if [ -z "$sim_id" ]; then
            return 1
        fi

        bootstatus_log_path="$(mktemp "/tmp/quartz-sim-bootstatus-${sim_id}-XXXX.log")"
        if prepare_simulator_with_bootstatus_log "$sim_id" "$bundle_id" "$bootstatus_timeout_seconds" "$bootstatus_log_path"; then
            rm -f "$bootstatus_log_path"
            printf '%s|%s|%s\n' "$sim_id" "$strategy" "$simulator_name"
            return 0
        fi

        if ! bootstatus_waiting_on_data_migration_in_log "$bootstatus_log_path" && ! xcodebuild_timeout_in_log "$bootstatus_log_path" && ! bootstatus_terminal_failure_in_log "$bootstatus_log_path"; then
            rm -f "$bootstatus_log_path"
            return 1
        fi

        rm -f "$bootstatus_log_path"
        delete_simulator "$sim_id"
        attempt=$((attempt + 1))
    done

    return 1
}

terminate_conflicting_macos_app_processes() {
    local pid=""
    local deadline=0
    local bundle_id=""
    local pattern=""

    for bundle_id in \
        com.granola.app \
        com.microsoft.Outlook \
        com.raycast.macos
    do
        osascript -e "tell application id \"$bundle_id\" to quit" >/dev/null 2>&1 || true
    done

    sleep 2

    for pattern in \
        '/Granola.app/' \
        '/Microsoft Outlook.app/' \
        '/Raycast.app/'
    do
        pkill -f "$pattern" >/dev/null 2>&1 || true
    done

    deadline=$((SECONDS + 10))
    while IFS= read -r pid; do
        [ -z "$pid" ] && continue
        kill "$pid" >/dev/null 2>&1 || true
    done < <(ps -ax -o pid=,command= | grep '/Quartz.app/Contents/MacOS/Quartz' | awk '{print $1}' || true)

    while [ "$SECONDS" -lt "$deadline" ]; do
        if ! pgrep -f '/Quartz.app/Contents/MacOS/Quartz' >/dev/null 2>&1; then
            return 0
        fi

        while IFS= read -r pid; do
            [ -z "$pid" ] && continue
            kill -9 "$pid" >/dev/null 2>&1 || true
        done < <(ps -ax -o pid=,command= | grep '/Quartz.app/Contents/MacOS/Quartz' | awk '{print $1}' || true)

        sleep 1
    done

    return 1
}

macos_launch_failure_in_log() {
    local log_path="$1"
    grep -Eq 'Could not launch “Quartz”|Could not launch "Quartz"|LaunchServices has returned error -600|application olli\.QuartzNotes is not running' "$log_path"
}

heal_macos_launch_failure() {
    pkill -f "QuartzUITests-Runner" >/dev/null 2>&1 || true
    pkill -f "xcodebuild test -scheme Quartz" >/dev/null 2>&1 || true
    terminate_conflicting_macos_app_processes
    sleep 2
}

swiftpm_runner_false_red_in_output() {
    local output="$1"
    printf '%s\n' "$output" | grep -qE "unexpected signal code (5|10)"
}

swift_test_failure_markers_in_output() {
    local output="$1"
    printf '%s\n' "$output" | grep -qE "failed after|Test Case .* failed|Expectation failed"
}

run_swift_test_with_serial_retry_to_log() {
    local log_path="$1"
    shift
    local first_output=""
    local retry_output=""
    local rc=0

    set +e
    first_output=$("$@" 2>&1)
    rc=$?
    set -e

    printf '%s\n' "$first_output" >"$log_path"
    printf '%s\n' "$first_output"

    if [ "$rc" -eq 0 ] && ! swift_test_failure_markers_in_output "$first_output"; then
        return 0
    fi

    if swift_test_failure_markers_in_output "$first_output"; then
        return 1
    fi

    if ! swiftpm_runner_false_red_in_output "$first_output"; then
        return "$rc"
    fi

    printf '\n[ui_test_helpers] SwiftPM runner false-red detected; retrying serially with --no-parallel.\n' >>"$log_path"

    set +e
    retry_output=$("$@" --no-parallel 2>&1)
    rc=$?
    set -e

    printf '\n%s\n' "$retry_output" >>"$log_path"
    printf '%s\n' "$retry_output"

    if [ "$rc" -eq 0 ] && ! swift_test_failure_markers_in_output "$retry_output"; then
        return 0
    fi

    return 1
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
    pkill -f "xcodebuild test -quiet -scheme QuartzKit" >/dev/null 2>&1 || true
    rm -rf /tmp/QuartzEditorShell_*.xcresult /tmp/QuartzUITests_*.xcresult >/dev/null 2>&1 || true
    xcrun simctl shutdown all >/dev/null 2>&1 || true
    terminate_conflicting_macos_app_processes
    sleep 2
}
