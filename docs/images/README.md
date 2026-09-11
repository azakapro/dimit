# Screenshots for the landing page and README

Two files belong here, both real captures of the popover (⌘⇧4, then Space,
then click the popover):

- `popover-off.png` — the filter off, showing the outlined ON/OFF button
- `popover-on.png` — the filter on, e.g. 2700K at 80% with EVENING selected

`docs/index.html` references both and removes the element if a file is
missing, so the page stays correct until they are added and starts using
them as soon as they are.

Do not generate these from `LayoutRenderTests`: off-screen SwiftUI rendering
silently drops most text labels in headless runs, which was verified twice
and produced a screenshot with no visible controls.
