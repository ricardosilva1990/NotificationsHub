//
//  Subscription.swift
//  NotificationsHub
//
//  Created by Ricardo Silva on 22/09/2026.
//

import Foundation

final class Subscription {
    private let id: UUID
    private let key: TopicKey
    private weak var hub: NotificationHub?
    
    private let stateLock = NSLock()
    private var isCancelled = false
    
    private init(_ id: UUID, _ key: TopicKey, _ hub: NotificationHub) {
        self.id = id
        self.key = key
        self.hub = hub
    }
    
    deinit {
        cancel()
    }
    
    /// Stops delivery of further messages to this subscription.
    /// Idempotent, and safe to call from any thread.
    func cancel() {
        stateLock.lock()
        defer { stateLock.unlock() }
        
        guard !isCancelled else { return }
        isCancelled = true
        
        hub?.removeSubscription(id: id, key: key)
    }
}

extension Subscription: Hashable {
    public static func ==(lhs: Subscription, rhs: Subscription) -> Bool {
        lhs === rhs
    }
 
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
