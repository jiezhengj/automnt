import Testing
import DiskArbitration
@testable import AutomntCLI
import AutomntCore

struct CLIEjectClassificationTests {
    @Test func diskArbitrationBusyAndUnixErrnoBusyAreBusy() {
        #expect(cliNormalEjectIssue(forDissenterStatus: DAReturn(kDAReturnBusy)) == .volumeBusy)
        // unix_err(EBUSY) as returned by DADissenterGetStatus for an open file.
        #expect(cliNormalEjectIssue(forDissenterStatus: DAReturn(0xC000 + EBUSY)) == .volumeBusy)
    }

    @Test func permissionErrorsMapToAuthorizationRequired() {
        #expect(cliNormalEjectIssue(forDissenterStatus: DAReturn(0xC000 + EACCES)) == .authorizationRequired)
        #expect(cliNormalEjectIssue(forDissenterStatus: DAReturn(kDAReturnNotPermitted)) == .authorizationRequired)
    }

    @Test func unknownStatusIsNotSilentlyTreatedAsSuccess() {
        #expect(cliNormalEjectIssue(forDissenterStatus: DAReturn(0xDEAD)) == .shareRejected)
    }
}
