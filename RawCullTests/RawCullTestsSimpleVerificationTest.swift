//
//  SimpleVerificationTest.swift
//  RawCull Tests
//
//  Created by Thomas Evensen on 18/03/2026.
//
//  Simple test to verify Swift Testing is working
//

import Testing

@Suite("Swift Testing Verification")
struct SimpleVerificationTest {
    
    @Test("Swift Testing is available")
    func swiftTestingWorks() {
        #expect(true, "If this test runs, Swift Testing is working!")
    }
    
    @Test("Basic arithmetic")
    func basicMath() {
        let result = 2 + 2
        #expect(result == 4)
    }
    
    @Test("Async test works")
    func asyncTest() async {
        try? await Task.sleep(for: .milliseconds(10))
        #expect(true, "Async tests work!")
    }
}
