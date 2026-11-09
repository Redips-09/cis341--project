#!/usr/bin/env bash
#===============================================================================
# File    : tests/run_all_tests.sh
# Project : CIS 341 Fall 2026 - sysaudit
# Task    : #13 Comprehensive Functionality Verification Suites
# Author  : Felix Tu
# Date    : 2026-11-08
#
# Runs every test suite in this folder (test_*.sh), one after another, and
# prints which suites passed. Adding a new test_*.sh file is enough to have it
# run here.
#
# Usage (from anywhere): bash tests/run_all_tests.sh
# Exit status: 0 if every suite passed, 1 if any suite failed.
#===============================================================================

TESTS="$(cd "$(dirname "$0")" && pwd)"
n_suites=0
failed_suites=""

for suite in "$TESTS"/test_*.sh; do
    [ -f "$suite" ] || continue
    n_suites=$((n_suites + 1))
    echo "=============================== $(basename "$suite")"
    bash "$suite"
    if [ $? -ne 0 ]; then
        failed_suites="$failed_suites $(basename "$suite")"
    fi
    echo
done

echo "==============================="
if [ -z "$failed_suites" ]; then
    echo "All $n_suites test suites passed"
    exit 0
fi
echo "Failed suites:$failed_suites" >&2
exit 1
