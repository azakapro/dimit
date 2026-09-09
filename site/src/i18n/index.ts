// All site copy, three languages. English is the source; Uzbek (Latin) and
// Russian were written alongside it and are marked for a fluent review in
// site/TRANSLATIONS.md before launch (docs/PLAN.md §2 C7 "Done when").
// Every claim below has a docs/QA.md row behind it — keep it that way.
export type Lang = "en" | "uz" | "ru";
export const langs: Lang[] = ["en", "uz", "ru"];
export const langNames: Record<Lang, string> = { en: "English", uz: "O‘zbekcha", ru: "Русский" };

export function prefix(lang: Lang): string {
  return lang === "en" ? "" : `/${lang}`;
}

type Faq = { q: string; a: string };
type Dict = {
  nav: { download: string; faq: string; help: string; science: string; changelog: string };
  footer: { terms: string; privacy: string; refund: string; contact: string; myOrders: string; noTracking: string };
  home: {
    title: string; tagline: string; lead: string; cta: string; secondary: string;
    features: { title: string; body: string }[];
    vsTitle: string; vs: { name: string; warmth: string; pwm: string }[];
    priceTitle: string; priceBody: string; priceNote: string;
    honestyTitle: string; honesty: string[];
  };
  download: {
    title: string; lead: string; cta: string; ctaSoon: string; from: string;
    requires: string; testedOn: string; testedList: string[]; notarized: string;
    installTitle: string; install: string[]; lostTitle: string; lost: string;
    afterTitle: string; after: string[];
  };
  faq: { title: string; items: Faq[] };
  help: { title: string; sections: { title: string; body: string[] }[] };
  science: { title: string; intro: string; studiesTitle: string; noClaims: string };
  changelog: { title: string; entries: { version: string; date: string; notes: string[] }[] };
  terms: { title: string; paras: string[] };
  privacy: { title: string; paras: string[] };
  refund: { title: string; paras: string[] };
};

const en: Dict = {
  nav: { download: "Download", faq: "FAQ", help: "Help", science: "Science", changelog: "Changelog" },
  footer: {
    terms: "Terms", privacy: "Privacy", refund: "Refunds", contact: "Contact",
    myOrders: "Find your download again", noTracking: "No analytics beyond cookieless page counts. The app never connects to the internet unless you turn on update checks.",
  },
  home: {
    title: "Dimit",
    tagline: "Warm your Mac's screen down to pure red. Dim it below the keyboard's floor. Stop the backlight from flickering.",
    lead: "A menu-bar app for macOS. Two sliders, three presets, one button. No account, no tracking, no subscription.",
    cta: "Download for Mac",
    secondary: "How it works",
    features: [
      { title: "Warmth, all the way to 0K", body: "Night Shift stops around 2500K and f.lux around 1900K. Dimit goes to a pure red \"0K\" — a name, not a physical temperature — by rewriting the display's colour tables, so the tint is applied by the graphics hardware itself." },
      { title: "Dimmer than the keys allow", body: "The brightness keys stop at the panel's minimum. Dimit dims in software from 100% down to 10%, on every connected display, with one slider." },
      { title: "PWM-Safe mode", body: "Many LED backlights dim by switching on and off very fast (PWM), which some people notice as flicker or strain. PWM-Safe keeps the backlight at 100% and does all dimming in software instead, so the backlight never pulses." },
      { title: "Screenshots stay normal", body: "Because the tint lives in the display's colour tables, screenshots, screen recordings and screen shares show the real colours at brightness 30% and above. Verified with QuickTime and Zoom on macOS 27." },
      { title: "Sunset to sunrise", body: "Warms up at sunset and turns itself off at sunrise, computed on your Mac from your city or, if you allow it once, your location. Nothing is sent anywhere. Fixed times work too." },
      { title: "Uzbek, Russian, English", body: "The whole app in three languages, switchable without a restart." },
    ],
    vsTitle: "Compared with what's built in",
    vs: [
      { name: "Night Shift", warmth: "~2500K", pwm: "no" },
      { name: "f.lux", warmth: "~1900K", pwm: "no" },
      { name: "Color Filters (Accessibility)", warmth: "tints, not a temperature", pwm: "no" },
      { name: "Dimit", warmth: "0K (pure red)", pwm: "yes, on supported displays" },
    ],
    priceTitle: "Pay what you want, from $5",
    priceBody: "One payment, your copy forever, free updates. Checkout by Lemon Squeezy — cards and PayPal, tax handled. No key to enter, nothing to activate.",
    priceNote: "Every copy is identical. There is no locked feature and no trial.",
    honestyTitle: "What it doesn't do",
    honesty: [
      "It is not a medical device and makes no health claims. Some studies on light and sleep are listed on the Science page; read them and decide for yourself.",
      "PWM-Safe holds the backlight at 100% on Apple displays. Third-party monitors need DDC/CI, which is experimental, off by default, and not yet confirmed on any monitor.",
      "Below 30% brightness and in Fallback mode, dimming uses an overlay window that screen recorders may capture. The app tells you when you're in those modes.",
      "It needs macOS 13 or later and does not run from the Mac App Store, because the App Store forbids the display access it uses.",
    ],
  },
  download: {
    title: "Download Dimit",
    lead: "Pay what you want, from $5. You get the download link right away and by email; the file is delivered by Lemon Squeezy.",
    cta: "Get Dimit — pay what you want, from $5",
    ctaSoon: "Checkout opens soon — the store is being set up.",
    from: "Minimum $5 USD. Cards and PayPal. VAT or sales tax is added where it applies and handled by Lemon Squeezy as the seller of record.",
    requires: "Requires macOS 13 Ventura or later, Apple silicon or Intel.",
    testedOn: "Tested on",
    testedList: [
      "MacBook Pro 16\" (M1 Pro), macOS 27 beta, built-in display — all features",
      "External monitor (Xiaomi Mi Monitor, 2560×1440) — warmth and dimming; DDC/CI brightness not supported by that monitor",
    ],
    notarized: "Signed with a Developer ID and notarized by Apple: it opens like any other download. (Beta builds before 1.0 were not; see the beta notes if you have one.)",
    installTitle: "Install",
    install: [
      "Open the DMG and drag Dimit to Applications.",
      "Open Dimit. It appears in the menu bar — there is no Dock icon.",
      "Click the icon: turn it ON, drag Warmth left. That's it.",
    ],
    lostTitle: "Bought it already?",
    lost: "Your download link is in your receipt email, and always at Lemon Squeezy → My Orders (enter the email you paid with). New versions appear there too.",
    afterTitle: "If something looks wrong",
    after: [
      "Right-click the menu-bar icon → Restore Colours puts the screen back to normal instantly.",
      "Quitting Dimit always restores normal colours and brightness.",
      "If a colour change doesn't show on macOS 26 or later, turn off automatic brightness in System Settings → Displays, or enable Fallback mode in Settings → Advanced.",
    ],
  },
  faq: {
    title: "Questions",
    items: [
      { q: "Is it really $5?", a: "The minimum is $5; you choose the amount. Everyone gets the same app and the same free updates regardless of what they paid." },
      { q: "Do I need an account or a licence key?", a: "No. The payment is on the website; the app has no key, no activation and no trial. It never connects to the internet unless you turn on update checks." },
      { q: "Will my screenshots be red?", a: "No, at brightness 30% and above: the tint is applied by the display's colour tables, which screen capture doesn't see. Verified with QuickTime and Zoom. Below 30% and in Fallback mode an overlay window is used, and some recorders may capture it." },
      { q: "What is PWM and why would I care?", a: "Many LED backlights dim by switching on and off hundreds of times a second (pulse-width modulation). Some people perceive it as flicker, eye strain or headaches, especially at low brightness. PWM-Safe keeps the backlight at 100% — where most panels don't pulse — and dims in software instead. Whether your display uses PWM, and whether it bothers you, is individual; Dimit doesn't claim to treat anything." },
      { q: "Does it work with my external monitor?", a: "Warmth and dimming: yes, on every connected display. Holding an external monitor's backlight at 100% needs DDC/CI, which is experimental, off by default, and hasn't yet been confirmed working on any monitor. Turn it on in Settings → Displays if you'd like to try, and tell us what happens." },
      { q: "Why isn't it on the Mac App Store?", a: "The App Store sandbox forbids the display and brightness access Dimit needs. It's distributed directly, signed and notarized." },
      { q: "Does it need any permissions?", a: "None — no Accessibility, no Screen Recording, no admin. The only optional prompt is Location, and only if you press \"Use my location\" for the sunset schedule; choosing a city avoids it entirely." },
      { q: "Something went wrong with my screen.", a: "Right-click the icon → Restore Colours, or just quit Dimit. Both put the display back to normal. If colours stay wrong after quitting, log out and back in — the system resets its colour tables." },
      { q: "Refunds?", a: "30 days, no questions asked, through Lemon Squeezy. See the Refunds page." },
    ],
  },
  help: {
    title: "Help",
    sections: [
      { title: "The main window", body: ["Click the menu-bar icon. The big button turns the filter ON and OFF. Warmth goes from 6500K (no change) to 0K (pure red). Brightness goes from 100% to 10%. DAY, EVENING and NIGHT are presets you can edit in Settings.", "Right-click the icon for presets, ON/OFF, Fallback mode, Restore Colours, Settings and Quit."] },
      { title: "PWM-Safe", body: ["Turn it on under the sliders. The line beneath tells you what happened: the backlight is being held at 100% (and the slider now dims in software), the display is being checked, the display won't hold 100%, or the display has no supported way to control its backlight.", "If you press the keyboard brightness keys while it's on, Dimit puts the backlight back to 100% within a few seconds and tells you once. Use the slider in the app instead.", "Because the backlight stays at 100%, laptops use slightly more battery."] },
      { title: "Schedule", body: ["Settings → Schedule. Sunset to sunrise: pick your city, or press \"Use my location\" once. Dimit warms to EVENING at sunset, to NIGHT at your bedtime, and turns itself off at sunrise, ramping over a duration you choose. Fixed times: the same three phases with times you set.", "Moving a slider while a schedule is active pauses it until the next phase."] },
      { title: "Fallback mode", body: ["On some Macs running macOS 26 or later with automatic brightness on, the system ignores colour-table changes. Fallback mode (Settings → Advanced, or the right-click menu) tints with an overlay window instead. It works everywhere, but screenshots and recordings will show the tint."] },
      { title: "Keyboard shortcuts", body: ["Toggle ON/OFF: ⌃⌥⌘Z by default. Cycle presets, warmth up/down and brightness up/down can be assigned in Settings → General. They work from any app."] },
      { title: "Diagnostics", body: ["Settings → Advanced → Copy diagnostics puts a short text on the clipboard: your macOS version, Mac model, display list and Dimit's own recent log lines. Nothing else, and it's never sent automatically — paste it into a message to us if you need help."] },
    ],
  },
  science: {
    title: "Science",
    intro: "Dimit changes two physical things: how much blue light your screen emits and whether its backlight pulses. Whether either matters to you is personal. The studies below are the ones usually cited; we list them so you can read them, not as evidence that the app treats or prevents anything.",
    studiesTitle: "Frequently cited studies",
    noClaims: "Dimit is a display utility, not a medical device. It does not diagnose, treat or prevent any condition.",
  },
  changelog: {
    title: "Changelog",
    entries: [
      { version: "0.4", date: "2026-09-10", notes: ["Beta for testers: release pipeline, tester checklist. No functional changes.", "Fixed: the onboarding privacy sentence mentioned a licence check that doesn't exist."] },
      { version: "0.3", date: "2026-09-09", notes: ["Sunset→sunrise and fixed-time schedules, with a bundled city list and optional one-time location.", "Experimental DDC/CI brightness for external monitors (off by default)."] },
      { version: "0.2", date: "2026-09-09", notes: ["Settings window, editable presets, global keyboard shortcuts, launch at login, onboarding, diagnostics, live language switch."] },
      { version: "0.1", date: "2026-09-09", notes: ["First build: warmth to 0K, software dimming, PWM-Safe on Apple displays, extreme dim, Fallback mode, three languages."] },
    ],
  },
  terms: {
    title: "Terms of use",
    paras: [
      "Dimit is sold by {legalEntity} (\"we\"). Purchases are processed by Lemon Squeezy, LLC as merchant of record; their terms apply to the payment itself.",
      "What you buy: a copy of the Dimit application for macOS, for your own use on Macs you own or control, plus updates to it for as long as we publish them. The price is set by you at checkout above the stated minimum.",
      "The software is provided as is. We test it on the hardware listed on the Download page and fix what testers and customers report, but we cannot guarantee it works on every Mac, display or macOS version, or that it is free of defects. Our liability is limited to the amount you paid.",
      "Dimit changes your display's colour tables and, in PWM-Safe mode, its backlight setting. Both are restored when you turn it off or quit; if anything ever looks wrong, Restore Colours in the app or quitting the app puts the display back.",
      "You may not redistribute the application or present it as your own. You may keep and use the copy you bought indefinitely; it has no expiry and no remote off switch.",
      "Contact: {supportEmail}.",
    ],
  },
  privacy: {
    title: "Privacy",
    paras: [
      "The app collects nothing. It has no account, no analytics, no crash reporting, no identifiers, and it does not connect to the internet — with one exception you control: if you turn on \"Check for updates automatically\" (off by default), it fetches a small signed file from dimit.uz once a day to see whether a new version exists. A manual \"Check for Updates…\" does the same when you click it. Nothing about you is included in that request beyond what any web request carries.",
      "If you press \"Use my location\" for the sunset schedule, macOS asks your permission and the app reads your coordinates once, on your Mac, to compute sunrise and sunset. They are stored in the app's own settings on your Mac and never leave it.",
      "The website uses Cloudflare Web Analytics, which counts page views without cookies or identifiers, and Lemon Squeezy's checkout, which sets its own cookies when you open it. We never see your payment details. Lemon Squeezy holds your email address and order to deliver the download and receipt; their privacy policy covers that data.",
      "Diagnostics you copy from the app (Settings → Advanced) contain your macOS version, Mac model, display list and the app's recent log lines. You choose whether to send them to us.",
      "Controller: {legalEntity}, {supportEmail}.",
    ],
  },
  refund: {
    title: "Refunds",
    paras: [
      "30 days, no questions. Write to {supportEmail} with the email you used at checkout, or use the link in your Lemon Squeezy receipt, and the payment is returned in full.",
      "Because Dimit has no licence keys, a refund cannot disable the copy you downloaded. We're telling you this plainly: the honour system is part of the price.",
    ],
  },
};

const uz: Dict = {
  nav: { download: "Yuklab olish", faq: "Savollar", help: "Yordam", science: "Ilmiy manbalar", changelog: "O‘zgarishlar" },
  footer: {
    terms: "Shartlar", privacy: "Maxfiylik", refund: "Pulni qaytarish", contact: "Aloqa",
    myOrders: "Yuklab olish havolasini qayta topish", noTracking: "Cookie-siz sahifa hisobidan boshqa hech qanday analitika yo‘q. Ilova siz yangilanishlarni tekshirishni yoqmaguningizcha internetga ulanmaydi.",
  },
  home: {
    title: "Dimit",
    tagline: "Mac ekranini to‘liq qizil ranggacha iliqlashtiring. Klaviatura chegarasidan ham pastroq xiralashtiring. Orqa yoritish miltillashini to‘xtating.",
    lead: "macOS uchun menyu paneli ilovasi. Ikki slayder, uch rejim, bitta tugma. Akkaunt yo‘q, kuzatuv yo‘q, obuna yo‘q.",
    cta: "Mac uchun yuklab olish",
    secondary: "Qanday ishlaydi",
    features: [
      { title: "Iliqlik — 0K gacha", body: "Night Shift taxminan 2500K da, f.lux esa 1900K da to‘xtaydi. Dimit displeyning rang jadvallarini qayta yozib, to‘liq qizil «0K» gacha boradi (bu nom, fizik harorat emas) — rang o‘zgarishini grafika uskunasining o‘zi bajaradi." },
      { title: "Tugmalar ruxsat berganidan ham xiraroq", body: "Yorqinlik tugmalari panelning minimumida to‘xtaydi. Dimit yorqinlikni dasturiy ravishda 100% dan 10% gacha, barcha ulangan displeylarda, bitta slayder bilan pasaytiradi." },
      { title: "PWM-xavfsiz rejim", body: "Ko‘p LED orqa yoritishlar juda tez yonib-o‘chish (PWM) orqali xiralashadi; ba’zilar buni miltillash yoki charchoq sifatida sezadi. PWM-xavfsiz rejim orqa yoritishni 100% da ushlab, xiralashtirishni dasturiy bajaradi — orqa yoritish umuman pulslamaydi." },
      { title: "Skrinshotlar oddiy qoladi", body: "Rang displeyning rang jadvallarida bo‘lgani uchun, 30% va undan yuqori yorqinlikda skrinshotlar, ekran yozuvlari va ekran ulashishlari haqiqiy ranglarni ko‘rsatadi. macOS 27 da QuickTime va Zoom bilan tekshirilgan." },
      { title: "Quyosh botishidan chiqishigacha", body: "Quyosh botganda iliqlashadi, chiqqanda o‘zini o‘chiradi — shahringiz yoki (bir marta ruxsat bersangiz) joylashuvingiz asosida Mac’ingizning o‘zida hisoblanadi. Hech narsa hech qayerga yuborilmaydi. Belgilangan vaqtlar ham ishlaydi." },
      { title: "O‘zbek, rus, ingliz", body: "Butun ilova uch tilda, qayta ishga tushirmasdan almashtiriladi." },
    ],
    vsTitle: "O‘rnatilgan vositalar bilan taqqoslash",
    vs: [
      { name: "Night Shift", warmth: "~2500K", pwm: "yo‘q" },
      { name: "f.lux", warmth: "~1900K", pwm: "yo‘q" },
      { name: "Rang filtrlari (Maxsus imkoniyatlar)", warmth: "bo‘yaydi, harorat emas", pwm: "yo‘q" },
      { name: "Dimit", warmth: "0K (to‘liq qizil)", pwm: "ha, qo‘llab-quvvatlanadigan displeylarda" },
    ],
    priceTitle: "Xohlaganingizcha to‘lang — 5 $ dan",
    priceBody: "Bir marta to‘lov, nusxa umrbod sizniki, yangilanishlar bepul. To‘lov Lemon Squeezy orqali — karta va PayPal, soliqlar hisobga olingan. Kalit kiritilmaydi, faollashtirish yo‘q.",
    priceNote: "Har bir nusxa bir xil. Yopiq funksiya ham, sinov muddati ham yo‘q.",
    honestyTitle: "Nima qilmaydi",
    honesty: [
      "Bu tibbiy vosita emas va sog‘liq haqida hech qanday da’vo qilmaydi. Yorug‘lik va uyqu haqidagi ayrim tadqiqotlar «Ilmiy manbalar» sahifasida — o‘qing va o‘zingiz xulosa qiling.",
      "PWM-xavfsiz rejim Apple displeylarida orqa yoritishni 100% da ushlaydi. Boshqa monitorlar uchun DDC/CI kerak — bu tajribaviy, sukut bo‘yicha o‘chiq va hali birorta monitorda tasdiqlanmagan.",
      "30% dan past yorqinlikda va Zaxira rejimda xiralashtirish ekran yozuvchilari yozib olishi mumkin bo‘lgan qatlam oynasi orqali bajariladi. Ilova bu rejimlarda ekanligingizni aytadi.",
      "macOS 13 yoki undan yangisi kerak. Mac App Store orqali tarqatilmaydi, chunki App Store u foydalanadigan displey kirishini taqiqlaydi.",
    ],
  },
  download: {
    title: "Dimit’ni yuklab olish",
    lead: "Xohlaganingizcha to‘lang, 5 $ dan. Yuklab olish havolasini darhol va elektron pochta orqali olasiz; faylni Lemon Squeezy yetkazib beradi.",
    cta: "Dimit’ni olish — xohlaganingizcha, 5 $ dan",
    ctaSoon: "To‘lov tez orada ochiladi — do‘kon sozlanmoqda.",
    from: "Minimal 5 AQSH dollari. Karta va PayPal. QQS yoki savdo solig‘i qo‘llaniladigan joyda qo‘shiladi va sotuvchi sifatida Lemon Squeezy tomonidan hal qilinadi.",
    requires: "macOS 13 Ventura yoki undan yangisi kerak, Apple silicon yoki Intel.",
    testedOn: "Sinovdan o‘tgan",
    testedList: [
      "MacBook Pro 16\" (M1 Pro), macOS 27 beta, o‘rnatilgan displey — barcha funksiyalar",
      "Tashqi monitor (Xiaomi Mi Monitor, 2560×1440) — iliqlik va xiralashtirish; DDC/CI yorqinligini bu monitor qo‘llab-quvvatlamaydi",
    ],
    notarized: "Developer ID bilan imzolangan va Apple tomonidan notarizatsiya qilingan: boshqa har qanday yuklab olingan ilova kabi ochiladi. (1.0 gacha bo‘lgan beta nusxalar bunday emas edi; agar sizda shunday nusxa bo‘lsa, beta eslatmalariga qarang.)",
    installTitle: "O‘rnatish",
    install: [
      "DMG faylini oching va Dimit’ni Applications papkasiga torting.",
      "Dimit’ni oching. U menyu panelida paydo bo‘ladi — Dock belgisi yo‘q.",
      "Belgini bosing: YOQING, Iliqlikni chapga torting. Tamom.",
    ],
    lostTitle: "Allaqachon sotib olganmisiz?",
    lost: "Yuklab olish havolasi kvitansiya xatingizda va har doim Lemon Squeezy → My Orders sahifasida (to‘lov qilgan pochtangizni kiriting). Yangi versiyalar ham o‘sha yerda paydo bo‘ladi.",
    afterTitle: "Agar biror narsa noto‘g‘ri ko‘rinsa",
    after: [
      "Menyu panelidagi belgini o‘ng tugma bilan bosing → «Ranglarni tiklash» ekranni darhol oddiy holatga qaytaradi.",
      "Dimit’dan chiqish har doim oddiy rang va yorqinlikni qaytaradi.",
      "Agar macOS 26 yoki undan yangisida rang o‘zgarishi ko‘rinmasa, Tizim sozlamalari → Displeylar bo‘limida avtomatik yorqinlikni o‘chiring yoki Sozlamalar → Qo‘shimcha bo‘limida Zaxira rejimni yoqing.",
    ],
  },
  faq: {
    title: "Savollar",
    items: [
      { q: "Rostdan ham 5 $ mi?", a: "Minimal — 5 $; summani o‘zingiz tanlaysiz. Qancha to‘lashidan qat’i nazar, hamma bir xil ilova va bir xil bepul yangilanishlarni oladi." },
      { q: "Akkaunt yoki litsenziya kaliti kerakmi?", a: "Yo‘q. To‘lov veb-saytda; ilovada kalit ham, faollashtirish ham, sinov muddati ham yo‘q. Siz yangilanishlarni tekshirishni yoqmaguningizcha u internetga ulanmaydi." },
      { q: "Skrinshotlarim qizil bo‘ladimi?", a: "Yo‘q, 30% va undan yuqori yorqinlikda: rang displeyning rang jadvallari orqali qo‘llanadi, ekran yozib olish esa ularni ko‘rmaydi. QuickTime va Zoom bilan tekshirilgan. 30% dan pastda va Zaxira rejimda qatlam oynasi ishlatiladi va ba’zi yozuvchilar uni yozib olishi mumkin." },
      { q: "PWM nima va nega bu muhim?", a: "Ko‘p LED orqa yoritishlar sekundiga yuzlab marta yonib-o‘chish orqali xiralashadi (impuls kengligi modulyatsiyasi). Ba’zilar buni, ayniqsa past yorqinlikda, miltillash, ko‘z charchog‘i yoki bosh og‘rig‘i sifatida sezadi. PWM-xavfsiz rejim orqa yoritishni 100% da — ko‘p panellar pulslamaydigan darajada — ushlab, xiralashtirishni dasturiy bajaradi. Displeyingiz PWM ishlatadimi va bu sizga xalaqit beradimi — bu shaxsiy; Dimit hech narsani davolashni da’vo qilmaydi." },
      { q: "Tashqi monitorim bilan ishlaydimi?", a: "Iliqlik va xiralashtirish: ha, barcha ulangan displeylarda. Tashqi monitor orqa yoritishini 100% da ushlash uchun DDC/CI kerak — bu tajribaviy, sukut bo‘yicha o‘chiq va hali birorta monitorda ishlashi tasdiqlanmagan. Sinab ko‘rmoqchi bo‘lsangiz, Sozlamalar → Displeylar bo‘limida yoqing va natijani bizga yozing." },
      { q: "Nega Mac App Store’da yo‘q?", a: "App Store sandbox’i Dimit’ga kerak bo‘lgan displey va yorqinlik kirishini taqiqlaydi. U to‘g‘ridan-to‘g‘ri, imzolangan va notarizatsiya qilingan holda tarqatiladi." },
      { q: "Biror ruxsat kerakmi?", a: "Hech qanday — Maxsus imkoniyatlar ham, Ekran yozuvi ham, administrator ham kerak emas. Yagona ixtiyoriy so‘rov — Joylashuv, faqat quyosh jadvali uchun «Joylashuvimdan foydalanish» tugmasini bossangiz; shahar tanlash bunga umuman hojat qoldirmaydi." },
      { q: "Ekranim bilan biror narsa bo‘ldi.", a: "Belgini o‘ng tugma bilan bosing → «Ranglarni tiklash» yoki shunchaki Dimit’dan chiqing. Ikkalasi ham displeyni oddiy holatga qaytaradi. Chiqqandan keyin ham ranglar noto‘g‘ri qolsa, tizimdan chiqib qayta kiring — tizim rang jadvallarini tiklaydi." },
      { q: "Pulni qaytarish?", a: "30 kun, savolsiz, Lemon Squeezy orqali. «Pulni qaytarish» sahifasiga qarang." },
    ],
  },
  help: {
    title: "Yordam",
    sections: [
      { title: "Asosiy oyna", body: ["Menyu panelidagi belgini bosing. Katta tugma filtrni YOQADI va O‘CHIRADI. Iliqlik 6500K (o‘zgarishsiz) dan 0K (to‘liq qizil) gacha. Yorqinlik 100% dan 10% gacha. KUN, KECH va TUN — Sozlamalarda tahrirlash mumkin bo‘lgan rejimlar.", "Rejimlar, YOQISH/O‘CHIRISH, Zaxira rejim, Ranglarni tiklash, Sozlamalar va Chiqish uchun belgini o‘ng tugma bilan bosing."] },
      { title: "PWM-xavfsiz rejim", body: ["Slayderlar ostida yoqing. Pastdagi satr nima bo‘lganini aytadi: orqa yoritish 100% da ushlab turilmoqda (endi slayder dasturiy xiralashtiradi), displey tekshirilmoqda, displey 100% ni ushlamayapti yoki displeyda orqa yoritishni boshqarishning qo‘llab-quvvatlanadigan usuli yo‘q.", "Rejim yoniq paytda klaviaturadagi yorqinlik tugmalarini bossangiz, Dimit bir necha soniya ichida orqa yoritishni yana 100% ga qaytaradi va buni bir marta aytadi. Uning o‘rniga ilovadagi slayderdan foydalaning.", "Orqa yoritish 100% da qolgani uchun noutbuklar biroz ko‘proq batareya sarflaydi."] },
      { title: "Jadval", body: ["Sozlamalar → Jadval. Quyosh botishidan chiqishigacha: shahringizni tanlang yoki bir marta «Joylashuvimdan foydalanish» tugmasini bosing. Dimit quyosh botganda KECH ga, uxlash vaqtingizda TUN ga iliqlashadi va quyosh chiqqanda o‘zini o‘chiradi — siz tanlagan davomiylikda silliq o‘tadi. Belgilangan vaqtlar: o‘sha uch bosqich, siz belgilagan vaqtlar bilan.", "Jadval faol paytda slayderni surish uni keyingi bosqichgacha to‘xtatib turadi."] },
      { title: "Zaxira rejim", body: ["macOS 26 yoki undan yangisi o‘rnatilgan, avtomatik yorqinlik yoqilgan ba’zi Mac’larda tizim rang jadvali o‘zgarishlarini e’tiborsiz qoldiradi. Zaxira rejim (Sozlamalar → Qo‘shimcha yoki o‘ng tugma menyusi) o‘rniga qatlam oynasi bilan bo‘yaydi. U hamma joyda ishlaydi, lekin skrinshot va yozuvlarda rang ko‘rinadi."] },
      { title: "Tezkor tugmalar", body: ["YOQISH/O‘CHIRISH: sukut bo‘yicha ⌃⌥⌘Z. Rejimlarni almashtirish, iliqlik va yorqinlikni oshirish/kamaytirish Sozlamalar → Umumiy bo‘limida tayinlanadi. Ular istalgan ilovadan ishlaydi."] },
      { title: "Diagnostika", body: ["Sozlamalar → Qo‘shimcha → Diagnostikani nusxalash — almashish buferiga qisqa matn qo‘yadi: macOS versiyangiz, Mac modeli, displeylar ro‘yxati va Dimit’ning so‘nggi jurnal satrlari. Boshqa hech narsa, va u hech qachon avtomatik yuborilmaydi — yordam kerak bo‘lsa, bizga xabarga qo‘shib yuboring."] },
    ],
  },
  science: {
    title: "Ilmiy manbalar",
    intro: "Dimit ikki jismoniy narsani o‘zgartiradi: ekraningiz qancha ko‘k nur chiqarishini va orqa yoritishi pulslaydimi-yo‘qmi. Bularning birortasi siz uchun muhimmi — bu shaxsiy. Quyidagi tadqiqotlar odatda keltiriladiganlari; biz ularni o‘qishingiz uchun ro‘yxatga oldik, ilova biror narsani davolashi yoki oldini olishiga dalil sifatida emas.",
    studiesTitle: "Ko‘p keltiriladigan tadqiqotlar",
    noClaims: "Dimit — displey yordamchisi, tibbiy vosita emas. U hech qanday holatni aniqlamaydi, davolamaydi va oldini olmaydi.",
  },
  changelog: {
    title: "O‘zgarishlar",
    entries: [
      { version: "0.4", date: "2026-09-10", notes: ["Sinovchilar uchun beta: chiqarish jarayoni, sinovchi ro‘yxati. Funksional o‘zgarishlar yo‘q.", "Tuzatildi: kirish oynasidagi maxfiylik jumlasi mavjud bo‘lmagan litsenziya tekshiruvini eslatardi."] },
      { version: "0.3", date: "2026-09-09", notes: ["Quyosh botishidan chiqishigacha va belgilangan vaqt jadvallari, o‘rnatilgan shaharlar ro‘yxati va ixtiyoriy bir martalik joylashuv bilan.", "Tashqi monitorlar uchun tajribaviy DDC/CI yorqinligi (sukut bo‘yicha o‘chiq)."] },
      { version: "0.2", date: "2026-09-09", notes: ["Sozlamalar oynasi, tahrirlanadigan rejimlar, global tezkor tugmalar, kirishda ishga tushirish, kirish oynasi, diagnostika, jonli til almashtirish."] },
      { version: "0.1", date: "2026-09-09", notes: ["Birinchi nusxa: 0K gacha iliqlik, dasturiy xiralashtirish, Apple displeylarida PWM-xavfsiz rejim, kuchli xiralashtirish, Zaxira rejim, uch til."] },
    ],
  },
  terms: {
    title: "Foydalanish shartlari",
    paras: [
      "Dimit’ni {legalEntity} («biz») sotadi. To‘lovlarni sotuvchi sifatida Lemon Squeezy, LLC amalga oshiradi; to‘lovning o‘ziga ularning shartlari qo‘llanadi.",
      "Siz nima sotib olasiz: macOS uchun Dimit ilovasining nusxasi — o‘zingizga tegishli yoki siz boshqaradigan Mac’larda shaxsiy foydalanish uchun, hamda biz chiqarib turgunimizcha uning yangilanishlari. Narxni to‘lov paytida ko‘rsatilgan minimumdan yuqori qilib o‘zingiz belgilaysiz.",
      "Dastur «qanday bo‘lsa shunday» taqdim etiladi. Biz uni «Yuklab olish» sahifasida keltirilgan uskunalarda sinaymiz va sinovchilar hamda mijozlar xabar qilgan muammolarni tuzatamiz, lekin u har bir Mac, displey yoki macOS versiyasida ishlashiga yoki nuqsonsiz ekanligiga kafolat bera olmaymiz. Bizning javobgarligimiz siz to‘lagan summa bilan cheklanadi.",
      "Dimit displeyingizning rang jadvallarini va PWM-xavfsiz rejimda orqa yoritish sozlamasini o‘zgartiradi. Ikkalasi ham uni o‘chirganingizda yoki ilovadan chiqqaningizda tiklanadi; agar biror narsa noto‘g‘ri ko‘rinsa, ilovadagi «Ranglarni tiklash» yoki ilovadan chiqish displeyni qaytaradi.",
      "Ilovani qayta tarqatish yoki o‘zingizniki sifatida ko‘rsatish mumkin emas. Sotib olgan nusxangizni cheksiz saqlashingiz va ishlatishingiz mumkin; unda muddat ham, masofadan o‘chirish ham yo‘q.",
      "Aloqa: {supportEmail}.",
    ],
  },
  privacy: {
    title: "Maxfiylik",
    paras: [
      "Ilova hech narsa yig‘maydi. Unda akkaunt, analitika, xatolik hisobotlari, identifikatorlar yo‘q va u internetga ulanmaydi — siz boshqaradigan bitta istisno bilan: agar «Yangilanishlarni avtomatik tekshirish» (sukut bo‘yicha o‘chiq) ni yoqsangiz, u kuniga bir marta dimit.uz dan yangi versiya bor-yo‘qligini bilish uchun kichik imzolangan faylni oladi. Qo‘lda «Yangilanishlarni tekshirish…» bosganingizda ham xuddi shunday. Bu so‘rovda siz haqingizda har qanday veb-so‘rov olib yuradigan ma’lumotdan boshqa hech narsa yo‘q.",
      "Agar quyosh jadvali uchun «Joylashuvimdan foydalanish» tugmasini bossangiz, macOS ruxsat so‘raydi va ilova koordinatalaringizni bir marta, Mac’ingizning o‘zida, quyosh chiqishi va botishini hisoblash uchun o‘qiydi. Ular ilovaning o‘z sozlamalarida, Mac’ingizda saqlanadi va uni hech qachon tark etmaydi.",
      "Veb-sayt Cloudflare Web Analytics’dan foydalanadi — u sahifa ko‘rishlarini cookie va identifikatorlarsiz hisoblaydi — hamda Lemon Squeezy to‘lov oynasidan, u ochilganda o‘z cookie’larini o‘rnatadi. Biz to‘lov ma’lumotlaringizni hech qachon ko‘rmaymiz. Lemon Squeezy yuklab olish va kvitansiyani yetkazish uchun elektron pochtangiz va buyurtmangizni saqlaydi; bu ma’lumotlarga ularning maxfiylik siyosati qo‘llanadi.",
      "Ilovadan nusxalagan diagnostika (Sozlamalar → Qo‘shimcha) macOS versiyangiz, Mac modeli, displeylar ro‘yxati va ilovaning so‘nggi jurnal satrlarini o‘z ichiga oladi. Uni bizga yuborish-yubormaslikni o‘zingiz hal qilasiz.",
      "Nazoratchi: {legalEntity}, {supportEmail}.",
    ],
  },
  refund: {
    title: "Pulni qaytarish",
    paras: [
      "30 kun, savolsiz. To‘lovda ishlatgan pochtangiz bilan {supportEmail} ga yozing yoki Lemon Squeezy kvitansiyasidagi havoladan foydalaning — to‘lov to‘liq qaytariladi.",
      "Dimit’da litsenziya kalitlari bo‘lmagani uchun pulni qaytarish yuklab olgan nusxangizni o‘chira olmaydi. Buni ochiq aytamiz: ishonch tizimi narxning bir qismi.",
    ],
  },
};

const ru: Dict = {
  nav: { download: "Скачать", faq: "Вопросы", help: "Помощь", science: "Исследования", changelog: "Изменения" },
  footer: {
    terms: "Условия", privacy: "Конфиденциальность", refund: "Возврат", contact: "Контакт",
    myOrders: "Найти свою загрузку снова", noTracking: "Никакой аналитики, кроме подсчёта страниц без cookie. Приложение не выходит в интернет, пока вы не включите проверку обновлений.",
  },
  home: {
    title: "Dimit",
    tagline: "Сделайте экран Mac тёплым вплоть до чистого красного. Затемните ниже предела клавиш. Остановите мерцание подсветки.",
    lead: "Приложение для строки меню macOS. Два ползунка, три режима, одна кнопка. Без аккаунта, без слежки, без подписки.",
    cta: "Скачать для Mac",
    secondary: "Как это работает",
    features: [
      { title: "Теплота — до 0K", body: "Night Shift останавливается около 2500K, f.lux — около 1900K. Dimit доходит до чистого красного «0K» (это название, а не физическая температура), переписывая цветовые таблицы дисплея, так что оттенок накладывает сама графическая система." },
      { title: "Темнее, чем позволяют клавиши", body: "Клавиши яркости упираются в минимум панели. Dimit затемняет программно от 100% до 10%, на каждом подключённом дисплее, одним ползунком." },
      { title: "Режим без мерцания (PWM)", body: "Многие LED-подсветки затемняются, очень быстро включаясь и выключаясь (ШИМ, PWM); некоторые воспринимают это как мерцание или напряжение. Режим без мерцания держит подсветку на 100% и затемняет программно — подсветка не пульсирует." },
      { title: "Скриншоты остаются обычными", body: "Оттенок живёт в цветовых таблицах дисплея, поэтому скриншоты, записи экрана и демонстрация экрана показывают настоящие цвета при яркости 30% и выше. Проверено с QuickTime и Zoom на macOS 27." },
      { title: "От заката до рассвета", body: "Теплеет на закате и выключается на рассвете — вычисляется на вашем Mac по городу или, если вы один раз разрешите, по местоположению. Ничего никуда не отправляется. Заданное время тоже работает." },
      { title: "Узбекский, русский, английский", body: "Всё приложение на трёх языках, переключение без перезапуска." },
    ],
    vsTitle: "В сравнении со встроенными средствами",
    vs: [
      { name: "Night Shift", warmth: "~2500K", pwm: "нет" },
      { name: "f.lux", warmth: "~1900K", pwm: "нет" },
      { name: "Цветовые фильтры (Универсальный доступ)", warmth: "окрашивает, не температура", pwm: "нет" },
      { name: "Dimit", warmth: "0K (чистый красный)", pwm: "да, на поддерживаемых дисплеях" },
    ],
    priceTitle: "Платите сколько хотите — от 5 $",
    priceBody: "Один платёж, копия навсегда, обновления бесплатно. Оплата через Lemon Squeezy — карты и PayPal, налоги учтены. Никаких ключей, ничего активировать не нужно.",
    priceNote: "Все копии одинаковы. Нет закрытых функций и нет пробного периода.",
    honestyTitle: "Чего оно не делает",
    honesty: [
      "Это не медицинское устройство, и оно не делает заявлений о здоровье. Некоторые исследования о свете и сне перечислены на странице «Исследования» — прочитайте и решите сами.",
      "Режим без мерцания держит подсветку на 100% на дисплеях Apple. Сторонним мониторам нужен DDC/CI — экспериментальная функция, выключенная по умолчанию и пока не подтверждённая ни на одном мониторе.",
      "Ниже 30% яркости и в Резервном режиме затемнение выполняется наложенным окном, которое могут захватить программы записи экрана. Приложение сообщает, когда вы в этих режимах.",
      "Нужна macOS 13 или новее. Не распространяется через Mac App Store, потому что App Store запрещает используемый доступ к дисплею.",
    ],
  },
  download: {
    title: "Скачать Dimit",
    lead: "Платите сколько хотите, от 5 $. Ссылку на загрузку вы получите сразу и по электронной почте; файл доставляет Lemon Squeezy.",
    cta: "Получить Dimit — сколько хотите, от 5 $",
    ctaSoon: "Оплата скоро откроется — магазин настраивается.",
    from: "Минимум 5 долларов США. Карты и PayPal. НДС или налог с продаж добавляется там, где применяется, и обрабатывается Lemon Squeezy как продавцом.",
    requires: "Требуется macOS 13 Ventura или новее, Apple silicon или Intel.",
    testedOn: "Проверено на",
    testedList: [
      "MacBook Pro 16\" (M1 Pro), macOS 27 beta, встроенный дисплей — все функции",
      "Внешний монитор (Xiaomi Mi Monitor, 2560×1440) — теплота и затемнение; яркость по DDC/CI этим монитором не поддерживается",
    ],
    notarized: "Подписано Developer ID и нотаризовано Apple: открывается как любая другая загрузка. (Бета-сборки до 1.0 не были нотаризованы; если у вас такая, см. заметки к бете.)",
    installTitle: "Установка",
    install: [
      "Откройте DMG и перетащите Dimit в Applications.",
      "Откройте Dimit. Он появится в строке меню — значка в Dock нет.",
      "Нажмите на значок: включите, потяните «Теплоту» влево. Всё.",
    ],
    lostTitle: "Уже купили?",
    lost: "Ссылка на загрузку есть в письме с чеком и всегда на Lemon Squeezy → My Orders (введите почту, с которой платили). Новые версии появляются там же.",
    afterTitle: "Если что-то выглядит не так",
    after: [
      "Правый клик по значку в строке меню → «Восстановить цвета» мгновенно возвращает экран в норму.",
      "Выход из Dimit всегда восстанавливает обычные цвета и яркость.",
      "Если на macOS 26 или новее изменение цвета не видно, отключите автояркость в Системных настройках → Дисплеи или включите Резервный режим в Настройках → Дополнительно.",
    ],
  },
  faq: {
    title: "Вопросы",
    items: [
      { q: "Правда 5 $?", a: "Минимум — 5 $; сумму выбираете вы. Все получают одно и то же приложение и одни и те же бесплатные обновления, сколько бы ни заплатили." },
      { q: "Нужен аккаунт или лицензионный ключ?", a: "Нет. Оплата на сайте; в приложении нет ключа, активации и пробного периода. Оно не выходит в интернет, пока вы не включите проверку обновлений." },
      { q: "Мои скриншоты будут красными?", a: "Нет, при яркости 30% и выше: оттенок накладывается через цветовые таблицы дисплея, которых захват экрана не видит. Проверено с QuickTime и Zoom. Ниже 30% и в Резервном режиме используется наложенное окно, и некоторые программы записи могут его захватить." },
      { q: "Что такое PWM и почему это важно?", a: "Многие LED-подсветки затемняются, включаясь и выключаясь сотни раз в секунду (широтно-импульсная модуляция). Некоторые воспринимают это как мерцание, усталость глаз или головную боль, особенно при низкой яркости. Режим без мерцания держит подсветку на 100% — где большинство панелей не пульсирует — и затемняет программно. Использует ли ваш дисплей PWM и мешает ли это вам — индивидуально; Dimit не претендует на лечение чего-либо." },
      { q: "Работает с моим внешним монитором?", a: "Теплота и затемнение: да, на каждом подключённом дисплее. Чтобы держать подсветку внешнего монитора на 100%, нужен DDC/CI — экспериментальная функция, выключенная по умолчанию и пока не подтверждённая ни на одном мониторе. Включите в Настройках → Дисплеи, если хотите попробовать, и расскажите нам, что получилось." },
      { q: "Почему его нет в Mac App Store?", a: "Песочница App Store запрещает доступ к дисплею и яркости, который нужен Dimit. Он распространяется напрямую, подписанный и нотаризованный." },
      { q: "Нужны какие-то разрешения?", a: "Никаких — ни Универсальный доступ, ни Запись экрана, ни администратор. Единственный необязательный запрос — Геопозиция, и только если вы нажмёте «Использовать моё местоположение» для расписания по солнцу; выбор города полностью его исключает." },
      { q: "С экраном что-то случилось.", a: "Правый клик по значку → «Восстановить цвета», или просто выйдите из Dimit. И то и другое возвращает дисплей в норму. Если после выхода цвета остаются неправильными, выйдите из системы и войдите снова — система сбрасывает свои цветовые таблицы." },
      { q: "Возврат?", a: "30 дней, без вопросов, через Lemon Squeezy. См. страницу «Возврат»." },
    ],
  },
  help: {
    title: "Помощь",
    sections: [
      { title: "Главное окно", body: ["Нажмите на значок в строке меню. Большая кнопка включает и выключает фильтр. Теплота — от 6500K (без изменений) до 0K (чистый красный). Яркость — от 100% до 10%. ДЕНЬ, ВЕЧЕР и НОЧЬ — режимы, которые можно изменить в Настройках.", "Правый клик по значку: режимы, ВКЛ/ВЫКЛ, Резервный режим, Восстановить цвета, Настройки и Выйти."] },
      { title: "Режим без мерцания", body: ["Включите под ползунками. Строка ниже сообщает, что произошло: подсветка удерживается на 100% (и ползунок теперь затемняет программно), дисплей проверяется, дисплей не держит 100% или у дисплея нет поддерживаемого способа управлять подсветкой.", "Если при включённом режиме нажать клавиши яркости, Dimit через несколько секунд вернёт подсветку на 100% и один раз сообщит об этом. Используйте ползунок в приложении.", "Поскольку подсветка остаётся на 100%, ноутбуки расходуют чуть больше батареи."] },
      { title: "Расписание", body: ["Настройки → Расписание. От заката до рассвета: выберите город или один раз нажмите «Использовать моё местоположение». Dimit теплеет до ВЕЧЕРА на закате, до НОЧИ в ваше время сна и выключается на рассвете, плавно за выбранную вами длительность. Заданное время: те же три фазы с вашими временами.", "Движение ползунка при активном расписании приостанавливает его до следующей фазы."] },
      { title: "Резервный режим", body: ["На некоторых Mac с macOS 26 и новее при включённой автояркости система игнорирует изменения цветовых таблиц. Резервный режим (Настройки → Дополнительно или меню по правому клику) окрашивает наложенным окном. Он работает везде, но скриншоты и записи будут окрашены."] },
      { title: "Горячие клавиши", body: ["ВКЛ/ВЫКЛ: по умолчанию ⌃⌥⌘Z. Переключение режимов, теплота и яркость вверх/вниз назначаются в Настройках → Основные. Работают из любого приложения."] },
      { title: "Диагностика", body: ["Настройки → Дополнительно → Скопировать диагностику помещает в буфер обмена короткий текст: версия macOS, модель Mac, список дисплеев и последние строки журнала Dimit. Больше ничего, и это никогда не отправляется автоматически — вставьте в сообщение нам, если нужна помощь."] },
    ],
  },
  science: {
    title: "Исследования",
    intro: "Dimit меняет две физические вещи: сколько синего света излучает экран и пульсирует ли его подсветка. Важно ли что-то из этого для вас — индивидуально. Исследования ниже — те, что обычно цитируют; мы перечисляем их, чтобы вы могли их прочитать, а не как доказательство того, что приложение что-то лечит или предотвращает.",
    studiesTitle: "Часто цитируемые исследования",
    noClaims: "Dimit — утилита для дисплея, а не медицинское устройство. Она не диагностирует, не лечит и не предотвращает никаких состояний.",
  },
  changelog: {
    title: "Изменения",
    entries: [
      { version: "0.4", date: "2026-09-10", notes: ["Бета для тестировщиков: конвейер выпуска, чек-лист тестировщика. Функциональных изменений нет.", "Исправлено: фраза о конфиденциальности в приветствии упоминала несуществующую проверку лицензии."] },
      { version: "0.3", date: "2026-09-09", notes: ["Расписания «от заката до рассвета» и по заданному времени, со встроенным списком городов и необязательным разовым определением местоположения.", "Экспериментальная яркость по DDC/CI для внешних мониторов (выключена по умолчанию)."] },
      { version: "0.2", date: "2026-09-09", notes: ["Окно настроек, редактируемые режимы, глобальные горячие клавиши, запуск при входе, приветствие, диагностика, переключение языка на лету."] },
      { version: "0.1", date: "2026-09-09", notes: ["Первая сборка: теплота до 0K, программное затемнение, режим без мерцания на дисплеях Apple, сильное затемнение, Резервный режим, три языка."] },
    ],
  },
  terms: {
    title: "Условия использования",
    paras: [
      "Dimit продаёт {legalEntity} («мы»). Платежи обрабатывает Lemon Squeezy, LLC как продавец (merchant of record); к самому платежу применяются их условия.",
      "Что вы покупаете: копию приложения Dimit для macOS для личного использования на Mac, которыми вы владеете или управляете, а также его обновления, пока мы их выпускаем. Цену вы задаёте сами при оплате, не ниже указанного минимума.",
      "Программа предоставляется «как есть». Мы тестируем её на оборудовании, перечисленном на странице «Скачать», и исправляем то, о чём сообщают тестировщики и покупатели, но не можем гарантировать работу на каждом Mac, дисплее или версии macOS и отсутствие дефектов. Наша ответственность ограничена уплаченной вами суммой.",
      "Dimit изменяет цветовые таблицы дисплея и, в режиме без мерцания, настройку подсветки. И то и другое восстанавливается при выключении или выходе; если что-то выглядит не так, «Восстановить цвета» в приложении или выход из него возвращает дисплей в норму.",
      "Нельзя распространять приложение или выдавать его за своё. Купленную копию можно хранить и использовать бессрочно; у неё нет срока действия и удалённого выключателя.",
      "Контакт: {supportEmail}.",
    ],
  },
  privacy: {
    title: "Конфиденциальность",
    paras: [
      "Приложение ничего не собирает. В нём нет аккаунта, аналитики, отчётов о сбоях, идентификаторов, и оно не выходит в интернет — с одним исключением, которым управляете вы: если включить «Проверять обновления автоматически» (по умолчанию выключено), оно раз в день загружает небольшой подписанный файл с dimit.uz, чтобы узнать, есть ли новая версия. Ручная «Проверить обновления…» делает то же самое по нажатию. В этом запросе нет ничего о вас сверх того, что несёт любой веб-запрос.",
      "Если нажать «Использовать моё местоположение» для расписания по солнцу, macOS спросит разрешение, и приложение один раз прочитает ваши координаты на вашем Mac, чтобы вычислить восход и закат. Они хранятся в настройках приложения на вашем Mac и никогда его не покидают.",
      "Сайт использует Cloudflare Web Analytics, который считает просмотры страниц без cookie и идентификаторов, и оплату Lemon Squeezy, которая ставит свои cookie при открытии. Мы никогда не видим ваши платёжные данные. Lemon Squeezy хранит ваш адрес электронной почты и заказ, чтобы доставить загрузку и чек; эти данные регулирует их политика конфиденциальности.",
      "Диагностика, которую вы копируете из приложения (Настройки → Дополнительно), содержит версию macOS, модель Mac, список дисплеев и последние строки журнала приложения. Отправлять ли её нам — решаете вы.",
      "Контролёр: {legalEntity}, {supportEmail}.",
    ],
  },
  refund: {
    title: "Возврат",
    paras: [
      "30 дней, без вопросов. Напишите на {supportEmail} с почты, которую использовали при оплате, или воспользуйтесь ссылкой в чеке Lemon Squeezy — платёж вернётся полностью.",
      "Поскольку у Dimit нет лицензионных ключей, возврат не может отключить скачанную вами копию. Говорим это прямо: система доверия — часть цены.",
    ],
  },
};

export const dict: Record<Lang, Dict> = { en, uz, ru };
export function t(lang: Lang): Dict { return dict[lang]; }

// Studies list shared by all locales (CLAUDE.md Appendix B; verify each
// DOI before publishing — titles here are citations, not summaries).
export const studies = [
  "Lockley et al. 2003, J Clin Endocrinol Metab 88(9):4502–5",
  "Brainard et al. 2001, J Neurosci 21:6405–6412",
  "Chang et al. 2015, PNAS 112(4):1232–7",
  "Gooley et al. 2011, J Clin Endocrinol Metab 96(3):E463–E472",
  "Wahl et al. 2019, J Biophotonics (PMC7065627)",
  "Gupta et al. 2022, Ophthalmol Ther (PMC9434525)",
  "IEEE PAR1789 (2015) — recommended practices for modulating current in LEDs",
  "Ionescu et al. 2021, Journal of Information Display",
];
