import type { NextConfig } from "next";
import { withSentryConfig } from "@sentry/nextjs";
import path from "node:path";

const nextConfig: NextConfig = {
  reactStrictMode: true,
  output: "standalone",
  outputFileTracingRoot: path.join(process.cwd(), "../.."),
  transpilePackages: ["@solo-compass/core", "@solo-compass/ai", "@solo-compass/data"],
};

export default withSentryConfig(nextConfig, { silent: true });
