/**
 * Loads the decryptor page's own content.txt code for the Node tools.
 *
 * docs/locker.html holds the one copy of the content.txt format, the
 * iteration counts and the decrypt steps, between the "BEGIN locker-core" and
 * "END locker-core" markers. encrypt-for-embed.js and verify-content.js run
 * that same code, so the tools and the published page cannot drift apart.
 *
 * Usage:
 *   const core = require('./locker-core.js').load();
 */

const fs = require('fs');
const path = require('path');
const { webcrypto } = require('crypto');

const PAGE_FILE = path.join(__dirname, 'docs', 'locker.html');

const EXPORTS = [
  'NEW_FILE_ITERATIONS', 'FORMAT_VERSION',
  'parseContent', 'passphraseKeyText', 'newPassphraseProblem',
  'formatContent', 'decryptContent'
];

function load(pageFile = PAGE_FILE) {
  const html = fs.readFileSync(pageFile, 'utf8');
  const match = html.match(/\/\/ BEGIN locker-core\r?\n([\s\S]*?)\/\/ END locker-core/);
  if (!match) {
    throw new Error(`No locker-core block in ${pageFile}`);
  }
  const body = `${match[1]}\nreturn { ${EXPORTS.join(', ')} };`;
  // eslint-disable-next-line no-new-func
  return new Function('crypto', 'atob', body)(webcrypto, atob);
}

module.exports = { load, PAGE_FILE };
