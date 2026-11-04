#!/bin/zsh
# Exercises Scripts/VerifyStaticSafety.sh against disposable repository
# skeletons. Each case must pass or fail exactly as expected, including on a
# PATH that lacks optional search tools such as `rg`.
set -uo pipefail

script_source="${0:A:h}/VerifyStaticSafety.sh"
work_root="$(mktemp -d)"
trap 'rm -rf "$work_root"' EXIT HUP INT TERM

# A PATH with only the base system tools: no Homebrew, so no `rg`.
minimal_path='/usr/bin:/bin:/usr/sbin:/sbin'
failures=0

make_skeleton() {
  local root="$1"
  mkdir -p "$root/Scripts" "$root/TrackerFree/Clipboard" "$root/TrackerFree/Resources"
  cp "$script_source" "$root/Scripts/VerifyStaticSafety.sh"
  print 'import AppKit\nlet board = NSPasteboard.general' \
    > "$root/TrackerFree/Clipboard/GeneralPasteboardClient.swift"
  print 'struct Clean {}' > "$root/TrackerFree/Clean.swift"
  cat > "$root/TrackerFree/Resources/TrackerFree.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key>
  <true/>
</dict>
</plist>
PLIST
}

# expect_result <label> <expected: pass|fail> <setup command run inside skeleton>
expect_result() {
  local label="$1" expected="$2" setup="$3"
  local root="$work_root/${label// /-}"
  make_skeleton "$root"
  (cd "$root" && eval "$setup")
  PATH="$minimal_path" /bin/zsh "$root/Scripts/VerifyStaticSafety.sh" >/dev/null 2>&1
  local exit_code=$?
  local actual=fail
  (( exit_code == 0 )) && actual=pass
  if [[ "$actual" == "$expected" ]]; then
    print "ok   - $label ($actual)"
  else
    print "FAIL - $label: expected $expected, got $actual (exit $exit_code)"
    failures=$((failures + 1))
  fi
}

expect_result "clean skeleton passes" pass ':'
expect_result "forbidden network API fails" fail \
  "print 'import Foundation\nlet s = URLSession.shared' > TrackerFree/Leak.swift"
expect_result "unchecked Sendable fails" fail \
  "print 'final class X: @unchecked Sendable {}' > TrackerFree/Unsafe.swift"
expect_result "General pasteboard outside adapter fails" fail \
  "print 'let b = NSPasteboard.general' > TrackerFree/Escape.swift"
expect_result "forbidden token in non-Swift file is ignored" pass \
  "print 'URLSession' > TrackerFree/notes.txt"
expect_result "missing sandbox fails" fail \
  "/usr/libexec/PlistBuddy -c 'Set :com.apple.security.app-sandbox false' TrackerFree/Resources/TrackerFree.entitlements"
expect_result "network client entitlement fails" fail \
  "/usr/libexec/PlistBuddy -c 'Add :com.apple.security.network.client bool true' TrackerFree/Resources/TrackerFree.entitlements"
expect_result "unreadable source subdirectory fails closed" fail \
  "mkdir TrackerFree/Locked && print 'struct L {}' > TrackerFree/Locked/L.swift && chmod 000 TrackerFree/Locked"

# Restore permissions so the trap can clean up.
chmod -R u+rwx "$work_root" 2>/dev/null

if (( failures > 0 )); then
  print -u2 "$failures VerifyStaticSafety case(s) failed."
  exit 1
fi
print "VerifyStaticSafety tests passed."
