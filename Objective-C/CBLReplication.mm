//
//  CBLReplication.mm
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/13/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLReplication+Internal.h"
#import "CBLCoreBridge.h"
#import "CBLStringBytes.h"
#import "CBLInternal.h"
#import "CBLStatus.h"

#import "c4Replicator.h"
#import "c4Socket.h"
#import "CBLWebSocket.h"
#import "FleeceCpp.hh"


#import "CBLReplicatorConfiguration.h"

using namespace fleece;
using namespace fleeceapi;

static C4LogDomain kCBLSyncLogDomain;

NSString* const kCBLReplicatorChangeNotification = @"kCBLReplicatorChangeNotification";
NSString* const kCBLReplicatorStatusUserInfoKey = @"kCBLReplicatorStatusUserInfoKey";
NSString* const kCBLReplicatorErrorUserInfoKey = @"kCBLReplicatorErrorUserInfoKey";


@interface CBLReplicatorStatus ()

- (instancetype) initWithActivity: (CBLReplicatorActivityLevel)activity
                         progress: (CBLReplicatorProgress)progress;
@end


@implementation CBLReplicatorStatus

@synthesize activity=_activity, progress=_progress;


- (instancetype) initWithActivity: (CBLReplicatorActivityLevel)activity
                         progress: (CBLReplicatorProgress)progress
{
    self = [super init];
    if (self) {
        _activity = activity;
        _progress = progress;
    }
    return self;
}

@end

@interface CBLReplication ()
@property (readwrite, nonatomic) CBLReplicatorStatus* status;
@property (readwrite, nonatomic) NSError* lastError;
@end


@implementation CBLReplication
{
    C4Replicator* _repl;
    AllocedDict _responseHeaders;   //TODO: Do something with these (for auth)
    NSError* _lastError;
}

@synthesize config=_config;
@synthesize status=_status, lastError=_lastError;


+ (void) initialize {
    if (self == [CBLReplication class]) {
        kCBLSyncLogDomain = c4log_getDomain("Sync", true);
        [CBLWebSocket registerWithC4];
    }
}


- (instancetype) initWithConfig: (CBLReplicatorConfiguration *)config {
    self = [super init];
    if (self) {
        NSParameterAssert(config.database != nil && config.target != nil);
        _config = [config copy];
    }
    return self;
}


- (CBLReplicatorConfiguration*) config {
    return [_config copy];
}


- (void) dealloc {
    c4repl_free(_repl);
}


- (NSString*) description {
    return [NSString stringWithFormat: @"%@[%s%s%s %@]",
            self.class,
            (isPull(_config.replicatorType) ? "<" : ""),
            (_config.continuous ? "*" : "-"),
            (isPush(_config.replicatorType)  ? ">" : ""),
            _config.target];
}


static C4ReplicatorMode mkmode(BOOL active, BOOL continuous) {
    C4ReplicatorMode const kModes[4] = {kC4Disabled, kC4Disabled, kC4OneShot, kC4Continuous};
    return kModes[2*!!active + !!continuous];
}


static BOOL isPush(CBLReplicatorType type) {
    return type == kCBLPushAndPull || type == kCBLPush;
}


static BOOL isPull(CBLReplicatorType type) {
    return type == kCBLPushAndPull || type == kCBLPull;
}


- (void) start {
    if (_repl) {
        CBLWarn(Sync, @"%@ has already started", self);
        return;
    }
    
    Assert(_config.database);
    Assert(_config.target);
    
    // Target:
    C4Address addr;
    CBLDatabase* otherDB;
    
    NSURL* remoteURL = _config.target.url;
    CBLStringBytes dbName(remoteURL.path.lastPathComponent);
    if (remoteURL) {
        // Fill out the C4Address:
        CBLStringBytes scheme(remoteURL.scheme);
        CBLStringBytes host(remoteURL.host);
        CBLStringBytes path(remoteURL.path.stringByDeletingLastPathComponent);
        addr = {
            .scheme = scheme,
            .hostname = host,
            .port = (uint16_t)remoteURL.port.shortValue,
            .path = path
        };
    } else {
        otherDB = _config.target.database;
        Assert(otherDB);
    }
    
    // If the URL has a hardcoded username/password, add them as an "auth" option:
    NSDictionary* options = _config.options;
    NSString* username = remoteURL.user;
    if (username && !options[kCBLReplicationAuthOption]) {
        NSMutableDictionary *auth = [NSMutableDictionary new];
        auth[kCBLReplicationAuthUserName] = username;
        auth[kCBLReplicationAuthPassword] = remoteURL.password;
        NSMutableDictionary *nuOpts = options ? [options mutableCopy] : [NSMutableDictionary new];
        nuOpts[kCBLReplicationAuthOption] = auth;
        options = nuOpts;
    }

    // Encode the options:
    alloc_slice optionsFleece;
    if (options.count) {
        Encoder enc;
        enc << options;
        optionsFleece = enc.finish();
    }

    // Push / Pull / Continuous:
    BOOL push = isPush(_config.replicatorType);
    BOOL pull = isPull(_config.replicatorType);
    BOOL continuos = _config.continuous;
    
    // Create a C4Replicator:
    C4Error err;
    _repl = c4repl_new(_config.database.c4db, addr, dbName, otherDB.c4db,
                       mkmode(push, continuos), mkmode(pull, continuos),
                       {optionsFleece.buf, optionsFleece.size},
                       &statusChanged, (__bridge void*)self, &err);
    C4ReplicatorStatus status;
    if (_repl) {
        status = c4repl_getStatus(_repl);
        [_config.database.activeReplications addObject: self];     // keeps me from being dealloced
    } else {
        status = {kC4Stopped, {}, err};
    }
    [self setC4Status: status];

    // Post an initial notification:
    statusChanged(_repl, status, (__bridge void*)self);
}


- (void) stop {
    if (_repl)
        c4repl_stop(_repl);
}


static void statusChanged(C4Replicator *repl, C4ReplicatorStatus status, void *context) {
    dispatch_async(dispatch_get_main_queue(), ^{ //TODO: Support other queues
        [(__bridge CBLReplication*)context c4StatusChanged: status];
    });
}


- (void) c4StatusChanged: (C4ReplicatorStatus)status {
    [self setC4Status: status];
    
    NSMutableDictionary* userinfo = [NSMutableDictionary new];
    userinfo[kCBLReplicatorStatusUserInfoKey] = self.status;
    userinfo[kCBLReplicatorErrorUserInfoKey] = self.lastError;
    [NSNotificationCenter.defaultCenter
        postNotificationName: kCBLReplicatorChangeNotification object: self userInfo: userinfo];

    if (!_responseHeaders) {
        C4Slice h = c4repl_getResponseHeaders(_repl);
        _responseHeaders = AllocedDict(slice{h.buf, h.size});
    }

    if (status.level == kC4Stopped) {
        // Stopped:
        c4repl_free(_repl);
        _repl = nullptr;
        [_config.database.activeReplications removeObject: self]; // this is likely to dealloc me
    }
}


- (void) setC4Status: (C4ReplicatorStatus)state {
    NSError *error = nil;
    if (state.error.code)
        convertError(state.error, &error);
    if (error != _lastError)
        self.lastError = error;
    
    CBLReplicatorActivityLevel level;
    switch (state.level) {
        case kC4Stopped:
            level = kCBLStopped;
            break;
        case kC4Idle:
        case kC4Offline:
            level = kCBLIdle;
            break;
        default:
            level = kCBLBusy;
            break;
    }
    CBLReplicatorProgress progress = { state.progress.completed, state.progress.total };
    self.status = [[CBLReplicatorStatus alloc] initWithActivity: level progress: progress];
    
    CBLLog(Sync, @"%@ is %s, progress %llu/%llu, error: %@",
           self, kC4ReplicatorActivityLevelNames[state.level],
           state.progress.completed, state.progress.total,
           error);
}


@end
