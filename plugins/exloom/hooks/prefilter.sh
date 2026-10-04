# exloom — cheap checks on the raw hook payload, run before lib.sh is loaded.
# Each answers "could this payload concern the hook at all?" and may say yes too
# often, never too rarely: a false yes costs a full check, a false no is a bypass.

exloom_may_touch_receipts() {
  case "$1" in
    *verdicts*|*reviews*|*exloom-gate*|*clean*|*apply*) return 0 ;;
  esac
  return 1
}

exloom_may_publish() {
  case "$1" in
    *push*|*create*|*merge_pull_request*|*delete_file*) return 0 ;;
  esac
  return 1
}

exloom_may_be_reviewer() {
  case "$1" in
    *l1-reviewer*|*adversarial-reviewer*|*security-auditor*) return 0 ;;
  esac
  return 1
}
