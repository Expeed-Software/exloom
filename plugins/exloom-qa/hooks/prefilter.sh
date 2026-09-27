# exloom-qa — cheap check on the raw hook payload, run before lib.sh is loaded.
# May say yes too often, never too rarely: a false no is an ungated board write.

exloomqa_may_write_board() {
  case "$1" in
    *az*|*curl*) return 0 ;;
  esac
  return 1
}
