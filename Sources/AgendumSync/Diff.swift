import Foundation
import AgendumModel

/// Pure data shape for an "incoming" task discovered from GitHub during a sync.
/// Mirrors the dict shape Python `syncer.run_sync` builds in `incoming_tasks`.
///
/// Sparse by design: a "bare" merged/closed PR payload only carries
/// `title=""` + the identifying fields, mirroring `syncer.py:202-257`.
/// Sparse-ness drives the diff comparison rules (see `diffTasks`).
public struct IncomingTask: Equatable, Sendable {
    public var title: String
    public var source: String           // "pr_authored" | "pr_review" | "issue" | "manual"
    public var status: String
    public var ghURL: String            // required — used as the join key
    public var ghNumber: Int?
    public var ghRepo: String?
    public var project: String?
    public var ghAuthor: String?        // login
    public var ghAuthorName: String?    // display-name first-token
    /// JSON-encoded array string (e.g. `["bug","ui"]`), matching the schema's
    /// storage format. Whether nil means "clear tags" or "leave unchanged" is
    /// determined by `presentFields.contains(.tags)`.
    public var tags: String?

    /// Fields the incoming dict carries. Tracks Python's `"key in item"`
    /// semantics for the sparse-update comparison: a field's presence here
    /// means it was extracted from the GitHub response and may legitimately
    /// participate in the diff; absence means "don't compare or write."
    public var presentFields: Set<Field>

    public enum Field: Hashable, Sendable {
        case title, source, status, ghURL, ghNumber, ghRepo
        case project, ghAuthor, ghAuthorName, tags
    }

    public init(
        title: String,
        source: String,
        status: String,
        ghURL: String,
        ghNumber: Int? = nil,
        ghRepo: String? = nil,
        project: String? = nil,
        ghAuthor: String? = nil,
        ghAuthorName: String? = nil,
        tags: String? = nil,
        presentFields: Set<Field>
    ) {
        self.title = title
        self.source = source
        self.status = status
        self.ghURL = ghURL
        self.ghNumber = ghNumber
        self.ghRepo = ghRepo
        self.project = project
        self.ghAuthor = ghAuthor
        self.ghAuthorName = ghAuthorName
        self.tags = tags
        self.presentFields = presentFields
    }
}

/// Existing-task snapshot used by `diffTasks`. Sufficient for the diff itself
/// — full mutation goes through `TaskStore` in the apply step.
public struct ExistingTask: Equatable, Sendable {
    public let id: Int
    public let title: String
    public let source: String
    public let status: String
    public let ghURL: String?
    public let ghRepo: String?
    public let project: String?
    public let ghAuthor: String?
    public let ghAuthorName: String?
    public let tags: String?

    public init(
        id: Int,
        title: String,
        source: String,
        status: String,
        ghURL: String? = nil,
        ghRepo: String? = nil,
        project: String? = nil,
        ghAuthor: String? = nil,
        ghAuthorName: String? = nil,
        tags: String? = nil
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.status = status
        self.ghURL = ghURL
        self.ghRepo = ghRepo
        self.project = project
        self.ghAuthor = ghAuthor
        self.ghAuthorName = ghAuthorName
        self.tags = tags
    }
}

/// The diff result. Three buckets, mirroring Python `SyncResult`.
public struct SyncDiff: Equatable, Sendable {
    public var toCreate: [IncomingTask]
    public var toUpdate: [UpdatePatch]
    public var toClose: [ExistingTask]

    public init(toCreate: [IncomingTask] = [], toUpdate: [UpdatePatch] = [], toClose: [ExistingTask] = []) {
        self.toCreate = toCreate
        self.toUpdate = toUpdate
        self.toClose = toClose
    }
}

/// A row in the to-update bucket. Carries only the columns that differ.
/// `changedFields` disambiguates "don't touch this column" from "write SQL
/// NULL". That distinction matters for Python parity: `syncer.diff_tasks`
/// can emit `{"gh_author": None}` and `db.update_task` writes it through.
public struct UpdatePatch: Equatable, Sendable {
    public let id: Int
    public var title: String?
    public var source: String?
    public var status: String?
    public var project: String?
    public var ghAuthor: String?
    public var ghAuthorName: String?
    public var tags: String?
    public var changedFields: Set<Field>

    public enum Field: Hashable, Sendable {
        case title, source, status, project, ghRepo, ghNumber, ghAuthor, ghAuthorName, tags
    }

    public init(
        id: Int,
        title: String? = nil,
        source: String? = nil,
        status: String? = nil,
        project: String? = nil,
        ghAuthor: String? = nil,
        ghAuthorName: String? = nil,
        tags: String? = nil,
        changedFields: Set<Field>? = nil
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.status = status
        self.project = project
        self.ghAuthor = ghAuthor
        self.ghAuthorName = ghAuthorName
        self.tags = tags
        if let changedFields {
            self.changedFields = changedFields
        } else {
            var inferred: Set<Field> = []
            if title != nil { inferred.insert(.title) }
            if source != nil { inferred.insert(.source) }
            if status != nil { inferred.insert(.status) }
            if project != nil { inferred.insert(.project) }
            if ghAuthor != nil { inferred.insert(.ghAuthor) }
            if ghAuthorName != nil { inferred.insert(.ghAuthorName) }
            if tags != nil { inferred.insert(.tags) }
            self.changedFields = inferred
        }
    }

    public var hasAnyChange: Bool {
        !changedFields.isEmpty
    }

    public var changedColumns: Set<String> {
        Set(changedFields.map(\.columnName))
    }
}

private extension UpdatePatch.Field {
    var columnName: String {
        switch self {
        case .title: return "title"
        case .source: return "source"
        case .status: return "status"
        case .project: return "project"
        case .ghRepo: return "gh_repo"
        case .ghNumber: return "gh_number"
        case .ghAuthor: return "gh_author"
        case .ghAuthorName: return "gh_author_name"
        case .tags: return "tags"
        }
    }
}

/// Pure diff function — no I/O, no side effects, totally testable.
///
/// Faithful port of `syncer.diff_tasks` (`syncer.py:32-99`):
///   - Indexes existing rows by `gh_url` (skips rows without one — those are
///     manual or malformed).
///   - For each incoming row keyed on `gh_url`:
///       - If `gh_url` not in existing index → `toCreate`.
///       - Else compute the column diff:
///         - `status` and `title` are compared UNCONDITIONALLY (always written
///           if they differ — including the `title=""` overwrite on
///           open→merged transitions, see syncer-spec §4 "Important behavior").
///         - `gh_author`, `gh_author_name`, `tags`, `project` are sparse-gated:
///           only compared when `presentFields.contains(.field)`.
///         - If any column changed → `toUpdate.append(UpdatePatch(...))`.
///   - For each existing row not in `incomingURLs` → close-eligibility:
///       1. Skip if no `gh_url`.
///       2. Skip if `gh_url` was in incoming.
///       3. Skip if `source == "manual"`.
///       4. Skip if `!reviewFetchOK && source == "pr_review"` (review fetch
///          incomplete protection).
///       5. Skip if `fetchedRepos != nil && source != "pr_review"
///          && task.ghRepo ∉ fetchedRepos` (partial fetch protection;
///          `pr_review` is exempt — gated by step 4 instead).
///       6. Otherwise → `toClose`.
public func diffTasks(
    existing: [ExistingTask],
    incoming: [IncomingTask],
    fetchedRepos: Set<String>? = nil,
    reviewFetchOK: Bool = true
) -> SyncDiff {
    var result = SyncDiff()

    // Build the join index keyed on gh_url.
    var existingByURL: [String: ExistingTask] = [:]
    existingByURL.reserveCapacity(existing.count)
    for task in existing {
        guard let url = task.ghURL else { continue }
        existingByURL[url] = task
    }

    // Walk incoming → toCreate / toUpdate.
    var incomingURLs: Set<String> = []
    incomingURLs.reserveCapacity(incoming.count)
    for item in incoming {
        incomingURLs.insert(item.ghURL)
        guard let old = existingByURL[item.ghURL] else {
            result.toCreate.append(item)
            continue
        }
        var patch = UpdatePatch(id: old.id)
        var changed = false

        // status + title: compared unconditionally (no presentFields gate).
        // Matches Python `syncer.py:68-73` which uses `old.get("status") != item.get("status")`
        // without an `"status" in item` guard. Empty title from a bare merged/closed
        // payload WILL overwrite the stored title — intentional in Python, retained here.
        if old.status != item.status {
            patch.status = item.status
            patch.changedFields.insert(.status)
            changed = true
        }
        if old.title != item.title {
            patch.title = item.title
            patch.changedFields.insert(.title)
            changed = true
        }

        // gh_author, gh_author_name, tags, project: sparse-gated.
        // Matches Python `for key in (…): if key in item and old.get(key) != item.get(key)`.
        if item.presentFields.contains(.ghAuthor) && old.ghAuthor != item.ghAuthor {
            patch.ghAuthor = item.ghAuthor
            patch.changedFields.insert(.ghAuthor)
            changed = true
        }
        if item.presentFields.contains(.ghAuthorName) && old.ghAuthorName != item.ghAuthorName {
            patch.ghAuthorName = item.ghAuthorName
            patch.changedFields.insert(.ghAuthorName)
            changed = true
        }
        if item.presentFields.contains(.tags) && old.tags != item.tags {
            patch.tags = item.tags
            patch.changedFields.insert(.tags)
            changed = true
        }
        if item.presentFields.contains(.project) && old.project != item.project {
            patch.project = item.project
            patch.changedFields.insert(.project)
            changed = true
        }

        if changed {
            result.toUpdate.append(patch)
        }
    }

    // Walk existing → close eligibility.
    for task in existing {
        // 1. Skip if no gh_url (manual/malformed).
        guard let url = task.ghURL, !url.isEmpty else { continue }
        // 2. Skip if still in incoming.
        guard !incomingURLs.contains(url) else { continue }
        // 3. Skip if manual (sync never closes manual rows).
        guard task.source != "manual" else { continue }
        // 4. Review-fetch incomplete protection: don't close pr_review when fetch was bad.
        if !reviewFetchOK && task.source == "pr_review" { continue }
        // 5. Partial-fetch protection (pr_review exempt; gated by step 4 instead).
        if let fetchedRepos, task.source != "pr_review" {
            let taskRepo = task.ghRepo ?? ""
            if !fetchedRepos.contains(taskRepo) { continue }
        }
        // 6. Eligible → close.
        result.toClose.append(task)
    }

    return result
}
