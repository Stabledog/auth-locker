/**
 * Encryption Script for Auth Locker
 * 
 * Encrypts plaintext using AES-256-GCM with PBKDF2 key derivation.
 * Outputs SALT_B64, IV_B64, and CT_B64 to docs/content.txt
 * 
 * Usage:
 *   node encrypt-for-embed.js                    # Interactive prompt
 *   node encrypt-for-embed.js plaintext.txt      # Encrypt file
 *   echo "secret text" | node encrypt-for-embed.js  # From stdin
 */

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const readline = require('readline');

// Crypto parameters
const PBKDF2_ITERATIONS = 200000;
const PBKDF2_KEYLEN = 32; // 256 bits for AES-256
const PBKDF2_DIGEST = 'sha256';
const SALT_LENGTH = 16; // bytes
const IV_LENGTH = 12; // bytes (96 bits for GCM)
const CIPHER_ALGORITHM = 'aes-256-gcm';
const OUTPUT_FILE = path.join(__dirname, 'docs', 'content.txt');

/**
 * Prompts user for input via readline
 */
function prompt(question) {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
  });
  
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer);
    });
  });
}

/**
 * Prompts for password with confirmation (hidden input)
 */
async function promptPassword() {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
  });

  return new Promise((resolve, reject) => {
    rl.question('Enter passphrase: ', (pass1) => {
      // Simple hidden input simulation (still visible but prompts twice)
      rl.question('Confirm passphrase: ', (pass2) => {
        rl.close();
        
        if (pass1 !== pass2) {
          reject(new Error('Passphrases do not match'));
        } else if (pass1.length === 0) {
          reject(new Error('Passphrase cannot be empty'));
        } else {
          resolve(pass1);
        }
      });
    });
  });
}

/**
 * Reads plaintext from various sources
 */
async function getPlaintext() {
  // Check if file argument provided
  if (process.argv[2]) {
    const filePath = process.argv[2];
    if (!fs.existsSync(filePath)) {
      throw new Error(`File not found: ${filePath}`);
    }
    console.log(`Reading plaintext from: ${filePath}`);
    return fs.readFileSync(filePath, 'utf8');
  }

  // Check if stdin has data (piped input)
  if (!process.stdin.isTTY) {
    console.log('Reading plaintext from stdin...');
    const chunks = [];
    for await (const chunk of process.stdin) {
      chunks.push(chunk);
    }
    return Buffer.concat(chunks).toString('utf8');
  }

  // Interactive prompt - use readline instead of stdin chunks
  console.log('Enter plaintext (type EOF on a new line when done, or Ctrl+C to cancel):');
  
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    prompt: ''
  });

  return new Promise((resolve) => {
    const lines = [];
    
    rl.on('line', (line) => {
      // Check for EOF marker
      if (line.trim() === 'EOF') {
        rl.close();
        return;
      }
      lines.push(line);
    });

    rl.on('close', () => {
      resolve(lines.join('\n'));
    });
  });
}

/**
 * Encrypts plaintext with the given passphrase
 */
function encryptData(plaintext, passphrase) {
  // Generate random salt and IV
  const salt = crypto.randomBytes(SALT_LENGTH);
  const iv = crypto.randomBytes(IV_LENGTH);

  // Derive key using PBKDF2
  console.log(`Deriving key with PBKDF2 (${PBKDF2_ITERATIONS} iterations)...`);
  const key = crypto.pbkdf2Sync(
    passphrase,
    salt,
    PBKDF2_ITERATIONS,
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
    saltB64: salt.toString('base64'),
    ivB64: iv.toString('base64'),
    ctB64: ctWithTag.toString('base64')
  };
}

/**
 * Writes encrypted data to docs/content.txt
 */
function writeOutput(encryptedData) {
  const outputContent = `SALT_B64=${encryptedData.saltB64}\nIV_B64=${encryptedData.ivB64}\nCT_B64=${encryptedData.ctB64}\n`;
  
  // Ensure docs directory exists
  const docsDir = path.dirname(OUTPUT_FILE);
  if (!fs.existsSync(docsDir)) {
    fs.mkdirSync(docsDir, { recursive: true });
  }

  fs.writeFileSync(OUTPUT_FILE, outputContent, 'utf8');
  console.log(`\n✓ Encrypted data written to: ${OUTPUT_FILE}`);
  console.log(`  Salt length: ${encryptedData.saltB64.length} chars (Base64)`);
  console.log(`  IV length: ${encryptedData.ivB64.length} chars (Base64)`);
  console.log(`  Ciphertext+Tag length: ${encryptedData.ctB64.length} chars (Base64)`);
}

/**
 * Main execution
 */
async function main() {
  try {
    console.log('=== Auth Locker Encryption Tool ===\n');

    // Get plaintext
    const plaintext = await getPlaintext();
    
    if (!plaintext || plaintext.trim().length === 0) {
      throw new Error('No plaintext provided');
    }
    
    console.log(`\nPlaintext length: ${plaintext.length} characters`);

    // Get passphrase
    const passphrase = await promptPassword();

    // Encrypt
    const encrypted = encryptData(plaintext, passphrase);

    // Write output
    writeOutput(encrypted);

    console.log('\n✓ Encryption complete!');
    console.log('\nNext steps:');
    console.log('1. Commit docs/content.txt to your repository');
    console.log('2. Deploy to GitHub Pages');
    console.log('3. Access the decryptor and use the same passphrase');
    
  } catch (error) {
    console.error(`\n✗ Error: ${error.message}`);
    process.exit(1);
  }
}

// Run if executed directly
if (require.main === module) {
  main();
}

module.exports = { encryptData, getPlaintext, promptPassword };
