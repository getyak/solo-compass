import { Telegraf, Markup, type Context } from "telegraf";
import OpenAI from "openai";
import { toFile } from "openai/uploads";
import { rankExperiences, type RankedExperience } from "@solo-compass/ai";
import type { Experience } from "@solo-compass/core";

import { DEMO_EXPERIENCES } from "./demo-experiences.js";
import { getSession, resetSession } from "./session.js";
import { track, optOut, isOptedOut } from "./lib/analytics.js";
import { initSentry, captureException } from "./lib/sentry.js";

// ─── Config ────────────────────────────────────────────────────────────────────

const TELEGRAM_BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN;
const OPENAI_API_KEY = process.env.OPENAI_API_KEY;
const WEBHOOK_URL = process.env.WEBHOOK_URL;

if (!TELEGRAM_BOT_TOKEN) {
  console.error("Missing TELEGRAM_BOT_TOKEN");
  process.exit(1);
}
if (!OPENAI_API_KEY) {
  console.error("Missing OPENAI_API_KEY");
  process.exit(1);
}
if (!process.env.ANTHROPIC_API_KEY) {
  console.error("Missing ANTHROPIC_API_KEY");
  process.exit(1);
}

const VOICE_MIN_SECONDS = 5;
const VOICE_MAX_SECONDS = 30;

// ─── Clients ───────────────────────────────────────────────────────────────────

initSentry();
const bot = new Telegraf(TELEGRAM_BOT_TOKEN);
const openai = new OpenAI({ apiKey: OPENAI_API_KEY });

// ─── Helpers ───────────────────────────────────────────────────────────────────

function localHour(): number {
  // Demo data is Chiang Mai — UTC+7 fixed for now.
  const utcHour = new Date().getUTCHours();
  return (utcHour + 7) % 24;
}

function escapeMarkdown(text: string): string {
  return text.replace(/([_*[\]()~`>#+\-=|{}.!])/g, "\\$1");
}

function firstSourceLink(exp: Experience): string | undefined {
  for (const s of exp.sources) {
    if (s.url) return s.url;
  }
  return undefined;
}

function formatRanking(ranked: RankedExperience[]): string {
  if (ranked.length === 0) {
    return "No good matches right now. Try a different intent or move closer to the old city.";
  }
  return ranked
    .map((r, i) => {
      const title = escapeMarkdown(r.experience.title);
      const reason = escapeMarkdown(r.reason);
      const solo = `${r.experience.soloScore.overall}/10`;
      const url = firstSourceLink(r.experience);
      const sourceLine = url ? `\n   source: ${escapeMarkdown(url)}` : "";
      return `*${i + 1}\\. ${title}* — ${r.walkingMinutes} min walk · solo ${escapeMarkdown(solo)}\n   ${reason}${sourceLine}`;
    })
    .join("\n\n");
}

function formatDetail(exp: Experience): string {
  const lines: string[] = [];
  lines.push(`*${escapeMarkdown(exp.title)}*`);
  lines.push("");
  lines.push(escapeMarkdown(exp.whyItMatters));
  lines.push("");

  lines.push("*How to:*");
  for (const step of exp.howTo) {
    lines.push(`${step.order}\\. ${escapeMarkdown(step.text)}`);
  }
  lines.push("");

  if (exp.realInconveniences.length > 0) {
    lines.push("*What will go wrong:*");
    for (const inc of exp.realInconveniences) {
      lines.push(`• _${escapeMarkdown(inc.category)}_: ${escapeMarkdown(inc.text)}`);
    }
    lines.push("");
  }

  if (exp.bestTimes.length > 0) {
    const times = exp.bestTimes
      .map((t) => {
        const base = `${t.startHour}–${t.endHour}`;
        return t.note ? `${base} (${t.note})` : base;
      })
      .join(", ");
    lines.push(`*Best time:* ${escapeMarkdown(times)}`);
  }

  lines.push(`*Solo score:* ${exp.soloScore.overall}/10`);
  if (exp.soloScore.hint) {
    lines.push(`_${escapeMarkdown(exp.soloScore.hint)}_`);
  }

  if (exp.sources.length > 0) {
    lines.push("");
    lines.push("*Sources:*");
    for (const s of exp.sources) {
      const label = s.attribution ?? s.type;
      const url = s.url ? ` ${s.url}` : "";
      lines.push(`• ${escapeMarkdown(label)}${escapeMarkdown(url)}`);
    }
  }

  return lines.join("\n");
}

async function transcribeVoice(fileUrl: string, durationSec: number): Promise<string | null> {
  if (durationSec < VOICE_MIN_SECONDS || durationSec > VOICE_MAX_SECONDS) {
    return null;
  }
  const res = await fetch(fileUrl);
  if (!res.ok) {
    throw new Error(`Telegram file fetch failed: ${res.status}`);
  }
  const arrayBuf = await res.arrayBuffer();
  // Audio bytes live only in this Buffer for the duration of the upload; once
  // toFile() resolves and we await Whisper, we drop our reference. We never
  // persist the .ogg to disk and never log the URL.
  let buf: Buffer | null = Buffer.from(arrayBuf);
  try {
    const file = await toFile(buf, "voice.ogg", { type: "audio/ogg" });
    const result = await openai.audio.transcriptions.create({
      file,
      model: "whisper-1",
    });
    return result.text.trim();
  } finally {
    buf = null;
  }
}

// ─── Handlers ──────────────────────────────────────────────────────────────────

bot.start(async (ctx) => {
  resetSession(ctx.from.id);
  const session = getSession(ctx.from.id);
  session.stage = "awaiting_location";
  await track(ctx.from.id, "session_start");
  await ctx.reply(
    [
      "Solo Compass.",
      "",
      "Drop a pin (📎 → Location) or type a place name to start.",
      "Then send a 5–30 second voice note saying what you feel like doing — or type it.",
      "I'll come back with three things worth doing nearby.",
      "",
      "Commands: /nearby /privacy /reset",
    ].join("\n"),
  );
});

bot.command("reset", async (ctx) => {
  resetSession(ctx.from.id);
  await ctx.reply("Reset. Send /start to begin again.");
});

bot.command("privacy", async (ctx) => {
  await ctx.reply(
    [
      "Privacy",
      "",
      "• I never store your Telegram username or display name.",
      "• Your user_id is hashed with a server-side salt before any analytics.",
      "• Voice notes are transcribed by Whisper and the audio is dropped — never written to disk, never sent to Sentry.",
      "• Transcripts are not retained after ranking.",
      "• Errors reported to Sentry have transcripts and message bodies stripped.",
      "",
      "Type /optout to stop all analytics from this device. /start to resume.",
      "Full doc: https://github.com/getyak/solo-compass/blob/main/docs/PRIVACY.md",
    ].join("\n"),
  );
});

bot.command("optout", async (ctx) => {
  await track(ctx.from.id, "opted_out");
  optOut(ctx.from.id);
  resetSession(ctx.from.id);
  await ctx.reply("Opted out. No further events from this chat. /start to resume.");
});

bot.command("nearby", async (ctx) => {
  const session = getSession(ctx.from.id);
  if (!session.location) {
    await ctx.reply(
      "I need a location first.",
      Markup.keyboard([[Markup.button.locationRequest("📍 Share location")]])
        .oneTime()
        .resize(),
    );
    session.stage = "awaiting_location";
    return;
  }
  // Already have location — ask for intent.
  session.stage = "awaiting_intent";
  await ctx.reply("What do you feel like doing? Voice (5–30s) or text.");
});

bot.on("location", async (ctx) => {
  const session = getSession(ctx.from.id);
  const { latitude, longitude } = ctx.message.location;
  session.location = [longitude, latitude];
  session.stage = "awaiting_intent";
  await ctx.reply(
    "Location locked.\n\nWhat do you feel like doing? Send a voice note (5–30s) or type.",
    Markup.removeKeyboard(),
  );
});

bot.on("voice", async (ctx) => {
  const session = getSession(ctx.from.id);
  if (!session.location) {
    await ctx.reply("Send a location pin first (📎 → Location).");
    return;
  }

  const voice = ctx.message.voice;
  if (voice.duration < VOICE_MIN_SECONDS) {
    await ctx.reply(
      `Voice was too short. Aim for ${VOICE_MIN_SECONDS}–${VOICE_MAX_SECONDS} seconds, or type instead.`,
    );
    return;
  }
  if (voice.duration > VOICE_MAX_SECONDS) {
    await ctx.reply(
      `Voice was too long. Keep it under ${VOICE_MAX_SECONDS} seconds — one or two sentences is enough. Or type instead.`,
    );
    return;
  }

  await ctx.sendChatAction("typing");
  let transcript: string | null;
  try {
    const link = await ctx.telegram.getFileLink(voice.file_id);
    transcript = await transcribeVoice(link.toString(), voice.duration);
  } catch (err) {
    console.error("voice transcribe failed");
    captureException(err, { stage: "transcribe" });
    await ctx.reply(
      "Couldn't transcribe that voice note. The bot didn't understand the audio. Try recording again in a quieter spot — or just type what you feel like doing.",
    );
    return;
  }

  if (!transcript) {
    await ctx.reply(
      "Couldn't make sense of that voice note. Try recording again — or just type what you feel like doing.",
    );
    return;
  }

  await handleIntent(ctx, transcript);
});

bot.on("text", async (ctx) => {
  const session = getSession(ctx.from.id);
  const text = ctx.message.text;

  if (session.stage === "awaiting_location" || !session.location) {
    await ctx.reply(
      "I need a real location pin to give walking distances. Use 📎 → Location, or share live location.",
    );
    return;
  }

  if (session.stage === "awaiting_intent") {
    await handleIntent(ctx, text);
    return;
  }

  // Allow follow-up intents after a previous ranking — treat any text as a new intent.
  await handleIntent(ctx, text);
});

bot.on("callback_query", async (ctx) => {
  const data = "data" in ctx.callbackQuery ? ctx.callbackQuery.data : undefined;
  if (!data) {
    await ctx.answerCbQuery();
    return;
  }

  const userId = ctx.from?.id;
  if (data.startsWith("detail:")) {
    const expId = data.slice("detail:".length);
    const exp = DEMO_EXPERIENCES.find((e) => (e.id as string) === expId);
    if (!exp) {
      await ctx.answerCbQuery("That option is no longer in this list.");
      return;
    }
    await ctx.answerCbQuery();
    if (userId) {
      await track(userId, "experience_opened", { experience_id: expId });
    }
    await ctx.reply(formatDetail(exp), {
      parse_mode: "MarkdownV2",
      ...Markup.inlineKeyboard(
        [
          Markup.button.callback("✅ Did it", `did:${expId}`),
          Markup.button.callback("⏭ Skip", `skip:${expId}`),
          Markup.button.callback("🚩 Report broken", `report:${expId}`),
        ],
        { columns: 3 },
      ),
    });
    return;
  }

  if (data.startsWith("did:") || data.startsWith("skip:") || data.startsWith("report:")) {
    const [action, expId] = data.split(":");
    if (userId && expId) {
      const eventName =
        action === "did"
          ? "experience_completed"
          : action === "skip"
            ? "experience_skipped"
            : "experience_reported";
      await track(userId, eventName, { experience_id: expId });
    }
    const ack =
      action === "did"
        ? "Logged. Glad it worked."
        : action === "skip"
          ? "Skipped."
          : "Flagged. We'll look at it.";
    await ctx.answerCbQuery(ack);
    return;
  }

  await ctx.answerCbQuery();
});

// ─── Core flow ─────────────────────────────────────────────────────────────────

async function handleIntent(ctx: Context, intent: string): Promise<void> {
  const userId = ctx.from!.id;
  const session = getSession(userId);
  if (!session.location) {
    await ctx.reply("Send a location pin first (📎 → Location).");
    return;
  }

  session.lastIntent = intent;
  await ctx.sendChatAction("typing");
  await track(userId, "intent_submitted");

  let result;
  try {
    result = await rankExperiences({
      userLocation: session.location,
      userIntent: intent,
      availableExperiences: [...DEMO_EXPERIENCES],
      currentHour: localHour(),
    });
  } catch (err) {
    console.error("rankExperiences failed");
    captureException(err, { stage: "rank" });
    await ctx.reply("Ranking failed. Try again in a moment.");
    return;
  }

  if (result.ranked.length === 0) {
    await ctx.reply("Nothing nearby matched. Try a different intent or share another location.");
    session.stage = "idle";
    return;
  }

  session.lastRankedIds = result.ranked.map((r) => r.experience.id as string);
  session.stage = "idle";

  await track(userId, "recommendations_shown", { count: result.ranked.length });

  const buttons = result.ranked.map((r, i) =>
    Markup.button.callback(
      `${i + 1}. ${shortTitle(r.experience.title)}`,
      `detail:${r.experience.id}`,
    ),
  );

  await ctx.reply(
    `Heard: _${escapeMarkdown(intent)}_\n\n${formatRanking(result.ranked)}\n\nTap one for the full detail\\.`,
    {
      parse_mode: "MarkdownV2",
      ...Markup.inlineKeyboard(buttons, { columns: 1 }),
    },
  );
}

function shortTitle(title: string): string {
  return title.length > 40 ? `${title.slice(0, 37)}…` : title;
}

// ─── Boot ──────────────────────────────────────────────────────────────────────

async function main(): Promise<void> {
  if (WEBHOOK_URL) {
    await bot.telegram.setWebhook(WEBHOOK_URL);
    const port = Number(process.env.PORT ?? 8080);
    await bot.launch({ webhook: { domain: WEBHOOK_URL, port } });
    console.log(`bot listening on webhook ${WEBHOOK_URL} (port ${port})`);
  } else {
    await bot.launch();
    console.log("bot started in long-polling mode");
  }
}

process.once("SIGINT", () => bot.stop("SIGINT"));
process.once("SIGTERM", () => bot.stop("SIGTERM"));

main().catch((err) => {
  console.error("fatal", err);
  captureException(err, { stage: "boot" });
  process.exit(1);
});
