#!/usr/bin/env bash

# Encrypts tmp/main.md (or tmp/<locker-name>.md) into docs/content.txt (or docs/lockers/{name}/content.txt).
# Create the former and then run encrypt.sh.  Then run verify.sh to check the result opens.
# When satisfied, a git commit + push will update the published recovery page at
# https://stabledog.github.io/auth-locker
#
# Usage:
#   bash encrypt.sh          # Encrypt to default locker (uses tmp/main.md → docs/content.txt)
#   bash encrypt.sh mylocker # Encrypt to named locker (uses tmp/mylocker.md → docs/lockers/mylocker/content.txt)
#
# Reports success only if the output file was actually rewritten by this run.
set -ue

#shellcheck disable=2154
PS4='$( _0=$?; exec 2>/dev/null; realpath -- "${BASH_SOURCE[0]:-?}:${LINENO} ^$_0 ${FUNCNAME[0]:-?}()=>" )'
[[ -n "${DEBUGSH:-}" ]] && set -x

set -o pipefail

scriptName="${scriptName:-"$(command readlink -f -- "$0")"}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ENCRYPTOR="encrypt-for-embed.js"

die() {
    builtin echo "ERROR($(basename "${scriptName}")): $*" >&2
    builtin exit 1
}

{  # outer scope braces

    fail() {
        echo
        echo -e "${RED}✗ Encryption failed: $*${NC}"
        exit 1
    }

    # Prints a checksum of the file, or nothing if it doesn't exist.
    file_sum() {
        if [[ -f "$1" ]]; then
            cksum <"$1"
        fi
    }

}

main() {
    local locker_name="${1:-}"
    local input_file output_file

    if [[ -n "$locker_name" ]]; then
        input_file="tmp/$locker_name.md"
        output_file="docs/lockers/$locker_name/content.txt"
    else
        input_file="tmp/main.md"
        output_file="docs/content.txt"
    fi

    echo "=== Auth Locker Encryption Wrapper ==="
    echo

    # Check if Node.js is available
    if ! command -v node &> /dev/null; then
        echo -e "${RED}✗ Error: Node.js is not installed or not in PATH${NC}"
        exit 1
    fi

    # Check if encryptor script exists
    if [[ ! -f "$ENCRYPTOR" ]]; then
        echo -e "${RED}✗ Error: $ENCRYPTOR not found${NC}"
        exit 1
    fi

    # Check if tmp directory exists
    if [[ ! -d "tmp" ]]; then
        echo -e "${YELLOW}⚠ Creating tmp/ directory${NC}"
        mkdir -p tmp
    fi

    # Check if input file exists
    if [[ ! -f "$input_file" ]]; then
        echo -e "${RED}✗ Error: $input_file not found${NC}"
        echo
        echo "Please create $input_file with your secrets, for example:"
        if [[ -n "$locker_name" ]]; then
            echo "  echo '# My Recovery Secrets for $locker_name' > $input_file"
        else
            echo "  echo '# My Recovery Secrets' > $input_file"
        fi
        echo "  echo '1Password Secret Key: A3-...' >> $input_file"
        echo
        exit 1
    fi

    # Display input file info
    local input_size input_lines
    input_size=$(wc -c < "$input_file")
    input_lines=$(wc -l < "$input_file")
    echo -e "${GREEN}✓${NC} Found input file: $input_file"
    echo "  Size: $input_size bytes"
    echo "  Lines: $input_lines"
    echo

    # Confirm before proceeding
    echo -e "${YELLOW}This will encrypt $input_file and overwrite $output_file${NC}"
    read -p "Continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi

    echo

    # Remember what the output looked like, so we can prove this run replaced it
    local sum_before sum_after
    sum_before="$(file_sum "$output_file")"

    # Run the encryptor
    local -a node_args=("$input_file")
    [[ -n "$locker_name" ]] && node_args+=(--locker "$locker_name")
    if ! node "$ENCRYPTOR" "${node_args[@]}"; then
        fail "the encryptor stopped with an error. $output_file was not changed."
    fi

    sum_after="$(file_sum "$output_file")"
    if [[ -z "$sum_after" ]]; then
        fail "$output_file does not exist after encrypting."
    fi
    if [[ "$sum_after" == "$sum_before" ]]; then
        fail "$output_file was not rewritten by this run. Do not commit it."
    fi
    if ! grep -q '^CT_B64=' "$output_file"; then
        fail "$output_file does not look like a locker file. Do not commit it."
    fi

    echo
    echo -e "${GREEN}✓ Encryption complete!${NC} $output_file was rewritten."
    echo
    echo "Next steps:"
    if [[ -n "$locker_name" ]]; then
        echo "  1. Check it opens:  bash verify.sh $locker_name"
        echo "  2. Commit and push docs/lockers/$locker_name/content.txt"
        echo "  3. Wait a few minutes for GitHub Pages to deploy"
        echo "  4. Test decryption at http://stabledog.github.io/auth-locker/$locker_name/"
    else
        echo "  1. Check it opens:  bash verify.sh"
        echo "  2. Commit and push docs/content.txt"
        echo "  3. Wait a few minutes for GitHub Pages to deploy"
        echo "  4. Test decryption at http://stabledog.github.io/auth-locker"
    fi
    echo
    echo -e "${YELLOW}⚠ Security reminders:${NC}"
    echo "  - Delete $input_file after verifying: rm $input_file"
    echo "  - The passphrase is NOT stored anywhere"
    echo "  - Remember your passphrase or you cannot decrypt"
    echo "  - After emergency use, rotate all exposed credentials"
}

if [[ -z "${sourceMe:-}" ]]; then
    main "$@"
    exit
fi
command true
