#!/usr/bin/env bash
# Dependency-free assert harness. Source this in test files.
TK_TESTS_RUN=0
TK_TESTS_FAILED=0

assert_eq() { # <actual> <expected> <msg>
  TK_TESTS_RUN=$((TK_TESTS_RUN+1))
  if [ "$1" = "$2" ]; then
    echo "  ok: $3"
  else
    TK_TESTS_FAILED=$((TK_TESTS_FAILED+1))
    echo "  FAIL: $3"
    echo "    expected: [$2]"
    echo "    actual:   [$1]"
  fi
}

assert_rc() { # <actual_rc> <expected_rc> <msg>
  assert_eq "$1" "$2" "$3"
}

tk_test_summary() {
  echo "----"
  echo "ran $TK_TESTS_RUN, failed $TK_TESTS_FAILED"
  [ "$TK_TESTS_FAILED" -eq 0 ]
}
