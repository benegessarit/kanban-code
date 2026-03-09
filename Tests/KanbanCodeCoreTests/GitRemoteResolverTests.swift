import Testing
@testable import KanbanCodeCore

@Suite("GitRemoteResolver")
struct GitRemoteResolverTests {

    @Test("Parses SSH remote URL")
    func sshRemote() {
        let result = GitRemoteResolver.parseGitHubURL(from: "git@github.com:langwatch/langwatch.git")
        #expect(result == "https://github.com/langwatch/langwatch")
    }

    @Test("Parses HTTPS remote URL")
    func httpsRemote() {
        let result = GitRemoteResolver.parseGitHubURL(from: "https://github.com/langwatch/langwatch.git")
        #expect(result == "https://github.com/langwatch/langwatch")
    }

    @Test("Parses HTTPS remote URL without .git suffix")
    func httpsNoGit() {
        let result = GitRemoteResolver.parseGitHubURL(from: "https://github.com/owner/repo")
        #expect(result == "https://github.com/owner/repo")
    }

    @Test("Returns nil for non-GitHub remote")
    func nonGitHub() {
        let result = GitRemoteResolver.parseGitHubURL(from: "git@gitlab.com:owner/repo.git")
        #expect(result == nil)
    }

    @Test("Constructs issue URL")
    func issueURL() {
        let url = GitRemoteResolver.issueURL(base: "https://github.com/langwatch/langwatch", number: 42)
        #expect(url == "https://github.com/langwatch/langwatch/issues/42")
    }

    @Test("Constructs PR URL")
    func prURL() {
        let url = GitRemoteResolver.prURL(base: "https://github.com/langwatch/langwatch", number: 17)
        #expect(url == "https://github.com/langwatch/langwatch/pull/17")
    }
}
