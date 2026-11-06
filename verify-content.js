/**
 * Decrypt-and-verify tool for Auth Locker
 *
 * Decrypts a content.txt with the decryptor page's own code (the locker-core
 * block of docs/locker.html, loaded by locker-core.js) and reports whether it
 * opens. The iteration count comes from the file itself. If the source
 * plaintext is given, also reports whether the decrypted content matches it
 * byte for byte. Never prints the decrypted content.
 *
 * Usage:
 *   node verify-content.js <content.txt> [--plaintext <file>]
 *
 * Usually run through verify.sh, which also checks that the page serving the
 * file is the current docs/locker.html. Exit code 0 means it opens (and
 * matches, if checked); anything else is a failure.
 */

const fs = require('fs');
const { askLines } = require('./encrypt-for-embed.js');
const core = require('./locker-core.js').load();

function parseArgs() {
  const args = process.argv.slice(2);
  const opts = { contentFile: null, plaintextFile: null };
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--plaintext' && i + 1 < args.length) {
      opts.plaintextFile = args[++i];
    } else if (!opts.contentFile && !args[i].startsWith('--')) {
      opts.contentFile = args[i];
    } else {
      throw new Error(`Unexpected argument: ${args[i]}`);
    }
  }
  if (!opts.contentFile) {
    throw new Error('Usage: node verify-content.js <content.txt> [--plaintext <file>]');
  }
  return opts;
}

async function main() {
  process.exitCode = 1;
  try {
    const opts = parseArgs();
    if (!fs.existsSync(opts.contentFile)) {
      throw new Error(`File not found: ${opts.contentFile}`);
    }
    const content = core.parseContent(fs.readFileSync(opts.contentFile, 'utf8'));
    const params = `format ${content.version}, ${content.iterations} iterations, as recorded in the file`;

    console.log(`Checking: ${opts.contentFile}`);
    const [passphrase] = await askLines(['Passphrase: ']);

    const plaintext = await core.decryptContent(content, passphrase);
    if (plaintext === null) {
      console.log(`\nOPENS: NO - ${opts.contentFile} does not decrypt with that passphrase`);
      console.log(`  (${params}).`);
      console.log('  Either the passphrase is wrong or the file is damaged. Do not commit it.');
      return;
    }
    console.log(`\nOPENS: yes - ${opts.contentFile} decrypts with that passphrase`);
    console.log(`  (${params}).`);

    if (!opts.plaintextFile || !fs.existsSync(opts.plaintextFile)) {
      const what = opts.plaintextFile ? `${opts.plaintextFile} not found` : 'no plaintext file given';
      console.log(`MATCHES: not checked - ${what}.`);
      process.exitCode = 0;
      return;
    }
    const source = fs.readFileSync(opts.plaintextFile);
    if (source.equals(Buffer.from(plaintext))) {
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
