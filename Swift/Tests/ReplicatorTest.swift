//
//  ReplicatorTest.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/26/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import XCTest
import CouchbaseLiteSwift


class ReplicatorTest: CBLTestCase {
    var otherDB: Database?
    var repl: Replication?

    override func setUp() {
        super.setUp()
        otherDB = try! openDB(name: "otherdb")
        XCTAssertNotNil(otherDB)
    }
    
    
    override func tearDown() {
        try! otherDB?.close()
        super.tearDown()
    }
    
    
    func run(push: Bool, pull: Bool, opts: Dictionary<String, Any>?, expectedError: Int?) {
        var config = ReplicatorConfiguration()
        config.database = db
        config.target = .database(otherDB!)
        config.replicationType = push && pull ? .pushAndPull : (push ? .push : .pull)
        config.options = opts
        run(config: config, expectedError: expectedError)
    }
    
    
    func run(push: Bool, pull: Bool, url: URL, opts: Dictionary<String, Any>?, expectedError: Int?) {
        var config = ReplicatorConfiguration()
        config.database = db
        config.target = .url(url)
        config.replicationType = push && pull ? .pushAndPull : (push ? .push : .pull)
        config.options = opts
        run(config: config, expectedError: expectedError)
    }
    
    
    func run(config: ReplicatorConfiguration, expectedError: Int?) {
        repl = Replication(config: config);
        let x = self.expectation(forNotification: Notification.Name.ReplicatorChange.rawValue, object: repl!)
        { (n) -> Bool in
            let status = n.userInfo![ReplicatorStatusUserInfoKey] as! Replication.Status
            if status.activity == .Stopped {
                if let err = expectedError {
                    let error = n.userInfo![ReplicatorErrorUserInfoKey] as! NSError
                    XCTAssertEqual(error.code, err)
                }
                return true
            }
            return false
        }
        repl!.start()
        wait(for: [x], timeout: 5.0)
    }
    
    
    func testEmptyPush() {
        run(push: true, pull: false, opts: nil, expectedError: nil)
    }
}
