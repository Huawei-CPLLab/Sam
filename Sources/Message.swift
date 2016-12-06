//
// Copyright (c) 2016 Huawei PT-Lab Open Source project authors.
// Licensed under Apache License v2.0
//
// Message.swift
// Defining the Message protocol and the system messages.
//

import Foundation

public protocol Message { }

// MARK: SystemMessage
public enum SystemMessage: Message {
    case poisonPill
    case terminated(sender: ActorRef)
    case messageWithOperationId(UUID)
    case errorMessage(Error)
    case deadLetter(Message)
    case askMessage(sender: ActorRef, Message, answerAction:(Any?)->Void)
    case answerMessage(answer: Any?, answerAction: (Any?)->Void)
}
