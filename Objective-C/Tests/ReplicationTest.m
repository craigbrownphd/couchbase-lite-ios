//
//  ReplicationTest.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/28/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"

@interface ReplicationTest : CBLTestCase
@end


@implementation ReplicationTest
{
    CBLDatabase* otherDB;
    CBLReplication* repl;
}


- (void) setUp {
    [super setUp];
    
    NSError* error;
    otherDB = [self openDBNamed: @"otherdb" error: &error];
    AssertNil(error);
    AssertNotNil(otherDB);
}


- (void) tearDown {
    NSError* error;
    Assert([otherDB close: &error]);
    otherDB = nil;
    repl = nil;
    [super tearDown];
}


- (void) push: (BOOL)push pull: (BOOL)pull opts: (NSDictionary*)opts error: (NSInteger) error {
    CBLReplicatorConfiguration* config = [[CBLReplicatorConfiguration alloc] init];
    config.database = self.db;
    config.target = [CBLReplicatorTarget database: otherDB];
    config.replicatorType = push && pull ? kCBLPushAndPull : (push ? kCBLPush : kCBLPull);
    config.options = opts;
    [self runWithConfig: config errorCode: error];
}


- (void) push: (BOOL)push pull: (BOOL)pull url: (NSString*)url opts: (NSDictionary*)opts
        error: (NSInteger) error
{
    CBLReplicatorConfiguration* config = [[CBLReplicatorConfiguration alloc] init];
    config.database = self.db;
    config.target = [CBLReplicatorTarget url: [NSURL URLWithString: url]];
    config.replicatorType = push && pull ? kCBLPushAndPull : (push ? kCBLPush : kCBLPull);
    config.options = opts;
    [self runWithConfig: config errorCode: error];
}


- (void) runWithConfig: (CBLReplicatorConfiguration*)config errorCode: (NSInteger)code {
    repl = [[CBLReplication alloc] initWithConfig: config];
    XCTestExpectation *x = [self expectationForNotification: kCBLReplicatorChangeNotification
                                                     object: repl
                                                    handler: ^BOOL(NSNotification *n)
    {
        CBLReplicatorStatus* status =  n.userInfo[kCBLReplicatorStatusUserInfoKey];
        if (status.activity == kCBLStopped) {
            NSError* error = n.userInfo[kCBLReplicatorErrorUserInfoKey];
            if (code != 0)
                AssertEqual(error.code, code);
            else
                AssertNil(error);
            return YES;
        }
        return NO;
    }];
    [repl start];
    [self waitForExpectations: @[x] timeout: 5.0];
}


- (void)testEmptyPush {
    [self push: YES pull: NO opts: nil error: 0];
}


// These test are disabled because they require a password-protected database 'seekrit' to exist
// on localhost:4984, with a user 'pupshaw' whose password is 'frank'.

- (void) dontTestAuthenticationFailure {
    [self push: NO pull: YES url: @"blip://localhost:4984/seekrit" opts: nil error: 401];
}


- (void) dontTestAuthenticatedPullHardcoded {
    [self push: NO pull: YES url: @"blip://pupshaw:frank@localhost:4984/seekrit" opts: nil error: 0];
}


- (void) dontTestAuthenticatedPull {
    NSDictionary* opts = @{@"auth": @{@"username": @"pupshaw", @"password": @"frank"}};
    [self push: NO pull: YES url: @"blip://localhost:4984/seekrit" opts: opts error: 0];
}

@end
