import Foundation

struct RouterTickInput: Equatable, Sendable {
    let sourceTrack: UUID
    let notes: [NoteEvent]
    let chordContext: Chord?
}

protocol RouterDispatcher: AnyObject {
    func dispatch(_ event: RouterEvent)
}

enum RouterEvent: Equatable, Sendable {
    case note(to: RouteDestination, event: NoteEvent)
    case chord(to: RouteDestination, chord: Chord, lane: String?)
}

final class MIDIRouter {
    private weak var dispatcher: RouterDispatcher?
    private var routes: [Route] = []
    private let lock = NSLock()

    init(dispatcher: RouterDispatcher) {
        self.dispatcher = dispatcher
    }

    func applyRoutesSnapshot(_ routes: [Route]) {
        lock.lock()
        self.routes = routes
        lock.unlock()
    }

    func tick(_ inputs: [RouterTickInput]) {
        guard let dispatcher else {
            return
        }

        let routes = routesSnapshot()
        for input in inputs {
            for route in routes where route.enabled {
                switch route.source {
                case let .track(trackID):
                    guard trackID == input.sourceTrack else {
                        continue
                    }

                    for note in input.notes where route.filter.matches(note) {
                        dispatcher.dispatch(.note(to: route.destination, event: note))
                    }

                case let .chordGenerator(trackID):
                    guard trackID == input.sourceTrack,
                          let chord = input.chordContext
                    else {
                        continue
                    }

                    let lane: String?
                    if case let .chordContext(broadcastTag) = route.destination {
                        lane = broadcastTag
                    } else {
                        lane = nil
                    }

                    dispatcher.dispatch(.chord(to: route.destination, chord: chord, lane: lane))
                }
            }
        }
    }

    private func routesSnapshot() -> [Route] {
        lock.lock()
        defer { lock.unlock() }
        return routes
    }
}
