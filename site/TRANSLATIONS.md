# Site translations — review before launch

`src/i18n/index.ts` holds all copy. English is the source. The Uzbek (Latin) and Russian
versions were written by Claude alongside the English on 2026-09-10, not by a fluent
reviewer — docs/PLAN.md §2 C7 "Done when" requires a fluent person to read both before
the site goes live. Things to check specifically: product terms (Iliqlik/Yorqinlik,
Теплота/Яркость match the app's own strings), the legal pages (terms/privacy/refund),
and anything that reads as a health claim (CLAUDE.md §1.7: none allowed).
