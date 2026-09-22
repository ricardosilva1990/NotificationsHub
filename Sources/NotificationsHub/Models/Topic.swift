//
//  Topic.swift
//  NotificationsHub
//
//  Created by Ricardo Silva on 22/09/2026.
//

/// A strongly-typed, named channel of messages.
public struct Topic<Message>: Hashable, Equatable {
    let name: String
    
    init(_ name: String) {
        self.name = name
    }
}
