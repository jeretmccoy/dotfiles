/**
 * Workspaces Extension
 *
 * Define named workspaces (sets of project folders), switch between them, and
 * jump to a folder's session — like nvim's workspaces.nvim.
 *
 * Usage:
 *   /ws              Activate a saved workspace (profile picker)
 *   /ws new        Pick folders → name → save as a new workspace
 *   /ws pick         Choose which subfolders of cwd to include (toggle loop)
 *   /ws save <name>  Snapshot the active folder set as a named workspace
 *   /ws load <name>  Load a named workspace into the active set
 *   /ws profiles     List / load / delete saved workspaces
 *   /ws go           Pick a folder → pick a session → jump (session switching)
 *   /ws add          Pin the current directory
 *   /ws list         Show pinned workspaces
 *   /ws remove       Remove a pinned workspace
 *   /ws scan         Re-scan parent directory for new subprojects
 *
 * Config: ~/.pi/workspaces.json
 *   { "dirs": ["/path/..."],
 *     "activeProfile": "work",
 *     "profiles": { "work": ["/path/..."], "personal": ["/path/..."] } }
 *
 * Footer shows the active workspace name + its subfolders, e.g.:
 *   📁 work — project-one, project-two, project-three
 */

import type { ExtensionAPI, SessionInfo } from "@earendil-works/pi-coding-agent";
import { SessionManager } from "@earendil-works/pi-coding-agent";
import { readFileSync, writeFileSync, existsSync, readdirSync, statSync } from "node:fs";
import { join, dirname, basename, resolve } from "node:path";
import { homedir } from "node:os";

const CONFIG_PATH = join(homedir(), ".pi", "workspaces.json");

const PROJECT_MARKERS = [".git", "package.json", "Cargo.toml", ".pi", "pyproject.toml", "go.mod"];

interface WorkspacesConfig {
	dirs: string[];
	profiles: Record<string, string[]>;
	activeProfile?: string;
}

function loadConfig(): WorkspacesConfig {
	try {
		if (existsSync(CONFIG_PATH)) {
			const raw = readFileSync(CONFIG_PATH, "utf-8");
			const parsed = JSON.parse(raw);
			const dirs = Array.isArray(parsed.dirs)
				? parsed.dirs.filter((d: unknown) => typeof d === "string")
				: [];
			const profiles: Record<string, string[]> =
				parsed.profiles && typeof parsed.profiles === "object"
					? Object.fromEntries(
							Object.entries(parsed.profiles).filter(
								([, v]) => Array.isArray(v),
							) as [string, string[]][],
						)
					: {};
			const activeProfile = typeof parsed.activeProfile === "string" ? parsed.activeProfile : undefined;
			return { dirs, profiles, activeProfile };
		}
	} catch {
		// Corrupt or missing config — start fresh.
	}
	return { dirs: [], profiles: {} };
}

function saveConfig(config: WorkspacesConfig): void {
	const dir = dirname(CONFIG_PATH);
	if (!existsSync(dir)) {
		writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2));
		return;
	}
	writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2));
}

function isProjectDir(path: string): boolean {
	return PROJECT_MARKERS.some((marker) => existsSync(join(path, marker)));
}

/** Scan `parent` one level deep for project-looking subdirectories. */
function scanForProjects(parent: string): string[] {
	try {
		const entries = readdirSync(parent);
		const projects: string[] = [];
		for (const entry of entries) {
			const full = join(parent, entry);
			try {
				if (!statSync(full).isDirectory()) continue;
			} catch {
				continue;
			}
			if (entry.startsWith(".")) continue;
			if (isProjectDir(full)) {
				projects.push(full);
			}
		}
		return projects.sort((a, b) =>
			basename(a).toLowerCase().localeCompare(basename(b).toLowerCase()),
		);
	} catch {
		return [];
	}
}

/** Return the set of workspace directories: pinned + auto-discovered from cwd parent. */
function getWorkspaces(cwd: string): { path: string; pinned: boolean }[] {
	const config = loadConfig();
	const pinned = new Set(config.dirs.map((d) => resolve(d)));

	// Auto-discover: scan the parent of cwd for project subdirectories.
	const parent = dirname(cwd);
	const discovered = scanForProjects(parent);

	const seen = new Set<string>();
	const out: { path: string; pinned: boolean }[] = [];

	// Pinned first (in config order).
	for (const d of config.dirs) {
		const r = resolve(d);
		if (!seen.has(r) && existsSync(r)) {
			seen.add(r);
			out.push({ path: r, pinned: true });
		}
	}
	// Then auto-discovered (only if not already pinned).
	for (const d of discovered) {
		if (!seen.has(d)) {
			seen.add(d);
			out.push({ path: d, pinned: false });
		}
	}
	return out;
}

function shortLabel(path: string, home: string): string {
	if (path.startsWith(home)) {
		return "~" + path.slice(home.length);
	}
	return path;
}

interface UICtx {
	ui: {
		setStatus: (key: string, text: string) => void;
	};
}

/** Footer: workspace name + subfolder names. */
function refreshFooter(ctx: UICtx): void {
	const config = loadConfig();
	const names = config.dirs.map((d) => basename(d));
	const folderPart =
		names.length === 0
			? "(no folders)"
			: names.length <= 4
				? names.join(", ")
				: `${names.slice(0, 3).join(", ")}, … +${names.length - 3}`;
	const wsName = config.activeProfile ?? "(unsaved)";
	ctx.ui.setStatus("ws", `📁 ${wsName} — ${folderPart}`);
}

/** List subdirectories of `currentDir` one level deep, sorted. */
function listSubdirs(currentDir: string): string[] {
	let entries: string[] = [];
	try {
		entries = readdirSync(currentDir);
	} catch {
		return [];
	}
	const folders: string[] = [];
	for (const entry of entries) {
		const full = join(currentDir, entry);
		try {
			if (statSync(full).isDirectory()) folders.push(full);
		} catch {
			continue;
		}
	}
	folders.sort((a, b) =>
		basename(a).toLowerCase().localeCompare(basename(b).toLowerCase()),
	);
	return folders;
}

export default function workspacesExtension(pi: ExtensionAPI) {
	pi.registerCommand("ws", {
		description: "Workspaces: activate, manage, and jump to project folders",
		getArgumentCompletions: (prefix) => {
			const subcommands = ["add", "go", "list", "load", "new", "pick", "profiles", "remove", "save", "scan"];
			const filtered = subcommands.filter((s) => s.startsWith(prefix));
			return filtered.length > 0
				? filtered.map((s) => ({ value: s, label: s }))
				: null;
		},
		handler: async (args, ctx) => {
			const sub = args.trim().split(/\s+/)[0];

			// --- /ws add ---
			if (sub === "add") {
				const config = loadConfig();
				const cwd = resolve(ctx.cwd);
				if (config.dirs.includes(cwd)) {
					ctx.ui.notify(`Already pinned: ${shortLabel(cwd, homedir())}`, "info");
					return;
				}
				config.dirs.push(cwd);
				saveConfig(config);
				ctx.ui.notify(`Pinned: ${shortLabel(cwd, homedir())}`, "info");
				refreshFooter(ctx);
				return;
			}

			// --- /ws pick: toggle subfolders of cwd in/out of the active set ---
			if (sub === "pick") {
				const home = homedir();
				const folders = listSubdirs(resolve(ctx.cwd));
				if (folders.length === 0) {
					ctx.ui.notify("No subdirectories in the current folder.", "info");
					return;
				}
				for (;;) {
					const config = loadConfig();
					const pinnedSet = new Set(config.dirs.map((d) => resolve(d)));
					const items = folders.map((f) => {
						const pinned = pinnedSet.has(f);
						const mark = pinned ? "✓" : "○";
						const proj = isProjectDir(f) ? "" : "  (no project markers)";
						return `${mark} ${basename(f)}${proj}  —  ${shortLabel(f, home)}`;
					});
					items.push("✓ Done");
					const choice = await ctx.ui.select(
						`Pick folders to include (${pinnedSet.size} pinned) — toggle on/off`,
						items,
					);
					if (!choice || choice === "✓ Done") {
						const cfg = loadConfig();
						ctx.ui.notify(`${cfg.dirs.length} folder(s) in active set.`, "info");
						refreshFooter(ctx);
						return;
					}
					const idx = items.indexOf(choice);
					const target = folders[idx];
					if (!target) continue;
					const cfg = loadConfig();
					const resolved = resolve(target);
					const already = cfg.dirs.findIndex((d) => resolve(d) === resolved);
					if (already >= 0) {
						cfg.dirs.splice(already, 1);
						saveConfig(cfg);
						ctx.ui.notify(`Unpinned: ${basename(target)}`, "info");
					} else {
						cfg.dirs.push(resolved);
						saveConfig(cfg);
						ctx.ui.notify(`Pinned: ${basename(target)}`, "info");
					}
				}
			}

			// --- /ws new: pick folders → name → save (always, even with existing workspaces) ---
			if (sub === "new") {
				const home = homedir();
				const folders = listSubdirs(resolve(ctx.cwd));
				if (folders.length === 0) {
					ctx.ui.notify("No subdirectories in the current folder.", "info");
					return;
				}
				// Start from a clean slate for this new workspace.
				const blank = loadConfig();
				blank.dirs = [];
				saveConfig(blank);
				for (;;) {
					const config = loadConfig();
					const pinnedSet = new Set(config.dirs.map((d) => resolve(d)));
					const items = folders.map((f) => {
						const pinned = pinnedSet.has(f);
						const mark = pinned ? "✓" : "○";
						const proj = isProjectDir(f) ? "" : "  (no project markers)";
						return `${mark} ${basename(f)}${proj}  —  ${shortLabel(f, home)}`;
				});
					items.push("✓ Done — save");
					items.push("✗ Cancel");
					const choice = await ctx.ui.select(
						`New workspace — pick folders (${pinnedSet.size} selected)`,
						items,
					);
					if (!choice || choice === "✗ Cancel") {
						ctx.ui.notify("Cancelled. No workspace created.", "info");
						refreshFooter(ctx);
						return;
					}
					if (choice === "✓ Done — save") {
						const cfg = loadConfig();
						if (cfg.dirs.length === 0) {
							ctx.ui.notify("Select at least one folder first.", "info");
							continue;
						}
						const nameInput = await ctx.ui.input("Save this set as workspace (name):", "");
						if (!nameInput) {
							ctx.ui.notify("Cancelled.", "info");
							refreshFooter(ctx);
							return;
						}
						cfg.profiles[nameInput] = [...cfg.dirs];
						cfg.activeProfile = nameInput;
						saveConfig(cfg);
						ctx.ui.notify(
							`Created workspace "${nameInput}" (${cfg.dirs.length} folder(s))`,
							"info",
						);
						refreshFooter(ctx);
						return;
					}
					const idx = items.indexOf(choice);
					const target = folders[idx];
					if (!target) continue;
					const cfg = loadConfig();
					const resolved = resolve(target);
					const already = cfg.dirs.findIndex((d) => resolve(d) === resolved);
					if (already >= 0) cfg.dirs.splice(already, 1);
					else cfg.dirs.push(resolved);
					saveConfig(cfg);
				}
			}

			// --- /ws save <name> ---
			if (sub === "save") {
				const name = args.trim().split(/\s+/).slice(1).join(" ").trim();
				if (!name) {
					ctx.ui.notify("Usage: /ws save <name>", "error");
					return;
				}
				const config = loadConfig();
				config.profiles[name] = [...config.dirs];
				config.activeProfile = name;
				saveConfig(config);
				ctx.ui.notify(
					`Saved workspace "${name}" (${config.dirs.length} folder(s))`,
					"info",
				);
				refreshFooter(ctx);
				return;
			}

			// --- /ws load <name> ---
			if (sub === "load") {
				const name = args.trim().split(/\s+/).slice(1).join(" ").trim();
				const config = loadConfig();
				const names = Object.keys(config.profiles);
				let target = name;
				if (!target && names.length > 0) {
					const choice = await ctx.ui.select("Load workspace:", names);
					if (!choice) return;
					target = choice;
				}
				if (!target) {
					ctx.ui.notify("No saved workspaces. Use /ws save <name> first.", "info");
					return;
				}
				const dirs = config.profiles[target];
				if (!dirs) {
					ctx.ui.notify(`No workspace named "${target}".`, "error");
					return;
				}
				config.dirs = [...dirs];
				config.activeProfile = target;
				saveConfig(config);
				ctx.ui.notify(
					`Loaded workspace "${target}" (${dirs.length} folder(s))`,
					"info",
				);
				refreshFooter(ctx);
				return;
			}

			// --- /ws profiles: list / load / delete ---
			if (sub === "profiles") {
				const config = loadConfig();
				const names = Object.keys(config.profiles);
				if (names.length === 0) {
					ctx.ui.notify("No saved workspaces. Use /ws save <name>.", "info");
					return;
				}
				const items = names.map((n) => {
					const count = config.profiles[n].length;
					const sample = config.profiles[n]
						.map((d) => basename(d))
						.slice(0, 3)
						.join(", ");
					const more = config.profiles[n].length > 3 ? ", …" : "";
					const activeTag = config.activeProfile === n ? " ✓ active" : "";
					return `${n}  (${count})  ${sample}${more}${activeTag}`;
				});
				items.push("✗ Delete a workspace…");
				const choice = await ctx.ui.select("Workspaces (load or delete)", items);
				if (!choice) return;
				if (choice === "✗ Delete a workspace…") {
					const delChoice = await ctx.ui.select("Delete workspace:", names);
					if (!delChoice) return;
					const cfg = loadConfig();
					delete cfg.profiles[delChoice];
					if (cfg.activeProfile === delChoice) cfg.activeProfile = undefined;
					saveConfig(cfg);
					ctx.ui.notify(`Deleted workspace "${delChoice}"`, "info");
					refreshFooter(ctx);
					return;
				}
				const idx = items.indexOf(choice);
				const targetName = names[idx];
				if (!targetName) return;
				const cfg = loadConfig();
				cfg.dirs = [...cfg.profiles[targetName]];
				cfg.activeProfile = targetName;
				saveConfig(cfg);
				ctx.ui.notify(
					`Loaded workspace "${targetName}" (${cfg.dirs.length} folder(s))`,
					"info",
				);
				refreshFooter(ctx);
				return;
			}

			// --- /ws scan ---
			if (sub === "scan") {
				const parent = dirname(resolve(ctx.cwd));
				const found = scanForProjects(parent);
				const config = loadConfig();
				let added = 0;
				for (const p of found) {
					if (!config.dirs.includes(p)) {
						config.dirs.push(p);
						added++;
					}
				}
				saveConfig(config);
				ctx.ui.notify(
					added > 0
						? `Added ${added} workspace(s). Total: ${config.dirs.length}`
						: `No new workspaces found. Total: ${config.dirs.length}`,
					"info",
				);
				refreshFooter(ctx);
				return;
			}

			// --- /ws list ---
			if (sub === "list") {
				const config = loadConfig();
				if (config.dirs.length === 0) {
					ctx.ui.notify("No pinned workspaces. Use /ws pick or /ws add.", "info");
					return;
				}
				const items = config.dirs.map((d) => shortLabel(d, homedir()));
				await ctx.ui.select("Pinned workspaces", items);
				return;
			}

			// --- /ws remove ---
			if (sub === "remove") {
				const config = loadConfig();
				if (config.dirs.length === 0) {
					ctx.ui.notify("No pinned workspaces to remove.", "info");
					return;
				}
				const items = config.dirs.map((d) => shortLabel(d, homedir()));
				const choice = await ctx.ui.select("Remove workspace:", items);
				if (!choice) return;
				const idx = items.indexOf(choice);
				if (idx >= 0) {
					config.dirs.splice(idx, 1);
					saveConfig(config);
					ctx.ui.notify(`Removed: ${choice}`, "info");
					refreshFooter(ctx);
				}
				return;
			}

			// --- /ws go: pick a folder → pick a session → jump ---
			if (sub === "go") {
				const home = homedir();
				const workspaces = getWorkspaces(ctx.cwd);
				if (workspaces.length === 0) {
					ctx.ui.notify("No workspaces. Use /ws pick to add folders.", "info");
					return;
				}
				const currentResolved = resolve(ctx.cwd);
				const items = workspaces.map((w) => {
					const label = shortLabel(w.path, home);
					const pinTag = w.pinned ? " ★" : "";
					const currentTag = w.path === currentResolved ? " (current)" : "";
					return {
						value: w.path,
						label: `${basename(w.path)}${pinTag}${currentTag}  —  ${label}`,
					};
				});
				const choice = await ctx.ui.select(
					"Jump to folder",
					items.map((i) => i.label),
				);
				if (!choice) return;
				const selected = items.find((i) => i.label === choice);
				if (!selected) return;
				const targetDir = selected.value;
				if (resolve(targetDir) === currentResolved) {
					ctx.ui.notify("Already in this folder.", "info");
					return;
				}
				let sessions: SessionInfo[] = [];
				try {
					sessions = await SessionManager.list(targetDir);
				} catch {
					sessions = [];
				}
				sessions.sort((a, b) => b.modified.getTime() - a.modified.getTime());
				const sessionLabels: string[] = [];
				if (sessions.length > 0) {
					for (const s of sessions.slice(0, 10)) {
						const time = s.modified.toLocaleString(undefined, {
							month: "short",
							day: "numeric",
							hour: "2-digit",
							minute: "2-digit",
						});
						const name = s.name || s.firstMessage?.slice(0, 40) || "(unnamed)";
						sessionLabels.push(`${name}  —  ${time}`);
					}
				}
				sessionLabels.push("✨ New session");
				const sessionChoice = await ctx.ui.select(
					`${basename(targetDir)} — pick session`,
					sessionLabels,
				);
				if (!sessionChoice) return;
				ctx.ui.setStatus("ws", `Switching to ${basename(targetDir)}…`);
				try {
					if (sessionChoice === "✨ New session") {
						const newSm = SessionManager.create(targetDir);
						const newFile = newSm.getSessionFile();
						if (!newFile) {
							ctx.ui.notify("Failed to create session.", "error");
							ctx.ui.setStatus("ws", "");
							return;
						}
						await ctx.switchSession(newFile, {
							withSession: async (newCtx) => {
								newCtx.ui.notify(
									`Switched to ${shortLabel(targetDir, home)} (new session)`,
									"info",
								);
							},
						});
					} else {
						const idx = sessionLabels.indexOf(sessionChoice);
						const target = sessions[idx];
						if (!target?.path) {
							ctx.ui.notify("Could not resolve session file.", "error");
							ctx.ui.setStatus("ws", "");
							return;
						}
						await ctx.switchSession(target.path, {
							withSession: async (newCtx) => {
								newCtx.ui.notify(
									`Switched to ${shortLabel(targetDir, home)}`,
									"info",
								);
							},
						});
					}
				} catch (err) {
					ctx.ui.notify(
						`Switch failed: ${err instanceof Error ? err.message : String(err)}`,
						"error",
					);
				} finally {
					refreshFooter(ctx);
				}
				return;
			}

			// --- /ws (default): activate a saved workspace ---
			if (sub) {
				ctx.ui.notify(
					"Unknown subcommand. Try: /ws, /ws new, /ws pick, /ws save <name>, /ws load <name>, /ws profiles, /ws go, /ws add, /ws list, /ws remove, /ws scan",
					"error",
				);
				return;
			}

			const config = loadConfig();
			const names = Object.keys(config.profiles);

			// No profiles yet — bootstrap by picking folders then naming the set.
			if (names.length === 0) {
				const boot = await ctx.ui.select(
					"No saved workspaces yet. Create one?",
					["Pick folders from current dir…", "Cancel"],
				);
				if (boot !== "Pick folders from current dir…") return;
				const home = homedir();
				const folders = listSubdirs(resolve(ctx.cwd));
				if (folders.length === 0) {
					ctx.ui.notify("No subdirectories here.", "info");
					return;
				}
				for (;;) {
					const cfg = loadConfig();
					const pinnedSet = new Set(cfg.dirs.map((d) => resolve(d)));
					const items = folders.map((f) => {
						const pinned = pinnedSet.has(f);
						const mark = pinned ? "✓" : "○";
						const proj = isProjectDir(f) ? "" : "  (no project markers)";
						return `${mark} ${basename(f)}${proj}  —  ${shortLabel(f, home)}`;
					});
					items.push("✓ Done");
					const choice = await ctx.ui.select(
						`Pick folders to include (${pinnedSet.size} pinned) — toggle`,
						items,
					);
					if (!choice || choice === "✓ Done") {
						const cfg2 = loadConfig();
						if (cfg2.dirs.length > 0) {
							const nameInput = await ctx.ui.input("Save this set as workspace (name):", "");
							if (nameInput) {
								cfg2.profiles[nameInput] = [...cfg2.dirs];
								cfg2.activeProfile = nameInput;
								saveConfig(cfg2);
								ctx.ui.notify(`Saved workspace "${nameInput}"`, "info");
								refreshFooter(ctx);
							}
						}
						return;
					}
					const idx = items.indexOf(choice);
					const target = folders[idx];
					if (!target) continue;
					const cfg2 = loadConfig();
					const resolved = resolve(target);
					const already = cfg2.dirs.findIndex((d) => resolve(d) === resolved);
					if (already >= 0) cfg2.dirs.splice(already, 1);
					else cfg2.dirs.push(resolved);
					saveConfig(cfg2);
				}
			}

			// List saved workspaces, mark active, pick to activate.
			const items = names.map((n) => {
				const count = config.profiles[n].length;
				const sample = config.profiles[n]
					.map((d) => basename(d))
					.slice(0, 3)
					.join(", ");
				const more = config.profiles[n].length > 3 ? ", …" : "";
				const activeTag = config.activeProfile === n ? " ✓ active" : "";
				return `${n}  (${count})  ${sample}${more}${activeTag}`;
			});
			const choice = await ctx.ui.select("Activate workspace", items);
			if (!choice) return;
			const idx = items.indexOf(choice);
			const targetName = names[idx];
			if (!targetName) return;
			const cfg = loadConfig();
			cfg.dirs = [...cfg.profiles[targetName]];
			cfg.activeProfile = targetName;
			saveConfig(cfg);
			ctx.ui.notify(
				`Activated workspace "${targetName}" (${cfg.dirs.length} folder(s))`,
				"info",
			);
			refreshFooter(ctx);
			return;
		},
	});

	// Footer: show active workspace name + subfolders.
	pi.on("session_start", async (_event, ctx) => {
		refreshFooter(ctx);
	});

	// Inject the active workspace into the system prompt so the LLM knows what
	// folders are the primary focus of this session.
	pi.on("before_agent_start", async (event, _ctx) => {
		const config = loadConfig();
		if (config.dirs.length === 0 && !config.activeProfile) return;
		const home = homedir();
		const folderLines = config.dirs.map((d) => `  - ${shortLabel(d, home)}`).join("\n");
		const wsName = config.activeProfile ?? "(unsaved set)";
		const block = [
			"",
			"## Active Workspace",
			`Workspace: ${wsName}`,
			config.dirs.length > 0 ? "Folders:" : "Folders: (none)",
			folderLines,
			"These folders are the primary focus of this session. When the user asks",
			"to work on 'the project' without naming one, they mean this workspace.",
		].join("\n");
		return { systemPrompt: event.systemPrompt + block };
	});
}
