#!/bin/bash

set -e

function plist_get() {
    local plist=$1
    local key=$2
    /usr/libexec/PlistBuddy -c "Print :$key" "$plist" 2>/dev/null || true
}

function plist_set() {
    local plist=$1
    local key=$2
    local value=$3
    /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :$key string $value" "$plist"
}

function next_whisperkiller_version() {
    local current=$1
    local major
    local minor

    IFS='.' read -r major minor _ <<< "$current"

    if [[ ! "$major" =~ ^[0-9]+$ ]] || [ "$major" -lt 3 ]; then
        echo "3.0"
        return
    fi

    if [[ ! "$minor" =~ ^[0-9]+$ ]]; then
        minor=0
    fi

    echo "$major.$((minor + 1))"
}

function resolve_whisperkiller_version() {
    local plist=$1
    local current
    local version

    if [ -n "${WHISPERKILLER_VERSION:-}" ]; then
        version="$WHISPERKILLER_VERSION"
    elif [ "${WHISPERKILLER_SKIP_VERSION_BUMP:-0}" = "1" ]; then
        version="$(plist_get "$plist" "CFBundleShortVersionString")"
    else
        current="$(plist_get "$plist" "CFBundleShortVersionString")"
        version="$(next_whisperkiller_version "${current:-3.0}")"
    fi

    if [ -z "$version" ]; then
        version="3.0"
    fi

    plist_set "$plist" "CFBundleShortVersionString" "$version"
    plist_set "$plist" "CFBundleVersion" "$version"
    plist_set "$plist" "CFBundleExecutable" "WhisperKiller"

    echo "$version"
}
