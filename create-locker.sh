#!/usr/bin/env bash

# Creates a new locker with all necessary files and directory structure.
# This script automates the process of setting up a new named locker.
#
# Usage:
#   bash create-locker.sh <locker-name>
#   bash create-locker.sh --force <locker-name>   # start an existing locker over (asks you to confirm)
#
# Example:
#   bash create-locker.sh sally
#   bash create-locker.sh banking
#
# It refuses to touch a locker that already has encrypted content or edited
# plaintext in tmp/, unless you pass --force AND type the locker name to
# confirm at a terminal.  With --force, the old plaintext and the old
# content.txt are moved/copied into tmp/ (gitignored, never published).
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
BLUE='\033[0;34m'
NC='\033[0m' # No Color

TEMPLATE_FILE="docs/locker.html"
TMP_DIR="tmp"

die() {
    builtin echo "ERROR($(basename "${scriptName}")): $*" >&2
    builtin exit 1
}

{  # outer scope braces

    usage() {
        echo -e "${RED}✗ Error: Locker name required${NC}"
        echo
        echo "Usage: bash create-locker.sh [--force] <locker-name>"
        echo
        echo "Examples:"
        echo "  bash create-locker.sh sally"
        echo "  bash create-locker.sh banking"
        echo "  bash create-locker.sh personal"
        exit 1
    }

    # The starter plaintext for a new locker.  $2 is the Created: timestamp.
    render_template() {
        local name="$1" created="$2"
        cut -c 13- <<EOF
            # Locker: $name
            Created: $created

            This is your new encrypted locker. Edit this file to add your secrets, then re-encrypt.

            ## Instructions
            1. Edit this file with your secrets
            2. Run: bash encrypt.sh "$name"
            3. Commit and push to deploy
            4. Access at: https://yourdomain.github.io/auth-locker/$name/

            ## Example Content
            - Username: myuser
            - Password: (add your password here)
            - Recovery codes: (add codes here)
            - Notes: (add any notes)
EOF
    }

    # True if the file is still the untouched starter template (ignoring its timestamp).
    is_untouched_template() {
        local file="$1" name="$2"
        diff -q <(grep -v '^Created: ' "$file") <(render_template "$name" "" | grep -v '^Created: ') &>/dev/null
    }

    # Ask the user to type the locker name.  Only works at a real terminal.
    confirm_force() {
        local name="$1" answer
        if [[ ! -t 0 ]]; then
            echo -e "${RED}✗ --force needs you at a terminal to confirm. Nothing was changed.${NC}"
            exit 1
        fi
        echo -e "${RED}--force will replace this locker's content with a new starter template.${NC}"
        read -r -p "Type the locker name ($name) to confirm: " answer
        if [[ "$answer" != "$name" ]]; then
            echo "Did not match. Aborted; nothing was changed."
            exit 1
        fi
    }

}

main() {
    local force=""
    local locker_name=""
    local arg
    for arg in "$@"; do
        case "$arg" in
            --force) force=1 ;;
            *) [[ -z "$locker_name" ]] && locker_name="$arg" ;;
        esac
    done

    # Check if locker name provided
    [[ -n "$locker_name" ]] || usage

    local locker_dir="docs/lockers/$locker_name"
    local content_file="$locker_dir/content.txt"
    local index_file="$locker_dir/index.html"
    local tmp_file="$TMP_DIR/$locker_name.md"

    echo -e "${BLUE}=== Auth Locker - Create New Locker ===${NC}"
    echo
    echo "Locker name: $locker_name"
    echo

    # Validate locker name (alphanumeric, hyphens, underscores only)
    if ! [[ "$locker_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}✗ Error: Invalid locker name${NC}"
        echo "Locker names must contain only letters, numbers, hyphens, and underscores"
        exit 1
    fi

    # Never wipe an existing locker by accident
    local has_content="" has_plaintext=""
    [[ -f "$content_file" ]] && has_content=1
    if [[ -f "$tmp_file" ]] && ! is_untouched_template "$tmp_file" "$locker_name"; then
        has_plaintext=1
    fi

    if [[ -n "$has_content" || -n "$has_plaintext" ]]; then
        echo -e "${YELLOW}⚠ Locker '$locker_name' is already in use:${NC}"
        [[ -n "$has_content" ]] && echo "  - $content_file has encrypted content"
        [[ -n "$has_plaintext" ]] && echo "  - $tmp_file has plaintext that is not the starter template"
        echo
        if [[ -z "$force" ]]; then
            echo -e "${RED}✗ Refusing to overwrite it. Nothing was changed.${NC}"
            echo
            echo "To change its secrets:  edit $tmp_file, then: bash encrypt.sh $locker_name"
            echo "To refresh only the page:  cp $TEMPLATE_FILE $index_file"
            echo "To start over anyway:  bash create-locker.sh --force $locker_name"
            exit 1
        fi
        confirm_force "$locker_name"

        # Back up into tmp/ (gitignored), never next to the published files
        local stamp
        stamp="$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$TMP_DIR"
        if [[ -n "$has_plaintext" ]]; then
            mv "$tmp_file" "$TMP_DIR/$locker_name.md.bak.$stamp"
            echo -e "${GREEN}✓${NC} Old plaintext moved to: $TMP_DIR/$locker_name.md.bak.$stamp"
        fi
        if [[ -n "$has_content" ]]; then
            cp "$content_file" "$TMP_DIR/$locker_name.content.txt.bak.$stamp"
            echo -e "${GREEN}✓${NC} Old content.txt copied to: $TMP_DIR/$locker_name.content.txt.bak.$stamp"
        fi
        echo
    elif [[ -d "$locker_dir" ]]; then
        echo -e "${YELLOW}⚠ Warning: Locker '$locker_name' already exists (no encrypted content yet)${NC}"
        echo
        read -p "Do you want to reinitialize it? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Aborted."
            exit 0
        fi
    fi

    # Check if template exists
    if [[ ! -f "$TEMPLATE_FILE" ]]; then
        echo -e "${RED}✗ Error: Template file not found: $TEMPLATE_FILE${NC}"
        exit 1
    fi

    # Create locker directory
    echo -e "${BLUE}[1/5]${NC} Creating locker directory..."
    mkdir -p "$locker_dir"
    echo -e "${GREEN}✓${NC} Created: $locker_dir"
    echo

    # Copy locker template
    echo -e "${BLUE}[2/5]${NC} Setting up locker UI..."
    cp "$TEMPLATE_FILE" "$index_file"
    echo -e "${GREEN}✓${NC} Created: $index_file"
    echo

    # Create tmp directory if needed
    mkdir -p "$TMP_DIR"

    # Create initial content file
    echo -e "${BLUE}[3/5]${NC} Creating initial content..."
    render_template "$locker_name" "$(date '+%Y-%m-%d %H:%M:%S')" >"$tmp_file"
    echo -e "${GREEN}✓${NC} Created: $tmp_file"
    echo

    # Encrypt the initial content
    echo -e "${BLUE}[4/5]${NC} Encrypting initial content..."
    echo "You'll be prompted to create a passphrase for this locker."
    echo

    # Use Node.js directly to encrypt
    if ! command -v node &> /dev/null; then
        echo -e "${RED}✗ Error: Node.js is not installed or not in PATH${NC}"
        exit 1
    fi

    if node encrypt-for-embed.js "$tmp_file" --locker "$locker_name"; then
        echo
        echo -e "${GREEN}✓${NC} Content encrypted successfully"
    else
        echo
        echo -e "${RED}✗ Error: Encryption failed${NC}"
        exit 1
    fi
    echo

    # Summary
    echo -e "${BLUE}[5/5]${NC} Summary"
    echo -e "${GREEN}✓ Locker '$locker_name' created successfully!${NC}"
    echo
    echo "Directory structure:"
    echo "  $locker_dir/"
    echo "  ├── index.html (UI)"
    echo "  └── content.txt (encrypted data)"
    echo
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Edit your secrets:"
    echo "   Open $tmp_file in your editor"
    echo
    echo "2. Re-encrypt when ready, and check it opens:"
    echo "   bash encrypt.sh \"$locker_name\""
    echo "   bash verify.sh \"$locker_name\""
    echo
    echo "3. Deploy to GitHub Pages:"
    echo "   git add docs/lockers/\"$locker_name\"/"
    echo "   git commit -m 'Add $locker_name locker'"
    echo "   git push"
    echo
    echo "4. Access your locker:"
    echo "   https://yourdomain.github.io/auth-locker/$locker_name/"
    echo
    echo -e "${BLUE}Note:${NC} The initial content in $tmp_file is a template."
    echo "      Remember to edit it before deploying!"
    echo
}

if [[ -z "${sourceMe:-}" ]]; then
    main "$@"
    exit
fi
command true
