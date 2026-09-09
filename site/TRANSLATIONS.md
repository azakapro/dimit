# Site translations — review before launch

`src/i18n/index.ts` holds all copy. English is the source. The Uzbek (Latin) and Russian
versions were written by Claude alongside the English on 2026-09-10, not by a fluent
reviewer — docs/PLAN.md §2 C7 "Done when" requires a fluent person to read both before
the site goes live. Things to check specifically: product terms (Iliqlik/Yorqinlik,
Теплота/Яркость match the app's own strings), the legal pages (terms/privacy/refund),
and anything that reads as a health claim (CLAUDE.md §1.7: none allowed).

## The app's own strings

On 2026-09-10 the 47 catalog entries that still showed English in Uzbek and Russian
(Settings tabs, hotkey names, schedule screen, onboarding, "Restore Colours", DDC help)
were translated in `Dimit/Resources/Localizable.xcstrings` and left in the
`needs_review` state so Xcode's String Catalog editor lists them for the reviewer.
The site copy names Settings paths using exactly those words (Umumiy / Jadval /
Displeylar / Qo‘shimcha; Основные / Расписание / Дисплеи / Дополнительно; "Ranglarni
tiklash" / «Восстановить цвета»), so review the two together. The app uses a straight
apostrophe in Uzbek (o'rnatilgan), the site the typographic one (o‘rnatilgan) — pick
one before launch.
