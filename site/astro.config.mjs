// @ts-check
import { defineConfig } from "astro/config";

// Static output only: no SSR, no API routes, no secrets (docs/ARCHITECTURE.md §7.1).
export default defineConfig({
  site: "https://dimit.uz",
  output: "static",
  // Default directory format (/uz/download/index.html): every static host
  // serves it for both /uz/download and /uz/download/ without configuration.
  i18n: {
    defaultLocale: "en",
    locales: ["en", "uz", "ru"],
    routing: { prefixDefaultLocale: false },
  },
});
