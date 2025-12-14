# Copilot Instructions for auth-locker

## Repository Overview

This is a **personal secret recovery tool** that provides zero-install, browser-based access to encrypted emergency credentials. The tool is designed for personal use only - the owner controls all data and hosting.

## Purpose

Provide a recovery path for critical secrets (like 1Password Secret Key) from any browser, even on borrowed or public computers, without requiring CLI tools or software installation.

## Architecture

- **Static HTML decryptor** (`docs/index.html`) - deployed once, never changes
- **Encrypted content** (`docs/content.txt`) - regenerated when secrets are updated
- **Encryption tool** (`encrypt-for-embed.js`) - Node.js script for creating encrypted content
- **Helper script** (`encrypt.sh`) - Bash wrapper for encryption workflow
- **GitHub Pages hosting** - Static hosting at https://stabledog.github.io/auth-locker

## Security Model

### Trust Model
- **Creation**: Occurs on a trusted local machine
- **Hosting**: Under user control (GitHub Pages)
- **Execution**: Browser-only, client-side decryption
- **Privacy**: Server never sees plaintext or passphrase
- **Post-use**: User rotates all exposed credentials

### Cryptography
- **Cipher**: AES-256-GCM (12-byte IV, 16-byte auth tag)
- **KDF**: PBKDF2-HMAC-SHA256 with 200,000 iterations
- **Salt**: 16 bytes, randomly generated, stored in Base64
- **Encoding**: Base64 for all binary data (salt, IV, ciphertext+tag)

### Critical Constraints
- ✅ **DO**: Maintain or improve crypto strength (AES-256-GCM, PBKDF2)
- ✅ **DO**: Keep `index.html` static - only fetches and parses `content.txt`
- ✅ **DO**: Perform all crypto operations client-side in the browser
- ❌ **NEVER**: Commit plaintext secrets to the repository
- ❌ **NEVER**: Add server-side processing or API endpoints
- ❌ **NEVER**: Downgrade crypto algorithms or reduce iteration counts
- ❌ **NEVER**: Send plaintext or passphrases over the network

## Development Guidelines

### File Purposes
- **`docs/index.html`**: Single-page decryptor app (static, committed once)
- **`docs/content.txt`**: Three lines: `SALT_B64=...`, `IV_B64=...`, `CT_B64=...`
- **`encrypt-for-embed.js`**: Node.js encryption tool (uses Node `crypto` module)
- **`encrypt.sh`**: User-friendly wrapper for the encryption workflow
- **`tmp/main.md`**: User's plaintext secrets (gitignored, never committed)

### When Making Changes
1. **Crypto changes**: Ensure backward compatibility or provide migration path
2. **UI enhancements**: Keep the interface simple and accessible
3. **Tool improvements**: Maintain the simple file-based workflow
4. **Documentation**: Update if crypto parameters or workflow changes

### Typical Workflows
- **Updating secrets**: Edit `tmp/main.md` → run `./encrypt.sh` → commit `docs/content.txt`
- **Testing**: Open `docs/index.html` in browser, enter passphrase, verify decryption
- **Deployment**: Git push triggers GitHub Pages deployment (~2-5 minutes)

## Code Assistance Guidelines

When helping with this repository:
- Preserve the zero-dependency, single-page architecture
- Help with HTML/CSS polish but don't change core crypto logic
- Suggest security improvements (e.g., increased iterations if feasible)
- Assist with developer tooling (testing, validation scripts)
- Keep solutions simple - this is a personal tool, not a product

## Important Notes

- **No distribution**: Code is never distributed or shared beyond GitHub Pages
- **No deployment**: No servers, APIs, or backend infrastructure
- **Personal use**: All data is owned and controlled by the repository owner
- **Browser-based**: All encryption/decryption happens in the browser using Web Crypto API
- **Plaintext handling**: Plaintext exists only in `tmp/main.md` (gitignored) and user's browser
