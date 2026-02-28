Feature: Project Management (CRUD)
  As a developer working across multiple repositories
  I want to add, edit, and remove projects in Kanban
  So that I can organize my Claude Code sessions by project

  Background:
    Given the Kanban application is running

  # ── Adding Projects ──

  Scenario: Adding a project via Settings
    When I open Settings → Projects tab
    And I click "Add Project..."
    Then a folder picker (NSOpenPanel) should appear
    When I select ~/Projects/remote/langwatch-saas
    Then a project edit sheet should open with:
      | Field        | Value                            |
      | name         | langwatch-saas                   |
      | path         | ~/Projects/remote/langwatch-saas |
      | visible      | true                             |
      | githubFilter | (empty)                          |
    And I can configure the name, GitHub filter, etc. before saving
    When I click "Add"
    Then the project should be saved to ~/.kanban/settings.json
    And it should appear in the Kanban menu project list

  Scenario: Adding a project via Kanban menu folder picker
    When I click the Kanban menu in the toolbar
    And I click "Add from folder..."
    Then a folder picker should appear
    When I select a folder
    Then the project should be added
    And the view should immediately switch to that project

  Scenario: Adding a project via Kanban menu text input
    When I click the Kanban menu in the toolbar
    And I click "Add from path..."
    Then a text input sheet should appear
    When I type "~/Projects/my-repo" and click "Add"
    Then the project should be added with path expanded from tilde
    And the view should immediately switch to that project

  Scenario: Auto-switch to newly created project
    Given I am viewing "All Projects"
    When I add a new project via any method
    Then the board should immediately switch to show that project
    And the Kanban menu should show the new project as selected

  Scenario: Project auto-names from folder
    When I add a project at ~/Projects/remote/scenario
    Then the name should default to "scenario"
    And I should be able to rename it in the edit sheet

  # ── Editing Projects ──

  Scenario: Renaming a project
    Given a project "langwatch-saas" exists
    When I edit its name to "LangWatch"
    Then the Kanban menu should show "LangWatch"
    And the settings file should be updated

  Scenario: Setting repoRoot override
    Given a project at ~/Projects/remote/langwatch-saas/langwatch
    When I set repoRoot to ~/Projects/remote/langwatch-saas
    Then PRs and worktrees should be resolved against the parent repo

  Scenario: Configuring per-project GitHub filter
    Given a project "LangWatch" exists
    When I set its githubFilter to "assignee:@me repo:langwatch/langwatch is:open"
    Then only matching issues should appear in this project's backlog
    And the global view should also include these issues

  Scenario: Toggling project visibility
    Given a project "SideProject" exists with visible=true
    When I toggle its visibility to false
    Then it should not appear in the Kanban menu project list
    But it should still appear in Settings for management
    And its sessions should still appear in the global view

  # ── Deleting Projects ──

  Scenario: Deleting a project
    Given a project "OldProject" exists
    When I click the delete button on it in Settings
    Then the project should be removed from settings
    And it should disappear from the Kanban menu
    And its sessions should still appear in the global view

  # ── Validation ──

  Scenario: Adding a duplicate project
    Given a project at ~/Projects/remote/kanban already exists
    When I try to add the same path again
    Then it should be rejected: "Project already configured"
