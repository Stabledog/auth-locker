# auth-locker
Self-hosted secrets recovery tool

## Hosted at:

https://stabledog.github.io/auth-locker/

# Multiple Lockers Support

You can now create multiple independent encrypted lockers, each with its own passphrase and content. This allows you to organize different types of secrets (e.g., personal, banking, work) into separate encrypted containers.

**Security Note:** Each locker uses its own temporary file to prevent accidentally mixing secrets:
- Default locker: `tmp/main.md`
- Named lockers: `tmp/<locker-name>.md` (e.g., `tmp/sally.md`, `tmp/banking.md`)

## Quick Start

### Creating a New Locker (Recommended)

Use the `create-locker.sh` script to automatically set up a new locker:

```bash
bash create-locker.sh mylocker
```

This will:
1. Create the locker directory structure
2. Generate a template content file at `tmp/mylocker.md`
3. Prompt you to create a passphrase
4. Encrypt the initial content
5. Set up the UI (index.html)

Then you can edit `tmp/mylocker.md` with your actual secrets and re-encrypt:
```bash
bash encrypt.sh mylocker
```

### Default Locker
```bash
bash encrypt.sh
```
Uses `tmp/main.md` and access at: https://stabledog.github.io/auth-locker/

### Named Lockers (Manual Method)
```bash
# Create your content file
echo "My secrets" > tmp/sally.md
bash encrypt.sh sally

# Another locker
echo "Banking info" > tmp/banking.md
bash encrypt.sh banking
```
Access at:
- https://stabledog.github.io/auth-locker/sally/
- https://stabledog.github.io/auth-locker/banking/

Each locker has its own passphrase and encrypted content file.

# How to Update Your Encrypted Secrets

## Procedure

1. **Decrypt your existing secrets**:
   - Open https://stabledog.github.io/auth-locker in your browser (or your named locker URL)
   - Enter your passphrase to decrypt
   - Copy the decrypted content

2. **Save to temporary file**:
   ```bash
   # For default locker, save to tmp/main.md
   # For named locker "sally", save to tmp/sally.md
   # (Use your preferred editor)
   ```

3. **Edit the secrets**:
   - Open the appropriate file in your editor (`tmp/main.md` for default, `tmp/<locker-name>.md` for named)
   - Update/add/remove secrets as needed
   - Save the file

4. **Re-encrypt**:
   
   For default locker:
   ```bash
   bash encrypt.sh
   ```
   
   For named locker (e.g., "sally"):
   ```bash
   bash encrypt.sh sally
   ```
   
   The script will:
   - Verify your setup
   - Show file size/lines
   - Ask for confirmation
   - Encrypt `tmp/main.md` → `docs/content.txt` (or `docs/lockers/{name}/content.txt`)

5. **Deploy**:
   
   For default locker:
   ```bash
   git add docs/content.txt
   git commit -m "Update encrypted secrets"
   git push
   ```
   
   For named locker:
   ```bash
   git add docs/lockers/sally/
   git commit -m "Update sally locker"
   git push
   ```

6. **Test**:
   - Wait for GitHub Pages to deploy (~2-5 minutes)
   - Test decryption at the appropriate URL

7. **Clean up** (recommended):
   ```bash
   # For default locker
   rm tmp/main.md
   
   # For named locker (e.g., sally)
   rm tmp/sally.md
   ```

## Creating a New Locker

### Automated Method (Recommended)

Use the `create-locker.sh` script to set up everything automatically:

```bash
bash create-locker.sh mylocker
```

The script will:
1. Create the directory structure (`docs/lockers/mylocker/`)
2. Set up the UI (`index.html`)
3. Generate a template content file (`tmp/mylocker.md`)
4. Prompt you for a passphrase
5. Encrypt the initial content

After the script completes:
1. Edit `tmp/mylocker.md` with your actual secrets
2. Re-encrypt: `bash encrypt.sh mylocker`
3. Commit and deploy (see step 5 below)

### Manual Method

If you prefer to do it manually:

1. Create your secrets file:
   ```bash
   echo "My secret content" > tmp/mylocker.md
   ```

2. Encrypt to a new locker:
   ```bash
   bash encrypt.sh mylocker
   ```

3. Copy the locker template (one-time setup per locker):
   ```bash
   cp docs/locker.html docs/lockers/mylocker/index.html
   ```

4. Commit and push:
   ```bash
   git add docs/lockers/mylocker/
   git commit -m "Add mylocker"
   git push
   ```

5. Access at: `https://stabledog.github.io/auth-locker/mylocker/`

## Important Notes

- **Passphrase**: Not stored anywhere - memorize it or store securely
- **After emergency use**: Rotate all exposed credentials immediately
- **Backup**: Consider keeping an encrypted offline backup of your passphrase
- **Multiple lockers**: Each locker is independent and can have different passphrases
