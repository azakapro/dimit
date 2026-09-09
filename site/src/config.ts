// The only place site-wide facts live (docs/ARCHITECTURE.md §7). Everything
// marked TODO is filled in by the owner before launch — the build refuses
// to publish a checkout button while checkoutUrl is still the placeholder.
export const config = {
  siteUrl: "https://dimit.uz",
  // Lemon Squeezy variant checkout URL, from the product's "Share" panel:
  // https://<store>.lemonsqueezy.com/checkout/buy/<variant-uuid>
  // ?embed=1 makes it an overlay; media=0 and desc=0 keep it compact.
  checkoutUrl: "TODO_LEMON_SQUEEZY_CHECKOUT_URL",
  checkoutParams: "embed=1&media=0&desc=0",
  myOrdersUrl: "https://app.lemonsqueezy.com/my-orders",
  // The minimum price appears in the copy itself ("$5" / "5 $" in
  // src/i18n/index.ts, every locale) — grep for it when it changes.
  currentVersion: "0.4",
  minMacOS: "13",
  // Shown in the footer and on the legal pages (docs/ARCHITECTURE.md §7:
  // a real entity and a real contact are a trust advantage).
  legalEntity: "TODO_LEGAL_ENTITY_NAME (LLC)",
  supportEmail: "TODO_support@dimit.uz",
  telegram: "TODO_https://t.me/…",
} as const;

export const checkoutReady = !config.checkoutUrl.startsWith("TODO");
export const checkoutHref = `${config.checkoutUrl}?${config.checkoutParams}`;
