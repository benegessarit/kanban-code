Feature: Project Auto-Discovery
  As a developer who may not have configured all projects
  I want Kanban to detect unconfigured project paths from my sessions
  So that I can easily add them to my project list

  Background:
    Given the Kanban application is running
    And I have configured projects:
      | Name       | Path                              |
      | LangWatch  | ~/Projects/remote/langwatch-saas  |

  # ── Discovery ──

  Scenario: Detecting unconfigured project paths
    Given Claude sessions exist for:
      | Path                              |
      | ~/Projects/remote/langwatch-saas  |
      | ~/Projects/remote/scenario        |
      | ~/Projects/remote/kanban          |
    When Kanban refreshes the board
    Then it should detect 2 unconfigured paths:
      | Path                              |
      | ~/Projects/remote/scenario        |
      | ~/Projects/remote/kanban          |

  Scenario: Discovered projects appear in Kanban menu
    Given there are unconfigured project paths
    When I open the Kanban project menu
    Then a "Discovered" section should appear after configured projects
    And it should list the unconfigured paths by folder name
    And each item should have a folder-badge-plus icon

  Scenario: Adding a discovered project from the menu
    When I click a discovered project in the Kanban menu
    Then it should be added to configured projects with default name from folder
    And the view should immediately switch to that project
    And it should disappear from the "Discovered" section

  # ── Path Grouping ──

  Scenario: Sessions in subdirectories group to parent
    Given sessions exist at:
      | Path                                          |
      | ~/Projects/remote/langwatch-saas/langwatch    |
      | ~/Projects/remote/langwatch-saas/api          |
    And ~/Projects/remote/langwatch-saas is already configured
    Then these sessions should NOT appear as unconfigured
    Because they are subdirectories of a configured project

  Scenario: Sessions in unrelated paths
    Given sessions exist at:
      | Path                       |
      | ~/Projects/personal/blog   |
      | ~/Projects/personal/tools  |
    Then both should appear as unconfigured project suggestions

  # ── Menu Behavior ──

  Scenario: Discovery section only shows when there are unconfigured paths
    Given all session paths match configured projects
    Then no "Discovered" section should appear in the menu

  Scenario: Discovery section limits to 8 items
    Given there are 12 unconfigured project paths
    When I open the Kanban menu
    Then the "Discovered" section should show at most 8 items

  # ── Edge Cases ──

  Scenario: Session with nil project path
    Given a session exists with no project path
    Then it should not count as an unconfigured project
    And it should still appear in the global view
