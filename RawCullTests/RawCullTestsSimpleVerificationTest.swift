//
//  RawCullTestsSimpleVerificationTest.swift
//  RawCull Tests
//
//  Created by Thomas Evensen on 18/03/2026.
//
//  Simple test to verify Swift Testing is working
//

import Testing

struct SimpleVerificationTest {
    @Test
    func `Swift Testing is available`() {
        #expect(true, "If this test runs, Swift Testing is working!")
    }

    @Test
    func `Basic arithmetic`() {
        let result = 2 + 2
        #expect(result == 4)
    }

    @Test
    func `Async test works`() async {
        try? await Task.sleep(for: .milliseconds(10))
        #expect(true, "Async tests work!")
    }
}
