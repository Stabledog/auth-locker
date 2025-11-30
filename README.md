# auth-locker
Self-hosted secrets recovery tool

## Hosted at:

https://stabledog.github.io/auth-locker/

# How to Update Your Encrypted Secrets

## Procedure

1. **Decrypt your existing secrets**:
   - Open https://stabledog.github.io/auth-locker in your browser
   - Enter your passphrase to decrypt
   - Copy the decrypted content

2. **Save to temporary file**:
   ```bash
   # Save the decrypted content to tmp/main.md
   # (Use your preferred editor)
   ```

3. **Edit the secrets**:
   - Open `tmp/main.md` in your editor
   - Update/add/remove secrets as needed
   - Save the file

4. **Re-encrypt**:
   ```bash
   bash encrypt.sh
   ```
   
   The script will:
   - Verify your setup
   - Show file size/lines
   - Ask for confirmation
   - Encrypt `tmp/main.md` → `docs/content.txt`

5. **Deploy**:
   ```bash
   git add docs/content.txt
   git commit -m "Update encrypted secrets"
   git push
   ```

6. **Test**:
   - Wait for GitHub Pages to deploy (~2-5 minutes)
   - Test decryption at https://stabledog.github.io/auth-locker

7. **Clean up** (recommended):
   ```bash
   rm tmp/main.md
   ```

## Important Notes

- **Passphrase**: Not stored anywhere - memorize it or store securely
- **After emergency use**: Rotate all exposed credentials immediately
- **Backup**: Consider keeping an encrypted offline backup of your passphrase
