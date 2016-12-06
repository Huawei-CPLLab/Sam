//
//  Dispatcher.swift
//  Sam
//
//  Created by Brice Dobry on 12/6/16.
//
//

import Foundation
import Dispatch

/// Wrapper function for both Linux and Mac
func randomInt()->Int {
    #if os(Linux)
        return random()
    #else
        return Int(arc4random())
    #endif
}

/// A Dispatcher has the capability to return a dispatch queue as mailbox
public protocol Dispatcher {
    func assignQueue() -> DispatchQueue
    func assignQueue(name: String) -> DispatchQueue
}

/// Assign a new dispatch_queue every time
public class DefaultDispatcher: Dispatcher {
    public func assignQueue() -> DispatchQueue {
        return DispatchQueue(label: "")
    }
    
    public func assignQueue(name: String) -> DispatchQueue {
        return DispatchQueue(label: name)
    }
}


/// A special dispathcer that share some queues among actors
public class ShareDispatcher: Dispatcher {
    
    /// Lock for protect the queues
    let lock = NSLock()
    var queues = [DispatchQueue]()
    var randomQueue: DispatchQueue? = nil
    let maxQueues: Int
    var queueCount = 0
    
    public init(queues:Int) {
        maxQueues = queues
        srandom(UInt32(NSDate().timeIntervalSince1970))
    }
    
    public func assignQueue() -> DispatchQueue {
        lock.lock()
        defer { lock.unlock() }
        if queueCount < maxQueues {
            let newQueue = DispatchQueue(label: "")
            if randomQueue == nil { randomQueue = newQueue }
            queueCount += 1
            self.queues.append(newQueue)
            return newQueue
        } else {
            let randomNumber = randomInt() % self.maxQueues
            return self.queues[randomNumber]
        }
    }
    
    public func assignQueue(name: String) -> DispatchQueue {
        return DispatchQueue(label: name)
    }
}
