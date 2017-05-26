//
//  CBLReplicatorConfiguration.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/25/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLDatabase;
@protocol CBLConflictResolver;

NS_ASSUME_NONNULL_BEGIN

extern NSString* const kCBLReplicationAuthOption;   ///< Options key for authentication dictionary
extern NSString* const kCBLReplicationAuthUserName; ///< Auth key for username string
extern NSString* const kCBLReplicationAuthPassword; ///< Auth key for password string


typedef enum {
    kCBLPushAndPull = 0,
    kCBLPush,
    kCBLPull
} CBLReplicatorType;


@interface CBLReplicatorTarget : NSObject

@property (readonly, nonatomic, nullable) CBLDatabase* database;

@property (readonly, nonatomic, nullable) NSURL* url;

+ (instancetype) url: (NSURL*)url;

+ (instancetype) database: (CBLDatabase*)database;

/** The URL of the remote database to replicate with, or nil if the target database is local. */
- (instancetype) initWithURL: (NSURL*)url;

/** The target database, if it's local, else nil. */
- (instancetype) initWithDatabase: (CBLDatabase*)database;

@end


@interface CBLReplicatorConfiguration : NSObject <NSCopying>

/** The local database. */
@property (nonatomic, nullable) CBLDatabase* database;

@property (nonatomic, nullable) CBLReplicatorTarget* target;

@property (nonatomic) CBLReplicatorType replicatorType;

/** Should the replication stay active indefinitely, and push/pull changed documents? */
@property (nonatomic) BOOL continuous;

@property (nonatomic, nullable) id <CBLConflictResolver> conflictResolver;

/** Extra options that can affect replication. There should be a list of keys somewhere :) */
@property (nonatomic, nullable) NSDictionary<NSString*,id>* options;

- (instancetype) init;

@end


NS_ASSUME_NONNULL_END
