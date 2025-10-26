# Self-Hosted Browser-Only Secret Recovery Decryptor — Context for Copilot

## Goal
Provide a zero-install, cross-platform recovery path for critical secrets (e.g., 1Password Secret Key) usable from any browser — even a borrowed or public computer.

## Concept
- Host **a one-page app** that performs **client-side AES-GCM decryption** via the Web Crypto API.  
- The ciphertext, salt, and IV are in a separate text file (`docs/content.txt`) that is fetched at runtime
- The user memorizes:
  - a Diceware-style passphrase (e.g., 6–8 random words)
  - the URL hosted on Github Pages (https://stabledog.github.io/auth-locker)
- In an emergency, the user opens the site, enters the passphrase, and the browser decrypts locally — no CLI tools, no server-side code.

## Trust Model
- Creation occurs on a **trusted** machine.
- Hosting is under user control (GitHub Pages).
- Browser executes only the user's static HTML; the server never sees plaintext or passphrase.
- After use, user rotates any exposed credentials.

## Crypto Parameters
| Item | Choice | Notes |
|------|---------|-------|
| KDF  | PBKDF2-HMAC-SHA256 | 200 000 iterations (configurable) |
| Cipher | AES-256-GCM | 12-byte IV, 16-byte tag |
| Salt | 16 bytes random | stored Base64 in content.txt |
| Encoding | Base64 for salt / iv / ciphertext (+ tag) | stored in content.txt |

## Implementation Components
### 1. **`encrypt-for-embed.js`** (Node script, prepares on trusted machine)
Reads plaintext file, prompts for passphrase, outputs to `docs/content.txt`:
```
SALT_B64=...
IV_B64=...
CT_B64=...
```
Uses Node `crypto`:
- `crypto.pbkdf2Sync(pass, salt, iter, 32, 'sha256')`
- `crypto.createCipheriv('aes-256-gcm', key, iv)`

### 2. **`index.html`** (hosted decryptor - STATIC, NEVER CHANGES)
Single-page app:
- Simple UI: password field, "Decrypt" / "Clear" buttons, `<pre>` output.
- On load, fetches `content.txt` from same directory
- Parses the three Base64 values from content.txt
- JS derives key with PBKDF2, decrypts AES-GCM using `crypto.subtle`, prints plaintext.  
- No network calls except initial load of index.html and content.txt; all processing local.

### 3. **`content.txt`** (regenerated when secrets change)
Simple text format:
```
SALT_B64=<base64-encoded-salt>
IV_B64=<base64-encoded-iv>
CT_B64=<base64-encoded-ciphertext-with-tag>
```

## Copilot / LLM Tasks
When editing this project, Copilot should:
- Maintain AES-GCM / PBKDF2 logic (don't downgrade crypto).  
- Help build small helper tools to:
  - generate ciphertext from plaintext (`encrypt-for-embed.js`)
  - optionally verify integrity (auth tag separation)
- Assist with HTML/CSS polish but not change core logic.
- Keep `index.html` static - it should only fetch and parse `content.txt`

## Notes
- Increase PBKDF2 iterations if performance allows.  
- Consider printing SHA256 of the served HTML for tamper checks.
- **Architecture benefit**: `index.html` is committed once and never changes; only `content.txt` is regenerated when secrets rotate.
