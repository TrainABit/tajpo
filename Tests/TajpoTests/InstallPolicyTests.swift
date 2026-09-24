import Foundation
import Testing
@testable import TajpoCore

@Suite struct InstallPolicyTests {
    @Test func temporaryBundlePathsAreRecognizedWithoutPrefixConfusion() {
        #expect(InstallPathPolicy.isTemporaryBundlePath("/Volumes/Tajpo/Tajpo.app"))
        #expect(InstallPathPolicy.isTemporaryBundlePath("/private/var/folders/AppTranslocation/abc/Tajpo.app"))
        #expect(!InstallPathPolicy.isTemporaryBundlePath("/Applications/Tajpo.app"))
        #expect(!InstallPathPolicy.isTemporaryBundlePath("/VolumesBackup/Tajpo.app"))
    }

    @Test func onlyTheCanonicalApplicationsDestinationIsAllowed() {
        #expect(InstallPathPolicy.isAllowedInstallDestination("/Applications/Tajpo.app"))
        #expect(InstallPathPolicy.isAllowedInstallDestination("/Applications/../Applications/Tajpo.app"))
        #expect(!InstallPathPolicy.isAllowedInstallDestination("/Applications/Tajpo.app/Contents"))
        #expect(!InstallPathPolicy.isAllowedInstallDestination("/tmp/Tajpo.app"))
        #expect(InstallPathPolicy.installDestination().path == "/Applications/Tajpo.app")
    }

    @Test func signedReplacementRequiresMatchingIdentity() {
        let signed = InstallSignature(
            bundleIdentifier: "com.trainabit.tajpo",
            teamIdentifier: "TEAM123456",
            authority: "Developer ID Application: TrainABit (TEAM123456)"
        )
        #expect(InstallSignaturePolicy.canReplace(
            replacement: signed,
            expectedBundleIdentifier: "com.trainabit.tajpo",
            expectedTeamIdentifier: "TEAM123456"
        ))
        #expect(!InstallSignaturePolicy.canReplace(
            replacement: signed,
            expectedBundleIdentifier: "com.other.tajpo"
        ))
        #expect(!InstallSignaturePolicy.canReplace(
            replacement: signed,
            expectedBundleIdentifier: "com.trainabit.tajpo",
            expectedTeamIdentifier: "OTHER12345"
        ))
        #expect(!InstallSignaturePolicy.canReplace(
            replacement: InstallSignature(
                bundleIdentifier: "com.trainabit.tajpo",
                teamIdentifier: "TEAM123456",
                authority: nil
            ),
            expectedBundleIdentifier: "com.trainabit.tajpo"
        ))
    }

    @Test func adHocBuildCannotReplaceATeamSignedInstall() {
        let adHoc = InstallSignature(bundleIdentifier: "com.trainabit.tajpo", teamIdentifier: nil, authority: nil)
        let signed = InstallSignature(
            bundleIdentifier: "com.trainabit.tajpo",
            teamIdentifier: "TEAM123456",
            authority: "Developer ID Application: TrainABit (TEAM123456)"
        )
        #expect(InstallSignaturePolicy.canReplace(
            replacement: adHoc,
            expectedBundleIdentifier: "com.trainabit.tajpo"
        ))
        #expect(!InstallSignaturePolicy.canReplace(
            replacement: adHoc,
            expectedBundleIdentifier: "com.trainabit.tajpo",
            existing: signed
        ))
        #expect(!InstallSignaturePolicy.canReplace(
            replacement: signed,
            expectedBundleIdentifier: "com.trainabit.tajpo",
            existing: adHoc
        ))
    }
}
