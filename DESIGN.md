# Design rationale
## Topics are typed, not just named
`Topic<Message>` pairs a string name with a payload type. `subscribe` and `post` both take the same `Topic<Message>`, so the compiler - not a runtime cast at the call site - guarantees a handler only ever receives the type it asked for. Internally, two topics that share a name but declare different `Message` types are still kept in separate buckets, so there's no way to accidentally cross-write an `Int` topic and a `String` topic that happen to be named the same thing. The one type-check in the whole file (a `guard ... as? Message` backed by `preconditionFailure`) is likely unreachable in practice because of that key - but if fails loudly with a description message instead of a generic trap if that invariant is ever broken by a future change.

## Subscriptions are RAII tokens, and the hub is the only API surface
`subscribe` returns a `Subscription` object rather than a UUID/string you have to remember. That choice is about failure modes: with an ID-based `unsubscribe(id)`, forgetting to call it leaks the closure (and anything it captures) silently, for as long as the hub lives. With a token, forgetting to *retain* it fails immediately and loudly instead - deinit runs right away and the subscription is already gone, which is far easier to notice than a slow leak.

`Subscription.cancel()` isn't public, though - only `deinit` and `NotificationsHub.unsubscribe(_:)` can call it. That keeps every operation (subscribing, posting, unsubscribing) reachable through exactly one place, the hub, rather than having two public spellings for "stop this scubscription" (`Subscription.cancel()` *and*  `hub.unsubscribe(subscription)`) that do the same thing. `Subscription` stays `Hashable` so it still works directly in a  `Set<Subscription>` if you want to manage several tokens' lifetimes together - no extra `store(in:)` wrapper needed. `Set.insert(_:)` already does that job.

## No forced singlton

`init()` is public and `.shared` is just a convenience default, the same relationship `NotificationCenter` has with `.default`. Callers can inject a scoped hub (per screen, per test) instead of reaching for a global if that fits their architecture better.

## Thread safety: a single lock, never held during delivery

All mutable state (the topic -> subscribers dictionary) lives behind one `NSLock`. Each topic's bucket stores one `Entry` per subscriber - bundling its handler and optional delivery queue together, rather than two parallel dictionaries keyed by the same ID that could drift out of sync on add/remove. `post` takes the lock only long enough to copy the current entries for that topic, then releases it *before* invoking any handler. That one property is what makes the rest of the concurrency story simple:

- A handler that subscribes, unsubscribes, or posts again - even re-entrantly, even to the same topic - can't deadlock, because the lock is never held on the call stack during a handler invocation. 
- Concurrent `subscribe`/`unsubscribe`/`post` calls from multiple threads can't corrupt the dictionary or crash from "mutated while iterating", since every read/write is a short, fully-locked critical section, and delivery always iterates a snapshot instead of the live storage.
- The trade-off is standard "at most the messages in flight" semantics: a subscriber added mid-`post` won't get that particular message, and one that unsubscribe mid-`post` still receives the message already handed to it - the same behaviour `NotificationCenter` has.

An `actor` was the other option on the table - same safety with less hand-written synchronisation. It wasn't chosen because it would make `subscribe`/`post` `async`, which breaks the "fire and forget" ergonomics pub/sub is supposed to have (posting from a synchronous UI event handler, for instance). A lock keeps the public API fully synchronous, like `NotificationCenter`'s default behaviour.

## Optional queue-hop for delivery

`subscribe(to:queue:handler:)` lets a subscriber ask to be called on a specific `DispatchQueue` (e.g. `main`) instead of whatever thread `post` happened to be called from. Default is synchronous, same thread delivery - opting into a queue is explicit, not implicit.

Dispatching to a queue requires a `@Sendable` closure, and neither a generic, unconstrained `Message` nor a caller supplied `handler` clousre is probably `Sendable`. The alternative fix - requiring `Message: Sendable` everywhere and marking every `handler` parameter `@Sendable` - was considered and rejected: it would force every subscriber, even ones that never touch `queue:`, to stop capturing a plain local `var` from their handler, which is the single most common thing a small pub/sub consumer does (every test is this package's suite does exactly that). Foundation's own callback APIs - `NotificationCenter`, `Time`, Combine's `.receive(on:)` - don't force `Sendable` on their callbacks either; thread-safety of a callback that's been dispatched somewhere specific stays the caller's responsability once they've oped into a queue. The fix here matches that: a small, explicitly `@unchecked Sendable` box (`UncheckedSendableBox`) confines the trade-off to the one line in `post` that actually crosses a queue boundary, rather than cascading a `Sendable` requirement through the whole public API.
