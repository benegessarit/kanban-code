#!/usr/bin/env node
import { Command } from "commander";
import { execSync } from "node:child_process";
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import {
  readLinks,
  readSettings,
  listTmuxSessions,
  captureTmuxPane,
  sendTmuxKeys,
  pasteTmuxPrompt,
  sendTmuxEscape,
  readLastTranscriptTurns,
  readSessionContext,
  filterActiveCards,
  filterByColumn,
  filterByProject,
  findCard,
  toCardSummary,
  toCardDetail,
} from "./data.js";
import {
  formatCardList,
  formatCardDetail,
  formatTmuxSessions,
} from "./format.js";
import type { KanbanColumn } from "./types.js";

const program = new Command();

program
  .name("kanban")
  .description("Kanban Code CLI — inspect cards, sessions, and orchestrate agents")
  .version("0.1.0");

// ── Helper: output as JSON or pretty ─────────────────────────────────

function output(data: unknown, opts: { json?: boolean }) {
  if (opts.json) {
    process.stdout.write(JSON.stringify(data, null, 2) + "\n");
  } else if (typeof data === "string") {
    process.stdout.write(data + "\n");
  } else {
    process.stdout.write(JSON.stringify(data, null, 2) + "\n");
  }
}

// ── kanban open [path] ───────────────────────────────────────────────

program
  .command("open")
  .description("Open a project in Kanban Code app")
  .argument("[path]", "Project path (defaults to current directory)", ".")
  .action((path: string) => {
    const resolved = resolve(path);
    const kanbanDir = join(homedir(), ".kanban-code");
    mkdirSync(kanbanDir, { recursive: true });
    writeFileSync(join(kanbanDir, "open-project"), resolved);
    try {
      execSync('open -a "KanbanCode"');
    } catch {
      console.error("Failed to open KanbanCode app");
      process.exit(1);
    }
  });

// Also support bare `kanban .` and `kanban /path` (no subcommand)
// Handled via default command at the bottom

// ── kanban list ──────────────────────────────────────────────────────

program
  .command("list")
  .alias("ls")
  .description("List cards grouped by column")
  .option("-c, --column <column>", "Filter by column (in_progress, requires_attention, in_review, done, backlog)")
  .option("-p, --project <path>", "Filter by project path")
  .option("-a, --all", "Include all_sessions (hidden by default)")
  .option("--with-last-message", "Include last transcript message (slower)")
  .option("-j, --json", "Output as JSON")
  .action((opts) => {
    let links = readLinks();
    const tmux = listTmuxSessions();
    const liveTmux = new Set(tmux.map((t) => t.name));

    if (opts.column) {
      links = filterByColumn(links, opts.column as KanbanColumn);
    } else if (!opts.all) {
      links = filterActiveCards(links);
    }

    if (opts.project) {
      const resolved = resolve(opts.project);
      links = filterByProject(links, resolved);
    }

    // Sort: in_progress first, then by lastActivity desc
    const colOrder: Record<string, number> = {
      in_progress: 0,
      requires_attention: 1,
      in_review: 2,
      done: 3,
      backlog: 4,
      all_sessions: 5,
    };
    links.sort((a, b) => {
      const ca = colOrder[a.column] ?? 9;
      const cb = colOrder[b.column] ?? 9;
      if (ca !== cb) return ca - cb;
      const ta = a.lastActivity || a.updatedAt;
      const tb = b.lastActivity || b.updatedAt;
      return tb.localeCompare(ta);
    });

    const summaries = links.map((l) => {
      const s = toCardSummary(l, liveTmux);
      if (opts.withLastMessage && l.sessionLink?.sessionPath) {
        const turns = readLastTranscriptTurns(l.sessionLink.sessionPath, 1);
        if (turns.length) s.lastMessage = turns[turns.length - 1].text;
      }
      return s;
    });

    if (opts.json) {
      output(summaries, { json: true });
    } else {
      output(formatCardList(summaries), { json: false });
    }
  });

// ── kanban show <card> ───────────────────────────────────────────────

program
  .command("show")
  .description("Show detailed card information")
  .argument("<card>", "Card ID, ID prefix, or name search")
  .option("-t, --transcript <n>", "Number of transcript turns to show", "5")
  .option("-j, --json", "Output as JSON")
  .action((cardQuery: string, opts) => {
    const links = readLinks();
    const card = findCard(links, cardQuery);
    if (!card) {
      console.error(`Card not found: ${cardQuery}`);
      process.exit(1);
    }

    const tmux = listTmuxSessions();
    const liveTmux = new Set(tmux.map((t) => t.name));
    const detail = toCardDetail(card, liveTmux, parseInt(opts.transcript));

    if (opts.json) {
      output(detail, { json: true });
    } else {
      output(formatCardDetail(detail), { json: false });
    }
  });

// ── kanban sessions ──────────────────────────────────────────────────

program
  .command("sessions")
  .description("List all tmux sessions with card associations")
  .option("-j, --json", "Output as JSON")
  .action((opts) => {
    const tmux = listTmuxSessions();
    const links = readLinks();

    // Build tmux→card map
    const tmuxToCard = new Map<string, string>();
    for (const link of links) {
      if (link.tmuxLink?.sessionName) {
        tmuxToCard.set(link.tmuxLink.sessionName, link.id);
      }
      for (const extra of link.tmuxLink?.extraSessions || []) {
        tmuxToCard.set(extra, link.id);
      }
    }

    const enriched = tmux.map((s) => ({
      ...s,
      cardId: tmuxToCard.get(s.name) || null,
    }));

    if (opts.json) {
      output(enriched, { json: true });
    } else {
      if (!enriched.length) {
        output("No tmux sessions running.", { json: false });
        return;
      }
      const lines = ["Tmux Sessions:", ""];
      for (const s of enriched) {
        const att = s.attached ? " (attached)" : "";
        const card = s.cardId ? ` -> ${s.cardId}` : "";
        lines.push(`  ${s.name}${att}${card}`);
        if (s.path) lines.push(`    path: ${s.path}`);
      }
      output(lines.join("\n"), { json: false });
    }
  });

// ── kanban capture <card> ────────────────────────────────────────────

program
  .command("capture")
  .description("Capture current terminal output for a card")
  .argument("<card>", "Card ID, ID prefix, or name search")
  .option("-j, --json", "Output as JSON")
  .action((cardQuery: string, opts) => {
    const links = readLinks();
    const card = findCard(links, cardQuery);
    if (!card) {
      console.error(`Card not found: ${cardQuery}`);
      process.exit(1);
    }
    if (!card.tmuxLink?.sessionName) {
      console.error(`Card has no tmux session: ${card.id}`);
      process.exit(1);
    }

    const pane = captureTmuxPane(card.tmuxLink.sessionName);

    if (opts.json) {
      output(
        { cardId: card.id, tmuxSession: card.tmuxLink.sessionName, output: pane },
        { json: true }
      );
    } else {
      output(pane, { json: false });
    }
  });

// ── kanban send <card> <message> ─────────────────────────────────────

program
  .command("send")
  .description("Send a message to a card's tmux session (paste + Enter)")
  .argument("<card>", "Card ID, ID prefix, or name search")
  .argument("<message>", "Message to send")
  .option("--keys", "Use send-keys instead of paste-buffer (for short single-line)")
  .option("-j, --json", "Output as JSON")
  .action((cardQuery: string, message: string, opts) => {
    const links = readLinks();
    const card = findCard(links, cardQuery);
    if (!card) {
      console.error(`Card not found: ${cardQuery}`);
      process.exit(1);
    }
    if (!card.tmuxLink?.sessionName) {
      console.error(`Card has no tmux session: ${card.id}`);
      process.exit(1);
    }

    const result = opts.keys
      ? sendTmuxKeys(card.tmuxLink.sessionName, message)
      : pasteTmuxPrompt(card.tmuxLink.sessionName, message);

    if (opts.json) {
      output(
        {
          cardId: card.id,
          tmuxSession: card.tmuxLink.sessionName,
          message,
          ...result,
        },
        { json: true }
      );
    } else {
      if (result.ok) {
        console.log(`Sent to ${card.tmuxLink.sessionName}`);
      } else {
        console.error(`Failed: ${result.error}`);
        process.exit(1);
      }
    }
  });

// ── kanban interrupt <card> ──────────────────────────────────────────

program
  .command("interrupt")
  .description("Send Escape to interrupt the assistant in a card's session")
  .argument("<card>", "Card ID, ID prefix, or name search")
  .option("-j, --json", "Output as JSON")
  .action((cardQuery: string, opts) => {
    const links = readLinks();
    const card = findCard(links, cardQuery);
    if (!card) {
      console.error(`Card not found: ${cardQuery}`);
      process.exit(1);
    }
    if (!card.tmuxLink?.sessionName) {
      console.error(`Card has no tmux session: ${card.id}`);
      process.exit(1);
    }

    const result = sendTmuxEscape(card.tmuxLink.sessionName);

    if (opts.json) {
      output(
        { cardId: card.id, tmuxSession: card.tmuxLink.sessionName, ...result },
        { json: true }
      );
    } else {
      if (result.ok) {
        console.log(`Interrupted ${card.tmuxLink.sessionName}`);
      } else {
        console.error(`Failed: ${result.error}`);
        process.exit(1);
      }
    }
  });

// ── kanban transcript <card> ─────────────────────────────────────────

program
  .command("transcript")
  .description("Show recent transcript for a card's session")
  .argument("<card>", "Card ID, ID prefix, or name search")
  .option("-n, --turns <n>", "Number of turns to show", "10")
  .option("-j, --json", "Output as JSON")
  .action((cardQuery: string, opts) => {
    const links = readLinks();
    const card = findCard(links, cardQuery);
    if (!card) {
      console.error(`Card not found: ${cardQuery}`);
      process.exit(1);
    }
    if (!card.sessionLink?.sessionPath) {
      console.error(`Card has no session transcript: ${card.id}`);
      process.exit(1);
    }

    const turns = readLastTranscriptTurns(
      card.sessionLink.sessionPath,
      parseInt(opts.turns)
    );

    if (opts.json) {
      output(turns, { json: true });
    } else {
      if (!turns.length) {
        console.log("No transcript turns found.");
        return;
      }
      for (const turn of turns) {
        const prefix = turn.role === "user" ? "YOU" : " AI";
        const text = turn.text.slice(0, 300);
        console.log(`[${prefix}] ${text}`);
        console.log("");
      }
    }
  });

// ── kanban projects ──────────────────────────────────────────────────

program
  .command("projects")
  .description("List configured projects")
  .option("-j, --json", "Output as JSON")
  .action((opts) => {
    const settings = readSettings();

    if (opts.json) {
      output(settings.projects, { json: true });
    } else {
      if (!settings.projects.length) {
        console.log("No projects configured.");
        return;
      }
      for (const p of settings.projects) {
        const vis = p.visible ? "" : " (hidden)";
        console.log(`  ${p.name}${vis}`);
        console.log(`    ${p.path}`);
      }
    }
  });

// ── kanban status ────────────────────────────────────────────────────

program
  .command("status")
  .description("Quick overview of active work across all projects")
  .option("-j, --json", "Output as JSON")
  .action((opts) => {
    const links = readLinks();
    const tmux = listTmuxSessions();
    const liveTmux = new Set(tmux.map((t) => t.name));
    const active = filterActiveCards(links);

    const byColumn: Record<string, number> = {};
    let aliveCount = 0;
    let withPR = 0;
    let queued = 0;
    let totalInputTokens = 0;
    let totalOutputTokens = 0;
    let totalCost = 0;

    for (const link of active) {
      byColumn[link.column] = (byColumn[link.column] || 0) + 1;
      if (link.tmuxLink?.sessionName && liveTmux.has(link.tmuxLink.sessionName))
        aliveCount++;
      if (link.prLinks?.length) withPR++;
      if (link.queuedPrompts?.length) queued += link.queuedPrompts.length;
      if (link.sessionLink?.sessionId) {
        const ctx = readSessionContext(link.sessionLink.sessionId);
        if (ctx) {
          totalInputTokens += ctx.totalInputTokens;
          totalOutputTokens += ctx.totalOutputTokens;
          totalCost += ctx.totalCostUsd;
        }
      }
    }

    const summary = {
      totalActive: active.length,
      byColumn,
      liveTerminals: aliveCount,
      totalTmuxSessions: tmux.length,
      cardsWithPRs: withPR,
      queuedPrompts: queued,
      tokens: {
        input: totalInputTokens,
        output: totalOutputTokens,
        total: totalInputTokens + totalOutputTokens,
        cost: Math.round(totalCost * 100) / 100,
      },
    };

    if (opts.json) {
      output(summary, { json: true });
    } else {
      console.log(`Active cards: ${summary.totalActive}`);
      for (const [col, count] of Object.entries(byColumn)) {
        console.log(`  ${col}: ${count}`);
      }
      console.log(`Live terminals: ${aliveCount} / ${tmux.length} tmux sessions`);
      console.log(`Cards with PRs: ${withPR}`);
      if (queued) console.log(`Queued prompts: ${queued}`);
      const tok = summary.tokens;
      if (tok.total > 0) {
        const fmt = (n: number) =>
          n >= 1_000_000
            ? `${(n / 1_000_000).toFixed(1)}M`
            : n >= 1_000
              ? `${(n / 1_000).toFixed(0)}k`
              : `${n}`;
        console.log(
          `Tokens: ${fmt(tok.input)} in / ${fmt(tok.output)} out (${fmt(tok.total)} total) — $${tok.cost.toFixed(2)}`
        );
      }
    }
  });

// ── Default: kanban [path] opens the app ─────────────────────────────

// Handle the case where user runs `kanban .` or `kanban /some/path`
// without a subcommand — this is the original bash script behavior
program
  .argument("[path]", "Project path to open (defaults to current directory)")
  .action((path: string | undefined, _opts, cmd) => {
    // Only trigger if no subcommand was matched
    if (cmd.args.length === 0 && !path) {
      // Bare `kanban` with no args — show help
      program.help();
      return;
    }
    // If path looks like a directory, open it
    if (path && !program.commands.some((c) => c.name() === path || c.aliases().includes(path))) {
      const resolved = resolve(path);
      if (existsSync(resolved)) {
        const kanbanDir = join(homedir(), ".kanban-code");
        mkdirSync(kanbanDir, { recursive: true });
        writeFileSync(join(kanbanDir, "open-project"), resolved);
        try {
          execSync('open -a "KanbanCode"');
        } catch {
          console.error("Failed to open KanbanCode app");
          process.exit(1);
        }
        return;
      }
    }
  });

program.parse();
