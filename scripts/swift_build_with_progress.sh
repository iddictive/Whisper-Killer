#!/bin/bash
set -u

if [ "$#" -eq 0 ]; then
    echo "Usage: $0 swift build [args...]" >&2
    exit 2
fi

INTERVAL="${BUILD_PROGRESS_INTERVAL:-15}"
START_SECONDS="$(date +%s)"

format_elapsed() {
    local total="$1"
    printf "%02d:%02d" "$((total / 60))" "$((total % 60))"
}

print_activity() {
    local now elapsed
    now="$(date +%s)"
    elapsed="$(format_elapsed "$((now - START_SECONDS))")"

    local active
    active="$(
        ps -axo pid=,etime=,comm= \
            | awk '
                {
                    command = $3
                    sub(/^.*\//, "", command)
                }
                command == "swift-frontend" ||
                command == "swift-build" ||
                command == "swift-driver" ||
                command == "clang" ||
                command == "ld" ||
                command == "ld64.lld" {
                    print "    " $0
                    count++
                    if (count >= 6) {
                        exit
                    }
                }
            '
    )"

    if [ -n "$active" ]; then
        echo ""
        echo "⏱️  Build still running after $elapsed. Active compiler/linker processes:"
        echo "$active"
    else
        echo ""
        echo "⏱️  Build still running after $elapsed. Waiting for SwiftPM output..."
    fi
}

"$@" &
BUILD_PID="$!"

while kill -0 "$BUILD_PID" 2>/dev/null; do
    sleep "$INTERVAL"
    if kill -0 "$BUILD_PID" 2>/dev/null; then
        print_activity
    fi
done

wait "$BUILD_PID"
exit "$?"
