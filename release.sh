#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

toc_version="$(
    awk -F ':[[:space:]]*' '/^## Version:/ { print $2; exit }' LeaveMeBe.toc \
        | tr -d '\r'
)"

if [[ -z "$toc_version" ]]; then
    echo "Could not find ## Version in LeaveMeBe.toc." >&2
    exit 1
fi

if [[ "$toc_version" != "@project-version@" ]]; then
    echo "Expected ## Version: @project-version@ in LeaveMeBe.toc." >&2
    exit 1
fi

version="${1:-}"
release_type="${2:-}"
prerelease_number="${3:-}"

if [[ -z "$version" ]]; then
    read -r -p "Version (for example 1.2.3): " version
fi

if [[ ! "$version" =~ ^[0-9]+(\.[0-9]+){2}$ ]]; then
    echo "Unsupported version: $version" >&2
    echo "Usage: ./release.sh <version> [release | beta [number] | alpha [number]]" >&2
    exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Warning: uncommitted changes will not be included in this release." >&2
    git status --short
fi

branch="$(git branch --show-current)"
if [[ -z "$branch" ]]; then
    echo "Cannot release from a detached HEAD." >&2
    exit 1
fi

if [[ -z "$release_type" ]]; then
    echo "Choose the CurseForge release type:"
    echo "  1) Release"
    echo "  2) Beta"
    echo "  3) Alpha"
    read -r -p "Selection [1]: " selection

    case "${selection:-1}" in
        1) release_type="release" ;;
        2) release_type="beta" ;;
        3) release_type="alpha" ;;
        *)
            echo "Invalid selection." >&2
            exit 1
            ;;
    esac
fi

case "$release_type" in
    release)
        if [[ -n "$prerelease_number" ]]; then
            echo "Release builds do not take a prerelease number." >&2
            exit 1
        fi
        tag="$version"
        ;;
    beta|alpha)
        if [[ -z "$prerelease_number" ]]; then
            read -r -p "Prerelease number [1]: " prerelease_number
            prerelease_number="${prerelease_number:-1}"
        fi
        if [[ ! "$prerelease_number" =~ ^[1-9][0-9]*$ ]]; then
            echo "The prerelease number must be a positive integer." >&2
            exit 1
        fi
        tag="$version-$release_type.$prerelease_number"
        ;;
    *)
        echo "Usage: ./release.sh <version> [release | beta [number] | alpha [number]]" >&2
        exit 1
        ;;
esac

if git rev-parse --verify --quiet "refs/tags/$tag" >/dev/null; then
    echo "Tag $tag already exists." >&2
    exit 1
fi

read -r -p "Create and push $tag as a CurseForge $release_type from branch $branch? [y/N] " answer
if [[ ! "$answer" =~ ^[Yy]$ ]]; then
    echo "Release cancelled."
    exit 0
fi

git tag -a "$tag" -m "Leave Me Be $tag"
git push origin "$branch" "$tag"

echo "Pushed $tag. CurseForge packaging should start shortly."
