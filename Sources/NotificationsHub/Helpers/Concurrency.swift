//
//  Concurrency.swift
//  NotificationsHub
//
//  Created by Ricardo Silva on 22/09/2026.
//

import Foundation

// MARK: - withLock

/// Runs `body` while holding `lock`, releasing it afterward via
/// `defer` — including on early return.
func withLock<T>(_ lock: NSLock, _ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    
    return body()
}

// MARK: - UncheckedSendableBox

/// A narrow, explicit escape hatch for the one place a non-Sendable
/// closure needs to cross into a `@Sendable` context,
struct UncheckedSendableBox: @unchecked Sendable {
    let work: () -> Void
}
