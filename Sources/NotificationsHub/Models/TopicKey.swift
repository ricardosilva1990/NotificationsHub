//
//  TopicKey.swift
//  NotificationsHub
//
//  Created by Ricardo Silva on 22/09/2026.
//

/// Type-erased key identifying a topic's subscriber bucket.
struct TopicKey: Hashable {
    private let name: String
    private let messageType: ObjectIdentifier
    
    init(name: String, messageType: ObjectIdentifier) {
        self.name = name
        self.messageType = messageType
    }
}
