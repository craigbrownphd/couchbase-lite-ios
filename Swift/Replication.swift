//
//  Replication.swift
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/29/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


extension Notification.Name {
    /** This notification is posted by a Dtabase in response to document changes. */
    public static let ReplicatorChange = Notification.Name(rawValue: "ReplicatorChangeNotification")
}


/** The key to access the replicator status object. */
public let ReplicatorStatusUserInfoKey = kCBLReplicatorStatusUserInfoKey


/** The key to access the replicator error object if exists. */
public let ReplicatorErrorUserInfoKey = kCBLReplicatorErrorUserInfoKey


/** A replication between a local and a remote database.
    Before starting the replication, you just set either the `push` or `pull` property, or both.
    The replication runs asynchronously, so set a delegate or observe the status property
    to be notified of progress. */
public final class Replication {

    /** Activity level of a replication. */
    public enum ActivityLevel : UInt8 {
        case Stopped = 0
        case Idle
        case Busy
    }
    

    /** Progress of a replication. If `total` is zero, the progress is indeterminate; otherwise,
        dividing the two will produce a fraction that can be used to draw a progress bar. */
    public struct Progress {
        public let completed: UInt64
        public let total: UInt64
    }
    

    /** Combined activity level and progress of a replication. */
    public struct Status {
        public let activity: ActivityLevel
        public let progress: Progress

        init(_ status: CBLReplicatorStatus) {
            activity = ActivityLevel(rawValue: UInt8(status.activity.rawValue))!
            progress = Progress(completed: status.progress.completed, total: status.progress.total)
        }
    }
    
    
    public init(config: ReplicatorConfiguration) {
        precondition(config.database != nil && config.target != nil)
        
        let c = CBLReplicatorConfiguration()
        c.database = config.database!._impl
        
        switch config.target! {
        case .url(let url):
            c.target = CBLReplicatorTarget(url: url)
        case .database(let db):
            c.target = CBLReplicatorTarget(database: db._impl)
        }
        
        c.continuous = config.continuous
        c.replicatorType = CBLReplicatorType(rawValue: UInt32(config.replicationType.rawValue))
        c.options = config.options
        c.conflictResolver = nil // TODO
        
        _impl = CBLReplication(config: c);
        _config = config
        
        setupNotificationBridge()
    }
    
    
    /** Starts the replication. This method returns immediately; the replication runs asynchronously
     and will report its progress to the delegate.
     (After the replication starts, changes to the `push`, `pull` or `continuous` properties are
     ignored.) */
    public func start() {
        _impl.start()
    }
    
    
    /** Stops a running replication. This method returns immediately; when the replicator actually
     stops, the CBLReplication will change its status's activity level to `kCBLStopped`
     and call the delegate. */
    public func stop() {
        _impl.stop()
    }
    
    
    public var config: ReplicatorConfiguration {
        return _config
    }
    
    
    /** The replication's current status: its activity level and progress. */
    public var status: Status {
        return Status(_impl.status)
    }
    

    // MARK: Private
    

    private let _impl: CBLReplication
    
    private let _config: ReplicatorConfiguration
    
    
    private func setupNotificationBridge() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(replicationChanged(notification:)),
            name: Notification.Name.cblReplicatorChange, object: _impl)
    }
    
    
    @objc func replicationChanged(notification: Notification) {
        var userinfo = Dictionary<String, Any>()
        
        let s = notification.userInfo![kCBLReplicatorStatusUserInfoKey] as! CBLReplicatorStatus
        userinfo[ReplicatorStatusUserInfoKey] = Status(s)
        
        if let error = notification.userInfo![kCBLReplicatorErrorUserInfoKey] as? NSError {
            userinfo[ReplicatorErrorUserInfoKey] = error
        }
        
        NotificationCenter.default.post(name: .ReplicatorChange, object: self, userInfo: userinfo)
    }
    
    
    // MARK: Deinit
    
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
