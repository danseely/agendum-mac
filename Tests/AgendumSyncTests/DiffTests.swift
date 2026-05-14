@testable import AgendumSync
import Testing

/// Parity test fixtures for `diffTasks` per `docs/syncer-spec.md` §9.
/// Each test maps 1:1 to a fixture case in the spec so a future spec
/// revision can audit coverage.
struct DiffTests {

    // MARK: - §9 case 1: empty existing + non-empty incoming → all toCreate

    @Test
    func emptyExistingPlusIncomingAllCreate() {
        let inc = [
            makeIncoming(url: "https://example/1", source: "issue", status: "open"),
            makeIncoming(url: "https://example/2", source: "pr_authored", status: "open"),
        ]
        let diff = diffTasks(existing: [], incoming: inc, fetchedRepos: nil, reviewFetchOK: true)
        #expect(diff.toCreate.count == 2)
        #expect(diff.toUpdate.isEmpty)
        #expect(diff.toClose.isEmpty)
    }

    // MARK: - §9 case 2: non-empty existing + identical incoming → no diff

    @Test
    func identicalIncomingProducesNoUpdate() {
        let existing = [makeExisting(id: 1, url: "https://example/1", source: "issue", status: "open", title: "Bug")]
        let inc = [makeIncoming(url: "https://example/1", source: "issue", status: "open", title: "Bug")]
        let diff = diffTasks(existing: existing, incoming: inc, fetchedRepos: ["acme/repo"], reviewFetchOK: true)
        #expect(diff.toCreate.isEmpty)
        #expect(diff.toUpdate.isEmpty)
        #expect(diff.toClose.isEmpty)
    }

    // MARK: - §9 case 3: existing with terminal-status incoming → "to_create with terminal"
    // (Spec says: the to_create branch checks for the existing row by gh_url and updates
    // its status to the terminal value. This is the apply-layer's behavior, not the diff's.
    // The diff itself just sees the row in existing and produces a toUpdate with status set.)

    @Test
    func existingNonTerminalRowWithTerminalIncomingProducesStatusUpdate() {
        let existing = [makeExisting(id: 7, url: "https://example/7", source: "pr_authored", status: "open", title: "Real title")]
        // The bare merged payload (from syncer.py:202-214): title="", status="merged".
        let inc = [makeIncoming(url: "https://example/7", source: "pr_authored", status: "merged", title: "")]
        let diff = diffTasks(existing: existing, incoming: inc, fetchedRepos: ["acme/repo"], reviewFetchOK: true)
        #expect(diff.toCreate.isEmpty)
        #expect(diff.toClose.isEmpty)
        #expect(diff.toUpdate.count == 1)
        let patch = try! #require(diff.toUpdate.first)
        #expect(patch.id == 7)
        #expect(patch.status == "merged")
        #expect(patch.title == "") // §9 case 11: title="" overwrites real title intentionally
    }

    // MARK: - §9 case 4: existing PR no longer in incoming, repo in fetchedRepos → toClose

    @Test
    func existingPRGoneAndRepoFetchedClosesIt() {
        let existing = [makeExisting(id: 1, url: "https://example/1", source: "pr_authored", status: "open", repo: "acme/widget")]
        let diff = diffTasks(existing: existing, incoming: [], fetchedRepos: ["acme/widget"], reviewFetchOK: true)
        #expect(diff.toClose.map(\.id) == [1])
        #expect(diff.toUpdate.isEmpty)
        #expect(diff.toCreate.isEmpty)
    }

    // MARK: - §9 case 5: existing PR no longer in incoming, repo NOT in fetchedRepos → skipped

    @Test
    func existingPRGoneButRepoNotFetchedIsSkipped() {
        let existing = [makeExisting(id: 1, url: "https://example/1", source: "pr_authored", status: "open", repo: "acme/other")]
        let diff = diffTasks(existing: existing, incoming: [], fetchedRepos: ["acme/widget"], reviewFetchOK: true)
        // partial-fetch guard skips the close.
        #expect(diff.toClose.isEmpty)
    }

    // MARK: - §9 case 6: existing pr_review no longer in incoming, reviewFetchOK == false → skipped

    @Test
    func existingPrReviewSkippedWhenReviewFetchIncomplete() {
        let existing = [makeExisting(id: 1, url: "https://example/1", source: "pr_review", status: "review requested", repo: "acme/widget")]
        let diff = diffTasks(existing: existing, incoming: [], fetchedRepos: ["acme/widget"], reviewFetchOK: false)
        #expect(diff.toClose.isEmpty)
    }

    // MARK: - §9 case 7: existing pr_review, reviewFetchOK == true, repo NOT in fetchedRepos → toClose
    // (pr_review exemption from the partial-fetch guard.)

    @Test
    func existingPrReviewClosesEvenWhenRepoMissingFromFetchedRepos() {
        let existing = [makeExisting(id: 1, url: "https://example/1", source: "pr_review", status: "review requested", repo: "acme/widget")]
        let diff = diffTasks(existing: existing, incoming: [], fetchedRepos: ["acme/other"], reviewFetchOK: true)
        // pr_review is exempt from partial-fetch guard, gated by reviewFetchOK (which is true).
        #expect(diff.toClose.map(\.id) == [1])
    }

    // MARK: - §9 case 8: manual task → never closed by sync

    @Test
    func manualTaskNeverClosed() {
        let existing = [makeExisting(id: 1, url: "https://example/1", source: "manual", status: "backlog")]
        let diff = diffTasks(existing: existing, incoming: [], fetchedRepos: ["acme/widget"], reviewFetchOK: true)
        #expect(diff.toClose.isEmpty)
    }

    // MARK: - §9 case 9: sparse incoming dict (only status present) → only status enters toUpdate

    @Test
    func sparseIncomingWithOnlyStatusOnlyTouchesStatus() {
        // Existing row carries title="Real" and ghAuthor="alice".
        let existing = [makeExisting(
            id: 1, url: "https://example/1", source: "pr_authored", status: "open",
            title: "Real", ghAuthor: "alice", ghAuthorName: "Alice"
        )]
        // Bare merged payload — present fields are status, title, source, ghURL, ghNumber, project, ghRepo.
        // ghAuthor is NOT present → not gated, NOT compared, NOT written.
        var inc = makeIncoming(url: "https://example/1", source: "pr_authored", status: "merged", title: "")
        inc.presentFields = [.status, .title, .source, .ghURL, .ghNumber, .project, .ghRepo]
        let diff = diffTasks(existing: existing, incoming: [inc], fetchedRepos: nil, reviewFetchOK: true)
        let patch = try! #require(diff.toUpdate.first)
        #expect(patch.status == "merged")
        #expect(patch.title == "") // unconditional
        #expect(patch.ghAuthor == nil) // sparse-gated; not written
        #expect(patch.ghAuthorName == nil)
        #expect(patch.tags == nil)
        #expect(patch.project == nil) // existing has project=nil too; would also be nil here, but the key insight is it's not even compared
    }

    // MARK: - §9 case 10: update where tags JSON differs → toUpdate includes tags

    @Test
    func tagsDiffProducesTagsInPatch() {
        let existing = [makeExisting(id: 1, url: "https://example/1", source: "issue", status: "open", title: "Bug", tags: #"["old"]"#)]
        var inc = makeIncoming(url: "https://example/1", source: "issue", status: "open", title: "Bug")
        inc.tags = #"["new"]"#
        inc.presentFields = [.status, .title, .source, .ghURL, .tags, .ghNumber, .project, .ghRepo]
        let diff = diffTasks(existing: existing, incoming: [inc], fetchedRepos: nil, reviewFetchOK: true)
        let patch = try! #require(diff.toUpdate.first)
        #expect(patch.tags == #"["new"]"#)
        #expect(patch.status == nil) // unchanged
        #expect(patch.title == nil)
    }

    @Test
    func sparsePresentNilFieldProducesExplicitNullUpdate() {
        let existing = [makeExisting(
            id: 1,
            url: "https://example/1",
            source: "pr_review",
            status: "review requested",
            title: "Review",
            ghAuthor: "deleted-user",
            ghAuthorName: "Deleted",
            tags: #"["review","stale"]"#
        )]
        var inc = makeIncoming(url: "https://example/1", source: "pr_review", status: "review requested", title: "Review")
        inc.ghAuthor = nil
        inc.ghAuthorName = nil
        inc.tags = nil
        inc.presentFields = [.status, .title, .source, .ghURL, .ghAuthor, .ghAuthorName, .tags]

        let diff = diffTasks(existing: existing, incoming: [inc], fetchedRepos: nil, reviewFetchOK: true)

        let patch = try! #require(diff.toUpdate.first)
        #expect(patch.ghAuthor == nil)
        #expect(patch.ghAuthorName == nil)
        #expect(patch.tags == nil)
        #expect(patch.changedFields.contains(.ghAuthor))
        #expect(patch.changedFields.contains(.ghAuthorName))
        #expect(patch.changedFields.contains(.tags))
        #expect(patch.changedColumns == ["gh_author", "gh_author_name", "tags"])
    }

    // MARK: - §9 case 11: open→merged transition overwrites title with ""

    @Test
    func openToMergedOverwritesTitleWithEmpty() {
        let existing = [makeExisting(id: 1, url: "https://example/1", source: "pr_authored", status: "open", title: "My real title")]
        // Bare merged payload exactly as syncer.py constructs it.
        let inc = IncomingTask(
            title: "", source: "pr_authored", status: "merged",
            ghURL: "https://example/1", ghNumber: 1,
            ghRepo: "acme/widget", project: "widget",
            presentFields: [.title, .source, .status, .ghURL, .ghNumber, .project, .ghRepo]
        )
        let diff = diffTasks(existing: existing, incoming: [inc], fetchedRepos: nil, reviewFetchOK: true)
        let patch = try! #require(diff.toUpdate.first)
        #expect(patch.title == "") // intentional per spec §4 + §9 case 11
        #expect(patch.status == "merged")
    }

    // MARK: - §9 case 12: sparse update with only status → unchanged fields stay intact

    @Test
    func sparseStatusOnlyUpdateLeavesUnrelatedFieldsIntact() {
        // Existing row carries title="My real title" and ghAuthor="me".
        // Incoming sparse: only status (no title overwrite).
        let existing = [makeExisting(
            id: 1, url: "https://example/1", source: "pr_authored",
            status: "open", title: "My real title", ghAuthor: "me", ghAuthorName: "Me"
        )]
        let inc = IncomingTask(
            title: "My real title", // same as existing — won't trigger title write
            source: "pr_authored", status: "approved", ghURL: "https://example/1",
            ghNumber: 1, ghRepo: "acme/widget", project: "widget",
            presentFields: [.title, .source, .status, .ghURL, .ghNumber, .project, .ghRepo]
        )
        let diff = diffTasks(existing: existing, incoming: [inc], fetchedRepos: nil, reviewFetchOK: true)
        let patch = try! #require(diff.toUpdate.first)
        #expect(patch.status == "approved")
        #expect(patch.title == nil) // title matched existing, no write
        #expect(patch.ghAuthor == nil) // not present in incoming, sparse-gated
    }

    // MARK: - fetchedRepos == nil → partial-fetch guard skipped (always close eligible)

    @Test
    func nilFetchedReposDisablesPartialFetchGuard() {
        let existing = [makeExisting(id: 1, url: "https://example/1", source: "pr_authored", status: "open", repo: "acme/widget")]
        let diff = diffTasks(existing: existing, incoming: [], fetchedRepos: nil, reviewFetchOK: true)
        // Without fetchedRepos, the partial-fetch guard doesn't kick in.
        #expect(diff.toClose.map(\.id) == [1])
    }

    // MARK: - existing with no gh_url → never closed (manual or malformed)

    @Test
    func existingWithoutGhURLNeverClosed() {
        let existing = [makeExisting(id: 1, url: nil, source: "pr_authored", status: "open")]
        let diff = diffTasks(existing: existing, incoming: [], fetchedRepos: ["acme/widget"], reviewFetchOK: true)
        #expect(diff.toClose.isEmpty)
    }
}

// MARK: - Helpers

private func makeIncoming(
    url: String,
    source: String,
    status: String,
    title: String = "T",
    ghNumber: Int? = 1,
    repo: String? = nil,
    project: String? = nil
) -> IncomingTask {
    IncomingTask(
        title: title, source: source, status: status,
        ghURL: url, ghNumber: ghNumber, ghRepo: repo, project: project,
        presentFields: [.title, .source, .status, .ghURL, .ghNumber, .ghRepo, .project]
    )
}

private func makeExisting(
    id: Int,
    url: String?,
    source: String,
    status: String,
    title: String = "T",
    repo: String? = nil,
    ghAuthor: String? = nil,
    ghAuthorName: String? = nil,
    tags: String? = nil
) -> ExistingTask {
    ExistingTask(
        id: id, title: title, source: source, status: status,
        ghURL: url, ghRepo: repo, ghAuthor: ghAuthor, ghAuthorName: ghAuthorName, tags: tags
    )
}
