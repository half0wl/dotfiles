/**
 * Statusline extension — mirrors ~/.claude/statusline.sh in pi.
 *
 * Segments (left → right):
 *   🤖 model[thinking] · 📁 project[/cwd] · ⚡ ctx% · session-time · +N -M · $cost · ⎇ branch
 *
 * Colors come from the active theme (e.g. Railway), so swapping themes
 * automatically restyles the statusline.
 */

import type { AssistantMessage } from "@mariozechner/pi-ai";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { isEditToolResult, isWriteToolResult } from "@mariozechner/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@mariozechner/pi-tui";
import { execFileSync } from "node:child_process";
import { basename } from "node:path";

const CTX_WARN_PCT = 75; // turn red when context >= this %

function fmtTokens(n: number): string {
  if (n < 1000) return `${n}`;
  if (n < 1_000_000) return `${(n / 1000).toFixed(1)}k`;
  return `${(n / 1_000_000).toFixed(2)}M`;
}

function fmtDuration(ms: number): string {
  const total = Math.floor(ms / 1000);
  const m = Math.floor(total / 60);
  const s = total % 60;
  return `${m}m${String(s).padStart(2, "0")}s`;
}

/** Cached `git rev-parse --show-toplevel` per cwd. */
const projectRootCache = new Map<string, string | null>();
function projectRoot(cwd: string): string | null {
  if (projectRootCache.has(cwd)) return projectRootCache.get(cwd)!;
  try {
    const out = execFileSync("git", ["rev-parse", "--show-toplevel"], {
      cwd,
      stdio: ["ignore", "pipe", "ignore"],
    })
      .toString()
      .trim();
    projectRootCache.set(cwd, out || null);
    return out || null;
  } catch {
    projectRootCache.set(cwd, null);
    return null;
  }
}

/** Count +/- lines in a unified diff, ignoring the `+++`/`---` file headers. */
function countDiffLines(diff: string): { added: number; removed: number } {
  let added = 0;
  let removed = 0;
  for (const line of diff.split("\n")) {
    if (line.startsWith("+++") || line.startsWith("---")) continue;
    if (line.startsWith("+")) added++;
    else if (line.startsWith("-")) removed++;
  }
  return { added, removed };
}

export default function(pi: ExtensionAPI) {
  let sessionStart = Date.now();
  let linesAdded = 0;
  let linesRemoved = 0;

  // Track lines added/removed from edit + write tools
  pi.on("tool_result", async (event) => {
    if (event.isError) return;

    if (isEditToolResult(event) && event.details?.diff) {
      const { added, removed } = countDiffLines(event.details.diff);
      linesAdded += added;
      linesRemoved += removed;
      return;
    }

    if (isWriteToolResult(event)) {
      const content = (event.input as { content?: string })?.content ?? "";
      if (content) {
        // Treat full file write as all-added (we don't have prior contents here).
        linesAdded += content.split("\n").length;
      }
    }
  });

  pi.on("session_start", async (_event, ctx) => {
    sessionStart = Date.now();
    linesAdded = 0;
    linesRemoved = 0;

    ctx.ui.setFooter((tui, theme, footerData) => {
      const unsub = footerData.onBranchChange(() => tui.requestRender());
      const interval = setInterval(() => tui.requestRender(), 1000);
      // pi.on returns void (no unsubscribe). Guard with `disposed` so the
      // handler is a no-op after the footer is torn down.
      let disposed = false;
      pi.on("thinking_level_select", () => {
        if (!disposed) tui.requestRender();
      });

      return {
        dispose: () => {
          disposed = true;
          unsub();
          clearInterval(interval);
        },
        invalidate() { },
        render(width: number): string[] {
          // --- aggregate session usage from message branch
          let cost = 0;
          let latestInput = 0;
          for (const e of ctx.sessionManager.getBranch()) {
            if (e.type === "message" && e.message.role === "assistant") {
              const m = e.message as AssistantMessage;
              cost += m.usage.cost.total;
              latestInput = m.usage.input; // last assistant turn = current ctx size
            }
          }

          // --- context window %
          const ctxWindow = ctx.model?.contextWindow ?? 0;
          const ctxPct = ctxWindow > 0 ? Math.round((latestInput / ctxWindow) * 100) : 0;
          const ctxColor = ctxPct >= CTX_WARN_PCT ? "error" : "success";

          // --- dir segment: project[/cwd]
          const cwd = process.cwd();
          const root = projectRoot(cwd);
          const project = basename(root ?? cwd);
          const current = basename(cwd);
          const dirSegment =
            root && current !== project
              ? `📁${theme.fg("accent", project)}/${theme.fg("accent", current)}`
              : `📁${theme.fg("accent", project)}`;

          // --- model + thinking level
          const modelId = ctx.model?.id?.replace(/^claude-/, "") ?? "no-model";
          const thinking = pi.getThinkingLevel();
          const thinkingColor = thinking === "off" ? "dim" : "accent";
          const modelSegment =
            `🤖${theme.fg("mdHeading", modelId)}` +
            theme.fg("dim", "[") +
            theme.fg(thinkingColor, thinking) +
            theme.fg("dim", "]");

          // --- ctx %
          const ctxSegment = `🧠${theme.fg(ctxColor, `${ctxPct}%`)}`;

          // --- session time
          const timeSegment = theme.fg("success", fmtDuration(Date.now() - sessionStart));

          // --- cost
          const costSegment = theme.fg("mdLink", `$${cost.toFixed(2)}`);

          // --- lines +/-
          const linesSegment =
            linesAdded || linesRemoved
              ? `${theme.fg("success", `+${linesAdded}`)}${theme.fg("error", `-${linesRemoved}`)}`
              : theme.fg("dim", "+0-0");

          // --- tokens
          const tokenSegment = theme.fg("dim", `↑${fmtTokens(latestInput)}`);

          // --- branch (right side)
          const branch = footerData.getGitBranch();
          const branchSegment = branch ? theme.fg("dim", `⎇ ${branch}`) : "";

          const sep = theme.fg("dim", " · ");
          const left = [
            modelSegment,
            dirSegment,
            ctxSegment,
            timeSegment,
            linesSegment,
            tokenSegment,
            costSegment,
          ].join(sep);

          const padLen = Math.max(1, width - visibleWidth(left) - visibleWidth(branchSegment));
          const line = left + " ".repeat(padLen) + branchSegment;
          return [truncateToWidth(line, width)];
        },
      };
    });
  });
}
