Feature: Manual Task Creation
  As a developer
  I want to add tasks manually to the Kanban backlog
  So that I can track work not tied to GitHub issues

  Background:
    Given the Kanban application is running

  Scenario: Creating a manual task
    When I click the "+" button or press ⌘N
    Then a task creation form should appear
    And I should be able to enter:
      | Field       | Required | Description                              |
      | Title       | yes      | Short description of the task            |
      | Description | no       | Detailed requirements for Claude         |
      | Project     | yes      | Dropdown from configured projects        |
    And the Project field should be a dropdown picker, not free text

  Scenario: Project defaults to current selection
    Given I'm viewing the "LangWatch" project
    When I create a new task
    Then the project dropdown should default to "LangWatch"

  Scenario: Quick-create with just a title
    When I type a title and press Enter
    Then the task should be created in the Backlog
    And the project should default to the currently selected project

  Scenario: Custom project path
    When I need a project path not in the configured list
    Then I should be able to select "Custom path..." from the dropdown
    And type a path manually

  Scenario: Start immediately checkbox
    When the task creation form appears
    Then a "Start immediately" checkbox should be visible
    And it should be checked by default
    When I create a task with "Start immediately" checked
    Then the task should be created in Backlog AND immediately launched
    And a tmux session should be created with Claude running

  Scenario: Start immediately preference persists
    Given I unchecked "Start immediately" on the last task I created
    When I open the task creation form again
    Then "Start immediately" should still be unchecked
    Because the preference is saved via @AppStorage

  Scenario: Create without starting
    When I uncheck "Start immediately" and create a task
    Then the task should appear in Backlog
    But no tmux session should be created
    And I can start it later by clicking the Start button on the card

  Scenario: Starting a manual task
    Given a manual task "Refactor database layer" exists in Backlog
    When I click "Start"
    Then Claude should be launched with `claude --worktree`
    And the worktree should get a random-words name (e.g., "fluffy-walrus")
    And the task description should be sent as the prompt

  Scenario: Manual task with specific project
    Given a manual task is linked to project "~/Projects/remote/langwatch-saas"
    When I start the task
    Then Claude should be launched in that project directory
    And `claude --worktree` should create a worktree in that repo

  Scenario: Editing a manual task
    Given a manual task exists in the Backlog
    When I click on the card to open it
    Then I should be able to edit the title and description
    And changes should save automatically

  Scenario: Deleting a manual task
    Given a manual task exists in the Backlog
    When I right-click and select "Delete"
    Then a confirmation dialog should appear
    And on confirm, the task should be permanently removed

  Scenario: Converting a manual task to track a GitHub issue
    Given a manual task is in progress
    And the Claude session created a PR linked to issue #456
    When the background process detects the link
    Then the card should be enriched with the GitHub issue metadata
    And it should behave like a GitHub-sourced card from now on
