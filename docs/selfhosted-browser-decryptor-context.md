# Self-Hosted Browser-Only Secret Recovery Decryptor — Context for Copilot

## Goal
Provide a zero-install, cross-platform recovery path for critical secrets (e.g., 1Password Secret Key) usable from any browser — even a borrowed or public computer.

## Concept
- Host **one static HTML file** that performs **client-side AES-GCM decryption** via the Web Crypto API.  
- The same file **embeds the ciphertext** (`salt`, `iv`, `ciphertext`) inside the page source.  
- The user memorizes:
  - a Diceware-style passphrase (e.g., 6–8 random words)
  - a short, memorable URL (e.g., TinyURL → the hosted page).  
- In an emergency, open the URL, enter the passphrase, and the browser decrypts locally — no CLI tools, no server-side code.

## Trust Model
- Creation occurs on a **trusted** machine.
- Hosting is under user control (GitHub Pages).
- Browser executes only the user’s static HTML; the server never sees plaintext or passphrase.
- After use, user rotates any exposed credentials.

## Crypto Parameters
| Item | Choice | Notes |
|------|---------|-------|
| KDF  | PBKDF2-HMAC-SHA256 | 200 000 iterations (configurable) |
| Cipher | AES-256-GCM | 12-byte IV, 16-byte tag |
| Salt | 16 bytes random | stored Base64 |
| Encoding | Base64 for salt / iv / ciphertext (+ tag) | embedded in HTML constants |

## Implementation Components
### 1. **`encrypt-for-embed.js`** (Node script, trusted machine)
Reads plaintext file, prompts for passphrase, outputs Base64:
```
SALT_B64=...
IV_B64=...
CT_B64=...
```
Paste these into the HTML template’s constants.  
Uses Node `crypto`:
- `crypto.pbkdf2Sync(pass, salt, iter, 32, 'sha256')`
- `crypto.createCipheriv('aes-256-gcm', key, iv)`

### 2. **`index.html`** (hosted decryptor)
Single-page app:
- Simple UI: password field, “Decrypt” / “Clear” buttons, `<pre>` output.
- Embedded constants:
  ```js
  const EMBED = {saltB64:"...", ivB64:"...", ctB64:"..."};
  ```
- JS derives key with PBKDF2, decrypts AES-GCM using `crypto.subtle`, prints plaintext.  
- No network calls after load; all local.  
- Include brief warning + cleanup instructions.

### 3. **Hosting**
1. Commit `index.html` to a public GitHub repo.  
2. Enable GitHub Pages → `https://<user>.github.io/<repo>/`.  
3. Create a TinyURL redirect for memorability.  
4. (Optional) host a duplicate copy elsewhere for redundancy.

### 4. **Emergency Workflow**
1. On any browser → open memorized TinyURL.  
2. Type memorized passphrase → click **Decrypt**.  
3. Copy displayed secret; complete recovery (e.g., 1Password login).  
4. Close browser; later, rotate affected secrets.

## Copilot / LLM Tasks
When editing this project, Copilot should:
- Maintain AES-GCM / PBKDF2 logic (don’t downgrade crypto).  
- Help build small helper tools to:
  - generate ciphertext from plaintext (`encrypt-for-embed.js`)
  - optionally verify integrity (auth tag separation)
- Assist with HTML/CSS polish but not change core logic.

## Notes
- Increase PBKDF2 iterations if performance allows.  
- Test decryption on multiple browsers.  
- Consider printing SHA256 of the served HTML for tamper checks.  
- Delete plaintext files on the trusted machine after encryption.
