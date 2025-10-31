# Tasks for Converting PoC to Production Decryptor

Based on the requirements in selfhosted-browser-decryptor-context.md, here are the tasks to transform the smoke test into a functional decryptor:

## Task 1: Update `content.txt` Format
**File:** `docs/content.txt` (create if doesn't exist)

Change from plain text to structured format:
```
SALT_B64=<base64-encoded-salt>
IV_B64=<base64-encoded-iv>
CT_B64=<base64-encoded-ciphertext-with-tag>
```

**Instructions:**
- Create a 3-line text file with the above format
- Each line contains a key=value pair
- The plaintext being encrypted can be arbitrarily long (multiple paragraphs, JSON, etc.)
- Base64 encoding ensures each value is a single continuous string (no newlines within the encoded values)
- The CT_B64 line may be very long depending on plaintext size, but it's still one line
- Use placeholder values for now (actual encryption script will generate these)

---

## Task 2: Create Encryption Script
**File:** `encrypt-for-embed.js` (new file in root)

Create a Node.js script that:
1. Prompts user for plaintext input (or reads from file) - **supports arbitrary length, multi-line text**
2. Prompts for passphrase (with confirmation)
3. Generates random 16-byte salt
4. Generates random 12-byte IV
5. Derives AES-256 key using PBKDF2-HMAC-SHA256 (200,000 iterations)
6. Encrypts plaintext with AES-256-GCM
7. Writes `SALT_B64=...`, `IV_B64=...`, `CT_B64=...` to `docs/content.txt` (each on separate lines)

**Dependencies:** Node.js `crypto` module (built-in)

**Instructions:**
- Accept plaintext from stdin, file argument, or interactive prompt
- Support multi-line plaintext (entire input is treated as one block to encrypt)
- Use `crypto.pbkdf2Sync(passphrase, salt, 200000, 32, 'sha256')`
- Use `crypto.createCipheriv('aes-256-gcm', key, iv)`
- Extract auth tag with `cipher.getAuthTag()`
- Concatenate ciphertext + tag before Base64 encoding (creates one long string)
- Write to `docs/content.txt` in the 3-line format (no line breaks within Base64 values)
- Include instructions in comments for running the script

---

## Task 3: Rewrite index.html UI
**File:** index.html

Transform from smoke test to production decryptor:

**Remove:**
- Section showing file content preview
- User input labeled as "secret string"
- XOR transformation demo code
- "How This Proves" explanation section

**Add/Change:**
1. **Branding:** Title: "��� Auth Locker - Secret Recovery"
2. **Input Section:**
   - Password input field (type="password") with label "Recovery Passphrase"
   - Show/hide password toggle
   - "Decrypt" button (primary action)
   - "Clear" button (secondary action)
3. **Output Section:**
   - Initially hidden `<pre>` block for decrypted plaintext
   - Monospace font, selectable text
   - Copy-to-clipboard button
   - Auto-clear after 60 seconds (optional security feature)
4. **Status/Error Messages:**
   - Loading indicator while fetching content.txt
   - Clear error messages for wrong passphrase or missing file
   - Success indicator

**Instructions:**
- Keep styling minimal and professional
- Use semantic HTML
- Ensure mobile-responsive design
- Add ARIA labels for accessibility

---

## Task 4: Implement Web Crypto API Decryption
**File:** index.html (JavaScript section)

Replace the `transformData()` function with actual decryption:

1. **On page load:**
   - Fetch `content.txt`
   - Parse the three lines by splitting on newlines
   - Extract values after `=` for each key (SALT_B64, IV_B64, CT_B64)
   - Decode Base64 values to ArrayBuffers
   - Store in variables, don't display

2. **On decrypt button click:**
   - Get passphrase from input
   - Validate passphrase is not empty
   - Show loading indicator
   - Derive key using `crypto.subtle.importKey()` + `crypto.subtle.deriveKey()`
     - Algorithm: PBKDF2
     - Hash: SHA-256
     - Iterations: 200,000
     - Salt: decoded from SALT_B64
   - Separate auth tag (last 16 bytes) from ciphertext
   - Decrypt using `crypto.subtle.decrypt()`
     - Algorithm: AES-GCM
     - IV: decoded from IV_B64
   - Decode decrypted ArrayBuffer to UTF-8 string with `TextDecoder` (preserves newlines/formatting from original plaintext)
   - Display decrypted plaintext in output section
   - Handle errors (wrong passphrase shows "Decryption failed")

3. **On clear button click:**
   - Clear passphrase input
   - Clear output display
   - Clear any error messages

**Instructions:**
- Use async/await syntax
- Proper error handling with try/catch
- Convert Base64 strings to ArrayBuffers using `Uint8Array.from(atob(str), c => c.charCodeAt(0))`
- Convert decrypted ArrayBuffer to UTF-8 string with `TextDecoder`
- Never log passphrase or plaintext to console
- Clear sensitive data from memory when possible

---

## Task 5: Add Security Features
**File:** index.html

Implement security enhancements:

1. **Content Security Policy (CSP) Meta Tag:**
   ```html
   <meta http-equiv="Content-Security-Policy" 
         content="default-src 'self'; script-src 'unsafe-inline' 'self'; style-src 'unsafe-inline' 'self';">
   ```

2. **Auto-clear Timeout:**
   - After successful decryption, start 60-second timer
   - Show countdown in UI
   - Auto-clear plaintext when timer expires
   - User can disable timer if needed

3. **Clipboard Copy:**
   - Add button to copy decrypted content
   - Use `navigator.clipboard.writeText()`
   - Show "Copied!" feedback

4. **Integrity Check (Optional):**
   - Add SHA-256 hash of current HTML in footer
   - User can verify against known good hash

**Instructions:**
- Keep security features user-friendly
- Don't make UX unnecessarily complex
- Document any security assumptions in comments

---

## Task 6: Input Assembly for Encryptor
**Status:** PENDING - To be defined

This task will focus on how to assemble the plaintext input for `encrypt-for-embed.js` from external sources (password managers, secure notes, environment variables, etc.).

**Scope:**
- Workflow for gathering secrets from various sources
- Format recommendations (JSON, YAML, plain text)
- Best practices for temporary file handling
- Integration with password managers (1Password CLI, Bitwarden CLI, etc.)
- Template examples

**Instructions:**
- To be expanded based on requirements
- Will define scripts/helpers to pull from external sources
- Document secure practices for handling plaintext before encryption

---

## Task 7: Create README and Documentation
**File:** README.md (root directory)

Document:
1. **Purpose:** Emergency secret recovery tool
2. **Setup Instructions:**
   - How to run `encrypt-for-embed.js`
   - How to deploy to GitHub Pages
3. **Usage Instructions:**
   - How to access and use the decryptor
4. **Security Considerations:**
   - Trust model
   - When to rotate secrets
   - Browser security requirements
5. **Architecture Notes:**
   - Why index.html stays static
   - How `content.txt` is generated/updated

---

## Task 8: Testing Checklist
Create test scenarios:

1. ✅ Encrypt sample text with known passphrase
2. ✅ Deploy to local HTTP server
3. ✅ Decrypt with correct passphrase - should succeed
4. ✅ Decrypt with wrong passphrase - should fail gracefully
5. ✅ Test with missing `content.txt` - should show error
6. ✅ Test with malformed `content.txt` - should show error
7. ✅ Test clipboard copy functionality
8. ✅ Test on multiple browsers (Chrome, Firefox, Safari)
9. ✅ Test on mobile device
10. ✅ Verify no network calls after initial load (check DevTools)


