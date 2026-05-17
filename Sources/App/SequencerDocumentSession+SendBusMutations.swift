import Foundation

extension SequencerDocumentSession {
    @discardableResult
    func mutateSendBus(_ id: SendBusID, _ update: (inout SendBusState) -> Void) -> Bool {
        let changed = store.mutateSendBus(id: id, update)
        guard changed else { return false }
        let sendBus = store.sendBus(id: id)
        revision = store.revision
        engineController.apply(sendBus: sendBus)
        scheduleFlushToDocument()
        return true
    }

    func setSendBusInserts(_ inserts: [SendBusInsert], busID: SendBusID) {
        mutateSendBus(busID) { sendBus in
            sendBus = SendBusState(id: busID, inserts: inserts)
        }
    }

    func addSendBusInsert(_ insert: SendBusInsert, to busID: SendBusID) {
        mutateSendBus(busID) { sendBus in
            sendBus.inserts.append(insert)
        }
    }

    func updateSendBusInsert(_ insertID: UUID, in busID: SendBusID, edit: (inout SendBusInsert) -> Void) {
        mutateSendBus(busID) { sendBus in
            guard let index = sendBus.inserts.firstIndex(where: { $0.id == insertID }) else { return }
            edit(&sendBus.inserts[index])
        }
    }

    func removeSendBusInsert(_ insertID: UUID, from busID: SendBusID) {
        mutateSendBus(busID) { sendBus in
            sendBus.inserts.removeAll { $0.id == insertID }
        }
    }

    func reorderSendBusInserts(_ ids: [UUID], in busID: SendBusID) {
        mutateSendBus(busID) { sendBus in
            let byID = Dictionary(uniqueKeysWithValues: sendBus.inserts.map { ($0.id, $0) })
            let ordered = ids.compactMap { byID[$0] }
            let missing = sendBus.inserts.filter { !ids.contains($0.id) }
            sendBus.inserts = ordered + missing
        }
    }
}
