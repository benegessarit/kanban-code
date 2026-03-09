Feature: Git Worktrees as Card Source
  As a developer using git worktrees for Claude Code sessions
  I want every worktree to appear as a card on the Kanban Code board
  So that I can track the lifecycle of work branches (worktree → PR → merge → cleanup)

  Background:
    Given the Kanban Code application is running
    And the user has configured at least one project
    And the project has a git repository with worktrees

  # ── Discovery ──

  Scenario: Worktrees discovered from configured project repos
    Given project "LangWatch" has effectiveRepoRoot "/Users/me/Projects/langwatch"
    And the repo has worktrees:
      | Path                                          | Branch                        |
      | /Users/me/Projects/langwatch                  | main                          |
      | .../langwatch/.worktrees/feat-encrypt-keys     | feat/encrypt-provider-keys    |
      | .../langwatch/.worktrees/fix-auto-shutdown     | fix/auto-shutdown-signals     |
    When the board refreshes
    Then cards should be created for "feat/encrypt-provider-keys" and "fix/auto-shutdown-signals"
    And no card should be created for "main" (filtered out)
    And no card should be created for bare worktrees

  Scenario: Worktree cards include project path
    Given a worktree is discovered in repo "/Users/me/Projects/langwatch"
    When a card is created for it
    Then the card's projectPath should be set to "/Users/me/Projects/langwatch"
    And the card should appear when filtering by that project

  Scenario: Multiple projects scanned for worktrees
    Given projects are configured:
      | Path                                    |
      | /Users/me/Projects/langwatch            |
      | /Users/me/Projects/scenario             |
    When the board refreshes
    Then worktrees from BOTH repos should be discovered
    And cards should appear under their respective project filters

  # ── 1:1 Mapping ──

  Scenario: One card per worktree branch
    Given a worktree exists with branch "feat/login"
    When the board refreshes multiple times
    Then exactly one card should exist for branch "feat/login"
    And it should not be duplicated on subsequent refreshes

  Scenario: Session on same branch merges with worktree card
    Given a worktree card exists for branch "feat/login" (no session)
    When a Claude session is discovered with gitBranch = "feat/login"
    Then the session should be linked to the EXISTING worktree card
    And the card should gain a sessionLink
    And no orphan worktree card should be created
    And the card label should change from "WORKTREE" to "SESSION"

  Scenario: Session discovered first, worktree discovered later
    Given a session card exists with gitBranch = "feat/login" (no worktreeLink)
    When the worktree scan discovers a worktree with branch "feat/login"
    Then the worktreeLink should be SET on the existing session card
    And no orphan worktree card should be created

  Scenario: Two sessions on the same worktree branch
    Given a session "s1" exists with worktreeLink.branch = "feat/login"
    And a session "s2" also exists with gitBranch = "feat/login"
    When the worktree scan discovers the worktree for "feat/login"
    Then both session cards should have worktreeLink.branch = "feat/login"
    And both should be separate cards (two sessions, one branch)

  # ── PR Matching ──

  Scenario: Worktree card gets PR linked automatically
    Given a worktree card exists with branch "feat/encrypt-provider-keys"
    And a merged PR exists with headRefName = "feat/encrypt-provider-keys"
    When the board refreshes with PR data
    Then the card's prLinks should contain the merged PR
    And the card should be in the "Done" column

  Scenario: Worktree with merged PR appears in Done
    Given worktrees exist with branches that all have merged PRs
    When the board refreshes
    Then those worktree cards should appear in the "Done" column
    And the cards should show the PR badge with merged status

  # ── Worktree Cleanup ──

  Scenario: Cleanup worktree button on worktree cards
    Given a worktree card exists for branch "feat/encrypt-keys"
    When I open the card detail
    Then a "Remove Worktree" button should appear in the actions menu
    When I click "Remove Worktree"
    Then `git worktree remove` should run for that worktree path
    And the worktreeLink should be cleared from the card

  Scenario: Dead worktree link is cleaned up automatically
    Given a card has worktreeLink.path = "/path/to/deleted-worktree"
    And the path no longer exists on disk (worktree was deleted externally)
    When the board refreshes with worktree scanning enabled
    Then the worktreeLink should be cleared from the card
    Unless manualOverrides.worktreePath is true
