//
// Copyright (c) 2016 Huawei PT-Lab Open Source project authors.
// Licensed under Apache License v2.0
//
// ActorCell.swift
// Defines the actor cell, the container for the actor which handles
// all of the components required to make an actor work.
//

import Foundation
import Dispatch

public class ActorCell {
    /// Points to the current actor instance. ActorCell is the owner
    /// It must have a value during the whole life cycle, but when an
    /// ActorCell is created, the actor instance has not been assigned,
    /// so use an implicitly unwrapped optional (!).
    var actor: UnspecifiedActor!
    
    /// A quick path to access the current ActorSystem
    public unowned let system : ActorSystem
    
    /// The current actor's parent. Actor system's parent is nil
    weak var parent : ActorRef? /// Only actor system's cell's parent is nil
    
    /// The current actor's children. Key: shortName; Value: child ActorRef
    /// Multiple threads may access it, use the lock to protect it.
    var children = [String:ActorRef]() //Hashtable<String , ActorRef>()
    
    /// The mailbox and the exectuor
    let underlyingQueue: DispatchQueue
    
    /// Flag to indicate the actor has started the termination process
    private var dying = false
    
    /// askResult is used to handle AskMessage. The asked Actor should store a
    /// result here, and the systemReceive will wrap it as an AnswerMessage
    /// If the result is not set (nil), a nil response still be sent back
    private var askResult:Any? = nil
    
    /// A lock for this actorCell. Used to protect Children update
    let lock = NSLock() //A lock to protect children update
    func sync<T>(_ closure: () -> T) -> T {
        self.lock.lock()
        defer { self.lock.unlock() }
        return closure()
    }
    
    /// To the ActorRef of this actor. Unowned due to not want to cause cycle
    public unowned var this: ActorRef
    
    /// Called by context.actorOf to create a cell with an actor
    public init(system: ActorSystem, parent: ActorRef?, actorRef: ActorRef) {
        self.this = actorRef
        self.parent = parent
        self.system = system
        self.underlyingQueue = system.assignQueue()
    }
    
    
    /// Look for an actor from the current context
    /// - parameter pathSections: sections of strings to represent the path
    public func actorFor(_ pathSections:ArraySlice<String>) -> ActorRef? {
        if pathSections.count == 0 { return nil }
        
        let curPath = pathSections.first!
        var curRef:ActorRef? = nil
        if curPath == "." {
            curRef = this
        } else if curPath == ".." {
            curRef = parent
        } else {
            curRef = sync { children[curPath] }
        }
        
        if curRef != nil && pathSections.count > 1 {
            return curRef!.actorFor(pathSections.dropFirst())
        } else {
            return curRef
        }
    }
    
    /// Look for an actor with the input path string
    /// The path string could be absolute path, starting with "/", or relative
    /// path. "." and ".." can be used in the path
    /// - parameter path: The path to the actor
    public func actorFor(_ path:String) -> ActorRef? {
        var pathSecs = ArraySlice<String>(path.components(separatedBy: "/"))
        //at least one "" in the pathSecs
        if pathSecs.last! == "" { pathSecs = pathSecs.dropLast() }
        
        if pathSecs.count == 0 { return nil } // Empty "" input case
        
        if pathSecs.first! == "" { // Absolute path "/something" case
            // Search from the system root
            return system.actorFor(pathSecs.dropFirst())
        } else { // "aPath/bPath"
            // search relative path
            return self.actorFor(pathSecs)
        }
    }
    
    /// Create a new child actor from an actor constructor with a name in the
    /// context
    /// Parameter name: the name of the actor. If not assigned, an UUID will
    ///   be used.
    /// Parameter actorConstructor: how to create the actor, the type must be
    ///  `(ActorCell)->Actor`. It could be an actor's constructor or a closure.
    public func actorOf<ChildType: Actor>(name: String = NSUUID().uuidString,
                        _ actorConstructor: @escaping (KnownActorCell<ChildType>)->ChildType
        ) -> KnownActorRef<ChildType> {
        var name = name
        if name == "" || name.contains("/") {
            name = NSUUID().uuidString
            print("[WARNING] Wrong actor name. Use generated UUID:\(name)")
        }
        
        // The steps to create an actor: 1. ActorRef; 2. ActorCell; 3. Actor
        
        // 1.The actorRef requires a complete path
        let completePath = this.path.asString + "/" + name
        let childRef = KnownActorRef<ChildType>(path: ActorPath(path:completePath))
        sync {
            children[name] = childRef // Add it to current actorCell's children
        }
        
        // 2. Create the child actor's actor cell
        let childContext = KnownActorCell(system:self.system,
                                          parent:self.this,
                                          actorConstructor: actorConstructor,
                                          actorRef:childRef)
        childRef.actorCell = childContext
        
        // 3. ChildActor
        var childActor = actorConstructor(childContext)
        childContext.actor = childActor
        childActor.preStart() // Now the actor is ready to use
        
        return childRef
    }
    
    /// The basic method to send a message to an actor
    final public func tell(_ msg : SystemMessage) -> Void {
        underlyingQueue.async {
            self.systemReceive(msg)
        }
    }
    
    /// Used to stop this actor (the cell and the instance) by sending the actor
    /// a PoisonPill
    public func stop() {
        this ! .poisonPill
    }
    
    /// systemReceive is the entry point to handles all kinds of messages.
    /// If the message is system related, the message will be processed here.
    /// If the message is user actor related, it will call the actor instance
    /// to process it either by actor instrance's receive() or by the state
    /// machine of the actor instance
    ///
    final private func systemReceive(_ message : SystemMessage) -> Void {
        switch message {
        case .errorMessage(let error):
            /// Even actor is dying, still need to handle error message.
            actor.supervisorStrategy(error: error)
        case .poisonPill:
            guard (self.dying == false) else {
                print("[WARNING]:\(self) receives double poison pills.")
                return
            }
            self.dying = true
            actor.willStop() /// At this point,  actor is still valid
            sync {
                if self.children.count == 0 {
                    if self.parent != nil {
                        // sender must not be null because the parent needs this
                        // to remove current actor from children dictionary
                        self.parent! ! .terminated(sender: this)
                    }
                    actor.postStop()
                } else {
                    self.children.forEach { (_,actorRef) in
                        actorRef ! .poisonPill
                    }
                }
            }
        case .terminated(let sender): // Child notifies parent that it stopped
            actor.childTerminated(sender)
            
            // Remove child actor from the children dictionary.
            // If current actor is also waiting to die, check the size of
            // children and die right away if all children are already dead.
            let childName = sender.shortName
            self.sync {
                //Remove two links
                //Need double check thek path's value is the same as the sender
                //It's possible the key is bound to another path
                self.children.removeValue(forKey: childName)
                //This is because the actorRef may be still hold by someone else
                //Then that guy cannot send message to the actor anymore
                
                //print("[Debug] clean: \(t.sender!) 's actorcell at \(this)")
                sender.actorCell = nil
                
                if dying {
                    if self.children.count == 0 {
                        if let parent = self.parent { // Not actorSystem
                            parent ! .terminated(sender: self.this)
                        } else {
                            // This is the root of supervision tree
                            print("[INFO] \(self.system) terminated")
                            self.system.semaphore.signal()
                        }
                        actor.postStop()
                    }
                }
            }
            //        case .askMessage(let sender, let msg, let action):
            //            // Must wrap the original message and call and wrap the result
            //            askResult = nil
            //            systemReceive(msg)
            //            //construct the reply
            //            sender ! .answerMessage(answer: self.askResult!,
            //                                    answerAction: action)
            //        case let answerMsg as Actor.AnswerMessage:
            //            // just perform the action
            //            answerMsg.answerAction(answerMsg.answer)
            //        case let actorSelectMsg as Actor.ActorSelect:
        //            receiveActorSelect(msg:actorSelectMsg)
        default:
            print("[WARNING] Unsupported system message \(message)")
        }
    }
}

extension ActorCell: CustomStringConvertible {
    public var description: String {
        return "ActorCell[\(this.path.asString)]"
    }
}

public class KnownActorCell<ActorType: Actor>: ActorCell {
    private var knownActor: ActorType!
    override var actor: UnspecifiedActor! {
        get { return self.knownActor }
        set {
            if newValue is ActorType {
                self.knownActor = newValue as! ActorType
            } else {
                print("invalid actor")
            }
        }
    }
    
    /// Used to restart the actor instance
    var actorConstructor: (KnownActorCell<ActorType>)->ActorType
    
    /// To the ActorRef of this actor. Unowned due to not want to cause cycle
    public unowned var ref: KnownActorRef<ActorType>
    
    public func tell(_ msg: ActorType.ActorMessage) {
        underlyingQueue.async {
            self.knownActor.receive(msg)
        }
    }
    
    /// Called by context.actorOf to create a cell with an actor
    public init(system: ActorSystem, parent: ActorRef?, actorConstructor: @escaping (KnownActorCell<ActorType>)->ActorType, actorRef: KnownActorRef<ActorType>) {
        self.actorConstructor = actorConstructor
        self.ref = actorRef
        super.init(system: system, parent: parent, actorRef: actorRef)
    }
}
