import Testing
@testable import TajpoCore

@Test func versionCompareTreatsVPrefixAsOptional() {
    #expect(VersionCompare.isNewer("v1.2.0", than: "1.1.0"))
    #expect(VersionCompare.isNewer("1.1.1", than: "1.1.0"))
    #expect(!VersionCompare.isNewer("1.1.0", than: "1.1.0"))
    #expect(!VersionCompare.isNewer("1.0.9", than: "1.1.0"))
}
