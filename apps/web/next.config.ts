import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  reactStrictMode: true,
  transpilePackages: ["@solo-compass/core", "@solo-compass/ai", "@solo-compass/data"],
};

export default nextConfig;
