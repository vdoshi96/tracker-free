#!/bin/zsh
set -euo pipefail

repository_root="${0:A:h:h}"
cd "$repository_root"

forbidden_source_pattern='@unchecked Sendable|URLSession|import WebKit|import Network|NWConnection|NWListener|CGEventTap|addGlobalMonitorForEvents|postEvent|Sparkle|Sentry|Firebase|Telemetry'

# Searches every Swift source under TrackerFree with the base-system grep, so the
# check never depends on an optional tool. grep exits 0 on a match and 1 on none;
# any other status (missing tool, unreadable tree) aborts the whole check rather
# than being mistaken for a clean scan.
scan_result=''
scan_swift_sources() {
  local pattern="$1" exit_code=0
  scan_result="$(/usr/bin/grep -rnE --include='*.swift' -e "$pattern" TrackerFree)" \
    || exit_code=$?
  if (( exit_code > 1 )); then
    print -u2 "Static safety check failed: could not scan Swift sources (grep exit $exit_code)."
    exit 1
  fi
}

scan_swift_sources "$forbidden_source_pattern"
if [[ -n "$scan_result" ]]; then
  print -u2 -r -- "$scan_result"
  print -u2 "Static safety check failed: forbidden API or unsafe suppression found."
  exit 1
fi

scan_swift_sources 'NSPasteboard[.]general'
unexpected_general=()
for line in "${(@f)scan_result}"; do
  [[ -z "$line" || "$line" == TrackerFree/Clipboard/GeneralPasteboardClient.swift:* ]] && continue
  unexpected_general+=("$line")
done
if (( ${#unexpected_general} > 0 )); then
  print -u2 -l -r -- "${unexpected_general[@]}"
  print -u2 "Static safety check failed: General pasteboard escaped its production adapter."
  exit 1
fi

entitlements='TrackerFree/Resources/TrackerFree.entitlements'

if [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$entitlements")" != "true" ]]; then
  print -u2 "Static safety check failed: App Sandbox is not enabled."
  exit 1
fi

for network_key in \
  'com.apple.security.network.client' \
  'com.apple.security.network.server'
do
  if /usr/libexec/PlistBuddy -c "Print :$network_key" "$entitlements" >/dev/null 2>&1; then
    print -u2 "Static safety check failed: $network_key must be absent."
    exit 1
  fi
done

print "Static safety checks passed."
