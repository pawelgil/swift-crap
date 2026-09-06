import Testing
@testable import XcodeFixture

@Test func includedReturnsOne() {
    #expect(included(true) == 1)
    #expect(configuration() == "debug")
}
