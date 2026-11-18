# Mac App Remote Ovis Session Support - Implementation Summary

## Overview
This implementation adds the ability for the Mac app to connect to remote Ovis sessions running on servers, similar to how the iOS app works. Users can now add remote servers via pairing links and switch between local and remote servers.

## Files Added/Modified

### New Files
1. **`app/mac/Sources/OvisMac/ServerStore.swift`** - Persistent storage for remote servers (mirrors iOS's PCStore)

### Modified Files
1. **`app/mac/Sources/OvisMac/Model.swift`** - Added remote server connection logic
2. **`app/mac/Sources/OvisMac/OvisMacApp.swift`** - Added UI for server selection and adding remote servers
3. **`app/mac/Sources/OvisMac/WebPage.swift`** - Updated to support remote server origins

## Key Features Implemented

### 1. ServerStore (ServerStore.swift)
- Persists remote servers in UserDefaults
- Stores: server_id, user-friendly name, origin URL, offer URL, timestamps
- Parses relay offer URLs (e.g., `https://app.ovis.sh/s/<server_id>/#offer=<base64url>`)
- Provides add/remove/use operations

### 2. Model Changes (Model.swift)
- Added `ServerKind` enum: `.local` or `.remote(id: String)`
- Added `serverKind` and `remoteServer` published properties
- Added `connectToRemoteServer(_:)` - connects to a remote server by verifying it answers as Ovis
- Added `switchToLocal()` - switches back to local server
- Added `removeRemoteServer(_:)` - removes a remote server from the list
- Added `openRemoteOffer(_:)` - parses and connects from a relay offer URL

### 3. UI Changes (OvisMacApp.swift)
- Server selector in the installed view showing:
  - "This Mac" button for local server
  - List of saved remote servers with connection status
  - "+" button to add new remote server
- Add Remote Server sheet:
  - Paste pairing link from another device
  - Optional custom name
  - Validation of offer URL format
- Menu item "Add Remote Server…" (Cmd+N replaced)

### 4. WebPageController Changes (WebPage.swift)
- Added `remoteServerId` parameter to distinguish local vs remote
- Updated `isOvis()` checks:
  - Local: same-origin check (unchanged)
  - Remote: allows navigation within `https://app.ovis.sh/s/<server_id>/` scope
- Updated draft carrying logic: only for loopback (local) origins

### 5. MainView (OvisMacApp.swift)
- Creates appropriate WebPageController based on `serverKind`
- Passes `remoteServerId` for remote connections

## User Flow

1. User opens Mac app
2. Clicks "Add Remote Server…" or "+" button
3. Pastes pairing link from another device (e.g., `https://app.ovis.sh/s/abc123/#offer=...`)
4. Optionally enters a custom name
5. App parses the offer, extracts server_id, constructs origin
6. Verifies server answers at `/api/health?scope=bridge`
7. On success: saves to ServerStore, switches main window to remote server
8. User can now use Ovis on the remote server
9. Can switch back to "This Mac" or add more servers

## Technical Details

### Relay Offer Format
The pairing link contains a base64url-encoded JSON in the fragment:
```json
{
  "v": 1,
  "server_id": "<32-char-hex>",
  "server_public_key": "<base64>",
  "relay": "wss://relay.ovis.sh",
  "code": "123456",
  "name": "My Server"
}
```

### Origin Construction
For remote servers, the origin is always:
```
https://app.ovis.sh/s/<server_id>/
```

This is the hosted shell that connects to the remote PC via the relay.

### Navigation Scope
Remote servers are restricted to their scope path `/s/<server_id>/` on `app.ovis.sh`. This matches the iOS app's `ScopePath` logic.

### Draft Handling
Drafts (unsent composer/terminal input) are only carried between local server addresses (loopback), as they were before. Remote servers have their own separate localStorage.

## Consistency with iOS
- ServerStore mirrors PCStore concept
- Relay offer parsing uses same format
- Origin construction matches iOS relay offer handling
- Scope-based navigation matches iOS ScopePath

## Future Enhancements (Not Implemented)
- Direct carrier support (like iOS's OvisDirectPlugin) for local network connections
- Push notifications for remote servers
- Account-linked servers (like iOS's account feature)
- Regional relay selection UI