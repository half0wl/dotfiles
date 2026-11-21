/**
 * Input bar with model+thinking level on the top border, and a centered
 * dot-separated status line in the footer below.
 *
 * Layout:
 *   ─────────────────────────────────────────🤖opus-4-7[xhigh]──
 *   > <user input>
 *   ─────────────────────────────────────────────────────────────
 *           📁 dotfiles • 🪵 main • 📊 +0-0 • 💰 $0.00
 */

import type { AssistantMessage } from "@mariozechner/pi-ai";
import {
	CustomEditor,
	type ExtensionAPI,
	isEditToolResult,
	isWriteToolResult,
	type KeybindingsManager,
} from "@mariozechner/pi-coding-agent";
import type { EditorTheme, TUI } from "@mariozechner/pi-tui";
import { truncateToWidth, visibleWidth } from "@mariozechner/pi-tui";
import { execFileSync } from "node:child_process";
import { basename } from "node:path";

const SPINNER_FRAMES = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];

// --- git helpers ----------------------------------------------------------

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

function currentBranch(cwd: string): string | null {
	try {
		const out = execFileSync("git", ["branch", "--show-current"], {
			cwd,
			stdio: ["ignore", "pipe", "ignore"],
		})
			.toString()
			.trim();
		return out || null;
	} catch {
		return null;
	}
}

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

/**
 * Build a horizontal border with a left-anchored and a right-anchored chunk
 * and configurable corner chars.
 */
function fitBorder(
	left: string,
	right: string,
	width: number,
	border: (text: string) => string,
	startCh: string = "─",
	endCh: string = "─",
): string {
	if (width <= 0) return "";
	if (width === 1) return border(startCh);

	let leftText = left;
	let rightText = right;
	const fixedWidth = 2;
	const minimumGap = 3;

	while (
		fixedWidth + visibleWidth(leftText) + visibleWidth(rightText) + minimumGap >
			width &&
		visibleWidth(rightText) > 0
	) {
		rightText = truncateToWidth(
			rightText,
			Math.max(0, visibleWidth(rightText) - 1),
			"",
		);
	}
	while (
		fixedWidth + visibleWidth(leftText) + visibleWidth(rightText) + minimumGap >
			width &&
		visibleWidth(leftText) > 0
	) {
		leftText = truncateToWidth(
			leftText,
			Math.max(0, visibleWidth(leftText) - 1),
			"",
		);
	}

	const gapWidth = Math.max(
		0,
		width - fixedWidth - visibleWidth(leftText) - visibleWidth(rightText),
	);
	return `${border(startCh)}${leftText}${border("─".repeat(gapWidth))}${rightText}${border(endCh)}`;
}

/** Strip ANSI escape sequences. */
const stripAnsi = (s: string): string => s.replace(/\x1b\[[0-9;]*m/g, "");

// --- extension ------------------------------------------------------------

export default function (pi: ExtensionAPI) {
	let isWorking = false;
	let spinnerIndex = 0;
	let spinnerTimer: ReturnType<typeof setInterval> | undefined;
	let activeTui: TUI | undefined;

	let linesAdded = 0;
	let linesRemoved = 0;

	const stopSpinner = () => {
		if (spinnerTimer) {
			clearInterval(spinnerTimer);
			spinnerTimer = undefined;
		}
	};

	pi.on("agent_start", () => {
		isWorking = true;
		stopSpinner();
		spinnerTimer = setInterval(() => {
			spinnerIndex = (spinnerIndex + 1) % SPINNER_FRAMES.length;
			activeTui?.requestRender();
		}, 80);
		activeTui?.requestRender();
	});

	pi.on("agent_end", () => {
		isWorking = false;
		stopSpinner();
		activeTui?.requestRender();
	});

	pi.on("thinking_level_select", () => activeTui?.requestRender());
	pi.on("model_select", () => activeTui?.requestRender());

	pi.on("tool_result", async (event) => {
		if (event.isError) return;
		if (isEditToolResult(event) && event.details?.diff) {
			const { added, removed } = countDiffLines(event.details.diff);
			linesAdded += added;
			linesRemoved += removed;
			activeTui?.requestRender();
			return;
		}
		if (isWriteToolResult(event)) {
			const content = (event.input as { content?: string })?.content ?? "";
			if (content) {
				linesAdded += content.split("\n").length;
				activeTui?.requestRender();
			}
		}
	});

	pi.on("session_shutdown", () => {
		stopSpinner();
		activeTui = undefined;
	});

	pi.on("session_start", (_event, ctx) => {
		linesAdded = 0;
		linesRemoved = 0;

		// We render our own spinner in the top-left of the editor border.
		ctx.ui.setWorkingVisible(false);

		// --- editor ---------------------------------------------------------

		const buildTopRight = (): string => {
			const thm = ctx.ui.theme;
			const modelId = ctx.model?.id?.replace(/^claude-/, "") ?? "no-model";
			const thinking = pi.getThinkingLevel();
			// Steel (thinkingText token) when thinking is on; muted when off.
			const thinkingColor = thinking === "off" ? "dim" : "thinkingText";
			// Two trailing dashes give a small gap before the right edge.
			return (
				`🤖${thm.fg("mdHeading", modelId)}` +
				thm.fg("border", "[") +
				thm.fg(thinkingColor, thinking) +
				thm.fg("border", "]") +
				thm.fg("border", "──")
			);
		};

		class BorderStatusEditor extends CustomEditor {
			constructor(
				tui: TUI,
				theme: EditorTheme,
				keybindings: KeybindingsManager,
			) {
				// Keep the base editor unpadded; this wrapper adds the visible
				// gutter between the custom side borders and editor content.
				super(tui, theme, keybindings, { paddingX: 0 });
				activeTui = tui;
			}

			render(width: number): string[] {
				// Reserve 1 column on each side for the vertical borders, plus a
				// one-column left gutter so input starts as `│ text` instead of `│text`.
				const leftGutter = width >= 4 ? " " : "";
				const innerWidth = Math.max(1, width - 2 - visibleWidth(leftGutter));
				const lines = super.render(innerWidth);
				if (lines.length < 2) return lines;

				const thm = ctx.ui.theme;
				// Static border color (duskPlum via borderAccent token); doesn't
				// follow thinking effort.
				const borderColor = (text: string) => thm.fg("borderAccent", text);
				const bar = borderColor("│");
				const topLeft = isWorking
					? thm.fg("accent", ` ${SPINNER_FRAMES[spinnerIndex]} `)
					: "";

				// Locate the bottom border line (last horizontal line, may be
				// followed by autocomplete entries).
				let bottomIdx = lines.length - 1;
				for (let i = lines.length - 1; i >= 1; i--) {
					if (stripAnsi(lines[i] ?? "").startsWith("─")) {
						bottomIdx = i;
						break;
					}
				}

				const result: string[] = [];
				for (let i = 0; i < lines.length; i++) {
					if (i === 0) {
						result.push(
							fitBorder(topLeft, buildTopRight(), width, borderColor, "╭", "╮"),
						);
					} else if (i === bottomIdx) {
						result.push(fitBorder("", "", width, borderColor, "╰", "╯"));
					} else {
						result.push(`${bar}${leftGutter}${lines[i]}${bar}`);
					}
				}
				return result;
			}
		}

		ctx.ui.setEditorComponent(
			(tui, theme, keybindings) =>
				new BorderStatusEditor(tui, theme, keybindings),
		);

		// --- footer (centered, dot-separated status) -----------------------

		ctx.ui.setFooter((_tui, theme) => {
			let disposed = false;
			return {
				dispose: () => {
					disposed = true;
				},
				invalidate() {},
				render(width: number): string[] {
					if (disposed) return [];

					// Aggregate session usage from the message branch.
					let cost = 0;
					for (const e of ctx.sessionManager.getBranch()) {
						if (e.type === "message" && e.message.role === "assistant") {
							const m = e.message as AssistantMessage;
							cost += m.usage.cost.total;
						}
					}

					const cwd = process.cwd();
					const root = projectRoot(cwd);
					const project = basename(root ?? cwd);
					const branch = currentBranch(root ?? cwd);

					const dirSeg = `📁 ${theme.fg("accent", project)}`;
					const branchSeg = branch
						? `🪵 ${theme.fg("mdLink", branch)}`
						: undefined;
					const diffSeg =
						linesAdded || linesRemoved
							? `📊 ${theme.fg("success", `+${linesAdded}`)}${theme.fg("error", `-${linesRemoved}`)}`
							: `📊 ${theme.fg("dim", "+0-0")}`;
					const costSeg = `💰 ${theme.fg("mdLink", `$${cost.toFixed(2)}`)}`;

					const sep = theme.fg("dim", " • ");
					const line = [dirSeg, branchSeg, diffSeg, costSeg]
						.filter((seg): seg is string => Boolean(seg))
						.join(sep);

					// Right-align with a small gutter from the edge.
					const gutter = 1;
					const lineWidth = visibleWidth(line);
					const pad = Math.max(0, width - lineWidth - gutter);
					return [truncateToWidth(" ".repeat(pad) + line, width)];
				},
			};
		});
	});
}
