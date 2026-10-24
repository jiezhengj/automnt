import Foundation
import Testing
@testable import AutomntPlatform

struct PendingNotificationStoreTests {
    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("automnt-pending-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var file: (URL) -> URL {
        { $0.appendingPathComponent("pending-notification.plist") }
    }

    @Test func missingRecordReadsAsNil() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(PendingNotificationStore(authorizedDirectory: directory).read() == nil)
    }

    @Test func recordRoundTripsAndNewestNoticeReplacesOlderOne() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PendingNotificationStore(authorizedDirectory: directory)
        let first = PendingNotification(count: 1, soundEnabled: true,
            soundPreferenceNeedsRepair: false, createdAt: Date(timeIntervalSince1970: 1_000))
        try store.enqueue(first)
        #expect(store.read() == first)

        // Only the newest count is worth delivering: a notice states the current failure
        // count, not a queue of historical events.
        let second = PendingNotification(count: 3, soundEnabled: false,
            soundPreferenceNeedsRepair: true, createdAt: Date(timeIntervalSince1970: 2_000))
        try store.enqueue(second)
        #expect(store.read() == second)

        store.remove()
        #expect(store.read() == nil)
    }

    @Test func noticeExpiresAfterItsShortLifetime() {
        let created = Date(timeIntervalSince1970: 1_000)
        let notice = PendingNotification(count: 1, soundEnabled: true,
            soundPreferenceNeedsRepair: false, createdAt: created)
        #expect(!notice.isExpired(now: created.addingTimeInterval(PendingNotification.maximumAge)))
        #expect(notice.isExpired(now: created.addingTimeInterval(PendingNotification.maximumAge + 1)))
        // Stale notices must not be presented as current after a later launch.
        #expect(notice.isExpired(now: created.addingTimeInterval(86_400)))
    }

    @Test func corruptOrUnknownRecordIsDiscarded() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = file(directory)
        try Data([0xff, 0x00, 0xff]).write(to: url)
        #expect(PendingNotificationStore(authorizedDirectory: directory).read() == nil)
    }

    @Test func countsAreClampedToAtLeastOne() {
        #expect(PendingNotification(count: 0, soundEnabled: false,
            soundPreferenceNeedsRepair: false).count == 1)
        #expect(PendingNotification(count: -5, soundEnabled: false,
            soundPreferenceNeedsRepair: false).count == 1)
    }
}
