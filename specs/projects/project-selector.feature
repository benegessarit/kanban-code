Feature: Project Selector (Kanban Code Menu)
  As a developer managing multiple projects
  I want to quickly switch between project views
  So that I can focus on one project or see everything at once

  Background:
    Given the Kanban Code application is running
    And I have configured projects:
      | Name       | Path                                  |
      | LangWatch  | ~/Projects/remote/langwatch-saas      |
      | Scenario   | ~/Projects/remote/scenario            |
      | Kanban Code     | ~/Projects/remote/kanban              |

  # ── Menu Structure ──

  Scenario: Kanban Code menu shows project selector
    When I click the Kanban Code menu in the toolbar
    Then I should see:
      | Item              | Type       |
      | ✓ All Projects    | selectable |
      | LangWatch         | selectable |
      | Scenario          | selectable |
      | Kanban Code            | selectable |
      | ─────────         | separator  |
      | Add New Project...| action     |
      | Settings...       | action     |
    And "All Projects" should be checked (default)

  Scenario: Menu label shows current selection
    Given I'm viewing "All Projects"
    Then the toolbar menu label should say "All Projects"
    When I switch to "LangWatch"
    Then the toolbar menu label should say "LangWatch"

  Scenario: Card count badges in menu
    Given LangWatch has 3 active sessions
    And Scenario has 1 active session
    When I open the Kanban Code menu
    Then each project should show its card count
    And "All Projects" should show the combined count (4)

  # ── Switching Views ──

  Scenario: Switching to a project view
    When I select "LangWatch" from the Kanban Code menu
    Then the board should immediately filter to only LangWatch sessions
    And the backlog should show only LangWatch's GitHub issues
    And the column counts should update

  Scenario: Switching back to global view
    Given I'm viewing "LangWatch"
    When I select "All Projects"
    Then sessions from all projects should appear
    And all GitHub issues should be combined

  Scenario: Switching is instant
    When I switch between project views
    Then filtering should happen instantly (client-side filter)
    And no network requests should be made
    And no loading spinner should appear

  # ── Keyboard Shortcuts ──

  Scenario: Keyboard shortcut for All Projects
    When I press ⌘1
    Then the view should switch to "All Projects"

  Scenario: Keyboard shortcuts for projects
    When I press ⌘2
    Then the view should switch to the first configured project (LangWatch)
    When I press ⌘3
    Then the view should switch to the second project (Scenario)

  Scenario: Shortcuts match project order
    Given projects are ordered: LangWatch, Scenario, Kanban Code
    Then ⌘2=LangWatch, ⌘3=Scenario, ⌘4=Kanban Code
    And ⌘5 through ⌘9 should do nothing (no project at that position)

  # ── Persistence ──

  Scenario: Selected project persists across restarts
    Given I selected "Scenario" as my project view
    When I quit and relaunch Kanban Code
    Then "Scenario" should still be selected
    And the board should show only Scenario sessions

  Scenario: Selected project removed from settings
    Given I selected "OldProject" as my view
    When someone removes "OldProject" from settings.json
    Then the view should fall back to "All Projects"
