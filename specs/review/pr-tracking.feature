Feature: PR Tracking
  As a developer with Claude Code creating PRs
  I want to see PR status on the Kanban board
  So that I know which PRs need attention

  Background:
    Given the Kanban application is running
    And `gh` CLI is installed and authenticated

  # ── PR Discovery ──
  # (Learned from git-orchard: batch fetch, branch name as key)

  Scenario: Discovering PRs via branch name
    Given a session is linked to worktree on branch "feat/issue-123"
    When the background process fetches PRs via `gh pr list`
    Then it should match the PR by headRefName == "feat/issue-123"
    And the PR should be linked to the session card

  Scenario: Batch PR fetching
    When the background process checks for PRs
    Then it should run a single `gh pr list --state all --json headRefName,number,state,title,url,reviewDecision --limit 100`
    And cache the result as Map<branchName, PrInfo>
    And NOT make individual API calls per session

  Scenario: PR enrichment via GraphQL
    Given basic PR info has been fetched
    When enrichment runs for open PRs
    Then a single GraphQL query should fetch for all open PRs:
      | Field                          | Purpose                          |
      | body                           | PR description for markdown view |
      | reviewThreads                  | Count unresolved review threads  |
      | reviews(states: APPROVED)      | Count of approvals               |
      | statusCheckRollup.state        | Aggregate CI check status        |
      | statusCheckRollup.contexts     | Individual check run names + status + conclusion |
    And the query should use field aliases (pr0, pr1, pr2...)
    And this should be a non-blocking background operation
    And results should be synced to PRLink (title, status, checkRuns, approvalCount, unresolvedThreads)
    But PR body should NOT be synced via orchestrator (lazy-loaded on demand)

  # ── PR Status Display ──

  Scenario: PR status badge on card
    Given a card has a linked PR
    Then the card should show a status badge:
      | PR State            | Icon | Color   | Label              |
      | CI failing          | ✕    | red     | failing            |
      | Unresolved threads  | ●    | yellow  | unresolved         |
      | Changes requested   | ✎    | red     | changes requested  |
      | Review needed       | ○    | yellow  | review needed      |
      | CI pending          | ○    | yellow  | pending            |
      | Approved            | ✓    | green   | ready              |
      | Merged              | ✓    | magenta | merged             |
      | Closed              | ✕    | red     | closed             |

  Scenario: PR status priority ordering
    Given a PR has both "CI failing" and "changes requested"
    Then the badge should show "failing" (highest priority)
    Because the priority order is: failing > unresolved > changes_requested > review_needed > pending_ci > approved

  Scenario: PR link opens in browser
    Given a card has a linked PR #42
    When I click the PR badge
    Then the PR should open in the default browser
    And the URL should be the GitHub PR URL

  # ── PR Detail Tab ──

  Scenario: PR tab header
    Given a card has prLink with number 42, title "Fix login flow", and status "approved"
    When I open the Pull Request tab
    Then the header should show "Fix login flow" as title
    And "#42" as the PR number
    And a status badge (reusing PRBadge component)
    And an "Open in Browser" button

  Scenario: PR tab shows individual CI check runs
    Given a PR has the following check runs:
      | Name            | Status    | Conclusion |
      | build           | completed | success    |
      | lint            | completed | failure    |
      | deploy-preview  | in_progress | (none)   |
    When I view the PR tab
    Then each check should display with:
      | Check           | Icon                | Color  |
      | build           | checkmark.circle    | green  |
      | lint            | xmark.circle        | red    |
      | deploy-preview  | clock               | yellow |

  Scenario: PR tab shows approval and comment counts
    Given a PR has 2 approvals and 3 unresolved review threads
    When I view the PR tab
    Then I should see "2 approvals" with a green checkmark icon
    And "3 unresolved" with an orange comment icon

  Scenario: PR body is lazy-loaded on tab open
    Given a card has prLink but the PR body has not been fetched yet
    When I switch to the Pull Request tab
    Then the body should be fetched via `gh pr view {number} --json body`
    And a spinner should show while loading
    And the body should be rendered as GitHub-flavored markdown once loaded

  Scenario: PR body is cached per card selection
    Given I already viewed the PR body for card A
    When I switch away from the PR tab and back
    Then the body should display immediately without re-fetching
    When I select a different card B
    Then the PR body cache should reset for the new card

  # ── PR Reviews ──

  Scenario: Unresolved thread count on PR tab
    Given a PR has 3 unresolved review threads
    Then the PR tab should show "3 unresolved" indicator with orange styling

  # ── CI Checks (Card Level) ──

  Scenario: CI check status badge on card
    Given a PR has GitHub Actions checks
    Then the card should show a CI indicator:
      | All passing     | Green checkmark  |
      | Some failing    | Red X            |
      | Some pending    | Yellow circle    |
      | No checks       | No indicator     |

  Scenario: CI check handles both CheckRun and StatusContext
    Given a PR has both CheckRun (GitHub Actions) and StatusContext (commit status)
    Then both types should be aggregated
    And any failure from either type should show as "failing"

  # ── Edge Cases ──

  Scenario: PR from sub-repo
    Given a project with repoRoot "~/Projects/remote/langwatch-saas"
    And code changes are in subrepo "~/Projects/remote/langwatch-saas/langwatch"
    When a PR is created on "langwatch-saas"
    Then the PR should still be discovered
    Because the worktree branch is on the repoRoot

  Scenario: Multiple PRs for same branch
    Given branch "feat/login" has 2 PRs (one closed, one open)
    Then the open PR should take priority
    And the closed PR should be ignored in the active display

  Scenario: gh CLI unavailable
    Given `gh` is not installed
    Then PR tracking should be disabled gracefully
    And cards should show "Install gh for PR tracking"
    And all other Kanban features should work normally
