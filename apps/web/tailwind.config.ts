import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./src/**/*.{js,ts,jsx,tsx,mdx}"],
  theme: {
    extend: {
      colors: {
        "paper-cream": "#F5F1E8",
        "ink-warm": "#2C2A26",
        "muted-road": "#D9D3C4",
        "soft-green": "#A8B89C",
        "deep-teal": "#2F6B6B",
        "warm-amber": "#C68E3F",
      },
      fontFamily: {
        sans: ["system-ui", "-apple-system", "Segoe UI", "Roboto", "sans-serif"],
      },
    },
  },
  plugins: [],
};

export default config;
