import Foundation
import Security

// Runs only when deliberately invoked after installing the isolated diagnostic
// right. A denied result alone is NOT proof that SecurityAgent loaded the plugin;
// verify its fixed unified-log marker as described in the experiment README.
let rightName = "dev.opencomputeruse.locked-use.preflight"
var authorization: AuthorizationRef?
let created = AuthorizationCreate(nil, nil, [], &authorization)
guard created == errAuthorizationSuccess, let authorization else {
    print("AuthorizationCreate failed: \(created)")
    exit(1)
}
defer { AuthorizationFree(authorization, [.destroyRights]) }
let status = rightName.withCString { name in
    var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
    return withUnsafeMutablePointer(to: &item) { pointer in
        var rights = AuthorizationRights(count: 1, items: pointer)
        return AuthorizationCopyRights(authorization, &rights, nil, [.extendRights, .destroyRights], nil)
    }
}
let report: [String: Any] = [
    "right": rightName,
    "status": status,
    "expectedDenied": status == errAuthorizationDenied,
    "pluginLoaded": "unverified; check the fixed plugin log marker",
    "sessionUnlockRequested": false,
    "note": "No screensaver right requested and no credentials supplied."
]
print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
// Permission success would contradict the deny-only experiment.
exit(status == errAuthorizationDenied ? 0 : 1)
