//
//  NotificationsHubTests.swift
//  NotificationsHub
//
//  Created by Ricardo Silva on 22/09/2026.
//

import Foundation
import Testing

@testable import NotificationsHub

@Suite("NotificationHub")
struct NotificationsHubTests {
    private let hub = NotificationsHub()
    
    // MARK: Basic Behaviour
    
    @Test("A single subscriber receives a pushed message.")
    func singleSubscriberReceivesMessage() {
        let topic = Topic<String>("greeting")
        var received: String?
        
        // Bound to a local, not discarded with `_`: Subscription cancels
        // itself in deinit, so an unretained token would unsubscribe
        // before `post` even runs.
        let subscription = hub.subscribe(to: topic, handler: { received = $0 })
        
        let expectedMessage = "hello"
        hub.post(expectedMessage, to: topic)
        
        #expect(received == expectedMessage)
        _ = subscription // keep token alive until here d
    }
    
    @Test("Multiple subscribers on the same topic all receive a posted message")
    func multipleSubscribersAllReceivedMessage() {
        let topic = Topic<Int>("counter")
        let numberOfSubscribers = 3
        var received = [Int?](repeating: nil, count: numberOfSubscribers)
        
        // Set<Subscription> works directly since Subscription is Hashable
        // — no store(in:) wrapper needed, this is also its only coverage
        var subscriptions = Set<Subscription>()
        for index in 0..<numberOfSubscribers {
            subscriptions.insert(
                hub.subscribe(to: topic, handler: { received[index] = $0 })
            )
        }
        
        let expectedMessage = 42
        hub.post(expectedMessage, to: topic)
         
        #expect(received.allSatisfy { $0 == expectedMessage })
    }
    
    @Test("Unsubscribing stops further delivery")
    func unsubscribeStopsDelivery() {
        let topic = Topic<Int>("counter")
        var callCount = 0
        
        let subscription = hub.subscribe(to: topic, handler: { _ in callCount += 1 })
        
        hub.post(1, to: topic)
        hub.unsubscribe(subscription)
        hub.post(2, to: topic)
        
        #expect(callCount == 1)
    }
    
    @Test("Deallocating the subscription token stops delivery automatically")
    func deinitAutomaticallyUnsubscribes() {
        let topic = Topic<Int>("counter")
        var callCount = 0
        
        var subscription: Subscription? = hub.subscribe(
            to: topic,
            handler: { _ in callCount += 1 }
        )
        
        hub.post(1, to: topic)
        subscription = nil
        hub.post(2, to: topic)
        
        #expect(callCount == 1)
        #expect(hub.subscriberCount(for: topic) == 0)
        _ = subscription
    }
    
    @Test("Posting to a topic with no subscribers is a no-op.")
    func onSubscribersIsANoOp() {
        let topic = Topic<Int>("counter")
        hub.post(1, to: topic)
        #expect(hub.subscriberCount(for: topic) == 0)
    }
    
    @Test("Topics with the same name but different message types are independent.")
    func sameNameDifferentMessageTypesAreIndependentTopics() {
        let stringTopic = Topic<String>("event")
        let intTopic = Topic<Int>("event")
        
        var stringReceived: String?
        var intReceived: Int?
        
        let stringSubscription = hub.subscribe(
            to: stringTopic,
            handler: { stringReceived = $0 }
        )
        let intSubscription = hub.subscribe(
            to: intTopic,
            handler: { intReceived = $0 }
        )
        
        hub.post("hi", to: stringTopic)
        hub.post(7, to: intTopic)
        
        #expect(stringReceived == "hi")
        #expect(intReceived == 7)
        _ = (stringSubscription, intSubscription) // keep tokens alive until here
    }
    
    // MARK: Reentrancy (proves the lock is never held during a handler call)
    
    @Test("A handler can cancel its own subscription mid-delivery without dealockings")
    func handlerCanCancelItsOwnSubscriptionDuringDelivery() {
        let topic = Topic<Int>("counter")
        
        // The handler needs the token it's registered under, which only
        // exists after `subscribe` returns. A small box lets the closure
        // capture a reference now and read the token later, instead of
        // capturing a `var` that's assigned after the closure is created
        // (that shape crashed the Swift 6.3 compiler's region analysis).
        final class TokenBox { var subscription: Subscription? }
        let box = TokenBox()
        
        box.subscription = hub.subscribe(to: topic) { [hub] _ in
            if let subscription = box.subscription {
                hub.unsubscribe(subscription)
            }
        }
        
        hub.post(1, to: topic)
        hub.post(2, to: topic) // would hang or double-fire if this deadlocked
        
        #expect(hub.subscriberCount(for: topic) == 0)
    }
    
    @Test("A handler can post to another topic mid-delivery without deadlocking.")
    func handlerCanPostToAnotherTopicDuringDelivery() {
        let topicA = Topic<Int>("A")
        let topicB = Topic<Int>("B")
        var receivedB: Int?
        
        let subscriptionA = hub.subscribe(
            to: topicA,
            handler: { hub.post($0 * 2, to: topicB) }
        )
        let subscriptionB = hub.subscribe(to: topicB, handler: { receivedB = $0 })
        
        hub.post(21, to: topicA)
        
        #expect(receivedB == 42)
        _ = (subscriptionA, subscriptionB) // keep tokens alive until here
    }
    
    // MARK: Thread safety
    
    @Test(
        "Concurrent subscribe/post/unsubscribe from many threads doesn't crash or deadlock",
        .timeLimit(.minutes(1))
    )
    func concurrentSubscribeUnsubscribePostDoesNotCrashOrDeadlock() async {
        let topic = Topic<Int>("stress")
        let iterations = 500
        
        let queue = DispatchQueue(label: "stress-test", attributes: .concurrent)
        let group = DispatchGroup()
        
        for index in 0 ..< iterations {
            group.enter()
            queue.async {
                let subscription = hub.subscribe(to: topic, handler: { _ in })
                if index % 2 == 0 { hub.post(1, to: topic) }
                hub.unsubscribe(subscription)
                group.leave()
            }
        }
        
        await withCheckedContinuation { continuation in
            group.notify(queue: .main, execute: { continuation.resume() })
        }
        
        #expect(hub.subscriberCount(for: topic) == 0)
    }
    
    @Test("A subscriber with queue: .main receives delivery on the main queue", .timeLimit(.minutes(1)))
    func queuedDeliveryDispatchesOnRequestedQueue() async {
        let topic = Topic<Int>("main-thread-delivery")
        var subscription: Subscription?
        
        await withCheckedContinuation { continuation in
            subscription = hub.subscribe(
                to: topic,
                queue: .main,
                handler: { _ in
                    #expect(Thread.isMainThread)
                    continuation.resume()
                }
            )
            
            DispatchQueue.global().async {
                hub.post(1, to: topic)
            }
        }
        
        _ = subscription // keep the token alive until here
    }
}
