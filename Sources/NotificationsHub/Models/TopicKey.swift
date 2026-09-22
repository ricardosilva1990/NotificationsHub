//
//  TopicKey.swift
//  NotificationsHub
//
//  Created by Ricardo Silva on 22/09/2026.
//

/// Type-erased key identifying a topic's subscriber bucket.
struct TopicKey: Hashable {
    let name: String
    let messageType: ObjectIdentifier
}
