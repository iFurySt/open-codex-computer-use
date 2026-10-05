import Foundation
import PowerCore
import PowerNative
import Darwin

let controller = LidLeaseController(power: PMSetSleepSwitch(), journal: FileRecoveryJournal())
guard geteuid() == 0 else { fputs("Helper requires launchd root service\n", stderr); exit(1) }
do { try controller.recoverOnStartup() }
catch { fputs("Initial recovery failed; new requests remain blocked\n", stderr) }
let result = ocu_power_helper_listen { request, uid, _, identity in
    let response: HelperResponse
    do {
        let parsed = try JSONDecoder().decode(HelperRequest.self, from: Data(String(cString: request!).utf8))
        response = controller.handle(parsed, uid: uid, connection: String(cString: identity!))
    } catch { response = .init(error: "Invalid helper request") }
    let data = (try? JSONEncoder().encode(response)) ?? Data("{\"error\":\"Response encoding failed\"}".utf8)
    return strdup(String(decoding: data, as: UTF8.self))
}
guard result == 0 else { fputs("Helper requires Developer ID signing\n", stderr); exit(1) }
let timer = DispatchSource.makeTimerSource(queue: .global())
timer.schedule(deadline: .now() + 1, repeating: 1)
timer.setEventHandler { controller.tick() }; timer.resume()
signal(SIGTERM, SIG_IGN); signal(SIGINT, SIG_IGN)
let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
termination.setEventHandler { try? controller.shutdown(); exit(0) }; termination.resume()
dispatchMain()
