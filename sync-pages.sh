#!/usr/bin/env bash
# sync-pages.sh — Make every published decryptor page a copy of docs/locker.html.
#
# docs/locker.html is the one decryptor page. docs/index.html (the main
# locker) and docs/lockers/<name>/index.html are copies of it, because GitHub
# Pages needs a page in each folder. Edit docs/locker.html only, then run this
# and commit the copies with it. verify.sh refuses to pass a locker whose page
# is out of date.
#
# Usage:
#   bash sync-pages.sh           # copy docs/locker.html over every page
#   bash sync-pages.sh --check   # change nothing; exit 1 if any page differs
set -ue

#shellcheck disable=2154
PS4='$( _0=$?; exec 2>/dev/null; realpath -- "${BASH_SOURCE[0]:-?}:${LINENO} ^$_0 ${FUNCNAME[0]:-?}()=>" )'
[[ -n "${DEBUGSH:-}" ]] && set -x

set -o pipefail

scriptName="${scriptName:-"$(command readlink -f -- "$0")"}"

TEMPLATE_FILE="docs/locker.html"

die() {
    builtin echo "ERROR($(basename "${scriptName}")): $*" >&2
    builtin exit 1
}

main() {
    local check=""
    case "${1:-}" in
        --check) check=1 ;;
        "") ;;
        *) die "Unknown argument: $1 (usage: bash sync-pages.sh [--check])" ;;
    esac

    [[ -f "$TEMPLATE_FILE" ]] || die "$TEMPLATE_FILE not found (run this from the repo root)"

    local -a pages=(docs/index.html)
    local dir
    for dir in docs/lockers/*/; do
        [[ -d "$dir" ]] && pages+=("${dir}index.html")
    done

    local page differ=0
    for page in "${pages[@]}"; do
        if cmp -s "$page" "$TEMPLATE_FILE"; then
            continue
        fi
        differ=$((differ + 1))
        if [[ -n "$check" ]]; then
            echo "out of date: $page"
        else
            cp "$TEMPLATE_FILE" "$page"
            echo "updated: $page"
        fi
    done

    if [[ -n "$check" && "$differ" -gt 0 ]]; then
        echo "$differ page(s) differ from $TEMPLATE_FILE. Run: bash sync-pages.sh"
        exit 1
    fi
    echo "All ${#pages[@]} pages match $TEMPLATE_FILE."
}

if [[ -z "${sourceMe:-}" ]]; then
    main "$@"
    exit
fi
command true
