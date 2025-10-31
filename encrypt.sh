#!/bin/bash

# Encrypts tmp/main.md into docs/content.txt.  Create the former and 
# then run encrypt.sh.   When satisfied, a git commit + push will update
# the published recovery page at https://stabledog.github.io/auth-locker

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# File paths
INPUT_FILE="tmp/main.md"
OUTPUT_FILE="docs/content.txt"
ENCRYPTOR="encrypt-for-embed.js"

echo "=== Auth Locker Encryption Wrapper ==="
echo

# Check if Node.js is available
if ! command -v node &> /dev/null; then
    echo -e "${RED}✗ Error: Node.js is not installed or not in PATH${NC}"
    exit 1
fi

# Check if encryptor script exists
if [ ! -f "$ENCRYPTOR" ]; then
    echo -e "${RED}✗ Error: $ENCRYPTOR not found${NC}"
    exit 1
fi

# Check if tmp directory exists
if [ ! -d "tmp" ]; then
    echo -e "${YELLOW}⚠ Creating tmp/ directory${NC}"
    mkdir -p tmp
fi

# Check if input file exists
if [ ! -f "$INPUT_FILE" ]; then
    echo -e "${RED}✗ Error: $INPUT_FILE not found${NC}"
    echo
    echo "Please create tmp/main.md with your secrets, for example:"
    echo "  echo '# My Recovery Secrets' > tmp/main.md"
    echo "  echo '1Password Secret Key: A3-...' >> tmp/main.md"
    echo
    exit 1
fi

# Display input file info
INPUT_SIZE=$(wc -c < "$INPUT_FILE")
INPUT_LINES=$(wc -l < "$INPUT_FILE")
echo -e "${GREEN}✓${NC} Found input file: $INPUT_FILE"
echo "  Size: $INPUT_SIZE bytes"
echo "  Lines: $INPUT_LINES"
echo

# Confirm before proceeding
echo -e "${YELLOW}This will encrypt $INPUT_FILE and overwrite $OUTPUT_FILE${NC}"
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo

# Run the encryptor
node "$ENCRYPTOR" "$INPUT_FILE"

# Check if encryption succeeded
if [ $? -eq 0 ] && [ -f "$OUTPUT_FILE" ]; then
    echo
    echo -e "${GREEN}✓ Encryption complete!${NC}"
    echo
    echo "Next steps:"
    echo "  1. Commit and push docs/content.txt"
    echo "  2. Wait a few minutes for GitHub Pages to deploy"
    echo "  3. Test decryption at http://stabledog.github.io/auth-locker"
    echo
    echo -e "${YELLOW}⚠ Security reminders:${NC}"
    echo "  - Deleting tmp/main.md: rm $INPUT_FILE"
    echo "  - The passphrase is NOT stored anywhere"
    echo "  - Remember your passphrase or you cannot decrypt"
    echo "  - After emergency use, rotate all exposed credentials"
else
    echo
    echo -e "${RED}✗ Encryption failed${NC}"
    exit 1
fi



