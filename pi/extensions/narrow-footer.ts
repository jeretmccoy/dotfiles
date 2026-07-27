/**
 * A narrow-terminal-friendly footer.
 *
 * The built-in footer truncates model information when it cannot share a row
 * with token stats. This footer gives model information its own wrapping row
 * and wraps every other footer section as well.
 */

import type { AssistantMessage } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { wrapTextWithAnsi } from "@earendil-works/pi-tui";
import { homedir } from "node:os";
import { relative, resolve, sep } from "node:path";

function formatTokens(count: number): string {
	if (count < 1_000) return String(count);
	if (count < 10_000) return `${(count / 1_000).toFixed(1)}k`;
	if (count < 1_000_000) return `${Math.round(count / 1_000)}k`;
	if (count < 10_000_000) return `${(count / 1_000_000).toFixed(1)}M`;
	return `${Math.round(count / 1_000_000)}M`;
}

function shortenHome(path: string): string {
	const home = resolve(homedir());
	const absolute = resolve(path);
	const fromHome = relative(home, absolute);
	const isInsideHome =
		fromHome === "" || (fromHome !== ".." && !fromHome.startsWith(`..${sep}`));

	if (!isInsideHome) return path;
	return fromHome === "" ? "~" : `~${sep}${fromHome}`;
}

function sanitizeStatus(text: string): string {
	return text.replace(/[\r\n\t]/g, " ").replace(/ +/g, " ").trim();
}

export default function narrowFooter(pi: ExtensionAPI) {
	pi.on("session_start", (_event, ctx) => {
		if (ctx.mode !== "tui") return;

		ctx.ui.setFooter((tui, theme, footerData) => {
			const unsubscribe = footerData.onBranchChange(() => tui.requestRender());

			return {
				dispose: unsubscribe,
				invalidate() {},
				render(width: number): string[] {
					const safeWidth = Math.max(1, Math.floor(width));
					const wrapDim = (text: string): string[] =>
						wrapTextWithAnsi(theme.fg("dim", text), safeWidth);
					const lines: string[] = [];

					let location = shortenHome(ctx.sessionManager.getCwd());
					const branch = footerData.getGitBranch();
					if (branch) location += ` (${branch})`;
					const sessionName = ctx.sessionManager.getSessionName();
					if (sessionName) location += ` • ${sessionName}`;
					lines.push(...wrapDim(location));

					let input = 0;
					let output = 0;
					let cacheRead = 0;
					let cacheWrite = 0;
					let cost = 0;
					for (const entry of ctx.sessionManager.getEntries()) {
						if (entry.type !== "message" || entry.message.role !== "assistant") continue;
						const message = entry.message as AssistantMessage;
						input += message.usage.input;
						output += message.usage.output;
						cacheRead += message.usage.cacheRead;
						cacheWrite += message.usage.cacheWrite;
						cost += message.usage.cost.total;
					}

					const usageParts: string[] = [];
					if (input) usageParts.push(`↑${formatTokens(input)}`);
					if (output) usageParts.push(`↓${formatTokens(output)}`);
					if (cacheRead) usageParts.push(`R${formatTokens(cacheRead)}`);
					if (cacheWrite) usageParts.push(`W${formatTokens(cacheWrite)}`);
					if (cost) usageParts.push(`$${cost.toFixed(3)}`);

					const context = ctx.getContextUsage();
					const contextWindow = context?.contextWindow ?? ctx.model?.contextWindow ?? 0;
					const contextPercent = context?.percent == null ? "?" : `${context.percent.toFixed(1)}%`;
					usageParts.push(`${contextPercent}/${formatTokens(contextWindow)}`);
					lines.push(...wrapDim(usageParts.join(" ")));

					const model = ctx.model;
					const modelName = model ? `${model.provider}/${model.id}` : "no-model";
					lines.push(...wrapDim(`${modelName} • ${pi.getThinkingLevel()}`));

					const statuses = Array.from(footerData.getExtensionStatuses().entries())
						.sort(([a], [b]) => a.localeCompare(b))
						.map(([, text]) => sanitizeStatus(text))
						.filter(Boolean);
					for (const status of statuses) {
						lines.push(...wrapDim(status));
					}

					return lines;
				},
			};
		});
	});
}
