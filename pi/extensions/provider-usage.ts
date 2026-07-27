import { getAgentDir, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";
import { createHash } from "node:crypto";
import { mkdir, readFile, rename, rm, stat, writeFile } from "node:fs/promises";
import { dirname } from "node:path";

// Subscription utilization comes from provider endpoints. API-key spend is a
// separate, persistent local ledger because ordinary API keys cannot read the
// providers' organization/admin billing APIs.
type ProviderKind = "anthropic" | "openai";
type UsagePart = { label: string; percent: number; resetsAt?: number };
type CacheEntry = { text: string; fetchedAt: number };
type DisplayMode =
	| { type: "oauth"; kind: ProviderKind; id: string }
	| { type: "api-key"; provider: string; label: string; id: string; fingerprint: string };

type KeyLedgerEntry = {
	provider: string;
	spent: number;
	updatedAt: number;
	eventIds: string[];
};

type KeyLedger = {
	version: 1;
	keys: Record<string, KeyLedgerEntry>;
};

const STATUS_ID = "provider-usage";
const REFRESH_INTERVAL_MS = 2 * 60 * 1000;
const REQUEST_TIMEOUT_MS = 10_000;
const LEDGER_PATH = process.env.PI_PROVIDER_USAGE_LEDGER ?? `${getAgentDir()}/provider-usage-ledger.json`;
const LOCK_PATH = `${LEDGER_PATH}.lock`;
const MAX_EVENT_IDS_PER_KEY = 10_000;

function asRecord(value: unknown): Record<string, unknown> | undefined {
	return value !== null && typeof value === "object" && !Array.isArray(value)
		? (value as Record<string, unknown>)
		: undefined;
}

function finiteNumber(value: unknown): number | undefined {
	return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function providerKind(provider: string | undefined): ProviderKind | undefined {
	if (provider === "anthropic") return "anthropic";
	if (provider === "openai" || provider === "openai-codex") return "openai";
	return undefined;
}

function providerLabel(kind: ProviderKind): string {
	return kind === "anthropic" ? "Claude" : "OpenAI";
}

function formatPercent(percent: number): string {
	const rounded = Math.round(percent * 10) / 10;
	return `${Number.isInteger(rounded) ? rounded.toFixed(0) : rounded.toFixed(1)}%`;
}

function formatMoney(amount: number): string {
	return `$${amount < 1 ? amount.toFixed(4) : amount.toFixed(2)}`;
}

function formatWindow(seconds: number): string {
	if (seconds === 5 * 60 * 60) return "5h";
	if (seconds === 7 * 24 * 60 * 60) return "7d";
	if (seconds % (24 * 60 * 60) === 0) return `${seconds / (24 * 60 * 60)}d`;
	if (seconds % (60 * 60) === 0) return `${seconds / (60 * 60)}h`;
	return `${Math.round(seconds / 60)}m`;
}

function parseTimestamp(value: unknown): number | undefined {
	if (typeof value === "string") {
		const timestamp = Date.parse(value);
		return Number.isFinite(timestamp) ? timestamp : undefined;
	}
	const timestamp = finiteNumber(value);
	if (timestamp === undefined) return undefined;
	return timestamp < 1_000_000_000_000 ? timestamp * 1000 : timestamp;
}

function formatReset(timestamp: number): string {
	const reset = new Date(timestamp);
	const now = new Date();
	const sameDay =
		reset.getFullYear() === now.getFullYear() &&
		reset.getMonth() === now.getMonth() &&
		reset.getDate() === now.getDate();
	const time = reset.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
	if (sameDay) return time;
	const day = reset.toLocaleDateString([], { weekday: "short" });
	return `${day} ${time}`;
}

function readAnthropicWindow(root: Record<string, unknown>, key: string, label: string): UsagePart | undefined {
	const window = asRecord(root[key]);
	const percent = finiteNumber(window?.utilization);
	return percent === undefined
		? undefined
		: { label, percent, resetsAt: parseTimestamp(window?.resets_at) };
}

export function parseAnthropicUsage(payload: unknown): UsagePart[] {
	const root = asRecord(payload);
	if (!root) return [];

	return [
		readAnthropicWindow(root, "five_hour", "5h"),
		readAnthropicWindow(root, "seven_day", "7d"),
		readAnthropicWindow(root, "seven_day_sonnet", "Sonnet 7d"),
		readAnthropicWindow(root, "seven_day_opus", "Opus 7d"),
		readAnthropicWindow(root, "seven_day_oauth_apps", "OAuth 7d"),
	].filter((part): part is UsagePart => part !== undefined);
}

export function parseOpenAIUsage(payload: unknown): UsagePart[] {
	const root = asRecord(payload);
	const rateLimit = asRecord(root?.rate_limit);
	if (!rateLimit) return [];

	const parts: Array<UsagePart & { seconds: number }> = [];
	for (const key of ["primary_window", "secondary_window"]) {
		const window = asRecord(rateLimit[key]);
		const percent = finiteNumber(window?.used_percent);
		const seconds = finiteNumber(window?.limit_window_seconds);
		if (percent !== undefined && seconds !== undefined && seconds > 0) {
			parts.push({
				label: formatWindow(seconds),
				percent,
				seconds,
				resetsAt: parseTimestamp(window?.reset_at),
			});
		}
	}

	parts.sort((a, b) => a.seconds - b.seconds);
	return parts.map(({ label, percent, resetsAt }) => ({ label, percent, resetsAt }));
}

function decodeOpenAIAccountId(token: string): string | undefined {
	try {
		const payload = token.split(".")[1];
		if (!payload) return undefined;
		const decoded = JSON.parse(Buffer.from(payload, "base64url").toString("utf8"));
		return decoded?.["https://api.openai.com/auth"]?.chatgpt_account_id;
	} catch {
		return undefined;
	}
}

async function fetchJson(url: string, headers: Record<string, string>): Promise<unknown> {
	const response = await fetch(url, {
		headers: { accept: "application/json", ...headers },
		signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
	});
	if (!response.ok) throw new Error(`Usage request returned HTTP ${response.status}`);
	return response.json();
}

async function fetchAnthropicUsage(ctx: ExtensionContext): Promise<UsagePart[]> {
	const token = (await ctx.modelRegistry.getProviderAuth("anthropic"))?.auth.apiKey;
	if (!token) throw new Error("Anthropic OAuth credentials are unavailable");

	const payload = await fetchJson("https://api.anthropic.com/api/oauth/usage", {
		authorization: `Bearer ${token}`,
		"anthropic-beta": "oauth-2025-04-20",
	});
	return parseAnthropicUsage(payload);
}

async function fetchOpenAIUsage(ctx: ExtensionContext): Promise<UsagePart[]> {
	const token = (await ctx.modelRegistry.getProviderAuth("openai-codex"))?.auth.apiKey;
	if (!token) throw new Error("OpenAI Codex OAuth credentials are unavailable");

	const accountId = decodeOpenAIAccountId(token);
	if (!accountId) throw new Error("OpenAI account ID is unavailable");

	const payload = await fetchJson("https://chatgpt.com/backend-api/wham/usage", {
		authorization: `Bearer ${token}`,
		"chatgpt-account-id": accountId,
	});
	return parseOpenAIUsage(payload);
}

function formatSubscriptionStatus(kind: ProviderKind, parts: UsagePart[]): string {
	const provider = providerLabel(kind);
	if (parts.length === 0) return `${provider}: no usage windows`;
	return `${provider}: ${parts
		.map((part) => {
			const reset = part.resetsAt === undefined ? "" : ` ↻ ${formatReset(part.resetsAt)}`;
			return `${part.label} ${formatPercent(part.percent)}${reset}`;
		})
		.join(" · ")}`;
}

function keyFingerprint(apiKey: string): string {
	return createHash("sha256").update(apiKey).digest("hex");
}

function emptyLedger(): KeyLedger {
	return { version: 1, keys: {} };
}

async function readLedger(): Promise<KeyLedger> {
	try {
		const parsed = JSON.parse(await readFile(LEDGER_PATH, "utf8"));
		return parsed?.version === 1 && asRecord(parsed.keys) ? (parsed as KeyLedger) : emptyLedger();
	} catch {
		return emptyLedger();
	}
}

async function acquireLedgerLock(): Promise<void> {
	await mkdir(dirname(LEDGER_PATH), { recursive: true });
	for (let attempt = 0; attempt < 100; attempt++) {
		try {
			await mkdir(LOCK_PATH);
			return;
		} catch (error) {
			if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error;
			try {
				const info = await stat(LOCK_PATH);
				if (Date.now() - info.mtimeMs > 30_000) {
					await rm(LOCK_PATH, { recursive: true, force: true });
					continue;
				}
			} catch {
				continue;
			}
			await new Promise((resolve) => setTimeout(resolve, 50));
		}
	}
	throw new Error("Timed out waiting for provider usage ledger lock");
}

async function updateKeySpend(
	fingerprint: string,
	provider: string,
	cost: number,
	eventId: string,
): Promise<number> {
	await acquireLedgerLock();
	try {
		const ledger = await readLedger();
		const current = ledger.keys[fingerprint] ?? {
			provider,
			spent: 0,
			updatedAt: Date.now(),
			eventIds: [],
		};
		if (!current.eventIds.includes(eventId)) {
			current.spent += cost;
			current.updatedAt = Date.now();
			current.eventIds.push(eventId);
			if (current.eventIds.length > MAX_EVENT_IDS_PER_KEY) {
				current.eventIds = current.eventIds.slice(-MAX_EVENT_IDS_PER_KEY);
			}
		}
		ledger.keys[fingerprint] = current;

		const temporaryPath = `${LEDGER_PATH}.${process.pid}.${Date.now()}.tmp`;
		await writeFile(temporaryPath, `${JSON.stringify(ledger, null, 2)}\n`, { mode: 0o600 });
		await rename(temporaryPath, LEDGER_PATH);
		return current.spent;
	} finally {
		await rm(LOCK_PATH, { recursive: true, force: true });
	}
}

async function readKeySpend(fingerprint: string): Promise<number> {
	return (await readLedger()).keys[fingerprint]?.spent ?? 0;
}

function messageEventId(message: {
	provider: string;
	model: string;
	responseId?: string;
	timestamp: number;
	usage: { totalTokens: number; cost: { total: number } };
}): string {
	return createHash("sha256")
		.update(
			[
				message.provider,
				message.model,
				message.responseId ?? "",
				message.timestamp,
				message.usage.totalTokens,
				message.usage.cost.total,
			].join("\0"),
		)
		.digest("hex");
}

async function resolveModelAuth(
	ctx: ExtensionContext,
	model: NonNullable<ExtensionContext["model"]>,
): Promise<{ apiKey: string; isOAuth: boolean } | undefined> {
	const auth = await ctx.modelRegistry.getApiKeyAndHeaders(model);
	if (!auth.ok || !auth.apiKey) return undefined;

	// This reflects effective auth, including a --api-key runtime override.
	return { apiKey: auth.apiKey, isOAuth: ctx.modelRegistry.isUsingOAuth(model) };
}

async function resolveDisplayMode(ctx: ExtensionContext): Promise<DisplayMode | undefined> {
	const model = ctx.model;
	if (!model) return undefined;

	const auth = await resolveModelAuth(ctx, model);
	if (!auth) return undefined;
	if (auth.isOAuth) {
		// Provider usage endpoints are available only for these subscription providers.
		const kind = providerKind(model.provider);
		if (kind && (model.provider === "anthropic" || model.provider === "openai-codex")) {
			return { type: "oauth", kind, id: `oauth:${model.provider}` };
		}
		return undefined;
	}

	const fingerprint = keyFingerprint(auth.apiKey);
	return {
		type: "api-key",
		provider: model.provider,
		label: ctx.modelRegistry.getProviderDisplayName(model.provider),
		fingerprint,
		id: `key:${fingerprint}`,
	};
}

export default function providerUsage(pi: ExtensionAPI) {
	const cache = new Map<ProviderKind, CacheEntry>();
	let sessionStarted = false;
	let tuiActive = false;
	let timer: ReturnType<typeof setInterval> | undefined;
	let inFlight: Promise<void> | undefined;
	let inFlightKind: ProviderKind | undefined;
	let selectedModeId: string | undefined;

	const refresh = async (ctx: ExtensionContext, force = false): Promise<void> => {
		if (!tuiActive) return;

		const mode = await resolveDisplayMode(ctx);
		selectedModeId = mode?.id;
		if (!mode) {
			ctx.ui.setStatus(STATUS_ID, undefined);
			return;
		}

		if (mode.type === "api-key") {
			const spent = await readKeySpend(mode.fingerprint);
			if (tuiActive && selectedModeId === mode.id) {
				const shortKey = mode.fingerprint.slice(0, 6);
				ctx.ui.setStatus(
					STATUS_ID,
					`${mode.label} API key ${shortKey}: ${formatMoney(spent)} tracked`,
				);
			}
			return;
		}

		const cached = cache.get(mode.kind);
		if (cached) ctx.ui.setStatus(STATUS_ID, cached.text);
		if (!force && cached && Date.now() - cached.fetchedAt < REFRESH_INTERVAL_MS) return;
		if (inFlight && inFlightKind === mode.kind) return inFlight;

		if (!cached) ctx.ui.setStatus(STATUS_ID, `${providerLabel(mode.kind)}: checking usage…`);

		inFlightKind = mode.kind;
		inFlight = (async () => {
			try {
				const parts =
					mode.kind === "anthropic" ? await fetchAnthropicUsage(ctx) : await fetchOpenAIUsage(ctx);
				const text = formatSubscriptionStatus(mode.kind, parts);
				cache.set(mode.kind, { text, fetchedAt: Date.now() });
				if (tuiActive && selectedModeId === mode.id) ctx.ui.setStatus(STATUS_ID, text);
			} catch {
				if (!cached && tuiActive && selectedModeId === mode.id) {
					ctx.ui.setStatus(STATUS_ID, `${providerLabel(mode.kind)}: usage unavailable`);
				}
			} finally {
				inFlight = undefined;
				inFlightKind = undefined;
			}
		})();

		return inFlight;
	};

	pi.on("session_start", (_event, ctx) => {
		sessionStarted = true;
		if (ctx.mode !== "tui") return;
		tuiActive = true;
		void refresh(ctx, true);
		timer = setInterval(() => void refresh(ctx), REFRESH_INTERVAL_MS);
		timer.unref();
	});

	pi.on("model_select", (_event, ctx) => {
		if (!tuiActive) return;
		selectedModeId = undefined;
		ctx.ui.setStatus(STATUS_ID, undefined);
		void refresh(ctx, true);
	});

	pi.on("message_end", async (event, ctx) => {
		if (!sessionStarted || event.message.role !== "assistant") return;
		const message = event.message;
		const cost = finiteNumber(message.usage.cost.total);
		if (cost === undefined || cost <= 0) return;

		const model = ctx.modelRegistry.find(message.provider, message.model);
		if (!model) return;
		const auth = await resolveModelAuth(ctx, model);
		if (!auth || auth.isOAuth) return;

		const fingerprint = keyFingerprint(auth.apiKey);
		await updateKeySpend(fingerprint, message.provider, cost, messageEventId(message));
		if (tuiActive && ctx.model?.provider === message.provider) await refresh(ctx, true);
	});

	pi.on("agent_settled", (_event, ctx) => {
		void refresh(ctx, true);
	});

	pi.on("session_shutdown", (_event, ctx) => {
		sessionStarted = false;
		tuiActive = false;
		selectedModeId = undefined;
		if (timer) clearInterval(timer);
		timer = undefined;
		ctx.ui.setStatus(STATUS_ID, undefined);
	});
}
