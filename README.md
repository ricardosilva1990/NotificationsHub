# NotificationHub
A lightweight, thread-safe publish–subscribe hub for Swift.

## What if offers
- **Type-safe topics.** `Topic<Message>` ties a channel name to a payload type, so subscribers get compiler-checked delivery - no `Any`, no cast at the call site.
- **Multiple subscribers per topic**, all notified from a single `post`.
- **Automatic subscription cleanup.** Subscriptions cancel themselves when their token is deallocated, or explicitly via `unsubscribe`.
- **Thread-safe by design.** Safe to subscribe, unsubcribe, and post concurrently from any thread, including reetrantly, from inside a handler, without deadlocking.
- **Optional queue-hop delivery.** Receive on a specific `DispatchQueue` (e.g. `main`) instead of whatever thread post the message.
- **No forced singleton.** Inject your own hub instances, or use `.shared` for a global default.
- **Zero dependencies.** Pure Foundation.

## Usage
```swift
let hub = NotificationsHub() // or NotificationsHub.shared
let userLoggedIn = Topic<User>("user.loggedIn")

let subscription = hub.subscribe(to: userLoggedIn) { user in 
  print("welcome, \(user.name)")
}

hub.post(User(name: "Ada", to: userLoggedIn))

hub.unsubscribe(subscription) // or just let `subscription` deallocate
```

Public surface is `subscribe`, `post`, and `unsubscribe` on `NotificationsHub`, plus `subscriberCount` (a small introspection helper, mainly for tests). `Subscription` is a `Hashable` token you can held onto or keep in a `Set`. It doesn't expose operations of its own.

## Not handled (by design, given "lightweight")
- No message replay/history for late subscribers.
- No ordering guarantees across independent subscribers.
- Retain cycles between a subscriber's `self` and its own closure are the caller's responsibility (`[weak self]`), same as with `NotificationCenter` or Combine.

## Design rationale
Why topics are typed rather than `Any` instead, why `Subscription` isn't itself the API surface, the thread-safety model are all written up in [DESIGN.md](DESIGN.md).
