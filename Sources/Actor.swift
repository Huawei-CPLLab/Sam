//
// Copyright (c) 2016 Huawei PT-Lab Open Source project authors.
// Licensed under Apache License v2.0
//
// Actor.swift
// The Actor protocols
//

public protocol UnspecifiedActor {
    /// The context of this actor
    unowned var context:ActorCell { get }

    mutating func supervisorStrategy(error: Error) -> Void
    
    func preStart()
    func willStop()
    func postStop()
    func childTerminated(_ child: ActorRef)
}

extension UnspecifiedActor {
    public var this: ActorRef { return context.this }
}

public protocol Actor: UnspecifiedActor {
    /// The context of this actor
    unowned var context:KnownActorCell<Self> { get }

    associatedtype ActorMessage: Message
    mutating func receive(_ msg: ActorMessage)
}

extension Actor {
    public var this: KnownActorRef<Self> { return context.this }
}
