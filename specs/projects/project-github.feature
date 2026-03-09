Feature: Per-Project GitHub Integration
  As a developer with multiple repos
  I want each project to have its own GitHub issue filter
  So that each project's backlog shows only relevant issues

  Background:
    Given the Kanban Code application is running
    And `gh` CLI is installed and authenticated
    And I have configured projects:
      | Name       | Path                              | githubFilter                                        |
      | LangWatch  | ~/Projects/remote/langwatch-saas  | assignee:@me repo:langwatch/langwatch is:open       |
      | Scenario   | ~/Projects/remote/scenario        | assignee:@me repo:langwatch/scenario is:open        |
      | SideProject| ~/Projects/personal/blog          | (none)                                              |

  # ── Per-Project Filters ──

  Scenario: Project view shows only its GitHub issues
    When I select the "LangWatch" project view
    Then the backlog should fetch issues using LangWatch's githubFilter
    And only issues from langwatch/langwatch should appear
    And no issues from langwatch/scenario should appear

  Scenario: Different project, different issues
    When I select the "Scenario" project view
    Then the backlog should fetch issues using Scenario's githubFilter
    And only issues from langwatch/scenario should appear

  Scenario: Project without filter inherits default
    Given SideProject has no githubFilter configured
    And the global default filter is "assignee:@me is:open"
    When I select the "SideProject" project view
    Then the backlog should use the global default filter

  # ── Global View ──

  Scenario: Global view combines all project filters
    When I select "All Projects"
    Then the backlog should fetch issues from ALL project filters
    And issues from langwatch/langwatch AND langwatch/scenario should appear
    And each issue card should show which repo it belongs to

  Scenario: Global view deduplicates issues
    Given the same issue appears in multiple project filters
    Then it should only appear once in the global backlog

  # ── Configuration UI ──

  Scenario: Editing a project's GitHub filter
    When I open Settings → Projects
    And I edit a project
    Then a "GitHub Issues" section should appear in the edit sheet
    And it should have a filter text field with monospace font
    And a hint should explain: "Uses `gh search issues` syntax"

  Scenario: Testing a GitHub filter
    When I type a filter in the GitHub Issues field
    And I click "Test filter"
    Then it should run `gh search issues --limit 100 <filter>`
    And show the result count (e.g. "12 issues found")
    And a spinner should show while the test is running

  Scenario: Clearing a project's GitHub filter
    When I clear a project's githubFilter field
    Then the project should fall back to the global default filter

  Scenario: Filter uses raw gh search syntax
    Then the githubFilter field should accept any valid `gh search issues` syntax
    And examples: "assignee:@me repo:org/repo is:open label:bug"
