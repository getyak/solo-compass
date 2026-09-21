# apps/bot · Telegram bot

> Telegraf + DeepSeek Flash. The lowest-cost validation lane.

## Why a Telegram bot

If the web app + iOS app are the "real product", the bot is the **cheap shadow** that runs in parallel to test specific hypotheses:

- "Will solo travelers really voice-input what they want to do?"
- "Are AI recommendations from raw text intent + location good enough?"
- "Does the experience-as-unit framing translate to a chat UI?"

Most digital nomads in Southeast Asia are already on Telegram. Distribution = a link in three Telegram groups. No App Store. No install.

## Status

🚧 Not started. Tracked as parallel lane to `apps/web`.

## Interaction model (target)

```
User: /start
Bot:  Hey. Where are you right now? (drop a pin or type a place)

User: [drops pin in Chiang Mai old town]
Bot:  Got it — Chiang Mai old city. What do you feel like doing?
       Send a voice note (5-30s) or type.

User: 🎙️ "I want somewhere quiet to read for 2 hours"
Bot:  Three options near you, ranked by fit:

      1. BluPort Reading Room — 8 min walk
         Local students study here, upstairs is quiet.

      2. Suriwong Books Café — 12 min walk
         An old bookstore with a café corner. Almost no tourists.

      3. Akha Ama (2nd floor) — 6 min walk
         Their second floor is the quiet one. First is loud.

      Pick one to see details, or send another voice note.
```

## Stack (target)

- Telegraf (Telegram bot framework)
- `@solo-compass/ai` for recommendations
- `@solo-compass/data` for experience lookup
- Whisper API for voice-to-text
- DeepSeek Flash (`deepseek-flash`, `DEEPSEEK_API_KEY`) for intent parsing, ranking, and explanation
