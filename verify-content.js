/**
 * Decrypt-and-verify tool for Auth Locker
 *
 * Decrypts a content.txt the same way the published page does (WebCrypto,
 * PBKDF2-SHA256 -> AES-256-GCM) and reports whether it opens. If the source
 * plaintext is given, also reports whether the decrypted content matches it
 * byte for byte. Never prints the decrypted content.
 *
 * Usage:
 *   node verify-content.js <content.txt> [--plaintext <file>] [--page <index.html>]
 *
 * --page reads the PBKDF2 iteration count from the decryptor page that will
 * serve this file, so the check fails if the page and the file disagree.
 * Without it, the encryptor's iteration count is used.
 *
 * Usually run through verify.sh. Exit code 0 means it opens (and matches, if
 * checked); anything else is a failure.
 */

const fs = require('fs');
const { webcrypto } = require('crypto');
const { askLines, PBKDF2_ITERATIONS } = require('./encrypt-for-embed.js');

function parseArgs() {
  const args = process.argv.slice(2);
  const opts = { contentFile: null, plaintextFile: null, pageFile: null };
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--plaintext' && i + 1 < args.length) {
      opts.plaintextFile = args[++i];
    } else if (args[i] === '--page' && i + 1 < args.length) {
      opts.pageFile = args[++i];
    } else if (!opts.contentFile && !args[i].startsWith('--')) {
      opts.contentFile = args[i];
    } else {
      throw new Error(`Unexpected argument: ${args[i]}`);
    }
  }
  if (!opts.contentFile) {
    throw new Error('Usage: node verify-content.js <content.txt> [--plaintext <file>] [--page <index.html>]');
  }
  return opts;
}

/**
 * Reads SALT_B64 / IV_B64 / CT_B64 from a content.txt
 */
function readContentFile(contentFile) {
  if (!fs.existsSync(contentFile)) {
    throw new Error(`File not found: ${contentFile}`);
  }
  const data = {};
  for (const line of fs.readFileSync(contentFile, 'utf8').split(/\r?\n/)) {
    const eq = line.indexOf('=');
    if (eq > 0) {
      data[line.slice(0, eq).trim()] = line.slice(eq + 1).trim();
    }
  }
  if (!data.SALT_B64 || !data.IV_B64 || !data.CT_B64) {
    throw new Error(`${contentFile} is not a locker file (needs SALT_B64, IV_B64 and CT_B64 lines)`);
  }
  return {
    salt: Buffer.from(data.SALT_B64, 'base64'),
    iv: Buffer.from(data.IV_B64, 'base64'),
    ct: Buffer.from(data.CT_B64, 'base64')
  };
}

/**
 * Reads the iteration count the decryptor page uses
 */
function readPageIterations(pageFile) {
  const html = fs.readFileSync(pageFile, 'utf8');
  const match = html.match(/const\s+PBKDF2_ITERATIONS\s*=\s*(\d+)/);
  if (!match) {
    throw new Error(`Could not find PBKDF2_ITERATIONS in ${pageFile}`);
  }
  return parseInt(match[1], 10);
}

/**
 * Same steps as decrypt() in docs/locker.html. Resolves to the plaintext
 * bytes, or null if the passphrase is wrong or the file is damaged.
 */
async function decrypt(content, passphrase, iterations) {
  const subtle = webcrypto.subtle;
  const keyMaterial = await subtle.importKey(
    'raw', new TextEncoder().encode(passphrase), 'PBKDF2', false, ['deriveKey']
  );
  const key = await subtle.deriveKey(
    { name: 'PBKDF2', salt: content.salt, iterations, hash: 'SHA-256' },
    keyMaterial,
    { name: 'AES-GCM', length: 256 },
    false,
    ['decrypt']
  );
  try {
    return Buffer.from(await subtle.decrypt({ name: 'AES-GCM', iv: content.iv }, key, content.ct));
  } catch {
    return null;
  }
}

async function main() {
  process.exitCode = 1;
  try {
    const opts = parseArgs();
    const content = readContentFile(opts.contentFile);

    let iterations = PBKDF2_ITERATIONS;
    let iterSource = 'the encryptor default';
    if (opts.pageFile) {
      iterations = readPageIterations(opts.pageFile);
      iterSource = `as used by ${opts.pageFile}`;
    }

    console.log(`Checking: ${opts.contentFile}`);
    const [passphrase] = await askLines(['Passphrase: ']);

    const plaintext = await decrypt(content, passphrase, iterations);
    if (plaintext === null) {
      console.log(`\nOPENS: NO - ${opts.contentFile} does not decrypt with that passphrase`);
      console.log(`  (${iterations} iterations, ${iterSource}).`);
      console.log('  Either the passphrase is wrong or the file is damaged. Do not commit it.');
      return;
    }
    console.log(`\nOPENS: yes - ${opts.contentFile} decrypts with that passphrase`);
    console.log(`  (${iterations} iterations, ${iterSource}).`);

    if (!opts.plaintextFile || !fs.existsSync(opts.plaintextFile)) {
      const what = opts.plaintextFile ? `${opts.plaintextFile} not found` : 'no plaintext file given';
      console.log(`MATCHES: not checked - ${what}.`);
      process.exitCode = 0;
      return;
    }
    const source = fs.readFileSync(opts.plaintextFile);
    if (source.equals(plaintext)) {
      console.log(`MATCHES: yes - the decrypted content is identical to ${opts.plaintextFile}.`);
      process.exitCode = 0;
    } else {
      console.log(`MATCHES: NO - the decrypted content differs from ${opts.plaintextFile}`);
      console.log(`  (${plaintext.length} bytes decrypted, ${source.length} bytes in the file).`);
      console.log('  Re-run encrypt.sh before committing.');
    }
  } catch (error) {
    console.error(`\nError: ${error.message}`);
    process.exitCode = 1;
  }
}

main();
