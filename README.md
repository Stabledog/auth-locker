# auth-locker
Self-hosted secrets recovery tool

## Hosted at:

https://stabledog.github.io/auth-locker/

# Multiple Lockers Support

You can now create multiple independent encrypted lockers, each with its own passphrase and content. This allows you to organize different types of secrets (e.g., personal, banking, work) into separate encrypted containers.

**Security Note:** Each locker uses its own temporary file to prevent accidentally mixing secrets:
- Default locker: `tmp/main.md`
- Named lockers: `tmp/<locker-name>.md` (e.g., `tmp/personal.md`, `tmp/banking.md`)

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

Then you can edit `tmp/mylocker.md` with your actual secrets, re-encrypt, and check the result opens:
```bash
bash encrypt.sh mylocker
bash verify.sh mylocker
```

`create-locker.sh` refuses to run on a locker that already has encrypted content or edited plaintext in `tmp/`. See "Creating a New Locker" below.

### Default Locker
```bash
bash encrypt.sh
bash verify.sh
```
Uses `tmp/main.md` and access at: https://stabledog.github.io/auth-locker/

### Named Lockers (Manual Method)
```bash
# Create your content file
echo "My secrets" > tmp/personal.md
bash encrypt.sh personal

# Another locker
echo "Banking info" > tmp/banking.md
bash encrypt.sh banking
```
Access at:
- https://stabledog.github.io/auth-locker/lockers/personal/
- https://stabledog.github.io/auth-locker/lockers/banking/

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
   # For named locker "mylocker", save to tmp/mylocker.md
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
   
   For named locker (e.g., "mylocker"):
   ```bash
   bash encrypt.sh mylocker
   ```
   
   The script will:
   - Verify your setup
   - Show file size/lines
   - Ask for confirmation
   - Encrypt `tmp/main.md` → `docs/content.txt` (or `docs/lockers/{name}/content.txt`)
   - Fail, and say so, if the output file was not actually rewritten

5. **Verify before committing**:

   ```bash
   bash verify.sh          # default locker
   bash verify.sh mylocker # named locker
   ```

   Type the passphrase you just used. It decrypts the new `content.txt` with the web page's
   own code (and first checks the page serving it is up to date) and tells you plainly:
   - `OPENS: yes` or `OPENS: NO`: whether the file decrypts with that passphrase
   - `MATCHES: yes` or `MATCHES: NO`: whether the decrypted text is identical to `tmp/main.md`
     (or `tmp/<name>.md`). It shows `not checked` if you've already deleted that file.

   It never prints your secrets. Don't commit unless it says `OPENS: yes` and `MATCHES: yes`.

6. **Deploy**:
   
   For default locker:
   ```bash
   git add docs/content.txt
   git commit -m "Update encrypted secrets"
   git push
   ```
   
   For named locker:
   ```bash
   git add docs/lockers/mylocker/
   git commit -m "Update mylocker locker"
   git push
   ```

7. **Test**:
   - Wait for GitHub Pages to deploy (~2-5 minutes)
   - Test decryption at the appropriate URL

8. **Clean up** (recommended):
   ```bash
   # For default locker
   rm tmp/main.md
   
   # For named locker (e.g., mylocker)
   rm tmp/mylocker.md
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
3. Check it opens: `bash verify.sh mylocker`
4. Commit and deploy (see step 6 above)

**Existing lockers are protected.** If `docs/lockers/mylocker/content.txt` already exists, or
`tmp/mylocker.md` holds anything other than the untouched starter template, the script stops
without changing anything. To change an existing locker's secrets, edit `tmp/mylocker.md` and run
`encrypt.sh` instead. To refresh only its page, run `bash sync-pages.sh`.

To really start a locker over, run `bash create-locker.sh --force mylocker` at a terminal and type
the locker name when asked. The old plaintext is moved to `tmp/mylocker.md.bak.<timestamp>`
and the old `content.txt` is copied to `tmp/mylocker.content.txt.bak.<timestamp>`. Both are in
`tmp/`, which is gitignored and never published.

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

3. Give it a page (one-time setup per locker), then check it opens:
   ```bash
   bash sync-pages.sh
   bash verify.sh mylocker
   ```

4. Commit and push:
   ```bash
   git add docs/lockers/mylocker/
   git commit -m "Add mylocker"
   git push
   ```

5. Access at: `https://stabledog.github.io/auth-locker/lockers/mylocker/`

## The decryptor page

`docs/locker.html` is the only decryptor page. `docs/index.html` and each
`docs/lockers/<name>/index.html` are exact copies, because GitHub Pages needs a page in
each folder. To change the page, edit `docs/locker.html`, run `bash sync-pages.sh`, and
commit the copies with it. `bash sync-pages.sh --check` lists any copy that is out of date,
and `verify.sh` refuses a locker whose page is out of date.

## The content.txt format

```
V=2
ITER=600000
SALT_B64=...
IV_B64=...
CT_B64=...
```

Each file records its own iteration count (`ITER`), so the count can be raised for new
files without breaking old ones. The format, the count for new files and the decrypt
steps live in one place: the `locker-core` block of `docs/locker.html`. `encrypt.sh` and
`verify.sh` load that same block (through `locker-core.js`), so the tools and the page
can't disagree.

From format 2 on, the passphrase is trimmed of spaces at both ends and Unicode-normalized
(NFC) before use, so the same passphrase typed on another device or keyboard opens the
locker. `encrypt.sh` won't accept a passphrase that starts or ends with a space. Files
with no `V=` line (format 1, made before this change) use 200000 iterations and the
passphrase exactly as typed, and keep opening. They move to format 2 the next time
they're re-encrypted.

## Important Notes

- **Passphrase**: Not stored anywhere - memorize it or store securely
- **After emergency use**: Rotate all exposed credentials immediately
- **Backup**: Consider keeping an encrypted offline backup of your passphrase
- **Multiple lockers**: Each locker is independent and can have different passphrases
