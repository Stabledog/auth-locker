#!/usr/bin/env bash
# run-tests.sh — Regression tests for the encrypt / create-locker / verify toolchain.
#
# Every case runs in a throwaway copy of the repo, so the real docs/ and tmp/
# are never touched.  Needs bash and node.
#
# Usage:
#   bash test/run-tests.sh
#
# Exit code: 0 if every check passes, 1 otherwise.
set -ue

#shellcheck disable=2154
PS4='$( _0=$?; exec 2>/dev/null; realpath -- "${BASH_SOURCE[0]:-?}:${LINENO} ^$_0 ${FUNCNAME[0]:-?}()=>" )'
[[ -n "${DEBUGSH:-}" ]] && set -x

set -o pipefail

scriptName="${scriptName:-"$(command readlink -f -- "$0")"}"
scriptDir="$(command dirname -- "${scriptName}")"
REPO_DIR="$(command dirname -- "${scriptDir}")"

PASS_COUNT=0
FAIL_COUNT=0
SCRATCH_ROOT=""
OUT=""
RC=0

die() {
    builtin echo "ERROR($(basename "${scriptName}")): $*" >&2
    builtin exit 1
}

{  # outer scope braces

    # Fresh copy of the repo in a scratch dir; cd into it.
    setup() {
        local dir
        dir="$(mktemp -d "${SCRATCH_ROOT}/case.XXXXXX")"
        local f
        for f in encrypt.sh create-locker.sh encrypt-for-embed.js verify.sh verify-content.js \
                locker-core.js sync-pages.sh; do
            [[ -f "${REPO_DIR}/${f}" ]] && cp "${REPO_DIR}/${f}" "${dir}/"
        done
        cp -r "${REPO_DIR}/docs" "${dir}/docs"
        mkdir -p "${dir}/tmp"
        cd "${dir}" || die "cannot cd to ${dir}"
    }

    # run <stdin-text> <command...>: sets OUT (stdout+stderr) and RC.
    run() {
        local input="$1"
        shift
        RC=0
        OUT="$(printf '%b' "${input}" | timeout 60 "$@" 2>&1)" || RC=$?
    }

    # run_no_stdin <command...>: like run, but stdin is /dev/null (immediate EOF).
    run_no_stdin() {
        RC=0
        OUT="$(timeout 60 "$@" </dev/null 2>&1)" || RC=$?
    }

    hash_of() {
        if [[ -f "$1" ]]; then
            cksum <"$1"
        else
            echo "missing"
        fi
    }

    ok() {
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "  ok    $1"
    }

    bad() {
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "  FAIL  $1"
        if [[ -n "${OUT}" ]]; then
            printf '%s\n' "${OUT}" | tail -n 8 | sed 's/^/          | /'
        fi
    }

    expect_rc_zero() {
        if [[ "${RC}" -eq 0 ]]; then ok "$1 (exit 0)"; else bad "$1 (expected exit 0, got ${RC})"; fi
    }

    expect_rc_nonzero() {
        if [[ "${RC}" -ne 0 ]]; then ok "$1 (exit ${RC})"; else bad "$1 (expected nonzero exit, got 0)"; fi
    }

    expect_out() {
        if printf '%s' "${OUT}" | grep -q -- "$2"; then ok "$1"; else bad "$1 (output lacks: $2)"; fi
    }

    expect_no_out() {
        if printf '%s' "${OUT}" | grep -q -- "$2"; then bad "$1 (output has: $2)"; else ok "$1"; fi
    }

    expect_same() {
        if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1"; fi
    }

    expect_differ() {
        if [[ "$2" != "$3" ]]; then ok "$1"; else bad "$1"; fi
    }

    expect_no_backup_in_docs() {
        local found
        found="$(find docs -name '*backup*' -o -name '*.bak*' -o -name '*.tmp-*' | head -n 1)"
        if [[ -z "${found}" ]]; then ok "$1"; else bad "$1 (found ${found})"; fi
    }

    expect_file_has() {
        if grep -q -- "$3" "$2" 2>/dev/null; then ok "$1"; else bad "$1 ($2 lacks: $3)"; fi
    }

    # A locker that already has encrypted content (the format-1 test fixture,
    # passphrase pw-format1) and the current page.
    make_existing_locker() {
        local name="$1"
        mkdir -p "docs/lockers/${name}"
        cp docs/locker.html "docs/lockers/${name}/index.html"
        cp "${REPO_DIR}/test/fixtures/format1-content.txt" "docs/lockers/${name}/content.txt"
    }

    # make_v2_content <file> <iterations> <passphrase>: encrypts tmp/main.md
    # into a format-2 content file, independently of the repo's encryptor.
    # Keep the passphrase ASCII: Windows node mangles non-ASCII arguments.
    make_v2_content() {
        node -e '
            const c = require("crypto"), fs = require("fs");
            const [file, iter, pass] = process.argv.slice(1);
            const salt = c.randomBytes(16), iv = c.randomBytes(12);
            const key = c.pbkdf2Sync(pass, salt, Number(iter), 32, "sha256");
            const ci = c.createCipheriv("aes-256-gcm", key, iv);
            const ct = Buffer.concat([ci.update(fs.readFileSync("tmp/main.md")), ci.final(), ci.getAuthTag()]);
            fs.writeFileSync(file, "V=2\nITER=" + iter + "\nSALT_B64=" + salt.toString("base64") +
                "\nIV_B64=" + iv.toString("base64") + "\nCT_B64=" + ct.toString("base64") + "\n");
        ' "$@"
    }

    # core_eval <js>: runs js with `core` bound to the page's locker-core;
    # sets OUT and RC like run.
    core_eval() {
        RC=0
        OUT="$(node -e "const core = require('./locker-core.js').load(); $1" 2>&1)" || RC=$?
    }

    # ---- H2: encryption must never silently do nothing ----

    test_h2_encryptor_eof_at_passphrase() {
        echo "H2: encryptor gets no passphrase (stdin ends)"
        setup
        local before
        before="$(hash_of docs/content.txt)"
        OUT=""
        run_no_stdin node encrypt-for-embed.js "${REPO_DIR}/test/lorem-1.txt"
        expect_rc_nonzero "encryptor fails"
        expect_same "docs/content.txt untouched" "${before}" "$(hash_of docs/content.txt)"
    }

    test_h2_encrypt_sh_eof() {
        echo "H2: encrypt.sh, user says y then input ends at passphrase"
        setup
        cp "${REPO_DIR}/test/lorem-1.txt" tmp/main.md
        local before
        before="$(hash_of docs/content.txt)"
        run 'y' bash encrypt.sh
        expect_rc_nonzero "encrypt.sh fails"
        expect_no_out "no success banner" "Encryption complete"
        expect_same "docs/content.txt untouched" "${before}" "$(hash_of docs/content.txt)"
        expect_no_backup_in_docs "no temp files left in docs/"
    }

    test_h2_encrypt_sh_mismatch() {
        echo "H2: encrypt.sh, passphrases do not match"
        setup
        cp "${REPO_DIR}/test/lorem-1.txt" tmp/main.md
        local before
        before="$(hash_of docs/content.txt)"
        run 'yone\ntwo\n' bash encrypt.sh
        expect_rc_nonzero "encrypt.sh fails"
        expect_no_out "no success banner" "Encryption complete"
        expect_same "docs/content.txt untouched" "${before}" "$(hash_of docs/content.txt)"
    }

    test_h2_encrypt_sh_happy() {
        echo "H2: encrypt.sh normal run writes new content and points at verify"
        setup
        cp "${REPO_DIR}/test/lorem-1.txt" tmp/main.md
        local before
        before="$(hash_of docs/content.txt)"
        run 'ypw-alpha\npw-alpha\n' bash encrypt.sh
        expect_rc_zero "encrypt.sh succeeds"
        expect_out "success banner" "Encryption complete"
        expect_differ "docs/content.txt rewritten" "${before}" "$(hash_of docs/content.txt)"
        expect_out "next step is verify.sh" "bash verify.sh"
        expect_no_backup_in_docs "no temp files left in docs/"
    }

    test_h2_named_locker_happy() {
        echo "H2: encrypt.sh into a named locker"
        setup
        printf 'deborah test secrets\n' >tmp/deborah.md
        local before
        before="$(hash_of docs/lockers/deborah/content.txt)"
        run 'ypw-deb\npw-deb\n' bash encrypt.sh deborah
        expect_rc_zero "encrypt.sh deborah succeeds"
        expect_differ "deborah content.txt rewritten" "${before}" "$(hash_of docs/lockers/deborah/content.txt)"
        expect_out "next step is verify.sh deborah" "bash verify.sh deborah"
    }

    test_h2_pipe_mode() {
        echo "H2: documented 'echo ... | node encrypt-for-embed.js' mode"
        setup
        local before
        before="$(hash_of docs/content.txt)"
        run 'secret text\n' node encrypt-for-embed.js
        expect_rc_nonzero "pipe mode fails loudly instead of doing nothing"
        expect_same "docs/content.txt untouched" "${before}" "$(hash_of docs/content.txt)"
        if grep -q '| node encrypt-for-embed.js' "${REPO_DIR}/README.md" "${REPO_DIR}/encrypt-for-embed.js"; then
            bad "pipe mode no longer documented"
        else
            ok "pipe mode no longer documented"
        fi
    }

    # ---- H3: create-locker.sh must not wipe an existing locker ----

    test_h3_refuses_real_plaintext() {
        echo "H3: create-locker.sh on a locker with real plaintext in tmp/"
        setup
        make_existing_locker existing
        printf 'REAL SECRETS
' >tmp/existing.md
        local before_tmp before_ct
        before_tmp="$(hash_of tmp/existing.md)"
        before_ct="$(hash_of docs/lockers/existing/content.txt)"
        run 'ypw
pw
' bash create-locker.sh existing
        expect_rc_nonzero "create-locker.sh refuses"
        expect_same "tmp/existing.md untouched" "${before_tmp}" "$(hash_of tmp/existing.md)"
        expect_same "existing content.txt untouched" "${before_ct}" "$(hash_of docs/lockers/existing/content.txt)"
        expect_no_backup_in_docs "no backup written under docs/"
    }

    test_h3_refuses_existing_content() {
        echo "H3: create-locker.sh on a locker with encrypted content, no tmp file"
        setup
        make_existing_locker existing
        local before_ct
        before_ct="$(hash_of docs/lockers/existing/content.txt)"
        run 'ypw
pw
' bash create-locker.sh existing
        expect_rc_nonzero "create-locker.sh refuses"
        expect_same "existing content.txt untouched" "${before_ct}" "$(hash_of docs/lockers/existing/content.txt)"
        expect_no_backup_in_docs "no backup written under docs/"
    }

    test_h3_force_needs_terminal() {
        echo "H3: --force without an interactive terminal is refused"
        setup
        make_existing_locker existing
        printf 'REAL SECRETS
' >tmp/existing.md
        local before_tmp before_ct
        before_tmp="$(hash_of tmp/existing.md)"
        before_ct="$(hash_of docs/lockers/existing/content.txt)"
        run 'existing
ypw
pw
' bash create-locker.sh --force existing
        expect_rc_nonzero "create-locker.sh --force refuses without a terminal"
        expect_same "tmp/existing.md untouched" "${before_tmp}" "$(hash_of tmp/existing.md)"
        expect_same "existing content.txt untouched" "${before_ct}" "$(hash_of docs/lockers/existing/content.txt)"
        expect_no_backup_in_docs "no backup written under docs/"
    }

    test_h3_new_locker() {
        echo "H3: create-locker.sh still creates a brand-new locker"
        setup
        run 'pw-new\npw-new\n' bash create-locker.sh fresh
        expect_rc_zero "create-locker.sh fresh succeeds"
        if [[ -f docs/lockers/fresh/content.txt && -f docs/lockers/fresh/index.html && -f tmp/fresh.md ]]; then
            ok "content.txt, index.html and tmp/fresh.md exist"
        else
            bad "content.txt, index.html and tmp/fresh.md exist"
        fi
        if [[ -f verify.sh ]]; then
            run 'pw-new\n' bash verify.sh fresh
            expect_rc_zero "new locker verifies"
            expect_out "new locker opens" "OPENS: yes"
        else
            bad "verify.sh exists"
        fi
    }

    test_h3_rerun_on_untouched_template() {
        echo "H3: re-running on a locker that only has the untouched template is allowed"
        setup
        run 'pw-new\npw-new\n' bash create-locker.sh fresh
        rm -f docs/lockers/fresh/content.txt
        run 'ypw-2\npw-2\n' bash create-locker.sh fresh
        expect_rc_zero "create-locker.sh fresh (again) succeeds"
        expect_no_backup_in_docs "no backup written under docs/"
    }

    # ---- Decrypt-and-verify ----

    # Encrypt test/lorem-1.txt into docs/content.txt with passphrase pw-alpha.
    encrypt_main() {
        cp "${REPO_DIR}/test/lorem-1.txt" tmp/main.md
        run 'ypw-alpha\npw-alpha\n' bash encrypt.sh
    }

    test_verify_good() {
        echo "verify: right passphrase, plaintext matches"
        setup
        encrypt_main
        run 'pw-alpha\n' bash verify.sh
        expect_rc_zero "verify succeeds"
        expect_out "reports it opens" "OPENS: yes"
        expect_out "reports it matches" "MATCHES: yes"
        expect_no_out "does not print the plaintext" "Lorem ipsum"
    }

    test_verify_wrong_passphrase() {
        echo "verify: wrong passphrase"
        setup
        encrypt_main
        run 'not-it\n' bash verify.sh
        expect_rc_nonzero "verify fails"
        expect_out "reports it does not open" "OPENS: NO"
    }

    test_verify_mismatch() {
        echo "verify: plaintext changed after encrypting"
        setup
        encrypt_main
        printf 'extra line\n' >>tmp/main.md
        run 'pw-alpha\n' bash verify.sh
        expect_rc_nonzero "verify fails"
        expect_out "reports it opens" "OPENS: yes"
        expect_out "reports mismatch" "MATCHES: NO"
    }

    test_verify_no_plaintext() {
        echo "verify: source plaintext already deleted"
        setup
        encrypt_main
        rm tmp/main.md
        run 'pw-alpha\n' bash verify.sh
        expect_rc_zero "verify succeeds"
        expect_out "reports it opens" "OPENS: yes"
        expect_out "says match was not checked" "MATCHES: not checked"
    }

    test_verify_eof() {
        echo "verify: no passphrase given (stdin ends)"
        setup
        encrypt_main
        OUT=""
        run_no_stdin bash verify.sh
        expect_rc_nonzero "verify fails"
        expect_no_out "does not claim it opens" "OPENS: yes"
    }

    test_verify_existing_format1_locker() {
        echo "verify: a locker encrypted before this format change still opens"
        setup
        make_existing_locker existing
        cp "${REPO_DIR}/test/lorem-1.txt" tmp/existing.md
        run 'pw-format1\n' bash verify.sh existing
        expect_rc_zero "verify succeeds"
        expect_out "reports it opens" "OPENS: yes"
        expect_out "reports it matches" "MATCHES: yes"
    }

    # ---- M5: one source for the iteration count ----

    test_m5_count_recorded_in_file() {
        echo "M5: the encryptor records the format and iteration count in content.txt"
        setup
        encrypt_main
        expect_rc_zero "encrypt.sh succeeds"
        expect_file_has "content.txt has a V=2 line" docs/content.txt '^V=2$'
        expect_file_has "content.txt has an ITER= line" docs/content.txt '^ITER=[0-9][0-9]*$'
    }

    test_m5_verify_uses_file_count() {
        echo "M5: verify.sh uses the count recorded in the file, not its own copy"
        setup
        cp "${REPO_DIR}/test/lorem-1.txt" tmp/main.md
        make_v2_content docs/content.txt 150000 pw-iter
        run 'pw-iter\n' bash verify.sh
        expect_rc_zero "verify succeeds"
        expect_out "reports it opens" "OPENS: yes"
        expect_out "names the count it used" "150000 iterations"
    }

    test_m5_no_stray_copies() {
        echo "M5: no script outside the decryptor page hardcodes an iteration count"
        local hits
        hits="$(grep -l -E '[0-9]{5,}' "${REPO_DIR}"/*.js "${REPO_DIR}"/*.sh 2>/dev/null || true)"
        OUT="${hits}"
        if [[ -z "${hits}" ]]; then ok "no iteration literals in *.js / *.sh"; else bad "no iteration literals in *.js / *.sh"; fi
    }

    test_m5_published_files_parse() {
        echo "M5: every published content.txt parses with the page's own code"
        setup
        core_eval '
            const fs = require("fs"), path = require("path");
            const files = ["docs/content.txt"].concat(fs.readdirSync("docs/lockers")
                .map((d) => path.join("docs/lockers", d, "content.txt")).filter(fs.existsSync));
            for (const f of files) {
                const c = core.parseContent(fs.readFileSync(f, "utf8"));
                console.log(f + ": format " + c.version + ", " + c.iterations + " iterations");
            }'
        expect_rc_zero "all published files parse"
        expect_out "the main locker parses" "docs/content.txt: format"
    }

    # ---- L1: the same passphrase typed differently still opens ----

    test_l1_nfd_typed_passphrase() {
        echo "L1: passphrase typed precomposed (NFC) at encrypt, decomposed (NFD) at verify"
        setup
        cp "${REPO_DIR}/test/lorem-1.txt" tmp/main.md
        run 'ycaf\xc3\xa9-pw\ncaf\xc3\xa9-pw\n' bash encrypt.sh
        expect_rc_zero "encrypt.sh succeeds"
        run 'cafe\xcc\x81-pw\n' bash verify.sh
        expect_rc_zero "verify succeeds"
        expect_out "reports it opens" "OPENS: yes"
    }

    test_l1_trailing_space_typed() {
        echo "L1: a stray space added by the keyboard does not lock you out"
        setup
        encrypt_main
        run 'pw-alpha \n' bash verify.sh
        expect_rc_zero "verify succeeds"
        expect_out "reports it opens" "OPENS: yes"
    }

    test_l1_encryptor_rejects_edge_spaces() {
        echo "L1: the encryptor refuses a passphrase that starts or ends with a space"
        setup
        cp "${REPO_DIR}/test/lorem-1.txt" tmp/main.md
        local before
        before="$(hash_of docs/content.txt)"
        run 'ypw-alpha \npw-alpha \n' bash encrypt.sh
        expect_rc_nonzero "encrypt.sh fails"
        expect_same "docs/content.txt untouched" "${before}" "$(hash_of docs/content.txt)"
    }

    test_l1_page_field_no_autocorrect() {
        echo "L1: the page's passphrase field turns off autocapitalize / autocorrect"
        expect_file_has "autocapitalize off" "${REPO_DIR}/docs/locker.html" 'autocapitalize="none"'
        expect_file_has "autocorrect off" "${REPO_DIR}/docs/locker.html" 'autocorrect="off"'
        expect_file_has "spellcheck off" "${REPO_DIR}/docs/locker.html" 'spellcheck="false"'
    }

    # ---- L3: base64 padding survives parsing ----

    test_l3_padding_kept() {
        echo "L3: the page's parser keeps base64 padding and rejects damaged fields"
        setup
        cp "${REPO_DIR}/test/fixtures/format1-content.txt" tmp/fixture.txt
        # shellcheck disable=SC2016  # $1 is a JS regex backreference
        core_eval '
            const fs = require("fs");
            const text = fs.readFileSync("tmp/fixture.txt", "utf8");
            const c = core.parseContent(text);
            if (c.salt.length !== 16) throw new Error("salt is " + c.salt.length + " bytes, expected 16");
            let rejected = false;
            try { core.parseContent(text.replace(/^(SALT_B64=.*?)=+$/m, "$1")); } catch { rejected = true; }
            if (!rejected) throw new Error("salt with its padding cut off was accepted");
            console.log("padding ok");'
        expect_rc_zero "parser checks pass"
        expect_out "padding kept" "padding ok"
        local hits
        hits="$(grep -l "split('=')" "${REPO_DIR}"/docs/*.html "${REPO_DIR}"/docs/lockers/*/index.html 2>/dev/null || true)"
        OUT="${hits}"
        if [[ -z "${hits}" ]]; then ok "no page splits on every ="; else bad "no page splits on every ="; fi
    }

    # ---- L2: one decryptor page ----

    test_l2_pages_identical() {
        echo "L2: every published decryptor page is the same file as docs/locker.html"
        local page drift=""
        for page in "${REPO_DIR}"/docs/index.html "${REPO_DIR}"/docs/lockers/*/index.html; do
            cmp -s "${page}" "${REPO_DIR}/docs/locker.html" || drift+="${page#"${REPO_DIR}"/} "
        done
        OUT="${drift}"
        if [[ -z "${drift}" ]]; then ok "no drifted pages"; else bad "no drifted pages"; fi
    }

    test_l2_verify_refuses_drifted_page() {
        echo "L2: verify.sh refuses when the page serving the locker has drifted"
        setup
        encrypt_main
        printf '<!-- local edit -->\n' >>docs/index.html
        run 'pw-alpha\n' bash verify.sh
        expect_rc_nonzero "verify fails"
        expect_out "points at sync-pages.sh" "sync-pages.sh"
    }

    test_l2_sync_pages() {
        echo "L2: sync-pages.sh brings every page back in line with docs/locker.html"
        setup
        make_existing_locker existing
        printf '<!-- local edit -->\n' >>docs/index.html
        printf '<!-- local edit -->\n' >>docs/lockers/existing/index.html
        run_no_stdin bash sync-pages.sh
        expect_rc_zero "sync-pages.sh succeeds"
        expect_same "root page synced" "$(hash_of docs/locker.html)" "$(hash_of docs/index.html)"
        expect_same "locker page synced" "$(hash_of docs/locker.html)" "$(hash_of docs/lockers/existing/index.html)"
        run_no_stdin bash sync-pages.sh --check
        expect_rc_zero "--check passes once synced"
    }

    # ---- Housekeeping ----

    test_housekeeping_removed() {
        echo "Housekeeping: proof-of-concept data.txt and the bot-made sally locker are gone"
        if [[ ! -e "${REPO_DIR}/docs/data.txt" ]]; then ok "docs/data.txt removed"; else bad "docs/data.txt removed"; fi
        if [[ ! -e "${REPO_DIR}/docs/lockers/sally" ]]; then ok "sally locker removed"; else bad "sally locker removed"; fi
    }

}

main() {
    command -v node >/dev/null || die "node not found in PATH"
    SCRATCH_ROOT="$(mktemp -d)"
    trap 'rm -rf "${SCRATCH_ROOT}"' EXIT

    local t
    for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
        "${t}"
        cd "${REPO_DIR}" || die "cannot cd to ${REPO_DIR}"
    done

    echo
    echo "${PASS_COUNT} passed, ${FAIL_COUNT} failed"
    [[ "${FAIL_COUNT}" -eq 0 ]]
}

if [[ -z "${sourceMe:-}" ]]; then
    main "$@"
    exit
fi
command true
