#!/bin/zsh
set -euo pipefail

repository_root="${0:A:h:h}"
cd "$repository_root"

forbidden_source_pattern='@unchecked Sendable|URLSession|import WebKit|import Network|NWConnection|NWListener|CGEventTap|addGlobalMonitorForEvents|postEvent|Sparkle|Sentry|Firebase|Telemetry'

if rg -n "$forbidden_source_pattern" TrackerFree --glob '*.swift'; then
  print -u2 "Static safety check failed: forbidden API or unsafe suppression found."
  exit 1
fi

unexpected_general="$(
  rg -n 'NSPasteboard[.]general' TrackerFree --glob '*.swift' \
    --glob '!**/Clipboard/GeneralPasteboardClient.swift' || true
)"
if [[ -n "$unexpected_general" ]]; then
  print -u2 "$unexpected_general"
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
