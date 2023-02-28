//
//  UDPTest.swift
//  
//
//  Created by Alexander Heinrich on 28.02.23.
//

import XCTest
@testable import SwiftSSDP

final class UDPTest: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
       // Open udp socket
        let expect = expectation(description: "Socket reply")
        let deviceType = "ZonePlayer"
        let testTarget = SSDPSearchTarget.deviceType(schema: SSDPSearchTarget.upnpOrgSchema, deviceType: deviceType, version: 1)
        
        let socket = try SSDPUDPSocket { data, adressInfo in
            let received = String(data: data, encoding: .utf8)!
            print("Received data \(received)")
            if received.contains(deviceType) {
               expect.fulfill()
            }
        } caughtErrorHandler: { error in
            print("Error on socket \(error.localizedDescription)")
        }

        // Send SSDP Packet for Chromecast discovery
        
        let request = SSDPMSearchRequest(delegate: self, searchTarget: testTarget)
        
        print("Sending message\n\(request.message)")
        try socket.send(messageData: request.message.data(using: .utf8)!, toHost: "239.255.255.250", port: 1900, withTimeout: -1, tag: 1000)
        
        wait(for: [expect], timeout: 10.0)
        try socket.close()
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}

extension UDPTest: SSDPDiscoveryDelegate {
    
}
