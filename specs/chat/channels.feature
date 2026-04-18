Feature: Chat channels for multi-agent coordination
  As a user running multiple Claude sessions in Kanban Code
  I want a Slack-like chat channel system where agents (and I) can coordinate
  So that agents running in parallel tmux sessions can broadcast, DM, and see history

  Background:
    Given Kanban Code is running
    And there is at least one card with a live tmux session

  # ── Creation ────────────────────────────────────────────────────────

  Scenario: Create a channel from the kanban UI
    When I click the "#" button in the toolbar
    Then a "Create channel" dialog appears asking for a channel name
    When I enter "general" and submit
    Then a new channel "#general" is created in ~/.kanban-code/channels/
    And the channel appears in the kanban column strip before "Backlog"
    And the channel appears in the fullscreen row above "Backlog"

  Scenario: Create a channel from the CLI
    When an agent runs `kanban channel create general`
    Then a new channel "#general" is created
    And the agent is automatically joined as a member
    And the agent's handle is derived from its tmux session name

  Scenario: Creating a channel with an existing name is rejected
    Given a channel "#general" already exists
    When an agent runs `kanban channel create general`
    Then the CLI exits non-zero with a "channel already exists" error

  # ── Handles ──────────────────────────────────────────────────────────

  Scenario: Handle is auto-generated from tmux session
    Given the agent runs inside tmux session "card-abc123def456"
    And the card has display name "viche test 1"
    When the agent runs `kanban channel join general`
    Then the agent is registered with handle "@viche_test_1"
    And the handle is stored alongside the card id in the channel membership

  Scenario: Handle disambiguation on collision
    Given channel "#general" already has member "@viche_test_1"
    And a new card also has display name "viche test 1"
    When the new card's agent joins "#general"
    Then the new agent is registered as "@viche_test_1_2"

  Scenario: Handle is truncated when too long
    Given a card has display name "an extremely long descriptive task title"
    When the agent joins a channel
    Then the assigned handle is no longer than 24 chars
    And it ends on a word boundary (no trailing underscore)

  # ── Membership ──────────────────────────────────────────────────────

  Scenario: Join and leave channels
    Given channel "#general" exists
    When an agent runs `kanban channel join general`
    Then the agent is listed in `kanban channel members general`
    When the agent runs `kanban channel leave general`
    Then the agent is no longer listed

  Scenario: Listing channels shows membership and last activity
    When an agent runs `kanban channel list`
    Then the output contains every channel with: name, member count, last message timestamp
    And channels the agent is a member of are marked as joined

  # ── Messaging ───────────────────────────────────────────────────────

  Scenario: Broadcast a message to a channel
    Given agents "@alice" and "@bob" are both members of "#general"
    And "@alice" has tmux session "card-alice"
    And "@bob" has tmux session "card-bob"
    When "@alice" runs `kanban channel send general "hello team"`
    Then a message is appended to ~/.kanban-code/channels/general.jsonl with from=@alice, body="hello team"
    And tmux session "card-bob" receives the prefixed broadcast `Message from #general @alice: hello team`
    And tmux session "card-alice" does NOT receive the broadcast (no echo back to sender)

  Scenario: Broadcast from the UI chat view
    Given I have the "#general" channel open in the kanban app
    And agents "@alice" and "@bob" are members
    When I type "standup in 5" into the chat input and press Enter
    Then the message is appended to general.jsonl with from="@user"
    And both agents' tmux sessions receive the prefixed broadcast
    And the message appears in the chat scrollback immediately

  Scenario: Sender does not receive echo
    Given "@alice" is the only human-typing agent
    When "@alice" sends a channel message
    Then "@alice"'s tmux session receives no send-keys

  # ── Direct messages ─────────────────────────────────────────────────

  Scenario: Send a DM to another agent
    Given "@alice" and "@bob" are both registered handles
    When "@alice" runs `kanban dm bob "private note"`
    Then a DM log is appended at ~/.kanban-code/channels/dm/<sorted-pair>.jsonl
    And "@bob"'s tmux session receives `DM from @alice: private note`
    And "@alice"'s session does not receive anything

  Scenario: DM history
    When "@alice" runs `kanban dm history bob`
    Then the last N DM exchanges between @alice and @bob are printed

  # ── History & catch-up ──────────────────────────────────────────────

  Scenario: Channel history on join
    Given "#general" has 20 prior messages
    When a new agent joins "#general"
    Then `kanban channel join general` prints the last 10 messages as context
    And the agent's tmux session also receives a summary banner

  Scenario: `channel history` shows last N messages
    When an agent runs `kanban channel history general -n 50`
    Then the last 50 messages are printed in chronological order
    And each line shows timestamp, @handle, and body

  # ── Presence ────────────────────────────────────────────────────────

  Scenario: Online/offline display
    Given "#general" has members @alice (live tmux) and @bob (dead tmux)
    When I open "#general" in the UI
    Then @alice is marked online (green dot)
    And @bob is marked offline (gray dot)
    And the CLI `kanban channel members general` shows the same

  Scenario: Presence updates live
    Given "#general" shows @alice as online
    When the tmux session for @alice is killed
    Then within 2 seconds the UI updates @alice to offline

  # ── Real-time UI ────────────────────────────────────────────────────

  Scenario: Chat view file-watches the channel jsonl
    Given "#general" is open in the UI
    When a new message is appended to general.jsonl by the CLI
    Then the message appears in the UI scrollback within 500ms without manual refresh

  Scenario: Chat view auto-scrolls on new message while at bottom
    Given I am scrolled to the bottom of "#general"
    When a new message arrives
    Then the scroll follows to the new bottom

  Scenario: Chat view preserves scroll position when scrolled up
    Given I am scrolled back reading history in "#general"
    When a new message arrives
    Then the scroll position does NOT jump
    And a "N new messages" pill appears near the bottom

  # ── Layout ──────────────────────────────────────────────────────────

  Scenario: Kanban mode puts channels in a column before Backlog
    Given at least one channel exists
    When the board is in kanban mode
    Then a "Channels" column is rendered as the leftmost visible column
    And each channel appears as a card-sized tile with "#name" and "6m ago" style timestamp
    When zero channels exist
    Then the "Channels" column is hidden

  Scenario: Fullscreen mode puts channels in a row above Backlog
    When the board is in fullscreen/list mode
    Then a "Channels" section is rendered above the "Backlog" section
    And each channel renders like a compact card with "#name" and "6m ago" timestamp

  # ── CLI auto-detect ─────────────────────────────────────────────────

  Scenario: CLI auto-detects the calling card via tmux
    Given an agent is inside tmux session linked to card "card_xyz"
    When the agent runs `kanban channel send general "hello"` without --as
    Then the CLI resolves the handle from $TMUX / the current tmux session name
    And the message's `from` is that handle

  Scenario: CLI --as flag overrides auto-detect
    When an agent runs `kanban channel send general --as alice "hello"`
    Then the `from` handle is "@alice"

  # ── Skill / onboarding ──────────────────────────────────────────────

  Scenario: Onboarding installs the kanban-code skill
    Given a first-time install
    When the onboarding wizard completes
    Then ~/.claude/skills/kanban-code exists (symlink to the repo skill)
    And the skill teaches agents how to discover / join / send in channels
