# Solo Compass Telegram bot
#
# Long-polling locally; webhook in prod (set WEBHOOK_URL).

FROM node:25-alpine@sha256:bdf2cca6fe3dabd014ea60163eca3f0f7015fbd5c7ee1b0e9ccb4ced6eb02ef4 AS base
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
USER node
EXPOSE 8080

CMD ["./node_modules/.bin/tsx", "src/index.ts"]
