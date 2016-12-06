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
public protocol Actor: UnspecifiedActor {
    associatedtype ActorMessage: Message
    mutating func receive(_ msg: ActorMessage)
}
