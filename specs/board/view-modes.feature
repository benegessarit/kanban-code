Feature: Board View Modes
  As a developer managing many Claude Code sessions
  I want to switch between kanban and list layouts
  So that I can use the presentation that fits the task at hand

  Background:
    Given the Kanban Code application is running
    And I have at least one visible card on the board

  Scenario: Switch from kanban to list view
    Given the board is shown in kanban view
    When I switch the board to list view
    Then I should see the same visible cards in a vertical list
    And the list should group cards by workflow status
    And each group should preserve the board column order

  Scenario: Selected card survives a view mode change
    Given I have selected a card on the board
    When I switch between kanban view and list view
    Then the same card should remain selected
    And the card detail inspector should continue showing that card

  Scenario: View mode persists across relaunch
    Given I switch the board to list view
    When I quit and relaunch Kanban Code
    Then the board should reopen in list view
