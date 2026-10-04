class_name CommunityLinks
extends RefCounted

## Purpose-named community destinations, stubbed empty until the real URLs
## exist (WEB-006): COMMUNITY is shown as Discord, SUPPORT as Patreon. An
## empty destination renders a disabled "Coming soon" control; never invent
## a URL. The website reads NEXT_PUBLIC_COMMUNITY_URL / _SUPPORT_URL.
##
## Implements: /spec/invariants.md#web-006
## See also: /docs/concepts/ux.md

const COMMUNITY := ""
const SUPPORT := ""


static func is_configured(url: String) -> bool:
	return url.begins_with("https://")
