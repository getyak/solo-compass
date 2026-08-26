# Solo Compass Telegram bot
#
# Long-polling locally; webhook in prod (set WEBHOOK_URL).

FROM node:22-alpine@sha256:c610fcdfb1d5b4740dd70c284ed3cb16bb857e0f7166196e36a5501df7a3aa32 AS base
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
