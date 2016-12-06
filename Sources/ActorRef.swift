//
// Copyright (c) 2016 Huawei PT-Lab Open Source project authors.
// Licensed under Apache License v2.0
//
// ActorRef.swift
// The ActorRef implementation
//

import Foundation

/// An actor system has a tree like structure, ActorPath gives you a url like
/// way to find an actor inside a given actor system.
///
/// For now ActorPath only stores a String path. In the future this class can
/// be extended to store network path, communication protocol, etc.

/// ActorPath is used to mark the location of an ActorRef.
/// The simple ActorRef points to a local ActorCell, and the ActorPath is just
//  simple path String, like "\user\ping", "\user\pong"
/// ActorPath can be extended later to store network path, communication
/// protocol, etc.
public class ActorPath : CustomStringConvertible {
    
    public let asString : String
    
    public var description: String {
        return asString
    }
    
    public init(path : String) {
        self.asString = path
    }
}

extension ActorPath: Hashable {
    public var hashValue: Int {
        return asString.hashValue
    }
}

public func ==(lhs: ActorPath, rhs: ActorPath) -> Bool {
    return lhs.asString == rhs.asString
}

public class ActorRef {
    /// ActorRef owns an ActorCell. So this is a strong optional type. And
    /// after the actorcell is stopped. The actor will be cleaned
    public var actorCell: ActorCell?
    
    /// ActorPath of this ActorRef
    public let path : ActorPath
    
    /// Actor path could be:/user/aName, /deadLetter, /system/system1
    /// The shortName is always the last section
    public var shortName: String {
        
        let shortName = path.asString.components(separatedBy: "/").last
        guard shortName != nil else {
            preconditionFailure("[ERROR] Wrong actorPath:\(description)")
        }
        return shortName!
    }
    
    /// Called by ActorCell.actorOf
    init(path : ActorPath) {
        self.path = path
    }
    
    /// Look for an actor in the current actor context
    /// The input is an array of strings. For example, if there is an actor
    /// "/user/Parent/Son". And if the actorFor() is called in "/user/Parent"
    /// actor, and input is "[Son]", the "/user/Parent/Son" will be returned.
    /// - Parameter pathSections: ArraySlice of String to express each section.
    /// - Returns: The actor ref corresponding to the path or nil if not found
    public func actorFor(_ pathSections:ArraySlice<String>) -> ActorRef? {
        return actorCell?.actorFor(pathSections)
    }
    
    /// Look for an actor in the current actor context
    /// The input is an absolute path, staring with "/", or relative path,
    /// starting with "." or ".." or a name.
    /// For example, if there is an actor "/user/Parent/Son". And if the
    /// actorFor() is called in "/user/Parent" actor with input is "Son", or
    /// "./Son", or "../Parent/Son", or "/user/Parent/Son", the
    /// "/user/Parent/Son" will be returned.
    /// - Parameter path: Relative path in String
    /// - Returns: The actor ref corresponding to the path or nil if not found
    public func actorFor(_ path:String) -> ActorRef? {
        return actorCell?.actorFor(path)
    }
    
    internal func stop(_ ref: ActorRef) {
        if let actorCell = self.actorCell {
            actorCell.stop() // the system message
        } else {
            // TODO:
            //send error msg to system. log
        }
    }
    
    public func tell (_ msg : SystemMessage) -> Void {
        if let actorCell = self.actorCell {
            /// Here we should just put the msg into actorCell's queue
            actorCell.tell(msg)
        } else {
            //            let senderString = msg.sender != nil ? "from \(msg.sender!) " : ""
            //            print("[WARNING] Fail to deliver message \(msg) \(senderString)to \(self)")
        }
    }
}

extension ActorRef: CustomStringConvertible {
    public var description: String {
        return "<\(type(of:self)): \(path)>"
    }
}

public class KnownActorRef<ActorType: Actor>: ActorRef {
    public var knownActorCell: KnownActorCell<ActorType>?
    override public var actorCell: ActorCell? {
        get { return self.knownActorCell }
        set {
            if newValue is KnownActorCell<ActorType> {
                self.knownActorCell = (newValue as! KnownActorCell<ActorType>)
            } else {
                print("invalid actor")
            }
        }
    }
    
    /// This method is used to send a message to the underlying Actor.
    /// - parameter msg : The message to send to the Actor.
    public func tell (_ msg : ActorType.ActorMessage) -> Void {
        if let actorCell = self.knownActorCell {
            ///Here we should just put the msg into actorCell's queue
            actorCell.tell(msg)
        } else {
            //            let senderString = msg.sender != nil ? "from \(msg.sender!) " : ""
            //            print("[WARNING] Fail to deliver message \(msg) \(senderString)to \(self)")
        }
    }
}

precedencegroup ActorMessageSendGroup {
    associativity: left
    higherThan: AssignmentPrecedence
    lowerThan: TernaryPrecedence
}
infix operator ! : ActorMessageSendGroup
//infix operator ! {associativity left precedence 130}

/// '!' is used to send message to an actor.
/// It is a shortcut for typing:
///  `actor ! msg` instead of `actorRef.tell(msg)`
@_transparent
public func !(actorRef : ActorRef, msg : SystemMessage) -> Void {
    actorRef.tell(msg)
}
@_transparent
public func !<ActorType: Actor>(actorRef: KnownActorRef<ActorType>, msg: ActorType.ActorMessage) -> Void {
    actorRef.tell(msg)
}
