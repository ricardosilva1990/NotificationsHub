//
//  NotificationsHub.swift
//  NotificationsHub
//
//  Created by Ricardo Silva on 22/09/2026.
//

import Foundation

/// A lightweight, thread-safe publish–subscribe hub.
public final class NotificationsHub: @unchecked Sendable {
    /// A shared, ready-to-use instance for callers who want a global
    /// default rather than injecting their own. Entirely optional to use.
    public static let shared = NotificationsHub()
    
    private let lock = NSLock()
    private var buckets = [TopicKey: Bucket]()
    
    // MARK: Subscribe
     
    /// Registers `handler` to be called with every message posted to
    /// `topic` from this point forward.
    ///
    /// - Parameters:
    ///   - topic: The channel to listen on.
    ///   - queue: If provided, `handler` is dispatched onto this queue
    ///     instead of being invoked synchronously on the posting thread.
    ///   - handler: Called once per message posted to `topic`.
    /// - Returns: A `Subscription` token. Keep it alive to keep
    ///   listening; unsubscribe or deallocate it to stop.
    @discardableResult
    public func subscribe<Message>(
        to topic: Topic<Message>,
        queue: DispatchQueue? = nil,
        handler: @escaping (Message) -> Void
    ) -> Subscription {
        let erasedHandler: (Any) -> Void = { anyMessage in
            guard let message = anyMessage as? Message else {
                preconditionFailure(
                    "NotificationHub: type mismatch delivering to topic \"\(topic.name)\" — this indicates a bug in NotificationHub itself, not in caller code."
                )
            }
            handler(message)
        }
        
        let key = TopicKey(name: topic.name, messageType: .init(Message.self))
        let id = UUID()
        
        withLock {
            var bucket = buckets[key] ?? Bucket()
            bucket.entries[id] = .init(handler: erasedHandler, queue: queue)
            buckets[key] = bucket
        }
        
        return .init(id: id, key: key, hub: self)
    }
    
    public func unsubscribe(_ subscription: Subscription) {
        subscription.cancel()
    }
    
    func removeSubscription(id: UUID, key: TopicKey) {}
}

// MARK: - Private supporting structures.

private extension NotificationsHub {
    struct Entry {
        let handler: (Any) -> Void
        let queue: DispatchQueue?
    }
    
    struct Bucket {
        var entries: [UUID: Entry] = [:]
    }
}

private extension NotificationsHub {
    /// Runs `body` while holding `lock`, releasing it afterward via
    /// `defer` — including on early return.
    func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        
        return body()
    }
}
