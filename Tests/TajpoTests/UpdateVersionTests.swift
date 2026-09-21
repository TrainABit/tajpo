import Testing
@testable import TajpoCore

@Test func versionCompareTreatsVPrefixAsOptional() {
    #expect(VersionCompare.isNewer("v1.2.0", than: "1.1.0"))
    #expect(VersionCompare.isNewer("1.1.1", than: "1.1.0"))
    #expect(!VersionCompare.isNewer("1.1.0", than: "1.1.0"))
    #expect(!VersionCompare.isNewer("1.0.9", than: "1.1.0"))
    // A shortened form is padded with zeros, so v1.2 == 1.2.0.
    #expect(!VersionCompare.isNewer("v1.2", than: "1.2.0"))
    #expect(VersionCompare.isNewer("v1.2.1", than: "v1.2"))
}

@Test func versionCompareTreatsPrereleaseAsLowerThanRelease() {
    #expect(!VersionCompare.isNewer("1.2.0-beta", than: "1.2.0"))
    #expect(VersionCompare.isNewer("1.2.0", than: "1.2.0-beta"))
    #expect(!VersionCompare.isNewer("v1.2.0-rc.2", than: "1.2.0"))
    #expect(VersionCompare.isNewer("1.2.0-beta.2", than: "1.2.0-beta.1"))
    // Numeric identifiers compare numerically, not lexically.
    #expect(VersionCompare.isNewer("1.2.0-beta.10", than: "1.2.0-beta.2"))
    // Numeric identifiers sort before alphanumeric ones.
    #expect(VersionCompare.isNewer("1.2.0-alpha", than: "1.2.0-1"))
    #expect(VersionCompare.isNewer("1.2.0-beta.1", than: "1.2.0-alpha.9"))
}

@Test func buildMetadataDoesNotChangePrecedence() {
    #expect(!VersionCompare.isNewer("1.2.0+build.7", than: "1.2.0"))
    #expect(!VersionCompare.isNewer("1.2.0", than: "1.2.0+build.7"))
    #expect(VersionCompare.isNewer("1.2.1+build.7", than: "1.2.0"))
}

@Test func malformedTagsAreRejectedInsteadOfGuessed() {
    // The old parser concatenated digits ("1.2.1rc1" became [1, 2, 11]) and
    // invented [0] for garbage. Both are now rejected outright.
    #expect(VersionCompare.parse("1.2.1rc1") == nil)
    #expect(VersionCompare.parse("garbage") == nil)
    #expect(VersionCompare.parse("v-beta") == nil)
    #expect(VersionCompare.parse("1.2.3.4") == nil)
    #expect(VersionCompare.parse("") == nil)
    #expect(VersionCompare.parse("1.2.0-") == nil)
    #expect(VersionCompare.normalize("garbage") == [])
    #expect(!VersionCompare.isNewer("garbage", than: "0.0.1"))
    #expect(!VersionCompare.isNewer("1.2.0", than: "garbage"))
    #expect(VersionCompare.parse("v1.2.3") == VersionCompare.Semver(core: [1, 2, 3]))
    #expect(VersionCompare.parse("1.2.0-beta.1") == VersionCompare.Semver(core: [1, 2, 0], prerelease: ["beta", "1"]))
}

@Test func repositoryMustBeAnOwnerNamePair() {
    #expect(UpdateChecker.isValidRepository("TrainABit/tajpo"))
    #expect(UpdateChecker.isValidRepository("owner/repo.with-dots_1"))
    #expect(!UpdateChecker.isValidRepository(""))
    #expect(!UpdateChecker.isValidRepository("tajpo"))
    #expect(!UpdateChecker.isValidRepository("/tajpo"))
    #expect(!UpdateChecker.isValidRepository("owner/"))
    #expect(!UpdateChecker.isValidRepository("owner/repo/extra"))
    #expect(!UpdateChecker.isValidRepository("https://github.com/owner/repo"))
    #expect(!UpdateChecker.isValidRepository("owner repo/x"))
}

@Test func releaseURLRequiresGitHubRepositoryMatch() {
    let checker = UpdateChecker(repository: "TrainABit/tajpo")
    #expect(checker.validatedReleaseURL("https://github.com/TrainABit/tajpo/releases/tag/v1.3.0") != nil)
    // Plain HTTP, a spoofed host, and a different repository are all rejected.
    #expect(checker.validatedReleaseURL("http://github.com/TrainABit/tajpo/releases/tag/v1.3.0") == nil)
    #expect(checker.validatedReleaseURL("https://evil.example/TrainABit/tajpo/releases/tag/v1.3.0") == nil)
    #expect(checker.validatedReleaseURL("https://github.com/other/repo/releases/tag/v1.3.0") == nil)
    #expect(checker.validatedReleaseURL("not a url") == nil)
}
