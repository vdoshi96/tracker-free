# Sources and Comparator Lessons

## Research authority

`VERIFIED`: This inventory records the implementation brief's reviewed research baseline of 2026-07-23. Recheck drift-prone platform behavior and comparator status before making a current release claim.

## Apple platform

- [SwiftUI MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)
- [ServiceManagement SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [SMAppService mainApp](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp)
- [NSPasteboard](https://developer.apple.com/documentation/appkit/nspasteboard)
- [NSPasteboard changeCount](https://developer.apple.com/documentation/appkit/nspasteboard/changecount)
- [NSPasteboardItem](https://developer.apple.com/documentation/appkit/nspasteboarditem)
- [NSPasteboard access behavior](https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior-swift.enum)
- [AppKit pasteboard privacy update](https://developer.apple.com/documentation/updates/appkit)
- [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox)
- [Preparing an app for distribution](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)
- [Inside Code Signing Requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)
- [Search Clipboard History](https://support.apple.com/guide/mac-help/mchl40d5b86b/mac)
- [Run a Shortcut with a keyboard shortcut](https://support.apple.com/guide/shortcuts-mac/apd163eb9f95/mac)

`VERIFIED`: These sources support the menu, login-item, pasteboard-generation, permission, sandbox, signing, Clipboard History, and user-created Shortcut boundaries.

## URL and authentication standards

- [URLComponents queryItems](https://developer.apple.com/documentation/foundation/nsurlcomponents/queryitems)
- [Swift Foundation URLComponents source](https://github.com/swiftlang/swift-foundation/blob/main/Sources/FoundationEssentials/URL/URLComponents.swift)
- [RFC 3986](https://www.rfc-editor.org/info/rfc3986/)
- [OAuth 2.0](https://www.rfc-editor.org/info/rfc6749/)
- [PKCE RFC 7636](https://datatracker.ietf.org/doc/html/rfc7636)
- [OpenID Connect Core](https://openid.net/specs/openid-connect-core-1_0.html)
- [AWS S3 SigV4 query authentication](https://docs.aws.amazon.com/AmazonS3/latest/developerguide/sigv4-query-string-auth.html)
- [CloudFront signed URLs](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-signed-urls.html)
- [Google Cloud signed URLs](https://docs.cloud.google.com/storage/docs/access-control/signed-urls)
- [Azure service SAS](https://learn.microsoft.com/en-us/rest/api/storageservices/create-service-sas)

`VERIFIED`: Reconstruction APIs can change spelling; structural parsing must precede decoding; signed/authentication tuples justify immutable whole-link protection.

## Initial rule provenance

- [Google Analytics campaign URL builder](https://support.google.com/analytics/answer/10917952)
- [Google Click ID](https://support.google.com/google-ads/answer/3095550)
- [Campaign Manager click identifiers](https://support.google.com/campaignmanager/answer/9182069)
- [GBRAID and WBRAID](https://support.google.com/google-ads/answer/16297842)
- [Microsoft Click ID](https://learn.microsoft.com/en-us/advertising/msa-help/hlp_ba_conc_microsoftclickidcheck)
- [TikTok Click ID](https://ads.tiktok.com/help/article/tiktok-click-id)
- [Mailchimp e-commerce tracking](https://mailchimp.com/developer/marketing/docs/e-commerce/)
- [YouTube player parameters](https://developers.google.com/youtube/player_parameters)
- [Apple Map Links](https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/MapLinks/MapLinks.html)
- [Google Maps URLs](https://developers.google.com/maps/documentation/urls/get-started)
- [Amazon Associates agreement](https://affiliate-program.amazon.com/help/operating/agreement/)

`INFERENCE`: `fbclid`, YouTube `si`, X/Twitter share fields, and Instagram share fields have community or behavioral evidence but lack equivalent current first-party semantic guarantees. Their documentation and rule confidence must say so.

## Comparator review

| Project | Reviewed lesson | Reuse policy |
|---|---|---|
| [TrackerZapper](https://github.com/rknightuk/TrackerZapper) | `VERIFIED`: Sandboxed menu utility, but first-item/content suppression, `.string` rewrite, broad rules, and 20 Hz polling risk loss and false positives | MIT reference only; do not fork |
| [Maccy](https://github.com/p0deje/Maccy) | `VERIFIED`: Serialized polling, typed inventories, source marker, and sensitive markers are useful; history/updater/auto-paste are out of scope | MIT concepts only |
| [Clipy](https://github.com/Clipy/Clipy) | `VERIFIED`: Serialized 500 ms monitoring is useful; persistence, Sparkle, Firebase, and paste automation are out of scope | MIT concepts only |
| [Pure Paste](https://sindresorhus.com/pure-paste) | `VERIFIED`: Publicly documents representation loss and cleaner races; proprietary implementation has no reuse license | Behavioral benchmark only |
| [Brave sanitizer](https://github.com/brave/brave-core/blob/master/components/url_sanitizer/core/browser/url_sanitizer_service.cc) | `VERIFIED`: Strict HTTP(S), host/path scope, and raw token removal inform conservative independent design | MPL-2.0 files/rules are not copied |
| [ClearURLs](https://github.com/ClearURLs/Addon) | `VERIFIED`: Broad regex/redirect/remote machinery and historical global `t` regression demonstrate false-positive risk | LGPL source/rules are not copied |
| [AdGuard tracking filters](https://github.com/AdguardTeam/AdguardFilters) | `VERIFIED`: Active allowlist evidence is useful for regression research | GPL data is not embedded or derived |
| [Clean Links](https://cleanlinks.app/en) | `VERIFIED`: Broad proprietary product with undisclosed representation handling | Product comparator only |
| [swift-url-stripper](https://github.com/arraypress/swift-url-stripper) | `VERIFIED`: MIT package reconstructs through `URLComponents` and removes unsafe generic names | Do not add |

`RECOMMENDATION`: The implementation is original and dependency-free. Comparator code and datasets are not copied. License notes guide conservative non-reuse and are not legal advice.

## Distribution references

- [Apple membership comparison](https://developer.apple.com/support/compare-memberships/)
- [Developer ID](https://developer.apple.com/support/developer-id/)
- [Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

`RECOMMENDATION`: Version 1 uses local ad-hoc signing. Personal Team is only an optional local fallback; Developer ID/notarization and Mac App Store distribution are separate later scopes requiring paid membership.
