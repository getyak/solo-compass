# Solo Compass Telegram bot
#
# Long-polling locally; webhook in prod (set WEBHOOK_URL).

FROM node:20-alpine AS base
RUN corepack enable
WORKDIR /app

# Workspace install — copy minimum needed for dependency graph.
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml turbo.json tsconfig.base.json ./
COPY apps/bot/package.json apps/bot/
COPY apps/bot/tsconfig.json apps/bot/
COPY packages/core/package.json packages/core/
COPY packages/ai/package.json packages/ai/

RUN pnpm install --frozen-lockfile --filter @solo-compass/bot...

# Sources
COPY packages/core packages/core
COPY packages/ai packages/ai
COPY apps/bot apps/bot

WORKDIR /app/apps/bot

ENV NODE_ENV=production
EXPOSE 8080

CMD ["pnpm", "start"]
