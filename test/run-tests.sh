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
        for f in encrypt.sh create-locker.sh encrypt-for-embed.js verify.sh verify-content.js; do
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
        printf 'REAL SALLY SECRETS\n' >tmp/sally.md
        local before_tmp before_ct
        before_tmp="$(hash_of tmp/sally.md)"
        before_ct="$(hash_of docs/lockers/sally/content.txt)"
        run 'ypw\npw\n' bash create-locker.sh sally
        expect_rc_nonzero "create-locker.sh refuses"
        expect_same "tmp/sally.md untouched" "${before_tmp}" "$(hash_of tmp/sally.md)"
        expect_same "sally content.txt untouched" "${before_ct}" "$(hash_of docs/lockers/sally/content.txt)"
        expect_no_backup_in_docs "no backup written under docs/"
    }

    test_h3_refuses_existing_content() {
        echo "H3: create-locker.sh on a locker with encrypted content, no tmp file"
        setup
        local before_ct
        before_ct="$(hash_of docs/lockers/sally/content.txt)"
        run 'ypw\npw\n' bash create-locker.sh sally
        expect_rc_nonzero "create-locker.sh refuses"
        expect_same "sally content.txt untouched" "${before_ct}" "$(hash_of docs/lockers/sally/content.txt)"
        expect_no_backup_in_docs "no backup written under docs/"
    }

    test_h3_force_needs_terminal() {
        echo "H3: --force without an interactive terminal is refused"
        setup
        printf 'REAL SALLY SECRETS\n' >tmp/sally.md
        local before_tmp before_ct
        before_tmp="$(hash_of tmp/sally.md)"
        before_ct="$(hash_of docs/lockers/sally/content.txt)"
        run 'sally\nypw\npw\n' bash create-locker.sh --force sally
        expect_rc_nonzero "create-locker.sh --force refuses without a terminal"
        expect_same "tmp/sally.md untouched" "${before_tmp}" "$(hash_of tmp/sally.md)"
        expect_same "sally content.txt untouched" "${before_ct}" "$(hash_of docs/lockers/sally/content.txt)"
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

    test_verify_existing_published_locker() {
        echo "verify: reads the published page's iteration count"
        setup
        run 'not-it\n' bash verify.sh sally
        expect_out "names the page it checked against" "docs/lockers/sally/index.html"
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
