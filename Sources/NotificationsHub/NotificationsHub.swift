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
        
        withLock(lock) {
            var bucket = buckets[key] ?? Bucket()
            bucket.entries[id] = .init(handler: erasedHandler, queue: queue)
            buckets[key] = bucket
        }
        
        return .init(id: id, key: key, hub: self)
    }
    
    /// Stops delivery to `subscription`.
    public func unsubscribe(_ subscription: Subscription) {
        subscription.cancel()
    }
    
    /// Delivers `message` to every subscriber currently registered on `topic`.
    public func post<Message>(_ message: Message, to topic: Topic<Message>) {
        let key = TopicKey(name: topic.name, messageType: .init(Message.self))
        
        let bucket = withLock(lock) { buckets[key] }
        guard let bucket else { return }
        
        for entry in bucket.entries.values {
            if let queue = entry.queue {
                let box = UncheckedSendableBox(work: { entry.handler(message) })
                queue.async { box.work() }
            } else {
                entry.handler(message)
            }
        }
    }
    
    func removeSubscription(id: UUID, key: TopicKey) {
        withLock(lock) {
            buckets[key]?.entries.removeValue(forKey: id)
            if buckets[key]?.entries.isEmpty == true {
                buckets.removeValue(forKey: key)
            }
        }
    }
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
