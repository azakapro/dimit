> **Superseded in part on 2026-09-09** (docs/PLAN.md → Decisions): Dimit is a *paid* download (pay what you want, $5 minimum, Lemon Squeezy) and the repository stays private — not free, not open source, no MIT licence, no GitHub link. §§3–4 and the "free and open source" wording in §§8–9 no longer apply; the beta process (§7), the claims table (§2) and the launch sequence still do. Substitute "pay what you want, from $5" and drop every source/GitHub reference when using the drafts.

# Dimit — first-product launch strategy

Prepared 9 September 2026; pricing discussion added 10 September 2026. A proposed strategy for a solo maker launching an open-source macOS utility. Platform rules, fees, and payout availability were checked during the launch discussion on 9 September; recheck them before activating checkout. Timelines, targets, and effort estimates below are planning assumptions, not forecasts.

## 1. The recommendation

Launch Dimit as a **free, open-source Mac app with optional financial support**. Start with a small Telegram beta, publish the source and a usable download, then use a coordinated content release and Product Hunt to reach more people.

**Pricing decision remains open.** The original audience-building recommendation is free access with optional support, or pay what you want with $0 minimum and $5 suggested. If the goal is to validate sales, the alternative recommendation is **$9 one-time for the packaged DMG, with free source code and build instructions**. Section 4 compares these options, fees, advertising economics, and revenue targets. The free-app copy throughout this document applies only to the free-download route; use the paid-copy substitutions below if choosing the paid DMG.

For your first product, the return can be practical experience, a public portfolio, a small audience that trusts you, and evidence of a problem worth solving. Tips can cover some costs. Do not make revenue or a Product Hunt ranking the condition for calling this launch successful.

The launch offer:

> **Dimit — make your Mac screen warmer and dimmer.**
> A native menu-bar app with warmth controls, software dimming, presets, and schedules. Free and open source. No account or subscription.

Use this copy once the public source, license, and advertised release are actually available. Before then, say “I’m preparing an open-source release.”

**Recommended scope change:** pause the old license-server, trial, activation, and custom checkout work in C7–C9 of `PLAN.md`. Move a simple download website forward, with hosted Lemon Squeezy checkout if choosing paid or pay-what-you-want distribution. Spend the saved time on installation, reliable display restoration, tested compatibility, documentation, and content. Keep the app offline; external purchase/support pages open only when someone chooses to visit them.

This document proposes that change; it does not change the app, grant a source license, publish the repository, or replace the engineering rulebook automatically. Before the next implementation cycle, reconcile `CLAUDE.md`, `PLAN.md`, and `ARCHITECTURE.md` so the old commercial roadmap does not keep driving development.

## 2. Who to reach and what to say

| Audience | Useful opening | Destination | Desired action |
|---|---|---|---|
| Mac users who want more control of screen warmth and dimming | Show the actual screen changing in seconds | Website | Download and try Dimit |
| Developers and open-source enthusiasts | Show how the native app works and a real engineering lesson | GitHub or a build-story video | Inspect, build, report a useful issue, or contribute |
| Your existing Uzbek-speaking community | “I’m launching my first Mac app and need real-world feedback” | Telegram post with download link | Join the beta and report results |
| Product Hunt users | A useful, finished utility with a short visual explanation | Website from Product Hunt | Try it and discuss it |

Lead public product posts with the screen-control benefit. Use “my first product, built from Uzbekistan” as the maker story underneath. Make AI-assisted development a separate developer-content angle; users first need to understand what the app does for them.

Use your existing personal accounts where possible. One Telegram channel with a pinned Dimit post is enough; avoid creating separate communities for every platform and language. Use English for GitHub and Product Hunt, and your natural language for your existing audience. Have a fluent person review Uzbek/Russian public copy and subtitles.

### Keep the claims inside the evidence

The current checkout contains scheduling and experimental DDC code; the README status is older than parts of `PLAN.md` and `QA.md`. Freeze a release and base public claims on that artifact, not on a planned feature or a source file merely existing.

| Subject | Launch wording or action |
|---|---|
| Core functionality | Lead with warmth, software dimming, presets, and schedules after smoke-testing the selected release. |
| Permissions | Dimit must not require Accessibility, Screen Recording, Input Monitoring, or admin. Optional location access is requested only for “Use my location”; city-based scheduling avoids it. Do not say “no permissions ever.” |
| Screen sharing | `QA.md` records untinted Zoom sharing and QuickTime recording in normal gamma mode on the development Mac. Describe this as a tested setup, with a compatibility note. Overlay dimming below 30% and Fallback mode do not have a general capture guarantee. |
| PWM-Safe | Explain the mechanism: it attempts to keep supported hardware backlights at 100% while dimming in software. A brightness read-back is not an optical flicker measurement. Do not promise flicker elimination on every display or use this as the launch headline. |
| External monitors | DDC is experimental, default off, and lacks real-monitor verification in the current QA record. Do not market universal external-monitor control. |
| Compatibility | macOS 13 is the build target, not proof every OS/hardware combination works. Publish “tested on” separately from the minimum version. Intel and other displays need actual testing. |
| Health and battery | Describe display controls. Omit promises about preventing headaches, treating eye strain, improving sleep, or saving battery. Battery impact has not been measured; a full backlight can use more power. |

Sources for this product assessment: `README.md`, `CLAUDE.md` §§1–3, `docs/PLAN.md` C5–C6, `docs/QA.md`, and `project.yml`. This is a review of recorded evidence, not a new hardware verification.

## 3. Open source: yes, with a deliberate license

Open source fits Dimit because curious users can inspect a system-level utility, other Mac owners can help test hardware you do not own, and the repository gives your videos a useful destination. It also makes Dimit a durable portfolio piece.

The tradeoff is that people may copy it, contributions may never arrive, and you still own release quality and support. Source visibility alone does not prove a downloaded binary matches that source or that the app is safe.

**Recommend MIT** if your priority is learning, adoption, and easy reuse. It permits commercial reuse, including closed-source derivatives, while requiring preservation of the copyright and license notices. Choose this knowingly. If keeping distributed derivatives open is essential, evaluate GPLv3 before publishing instead. Do not invent a “no commercial use” restriction and call it open source. [MIT license explanation](https://choosealicense.com/licenses/mit/)

A public repository without a license is not the intended open-source release: people need explicit rights to use, modify, and distribute it. Confirm whether you or your LLC holds the copyright before inserting the license owner. [GitHub licensing guidance](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository)

Before making the source public:

- Add the selected `LICENSE`; preserve dependency notices and confirm redistribution rights for icons, screenshots, and any borrowed code.
- Review tracked files and history for credentials, signing material, private diagnostics, and personal/customer data. If a credential was exposed, rotate it; deleting the latest copy is insufficient.
- Rewrite the README around the user: what it does, demo, download, tested systems, installation, limitations, support, then build instructions.
- Verify a fresh clone builds. Document actual Xcode/toolchain and XcodeGen requirements; do not promise that the latest development toolchain runs on every supported target OS.
- Publish a versioned release, matching source tag, DMG, checksum, and release notes. Mark whether the download is notarized. A checksum detects a changed file but does not replace signing.
- Add short contribution instructions and a bug template asking for app version, Mac model, macOS, display/connection, reproduction steps, and expected versus actual behavior. Avoid asking for serial numbers or unreviewed full logs.
- Mark hardware testing, documentation, and human translation review as welcome contributions. Do not call unverified display-driver work an easy beginner issue.
- Add a funding link only after the payment account is ready. Keep this strategy and other internal planning documents out of the README's primary navigation.

Keep source access ungated. For free distribution, also provide a direct download without an email or social-membership requirement. For the paid-DMG option, checkout may require payment and receipt details, but never require Telegram membership, GitHub stars, or social follows. Say clearly that the source can be built for free.

## 4. Monetization: pricing, support, and realistic earnings

### 4.1 Free download with optional support

**If choosing a free direct download, start with Buy Me a Coffee for general users.** The concept is easy to explain: “If Dimit is useful to you, you can support its development.” Suggest $5, with optional $3 and $10 amounts. Every user gets the same app. Choose one payment approach initially rather than adding Buy Me a Coffee, GitHub Sponsors, and Lemon Squeezy together.

Buy Me a Coffee currently lists **Uzbekistan under Stripe Express payouts**. That is provider-specific availability; it does not imply that every Stripe product is available to an Uzbek business. Complete identity and bank onboarding and confirm your account can receive payouts before promoting it. [Supported payout countries](https://help.buymeacoffee.com/en/articles/6258038-supported-countries-for-payouts-on-buy-me-a-coffee)

It has no monthly platform fee and charges a 5% platform fee, with payment-processing costs also applying. Its help page gives 2.9% + $0.30 as a typical processing rate; actual payout, conversion, and other applicable charges can differ. [Buy Me a Coffee overview and fees](https://help.buymeacoffee.com/en/articles/10182730-what-is-buy-me-a-coffee-and-how-does-it-work)

**GitHub Sponsors is a good second option** once the public project is established. It also lists Uzbekistan. Sponsorships from personal accounts have no GitHub fee; organization-funded sponsorships have fees up to 6%. Eligibility and onboarding still apply. Start with one funding service; add the second only if it helps your audience. [GitHub Sponsors](https://docs.github.com/en/sponsors/getting-started-with-github-sponsors/about-github-sponsors)

Place the support link in the website footer, a README support section, and a pinned Telegram resource post. The primary button remains **Download for Mac**. Skip donation popups and paid feature locks. If payout onboarding is delayed, launch with no funding button and add it later.

Suggested support-page copy:

> Dimit is free and open source. If it has earned a place in your menu bar, you can help cover signing and continued maintenance. Support is optional and does not unlock additional features or guarantee a delivery date.

Illustrative economics, not a prediction:

| Scenario | Gross support | Approximate amount after 5% + 2.9% + $0.30 per payment |
|---|---:|---:|
| 10 people give $5 | $50 | $43.05 |
| 25 people give $5 | $125 | $107.63 |
| 50 people give $5 | $250 | $215.25 |

Those figures exclude any additional charges and taxes. Under this simplified example, about 23 $5 tips cover a $99 membership fee before those other costs. Budget as if you receive **zero tips**; a donation button is not a reliable business model on its own.

After 60–90 days, review whether support covers costs and whether maintenance still fits your schedule. You can keep Dimit as a free portfolio project, seek a relevant sponsor, or build a separate paid product from what you learn. Do not promise lifetime maintenance or imply that already granted open-source rights can later be withdrawn from recipients.

### 4.2 Lemon Squeezy can sell and deliver the DMG

The flow is **website → hosted checkout → payment → DMG download**, with a receipt email containing access to the purchase. Upload the DMG as a digital product and place its checkout link or overlay on the website. This does not require a custom payment server, app accounts, license activation, or network calls inside Dimit. Replacing product files can also make updated downloads available to existing customers; define what updates the purchase includes before selling. [Product setup and file delivery](https://docs.lemonsqueezy.com/help/products/adding-products)

Lemon Squeezy lists **Uzbekistan for bank payouts**, subject to merchant activation and identity/bank checks. Country support does not guarantee account approval. It also currently excludes purchases from the Russian Federation, which matters if the Russian-language audience is part of the launch. [Supported merchant and customer countries](https://docs.lemonsqueezy.com/help/getting-started/supported-countries)

Lemon Squeezy handles checkout and delivery; it does not sign or notarize the app. Test installation from the purchased artifact and the receipt-download path before broad promotion.

| Option | Offer | What it tests | Recommendation |
|---|---|---|---|
| Free + optional tips | Free direct DMG; separate support link | Adoption, feedback, audience growth | Best fit for the original first-product goal |
| Pay what you want | $0 minimum; $5 suggested for the DMG | Adoption plus voluntary payment | Good if you want one checkout service; keep a direct free path to avoid forcing receipt details on everyone |
| $1 fixed | $1 for the packaged DMG; source free | Very low-price purchases | Avoid: the fixed processing fee consumes much of the sale |
| $5 fixed | $5 one-time DMG; source free | First paid customers | A possible introductory test; limited advertising margin |
| $9 fixed | $9 one-time DMG; source free | Willingness to pay for a usable, packaged app | Recommended starting experiment if revenue is the priority |
| $9–$15 price experiment | Test a higher price after initial sales | Whether more margin offsets fewer purchases | An experiment, not an established market price |

Lemon Squeezy supports minimum and suggested prices for pay-what-you-want products. [Pricing configuration](https://docs.lemonsqueezy.com/help/products/pay-what-you-want)

Charging for the packaged download can coexist with an MIT-licensed source repository. Buyers pay for the offered distribution and convenience; the license still permits others to build and redistribute it, including commercially. Do not promise exclusive access or describe the paid download as a required open-source license fee. [MIT permissions](https://choosealicense.com/licenses/mit/)

### 4.3 What remains from each sale

Lemon Squeezy's standard base fee is **5% + $0.50 per transaction**. The simple examples below assume no sales tax in the order and no additional fees: amount remaining = price × 0.95 − $0.50.

| Product price | Base fee | Amount after base fee | Base fee as share of price |
|---|---:|---:|---:|
| $1 | $0.55 | $0.45 | 55% |
| $3 | $0.65 | $2.35 | 21.7% |
| $5 | $0.75 | $4.25 | 15% |
| $9 | $0.95 | $8.05 | 10.6% |
| $15 | $1.25 | $13.75 | 8.3% |

These amounts are **not take-home profit**. Fees are calculated on the total order value, including sales tax where applicable. Additional charges include 1.5% for international transactions, 1.5% for PayPal, and a 1% bank-payout fee outside the US; other features can incur fees. Taxes, refunds, advertising, and ongoing costs further affect what remains. Use the actual settlement figures to evaluate profitability. [Lemon Squeezy fee schedule](https://docs.lemonsqueezy.com/help/getting-started/fees)

### 4.4 Can a $5 product pay for targeted advertising?

Only if the cost of acquiring a paying customer stays below the amount left from that sale. At $5, **$4.25 is an optimistic ceiling before extra fees and all other costs**, not a sustainable acquisition target. Aim below **$2.50 per paying customer** for an initial $5 experiment to leave some margin; this is a suggested decision threshold, not an expected ad result.

Hypothetical example: $100 spent on Instagram/Facebook ads, $0.20 per website click, giving 500 clicks. The click price and purchase rates here are assumptions, not market benchmarks.

| Share of clicks resulting in a $5 purchase | Buyers | Sales revenue | After base fees | After the $100 ad spend |
|---|---:|---:|---:|---:|
| 1% | 5 | $25 | $21.25 | −$78.75 |
| 2% | 10 | $50 | $42.50 | −$57.50 |
| 5% | 25 | $125 | $106.25 | +$6.25 |

Even the last row barely covers media spend before other costs. At these assumed click costs, base-fee break-even requires about **4.71% purchase conversion** at $5. At $9 it would require about **2.48%**, but a higher price may reduce conversion; it does not guarantee a better outcome.

Start with organic videos, Telegram, GitHub, and Product Hunt. After real purchases and a reliable installation flow, consider a **capped $50–$100 ad experiment that you can afford to lose**. This is optional and separate from the original launch budget. Measure cost per paid, non-refunded order; free downloads, likes, and video views are not purchases. For pay-what-you-want, calculate actual receipts across the whole campaign rather than assuming everyone pays the suggested $5.

Keep a simple record of campaign spend and attributed orders using checkout/reporting data and optional customer feedback; do not introduce app telemetry. Attribution will be imperfect, especially when someone sees an ad on a phone and later buys on a Mac. Treat the small test as directional evidence. Stop at the cap and review; do not increase spend while acquisition cost exceeds your margin or installation issues remain.

### 4.5 Realistic earnings targets

**Budget for $0. Aim for the first 10–20 paying customers**, ideally including at least 10 people who are not friends. At $9, that means $90–$180 gross and $80.50–$161 after base fees, before other costs. This is a first-month target, not a forecast: audience reach, purchase conversion, and repeat use are not yet established.

| New $9 buyers in a month | Gross sales | After base fees, before all other costs |
|---|---:|---:|
| 10 | $90 | $80.50 |
| 50 | $450 | $402.50 |
| 100 | $900 | $805 |
| 500 | $4,500 | $4,025 |

Tens or hundreds of dollars are a reasonable initial goal to work toward. To reach $500–$1,000 per month **after base fees alone**, you need about 63–125 new $9 buyers each month. Several thousand dollars per month is an upside scenario to validate, not a dependable budget assumption. These numbers describe required sales volume, not the probability of achieving it.

One-time purchases are not recurring revenue: 100 buyers this month do not pay again next month. A Product Hunt spike does not establish steady monthly income. Free downloads with tips are even less predictable; do not apply the paid-buyer table to all downloads.

Before increasing marketing spend, ask consenting customers whether they still use Dimit after a week and what nearly made them uninstall it. Review actual sales, refunds, fees, and acquisition spend after the first month. The next milestone is 50 paying customers and evidence of continued use, rather than a forecast built from stars or views.

## 5. The path from a post to a user

```text
Reels / Shorts / Telegram / Product Hunt
                  ↓
           Dimit landing page
                  ↓
             Download DMG
                  ↓
          Try warmth + dimming
                  ↓
     Optional feedback / updates / support

Developer videos → GitHub → inspect or build → issues / contributions
                         ↘ download the ready-made app
```

The source-code link builds trust and serves developers. It should not force an ordinary Mac user to navigate a repository before downloading.

For the paid route, insert Lemon Squeezy checkout between the landing page and DMG download. Use **Buy for Mac — $9 one-time** as the primary CTA and **View source / build for free** as the secondary link. For pay-what-you-want, say **Download — choose your price**, with the free option visible. Show any applicable tax treatment clearly at checkout.

Use `dimit.uz` if you register and control it; it is currently a planned domain in the project documents. Otherwise launch from an available static page and the release page. Avoid delaying the beta for a premium domain.

The landing page needs:

1. Headline, a one-sentence explanation, and a **Download for Mac** button.
2. A secondary **View source on GitHub** link.
3. A 20–40 second real demonstration.
4. Three feature blocks: warmth, dimming/presets, and scheduling.
5. Current version, minimum OS, tested configurations, signing status, and a short install guide.
6. FAQ: restoring normal colors, capture limitations, optional location, compatibility, and feedback.
7. An optional Telegram updates link and support link, plus a short privacy explanation.

Keep source access ungated and retain an ungated download for the free route. The paid route uses only the necessary purchase and delivery steps. Avoid a multi-step link hub, unrelated email capture wall, or “comment CODE and I’ll DM you” mechanism.

Use distinct web links such as `?utm_source=telegram&utm_medium=social&utm_campaign=first_launch` and analogous `instagram`, `youtube`, and `producthunt` links. These parameters label traffic; they do not collect statistics by themselves. If desired, configure disclosed aggregate website/download counts. Keep attribution out of the app and do not attach individual identifiers to downloads.

## 6. Content you can produce in one recording session

Aim for one useful YouTube video, four short clips reused on Instagram and YouTube, and four Telegram posts over the preparation and launch period. Extra posts are optional. Reserve time for feedback and fixes.

**Record the physical screen with a phone to demonstrate gamma tint.** A normal screen recording can omit the very effect you want to show. Lock the camera exposure and white balance for a fair comparison; keep room lighting and the displayed page constant. Pair this with a crisp screen recording for readable app controls. Label simulated effects if you use them. Phone footage demonstrates appearance, not scientific proof that PWM is gone.

| Asset | Opening / topic | What to show | One main call to action |
|---|---|---|---|
| Short 1, 20–30 seconds | “I wanted more control over my Mac screen at night, so I made Dimit.” | Physical before/after; warmth and brightness sliders | Try the free app via the profile link |
| Short 2, 25–40 seconds | “My screen looks warm, but this recording looks normal.” | Side-by-side physical screen and recorded output on the tested normal-mode setup; state scope | Watch the demo / visit the app page |
| Short 3, 30–45 seconds | “I’m publishing the source of my first Mac app.” | Native UI, repository, one short readable code excerpt | Explore the source |
| Short 4, 20–35 seconds | “A tester found this. Here’s what changed.” | A real reported problem and the verified fix; use only when available | Try the updated release |
| YouTube, 5–7 minutes | “I built a free, open-source Mac screen dimmer — Dimit” | Problem, live demo, install, one build lesson, limitations, source | Download; source link alongside it |
| Telegram 1 | Recruit 10–20 Mac beta testers | Clip + precise test request | Try the beta |
| Telegram 2 | Public source and download announcement | What works, known limitations, direct links | Download or inspect source |
| Telegram 3 | Product Hunt launch | Brief maker story and demo | Try it and share feedback on the launch page |
| Telegram 4 | First-week results | Real numbers, fixes, next small priority | Update and report issues |

Long-video outline: 0:00 physical result; 0:15 problem and who Dimit helps; 0:45 core controls; 2:00 installation and restoring colors; 3:00 native implementation/open-source story; 4:30 limitations and tested hardware; 5:30 links and optional support.

For YouTube Shorts, say “link on my channel” or use a related-video link to the full demo. URLs in Shorts descriptions and comments are not clickable. External links in long-form descriptions/comments require advanced-feature access. Verify access before choosing the CTA. [YouTube link rules](https://support.google.com/youtube/answer/13748639?hl=en)

For Instagram, use a profile website link and, where available, a Story link sticker. Test the path from another account on a phone before posting. For Telegram, put the direct destination link in the post. Reuse footage, but adjust the last sentence to the actual link location.

## 7. Four-week launch schedule

Use relative days so Apple enrollment or a hardware issue does not force a premature date. This is a suggested four-week sequence; unresolved reliability problems extend it.

| Window | Work | Concrete output / decision |
|---|---|---|
| Days 1–3 | Choose free/open-source direction and license; begin signing enrollment if affordable; create Product Hunt profile and complete onboarding; set up optional payout account | Written scope decision and working accounts; no need to wait for donations |
| Days 4–7 | Package a beta; recruit 10–20 testers from people you know and relevant communities that allow it; record first demo | Installable beta, test instructions, at least five completed test reports as an initial target |
| Days 8–14 | Fix installation/restoration problems; test current release on other Macs; prepare public README, license, release and landing page | Public source + download soft launch once ready; no Product Hunt deadline yet |
| Days 15–18 | Publish full video and first short; use Telegram feedback to improve page clarity; prepare Product Hunt gallery and copy | One coherent launch kit and a support FAQ |
| Days 19–21 | Check release gates below; schedule Product Hunt on a day you can respond; publish another short | Go / delay decision based on reliability, not follower count |
| Launch day | Verify links, publish maker comment, share launch, answer questions, record issues | Usable app, accessible maker, clear known-issues update if needed |
| Days 22–28 | Ship necessary fixes, publish recap, follow up with consenting testers, review traffic sources | First learning report and next small maintenance release |

A preparation budget of **16–24 hours for content, copy, website setup, and account work** is a planning estimate. App fixes, hardware testing, and enrollment waiting are additional. At 5 hours per week, stretch the schedule or reduce assets to one demo, two shorts, and three Telegram posts.

### Minimum release gates

- [ ] A fresh browser download opens on a tester's Mac using the published instructions. Test the distributed artifact, not only an Xcode build.
- [ ] OFF, quit, recovery after interruption, and sleep/wake work for the configurations you advertise. Resolve or narrow around open restoration issues in `QA.md`.
- [ ] At least one Mac on a stable macOS release has been tested in addition to the development beta OS. Do not market Intel or all older versions as verified without evidence.
- [ ] Any known issue that can leave the display unusable is resolved before broad promotion. Experimental DDC stays off by default and outside the headline offer.
- [ ] The page lists real tested configurations and capture limitations. Every demo matches the shipped version.
- [ ] The source license, release tag, artifact, download link, and install instructions agree.
- [ ] There is one clear feedback route and time reserved to answer it.

**Signing choice:** a clearly labeled unsigned/ad-hoc beta can start immediately. Users may need System Settings → Privacy & Security → Open Anyway after attempting to open it; managed Macs can restrict this. Link to [Apple's official instructions](https://support.apple.com/en-gb/102445). Open source does not remove Gatekeeper checks.

Recommend Developer ID signing and notarization before the larger Product Hunt push. If you choose to launch unsigned, disclose that near the download button and in release notes, and expect installation friction. Signing is a recommendation for distribution quality, not a requirement to publish source or a Product Hunt eligibility rule. Notarization is separate from App Store review. [Apple direct distribution](https://developer.apple.com/documentation/technologyoverviews/distribution)

## 8. Product Hunt launch kit

Post it yourself from your personal maker account. Complete onboarding well in advance and confirm the account can post before announcing a date; current help pages describe onboarding, while the launch guide also mentions a one-week participation wait. There is no need to hire a hunter. The primary URL should lead to the usable product page. [Posting instructions](https://help.producthunt.com/en/articles/479557-how-to-post-a-product), [launch preparation guidance](https://www.producthunt.com/launch/sharing-your-launch)

Suggested listing, ready to adapt after the open-source release:

**Name:** Dimit

**Tagline:** Free, open-source warmth and dimming for your Mac

**Description:** Dimit is a native macOS menu-bar app for screen warmth, software dimming, presets, and schedules. Free and open source, with no account or subscription. Download the app or explore the code.

**Pricing:** Free for the free-download route. Optional tips do not create a paid feature tier. If selling the packaged DMG, choose the Product Hunt pricing label that accurately reflects paid downloads and disclose the free-source option in the description; do not mark it free solely because source code is available.

**Paid-route copy substitutions:**

- Tagline: “Open-source warmth and dimming for your Mac”.
- Description: “Dimit is a native macOS menu-bar app for screen warmth, software dimming, presets, and schedules. Get the packaged app for $9 one-time, or build it from the free source code. No subscription.”
- Replace “app and source for free” in the maker comment with “source for free, with a packaged Mac download for $9 one-time”.
- Apply the same distinction to the website, gallery, video titles, and all social drafts below. Use the actual selected price everywhere, and describe included updates consistently.

**Topics:** Choose the closest available macOS, open-source, and productivity topics in the posting form.

**Gallery plan:**

1. App UI with “Make your Mac screen warmer and dimmer.”
2. Physical display comparison, clearly labeled as a camera photo.
3. Presets and schedule controls, from the released app.
4. “Free and open source” with source and compatibility cues.

Prepare a square thumbnail and landscape gallery. Product Hunt currently recommends 240×240 for the thumbnail and 1270×760 for gallery images; a visible gallery needs at least two images. Its video field accepts full YouTube URLs; upload ahead of time and make the demo accessible. [Asset requirements](https://help.producthunt.com/en/articles/479557-how-to-post-a-product)

**First maker comment:**

> Hi Product Hunt — I’m [NAME], a maker from Uzbekistan, and Dimit is my first product.
>
> I built it to give Mac users a simple way to adjust screen warmth and software dimming from the menu bar. It includes presets and schedules, and I’m releasing the app and source for free.
>
> The download page lists tested systems and current limitations, including experimental external-display controls. Optional tips help with maintenance; the app has no paid feature locks.
>
> I’d love feedback on installation and everyday use: does Dimit work on your Mac, and what is the first thing you would change?
>
> Download: [SITE] · Source: [REPO]

Pick a day when you can spend roughly 4–6 hours across several sessions responding. Use the scheduler's displayed launch time and verify its conversion to Tashkent time; do not rely on an old PST/PDT conversion copied from a guide.

On launch day, check the page and download first, post the maker comment, then share one relevant announcement per channel. Ask existing testers for honest experiences if they want to participate. Request feedback, not votes; avoid vote swaps, rewards for votes, bulk unsolicited messages, and paid hunters. [Promotion rules](https://www.producthunt.com/launch/sharing-your-launch)

Product Hunt is one distribution channel. Homepage featuring is discretionary, and an immediately usable product gives the launch a stronger foundation. If it is not featured, keep sharing the useful demo and helping users. [Featuring criteria](https://help.producthunt.com/en/articles/9883485-product-hunt-featuring-guidelines)

## 9. Ready-to-edit social posts

All links below are placeholders. Replace them only with verified public destinations. These are drafts for you to publish; none have been sent.

**Telegram beta invitation**

> I’m preparing my first product: Dimit, a small Mac menu-bar app for screen warmth and dimming.
>
> I’m looking for 10–20 people to try it and tell me what breaks. The most useful checks are installation, adjusting the screen, sleeping/waking the Mac, and confirming that quitting restores normal colors.
>
> Beta download + tested systems + installation notes: [BETA_PAGE]
>
> Send feedback to [FEEDBACK]: Mac model, macOS version, display setup, and what happened. Please check the release notes before trying experimental display controls.

**Telegram / personal social launch**

> My first product is out: Dimit.
>
> It lets you adjust your Mac screen’s warmth and dimming from the menu bar, with presets and schedules. I’m releasing it free and open source so you can use it, inspect it, or help improve it.
>
> Download + compatibility: [SITE]
> Source: [REPO]
>
> If you try it, tell me whether it works on your Mac and what felt confusing. I’m especially interested in installation feedback.

**Instagram caption / Short 1 script**

> I wanted more control over my Mac screen, so I built a small app called Dimit. Here’s the screen before, and here it is with warmth and dimming adjusted. It lives in the menu bar, and I’m releasing it free and open source. Download and source are at the link on my profile.

**Developer post / Short 3 script**

> I’m open-sourcing my first macOS app, Dimit. It changes screen warmth and dimming from the menu bar. One lesson from building it: a successful display API call doesn’t always mean the physical screen changed. I’m sharing the implementation, tests, and known limitations here: [REPO]. Hardware test reports and readable bug reports are welcome.

**Product Hunt announcement**

> Dimit, my free, open-source Mac warmth and dimming app, is on Product Hunt today. The app is available to try, and I’d appreciate honest feedback on installation and daily use: [PH_URL].

**First-week recap**

> One week after releasing Dimit: [DOWNLOAD_EVENTS] download events, [TESTER_COUNT] people who sent test reports, and [FIX_COUNT] fixes shipped. These are downloads and voluntary reports, not tracked active users. The most useful lesson was [LESSON]. Next I’m working on [ONE_PRIORITY]. Latest release: [SITE].

## 10. What to measure without tracking people inside the app

Use a simple weekly spreadsheet or Markdown table. Check platform statistics and voluntary feedback; do not add telemetry, activation calls, or update pings to measure launch success.

| Measure | Collection | Initial target / interpretation |
|---|---|---|
| People who actually tried the beta | Voluntary replies from recruited testers | 10–20 recruited; aim for at least 5 complete reports before broader sharing |
| Website visits and download requests | Aggregate host counts if configured and disclosed | Directional channel comparison; bots, reloads, and repeat downloads affect totals |
| GitHub release downloads and stars | Repository/release statistics | Downloads are not installs; stars measure interest, not regular use |
| Useful feedback | Manual issue log | 10 specific reports or conversations in the first month is a useful learning target |
| Returning use | Ask consenting testers again after seven days | Aim for 5 people saying they used it on several days; report sample size and nonresponses |
| Sales / support money | Checkout or funding dashboard | Record gross, fees, refunds, and actual settlements; $0 is an acceptable first-month outcome |
| Paying customers and acquisition cost | Non-refunded order counts and campaign spend | First 10–20 buyers as a target; evaluate ad spend per attributed buyer against actual margin |
| Maker audience | Platform follower/subscriber changes | Observe whether people want the next update; no minimum required |

A reasonable first-month aspiration is **100 download events and five repeat users identified through voluntary follow-up**. This is a target, not a forecast or a requirement for launching. With a small starting audience, fewer downloads plus strong feedback can still justify continuing.

Decision rules:

- People watch but do not visit: make the use case and link location clearer; test that the link is reachable.
- People visit but do not download: check compatibility, signing disclosure, and whether the value is understandable. Website conversion is only meaningful if both visits and download requests are measured consistently.
- People download but cannot open it: prioritize installation instructions and signing before more promotion.
- People try it once but do not return: interview five volunteers about what they expected and what they use instead.
- Developers star it but users do not adopt it: keep the developer audience, but make the next video a practical use case rather than another code tour.
- Repeated restoration or display-control failures: pause broad promotion, update known issues, and fix the release.

Ask follow-up recipients: “Did you use Dimit again this week? Which feature did you use, and what almost made you uninstall it?” Do not turn incomplete replies into a retention percentage for all users.

## 11. Spend and maintenance limits

| Item | Recommended first-launch spend |
|---|---|
| Product Hunt standard submission, organic social posts, public source | $0 platform posting budget; no paid promotion |
| Apple Developer Program | $99 USD/year or local pricing, plus applicable tax, if choosing the signed/notarized route. [Apple pricing](https://developer.apple.com/help/account/membership/program-enrollment/) |
| Website/domain | Use an existing domain or free hosted address first; set a discretionary $30 domain budget, not a quoted market price |
| Video and images | $0 new equipment/software budget; use your phone and existing editing tools |
| Sales / support checkout | Transaction fees when money is received; use hosted checkout or a support link, no custom payment backend |
| Targeted ads | $0 initially; optional capped $50–$100 test after purchase and installation validation (§4.4) |
| Paid hunters / vote incentives | $0; do not use them |

With signing, aim for a cash budget around **$99–$130 before tax or optional hosting costs**. With an unsigned beta and an existing/free web address, incremental cash spend can be $0. The optional ad experiment adds $50–$100, making the signed route approximately $149–$230 before those other costs. These estimates exclude transaction fees, your development time, and existing tools.

Maintain one public issue tracker, check support a few times per week after launch, and state that this is a solo project without a response-time guarantee. Share small release notes when fixes are ready. Schedule content around real improvements instead of promising a weekly feature release.

## 12. Start here

1. Choose free + support, $0-minimum/$5-suggested, or a $9 paid-DMG experiment with free source (§4). Confirm the license and reconcile the old paid roadmap before further feature work.
2. Prepare one distributable beta and its honest compatibility/install page; start Apple enrollment in parallel if choosing signing.
3. Invite a small set of Mac testers and collect structured reports.
4. Film a 30-second physical-screen demo, then use the same session for the longer video.
5. Prepare the public README, license, matching release, and one support or hosted-checkout service. If selling the DMG, test payment, receipt, download, and installation before launch.
6. Publish the source and download, improve them from feedback, and schedule Product Hunt when the release gates pass.

The first launch should leave you with a product people can use, a source repository people can learn from, and a clear next improvement based on actual feedback.
