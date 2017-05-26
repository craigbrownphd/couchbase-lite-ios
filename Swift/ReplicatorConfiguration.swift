//
//  ReplicatorConfiguration.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/25/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/** Replicator type. */
public enum ReplicatorType: UInt8 {
    case pushAndPull = 0        ///< Bidirectional; both push and pull
    case push                   ///< Pushing changes to the target
    case pull                   ///< Pulling changes from the target
}


/** Replicator target which can be either a URL to the remote database or a local database. */
public enum ReplicatorTarget {
    case url (URL)              ///< A URL to the remote database
    case database (Database)    ///< A local database
}


/** Replicator configuration. */
public struct ReplicatorConfiguration {
    /** The local database to replicate with the target database. 
        The database property is required. */
    public var database: Database?
    
    /** The replication target. The ReplicatorTarget property is required. */
    public var target: ReplicatorTarget?
    
    public var replicatorType: ReplicatorType
    
    public var continuous: Bool
    
    public var conflictResolver: ConflictResolver?
    
    public var options: Dictionary<String, Any>?
    
    public init() {
        replicationType = .pushAndPull
        continuous = false
    }
}
