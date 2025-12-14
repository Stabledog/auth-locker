#!/bin/bash

# Creates a new locker with all necessary files and directory structure.
# This script automates the process of setting up a new named locker.
#
# Usage:
#   bash create-locker.sh <locker-name>
#
# Example:
#   bash create-locker.sh sally
#   bash create-locker.sh banking

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if locker name provided
if [ -z "$1" ]; then
    echo -e "${RED}✗ Error: Locker name required${NC}"
    echo
    echo "Usage: bash create-locker.sh <locker-name>"
    echo
    echo "Examples:"
    echo "  bash create-locker.sh sally"
    echo "  bash create-locker.sh banking"
    echo "  bash create-locker.sh personal"
    exit 1
fi

LOCKER_NAME="$1"
LOCKER_DIR="docs/lockers/$LOCKER_NAME"
CONTENT_FILE="$LOCKER_DIR/content.txt"
INDEX_FILE="$LOCKER_DIR/index.html"
TEMPLATE_FILE="docs/locker.html"
TMP_DIR="tmp"
TMP_FILE="$TMP_DIR/$LOCKER_NAME.md"

echo -e "${BLUE}=== Auth Locker - Create New Locker ===${NC}"
echo
echo "Locker name: $LOCKER_NAME"
echo

# Validate locker name (alphanumeric, hyphens, underscores only)
if ! [[ "$LOCKER_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo -e "${RED}✗ Error: Invalid locker name${NC}"
    echo "Locker names must contain only letters, numbers, hyphens, and underscores"
    exit 1
fi

# Check if locker already exists
if [ -d "$LOCKER_DIR" ]; then
    echo -e "${YELLOW}⚠ Warning: Locker '$LOCKER_NAME' already exists${NC}"
    echo
    
    # Offer to backup existing content
    if [ -f "$CONTENT_FILE" ]; then
        echo "Existing encrypted content found. A backup will be created."
        BACKUP_FILE="${CONTENT_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
    fi
    
    read -p "Do you want to reinitialize it? This will overwrite existing files. (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
    
    # Create backup if content exists
    if [ -n "$BACKUP_FILE" ] && [ -f "$CONTENT_FILE" ]; then
        cp "$CONTENT_FILE" "$BACKUP_FILE"
        echo -e "${GREEN}✓${NC} Backup created: $BACKUP_FILE"
        echo
    fi
fi

# Check if template exists
if [ ! -f "$TEMPLATE_FILE" ]; then
    echo -e "${RED}✗ Error: Template file not found: $TEMPLATE_FILE${NC}"
    exit 1
fi

# Create locker directory
echo -e "${BLUE}[1/5]${NC} Creating locker directory..."
mkdir -p "$LOCKER_DIR"
echo -e "${GREEN}✓${NC} Created: $LOCKER_DIR"
echo

# Copy locker template
echo -e "${BLUE}[2/5]${NC} Setting up locker UI..."
cp "$TEMPLATE_FILE" "$INDEX_FILE"
echo -e "${GREEN}✓${NC} Created: $INDEX_FILE"
echo

# Create tmp directory if needed
if [ ! -d "$TMP_DIR" ]; then
    mkdir -p "$TMP_DIR"
fi

# Create initial content file
echo -e "${BLUE}[3/5]${NC} Creating initial content..."
cat > "$TMP_FILE" <<EOF
# Locker: $LOCKER_NAME
Created: $(date '+%Y-%m-%d %H:%M:%S')

This is your new encrypted locker. Edit this file to add your secrets, then re-encrypt.

## Instructions
1. Edit this file with your secrets
2. Run: bash encrypt.sh "$LOCKER_NAME"
3. Commit and push to deploy
4. Access at: https://yourdomain.github.io/auth-locker/$LOCKER_NAME/

## Example Content
- Username: myuser
- Password: (add your password here)
- Recovery codes: (add codes here)
- Notes: (add any notes)
EOF
echo -e "${GREEN}✓${NC} Created: $TMP_FILE"
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

if node encrypt-for-embed.js "$TMP_FILE" --locker "$LOCKER_NAME"; then
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
echo -e "${GREEN}✓ Locker '$LOCKER_NAME' created successfully!${NC}"
echo
echo "Directory structure:"
echo "  $LOCKER_DIR/"
echo "  ├── index.html (UI)"
echo "  └── content.txt (encrypted data)"
echo
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Edit your secrets:"
echo "   Open $TMP_FILE in your editor"
echo
echo "2. Re-encrypt when ready:"
echo "   bash encrypt.sh \"$LOCKER_NAME\""
echo
echo "3. Deploy to GitHub Pages:"
echo "   git add docs/lockers/\"$LOCKER_NAME\"/"
echo "   git commit -m 'Add $LOCKER_NAME locker'"
echo "   git push"
echo
echo "4. Access your locker:"
echo "   https://yourdomain.github.io/auth-locker/$LOCKER_NAME/"
echo
echo -e "${BLUE}Note:${NC} The initial content in $TMP_FILE is a template."
echo "      Remember to edit it before deploying!"
echo
