import Foundation
import GameController
import Network

// naga-pads — local controller bridge for the 3D game demos.
//
// Chrome on this Mac will not expose the DualShock pads through the Gamepad API,
// but macOS itself delivers them through the GameController framework. This
// process reads the pads with that framework and pushes their state to any open
// page over Server-Sent Events on http://127.0.0.1:8777/pads, so the games can
// read real pads regardless of what the browser reports.

let port: NWEndpoint.Port = 8777
let queue = DispatchQueue(label: "naga.pads")

struct PadEntry {
    let controller: GCController
    var name: String
}

var pads: [PadEntry] = []
var sseClients: [NWConnection] = []

func jsonString(_ s: String) -> String {
    let escaped = s
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
}

func shortName(_ c: GCController) -> String {
    let vendor = c.vendorName ?? "Controller"
    if vendor.contains("DUALSHOCK 4") { return "DualShock 4" }
    if vendor.contains("Wireless Controller") { return "DualShock 4" }
    return vendor
}

func addPad(_ c: GCController, reason: String) {
    if pads.contains(where: { $0.controller === c }) { return }
    pads.append(PadEntry(controller: c, name: shortName(c)))
    let slot = pads.count - 1
    c.playerIndex = GCControllerPlayerIndex(rawValue: slot) ?? .indexUnset
    print("P\(pads.count): \(shortName(c)) [\(reason)]  -> \(pads.count) pad\(pads.count == 1 ? "" : "s")")
    fflush(stdout)
}

func removePad(_ c: GCController) {
    guard let i = pads.firstIndex(where: { $0.controller === c }) else { return }
    let gone = pads.remove(at: i).name
    for (slot, entry) in pads.enumerated() {
        entry.controller.playerIndex = GCControllerPlayerIndex(rawValue: slot) ?? .indexUnset
    }
    print("lost \(gone) -> \(pads.count) pad\(pads.count == 1 ? "" : "s")")
    fflush(stdout)
}

func snapshotJSON() -> String {
    var items: [String] = []
    for (i, entry) in pads.enumerated() {
        var axes: [Float] = [0, 0, 0, 0]
        var buttons = Array(repeating: false, count: 16)
        if let g = entry.controller.extendedGamepad {
            // GameController counts Y upwards; a browser gamepad counts it
            // downwards (axis 1 = +1 when pushed down). Flip both Y axes so the
            // games read these pads exactly like a browser pad.
            axes = [
                g.leftThumbstick.xAxis.value, -g.leftThumbstick.yAxis.value,
                g.rightThumbstick.xAxis.value, -g.rightThumbstick.yAxis.value,
            ]
            buttons = [
                g.buttonA.isPressed, g.buttonB.isPressed, g.buttonX.isPressed, g.buttonY.isPressed,
                g.leftShoulder.isPressed, g.rightShoulder.isPressed,
                g.leftTrigger.isPressed, g.rightTrigger.isPressed,
                g.buttonOptions?.isPressed ?? false, g.buttonMenu.isPressed,
                g.leftThumbstickButton?.isPressed ?? false, g.rightThumbstickButton?.isPressed ?? false,
                g.dpad.up.isPressed, g.dpad.down.isPressed, g.dpad.left.isPressed, g.dpad.right.isPressed,
            ]
        }
        let axisText = axes.map { String(format: "%.3f", $0) }.joined(separator: ",")
        let buttonText = buttons.map { $0 ? "1" : "0" }.joined(separator: ",")
        items.append(
            "{\"index\":\(i),\"id\":\(jsonString(entry.name)),\"mapping\":\"standard\"," +
            "\"axes\":[\(axisText)],\"buttons\":[\(buttonText)]}"
        )
    }
    return "{\"pads\":[" + items.joined(separator: ",") + "]}"
}

func sendChunk(_ connection: NWConnection, _ text: String) {
    let payload = Data("data: \(text)\n\n".utf8)
    var framed = Data("\(String(payload.count, radix: 16))\r\n".utf8)
    framed.append(payload)
    framed.append(Data("\r\n".utf8))
    connection.send(content: framed, completion: .contentProcessed { _ in })
}

// MARK: – pads

GCController.startWirelessControllerDiscovery {}

NotificationCenter.default.addObserver(
    forName: .GCControllerDidConnect, object: nil, queue: nil
) { note in
    guard let controller = note.object as? GCController else { return }
    queue.async { addPad(controller, reason: "connected") }
}

NotificationCenter.default.addObserver(
    forName: .GCControllerDidDisconnect, object: nil, queue: nil
) { note in
    guard let controller = note.object as? GCController else { return }
    queue.async { removePad(controller) }
}

// MARK: – HTTP server (SSE)

// A fresh parameter set per attempt: reusing one after a failed bind can keep the
// old socket half-alive, which then reports "in use" again and again.
func makeParameters() -> NWParameters {
    let p = NWParameters.tcp
    p.allowLocalEndpointReuse = true
    p.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: port)
    return p
}

// A previous copy can still hold the port for a moment while it exits, which shows
// up as "Address already in use". Retry the bind instead of dying on the first try.
var activeListener: NWListener?
var bindRetries = 0

func startListener() {
    guard let listener = try? NWListener(using: makeParameters()) else {
        print("cannot listen on 127.0.0.1:\(port) — is another copy of naga-pads running?")
        exit(1)
    }
    activeListener = listener
    listener.newConnectionHandler = { connection in
    connection.start(queue: queue)
    connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
        let request = String(data: data ?? Data(), encoding: .utf8) ?? ""
        let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
        if path.hasPrefix("/pads") {
            let headers = [
                "HTTP/1.1 200 OK",
                "Content-Type: text/event-stream",
                "Cache-Control: no-cache, no-transform",
                "Connection: keep-alive",
                "Access-Control-Allow-Origin: *",
                "Transfer-Encoding: chunked",
                "",
                "",
            ].joined(separator: "\r\n")
            connection.send(content: Data(headers.utf8), completion: .contentProcessed { _ in })
            sseClients.append(connection)
            print("page connected (\(sseClients.count) client\(sseClients.count == 1 ? "" : "s"))")
            if sseClients.count >= 6 {
                print("  note: browsers allow about 6 parallel connections per host — close extra game tabs if a page shows no pads")
            }
            fflush(stdout)
            sendChunk(connection, snapshotJSON())
        } else {
            let body = "{\"pads\":\(pads.count)}"
            let response = [
                "HTTP/1.1 200 OK",
                "Content-Type: application/json",
                "Access-Control-Allow-Origin: *",
                "Content-Length: \(body.utf8.count)",
                "Connection: close",
                "",
                body,
            ].joined(separator: "\r\n")
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}

    listener.stateUpdateHandler = { state in
        switch state {
        case .ready:
            bindRetries = 0
            print("listening on http://127.0.0.1:\(port)/pads — quit with Ctrl-C")
            fflush(stdout)
        case .failed(let error):
            if case NWError.posix(let code) = error, code == .EADDRINUSE, bindRetries < 120 {
                bindRetries += 1
                activeListener?.cancel()
                if bindRetries == 1 {
                    print("port \(port) is still held by a previous copy — waiting for it to close…")
                }
                fflush(stdout)
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { startListener() }
                return
            }
            print("listener failed: \(error)")
            fflush(stdout)
            exit(1)
        default:
            break
        }
    }
    listener.start(queue: queue)
}

startListener()

// Poll the pads at 60 Hz and push to every connected page.
let timer = DispatchSource.makeTimerSource(queue: queue)
timer.schedule(deadline: .now(), repeating: .milliseconds(16))
timer.setEventHandler {
    for controller in GCController.controllers() {
        addPad(controller, reason: "discovered")
    }
    if sseClients.isEmpty { return }
    let json = snapshotJSON()
    for client in sseClients { sendChunk(client, json) }
}
timer.resume()

// Periodically drop clients whose page was closed.
let cleanup = DispatchSource.makeTimerSource(queue: queue)
cleanup.schedule(deadline: .now() + 5, repeating: 5)
cleanup.setEventHandler {
    sseClients.removeAll { client in
        if case .failed = client.state { return true }
        if case .cancelled = client.state { return true }
        return false
    }
}
cleanup.resume()

dispatchMain()
