/**
 * Encryption Script for Auth Locker
 * 
 * Encrypts plaintext using AES-256-GCM with PBKDF2 key derivation.
 * Writes a format-2 content.txt (V, ITER, SALT_B64, IV_B64, CT_B64) to
 * docs/content.txt or docs/lockers/{name}/content.txt. The format, the
 * iteration count and the passphrase rules come from the decryptor page
 * (docs/locker.html, via locker-core.js), so the page can always open it.
 * 
 * Usage:
 *   node encrypt-for-embed.js plaintext.txt           # Encrypt file, default locker
 *   node encrypt-for-embed.js plaintext.txt --locker mylocker  # Encrypt to named locker
 *
 * The plaintext must come from a file: stdin is reserved for the passphrase.
 * Exits nonzero, without touching the output file, if anything goes wrong.
 */

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const readline = require('readline');
const core = require('./locker-core.js').load();

// Crypto parameters (the iteration count is core.NEW_FILE_ITERATIONS)
const PBKDF2_KEYLEN = 32; // 256 bits for AES-256
const PBKDF2_DIGEST = 'sha256';
const SALT_LENGTH = 16; // bytes
const IV_LENGTH = 12; // bytes (96 bits for GCM)
const CIPHER_ALGORITHM = 'aes-256-gcm';

/**
 * Parse command-line arguments to extract locker name
 */
function parseArgs() {
  const args = process.argv.slice(2);
  let inputFile = null;
  let lockerName = null;
  
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--locker' && i + 1 < args.length) {
      lockerName = args[i + 1];
      i++; // skip next arg
    } else if (!inputFile && !args[i].startsWith('--')) {
      inputFile = args[i];
    }
  }
  
  return { inputFile, lockerName };
}

/**
 * Get output file path based on locker name
 */
function getOutputPath(lockerName) {
  if (lockerName) {
    return path.join(__dirname, 'docs', 'lockers', lockerName, 'content.txt');
  }
  return path.join(__dirname, 'docs', 'content.txt');
}

/**
 * Asks each question in turn on stdin and resolves with the answers.
 * Rejects if stdin ends (Ctrl-D, EOF, an exhausted pipe) before every
 * question is answered, so a missing answer can never pass silently.
 */
function askLines(questions) {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
  });
  const answers = [];
  let settled = false;

  return new Promise((resolve, reject) => {
    rl.on('line', (line) => {
      if (settled) return;
      answers.push(line);
      if (answers.length === questions.length) {
        settled = true;
        rl.close();
        resolve(answers);
      } else {
        rl.setPrompt(questions[answers.length]);
        rl.prompt();
      }
    });
    rl.on('close', () => {
      if (settled) return;
      settled = true;
      process.stdout.write('\n');
      reject(new Error('Input ended before a passphrase was entered.'));
    });
    rl.setPrompt(questions[0]);
    rl.prompt();
  });
}

/**
 * Prompts for password with confirmation (input is still visible)
 */
async function promptPassword() {
  const [pass1, pass2] = await askLines(['Enter passphrase: ', 'Confirm passphrase: ']);
  const problem = core.newPassphraseProblem(pass1);
  if (problem) {
    throw new Error(problem);
  }
  const keyText = core.passphraseKeyText(pass1, core.FORMAT_VERSION);
  if (keyText !== core.passphraseKeyText(pass2, core.FORMAT_VERSION)) {
    throw new Error('Passphrases do not match');
  }
  return keyText;
}

/**
 * Reads plaintext from the input file
 */
async function getPlaintext(inputFile) {
  if (!inputFile) {
    throw new Error('No plaintext file given. Usage: node encrypt-for-embed.js <plaintext-file> [--locker <name>]');
  }
  if (!fs.existsSync(inputFile)) {
    throw new Error(`File not found: ${inputFile}`);
  }
  console.log(`Reading plaintext from: ${inputFile}`);
  return fs.readFileSync(inputFile, 'utf8');
}

/**
 * Encrypts plaintext with the given passphrase (already in key-text form)
 */
function encryptData(plaintext, passphrase) {
  const iterations = core.NEW_FILE_ITERATIONS;

  // Generate random salt and IV
  const salt = crypto.randomBytes(SALT_LENGTH);
  const iv = crypto.randomBytes(IV_LENGTH);

  // Derive key using PBKDF2
  console.log(`Deriving key with PBKDF2 (${iterations} iterations)...`);
  const key = crypto.pbkdf2Sync(
    Buffer.from(passphrase, 'utf8'),
    salt,
    iterations,
    PBKDF2_KEYLEN,
    PBKDF2_DIGEST
  );

  // Encrypt with AES-256-GCM
  console.log('Encrypting data...');
  const cipher = crypto.createCipheriv(CIPHER_ALGORITHM, key, iv);
  
  let ciphertext = cipher.update(plaintext, 'utf8');
  ciphertext = Buffer.concat([ciphertext, cipher.final()]);
  
  // Get authentication tag
  const authTag = cipher.getAuthTag();
  
  // Concatenate ciphertext + auth tag
  const ctWithTag = Buffer.concat([ciphertext, authTag]);

  // Return Base64-encoded values
  return {
    iterations,
    saltB64: salt.toString('base64'),
    ivB64: iv.toString('base64'),
    ctB64: ctWithTag.toString('base64')
  };
}

/**
 * Writes encrypted data to the specified output file
 */
function writeOutput(encryptedData, outputPath) {
  const outputContent = core.formatContent(
    encryptedData.iterations, encryptedData.saltB64, encryptedData.ivB64, encryptedData.ctB64
  );
  
  // Ensure output directory exists
  const outputDir = path.dirname(outputPath);
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }

  // Write a temp file and rename it over the target, so the target is either
  // fully replaced or left exactly as it was.
  const tmpPath = `${outputPath}.tmp-${process.pid}`;
  try {
    fs.writeFileSync(tmpPath, outputContent, 'utf8');
    fs.renameSync(tmpPath, outputPath);
  } finally {
    if (fs.existsSync(tmpPath)) fs.unlinkSync(tmpPath);
  }
  console.log(`\n✓ Encrypted data written to: ${outputPath}`);
  console.log(`  Salt length: ${encryptedData.saltB64.length} chars (Base64)`);
  console.log(`  IV length: ${encryptedData.ivB64.length} chars (Base64)`);
  console.log(`  Ciphertext+Tag length: ${encryptedData.ctB64.length} chars (Base64)`);
}

/**
 * Main execution
 */
async function main() {
  // Fail unless we reach the end: if the event loop ever drains early, the
  // exit code is nonzero rather than a silent 0.
  process.exitCode = 1;
  try {
    console.log('=== Auth Locker Encryption Tool ===\n');

    // Parse command-line arguments
    const { inputFile, lockerName } = parseArgs();
    const outputPath = getOutputPath(lockerName);
    
    if (lockerName) {
      console.log(`Locker name: ${lockerName}`);
    } else {
      console.log('Using default locker (docs/content.txt)');
    }

    // Get plaintext
    const plaintext = await getPlaintext(inputFile);
    
    if (!plaintext || plaintext.trim().length === 0) {
      throw new Error('No plaintext provided');
    }
    
    console.log(`\nPlaintext length: ${plaintext.length} characters`);

    // Get passphrase
    const passphrase = await promptPassword();

    // Encrypt
    const encrypted = encryptData(plaintext, passphrase);

    // Write output
    writeOutput(encrypted, outputPath);

    console.log('\n✓ Encryption complete!');
    console.log('\nNext steps:');
    if (lockerName) {
      console.log(`1. Check it opens: bash verify.sh ${lockerName}`);
      console.log(`2. Commit docs/lockers/${lockerName}/content.txt to your repository`);
      console.log('3. Deploy to GitHub Pages');
      console.log(`4. Access at https://yourdomain.github.io/auth-locker/${lockerName}/`);
    } else {
      console.log('1. Check it opens: bash verify.sh');
      console.log('2. Commit docs/content.txt to your repository');
      console.log('3. Deploy to GitHub Pages');
      console.log('4. Access the decryptor and use the same passphrase');
    }
    process.exitCode = 0;

  } catch (error) {
    console.error(`\n✗ Error: ${error.message}`);
    process.exit(1);
  }
}

// Run if executed directly
if (require.main === module) {
  main();
}

module.exports = { encryptData, getPlaintext, promptPassword, askLines, parseArgs, getOutputPath };
