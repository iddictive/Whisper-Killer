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

function version_sort_key() {
    local version=${1#v}
    local major
    local minor

    IFS='.' read -r major minor _ <<< "$version"

    if [[ ! "$major" =~ ^[0-9]+$ ]]; then
        major=0
    fi
    if [[ ! "$minor" =~ ^[0-9]+$ ]]; then
        minor=0
    fi

    printf "%08d.%08d\n" "$major" "$minor"
}

function max_whisperkiller_version() {
    local first=${1#v}
    local second=${2#v}

    if [ -z "$first" ]; then
        echo "$second"
        return
    fi
    if [ -z "$second" ]; then
        echo "$first"
        return
    fi

    if [[ "$(version_sort_key "$second")" > "$(version_sort_key "$first")" ]]; then
        echo "$second"
    else
        echo "$first"
    fi
}

function latest_whisperkiller_tag_version() {
    local major=${1:-3}

    git tag -l "v$major.*" 2>/dev/null \
        | sed 's/^v//' \
        | awk -F. '$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ { print }' \
        | sort -t. -k1,1n -k2,2n \
        | tail -n 1
}

function next_release_version() {
    local plist=$1
    local current
    local latest_tag
    local base

    current="$(plist_get "$plist" "CFBundleShortVersionString")"
    latest_tag="$(latest_whisperkiller_tag_version 3)"
    base="$(max_whisperkiller_version "${current:-3.0}" "$latest_tag")"

    if [ -z "$base" ]; then
        base="3.0"
    fi

    if [ "$base" = "${current:-}" ] && [ -n "$latest_tag" ] && [ "$(max_whisperkiller_version "$current" "$latest_tag")" = "$current" ] && [[ "$(version_sort_key "$current")" > "$(version_sort_key "$latest_tag")" ]]; then
        echo "$current"
    else
        echo "$(next_whisperkiller_version "$base")"
    fi
}

function resolve_whisperkiller_version() {
    local plist=$1
    local current
    local version

    if [ -n "${WHISPERKILLER_VERSION:-}" ]; then
        version="$WHISPERKILLER_VERSION"
    elif [ "${WHISPERKILLER_BUMP_VERSION:-0}" = "1" ]; then
        current="$(plist_get "$plist" "CFBundleShortVersionString")"
        version="$(next_whisperkiller_version "${current:-3.0}")"
    else
        version="$(plist_get "$plist" "CFBundleShortVersionString")"
    fi

    if [ -z "$version" ]; then
        version="3.0"
    fi

    plist_set "$plist" "CFBundleShortVersionString" "$version"
    plist_set "$plist" "CFBundleVersion" "$version"
    plist_set "$plist" "CFBundleExecutable" "WhisperKiller"

    echo "$version"
}
