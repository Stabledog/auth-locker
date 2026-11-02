#!/usr/bin/env bash
# verify.sh — Check that a freshly encrypted content.txt opens, before you commit it.
#
# Prompts for the passphrase, decrypts docs/content.txt (or
# docs/lockers/<name>/content.txt) exactly as the published page would, and
# reports whether it opens. If tmp/main.md (or tmp/<name>.md) is still there,
# also reports whether the decrypted content matches it. Never prints secrets.
#
# Run it after encrypt.sh and before git commit.
#
# Usage:
#   bash verify.sh          # Default locker: docs/content.txt vs tmp/main.md
#   bash verify.sh sally    # Named locker: docs/lockers/sally/content.txt vs tmp/sally.md
#
# Exit code: 0 if it opens (and matches, when the plaintext is present); 1 otherwise.
set -ue

#shellcheck disable=2154
PS4='$( _0=$?; exec 2>/dev/null; realpath -- "${BASH_SOURCE[0]:-?}:${LINENO} ^$_0 ${FUNCNAME[0]:-?}()=>" )'
[[ -n "${DEBUGSH:-}" ]] && set -x

set -o pipefail

scriptName="${scriptName:-"$(command readlink -f -- "$0")"}"

VERIFIER="verify-content.js"

die() {
    builtin echo "ERROR($(basename "${scriptName}")): $*" >&2
    builtin exit 1
}

main() {
    local locker_name="${1:-}"
    local content_file plaintext_file page_file

    if [[ -n "$locker_name" ]]; then
        if ! [[ "$locker_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            die "Invalid locker name: $locker_name"
        fi
        content_file="docs/lockers/$locker_name/content.txt"
        plaintext_file="tmp/$locker_name.md"
        page_file="docs/lockers/$locker_name/index.html"
    else
        content_file="docs/content.txt"
        plaintext_file="tmp/main.md"
        page_file="docs/index.html"
    fi

    echo "=== Auth Locker Verify ==="
    echo

    command -v node &>/dev/null || die "Node.js is not installed or not in PATH"
    [[ -f "$VERIFIER" ]] || die "$VERIFIER not found (run this from the repo root)"
    [[ -f "$content_file" ]] || die "$content_file not found"

    local -a args=("$content_file" --plaintext "$plaintext_file")
    if [[ -f "$page_file" ]]; then
        args+=(--page "$page_file")
    else
        echo "Note: $page_file not found; checking with the encryptor's iteration count."
    fi

    node "$VERIFIER" "${args[@]}"
}

if [[ -z "${sourceMe:-}" ]]; then
    main "$@"
    exit
fi
command true
