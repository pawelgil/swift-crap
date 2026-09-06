import Testing
@testable import XcodeFixture

@Test func `included returns one`() {
    #expect(included(true) == 1)
    #expect(configuration() == "debug")
}

@Test func `selects first closure`() {
    #expect(selectClosure(true) == 1)
}
