# Glance — design direction

*Website, icon studies, and browser extension · 27 October 2026*

## The idea

Glance should feel like a small, well-made Mac utility. It lives in a part of the screen that people already look at, makes a few everyday actions easier, and gets out of the way. The website ought to behave the same way.

The visual idea is **a quiet page with one very precise interruption: the notch**. Light paper, dark type, a little green, generous room around the product. The interesting thing is what the app does—not what the marketing page does around it.

A visitor should understand three things in the first screen: Glance belongs at the top of a Mac, it brings music and focus into reach, and **Get Glance** takes them to GitHub Releases. Optional activity updates can follow once that basic idea lands.

This is not a SaaS site. There is no account, waitlist, pricing table, checkout, testimonial carousel, or fabricated social proof. The icon study is a separate gallery of motion explorations, not another sales funnel. The extension UI is a local tool, not a second product with a competing session model.

### The feeling to aim for

- **Mac-native, not Apple cosplay.** Borrow its clarity and measured motion; don't borrow entire interface treatments, fake window chrome, or glass everywhere.
- **Friendly without being cute.** Ordinary words, good spacing, readable controls. No breathless claims, mascot, decorative emojis, or exclamation marks doing the design's work.
- **Specific rather than impressive.** One believable timer state is worth ten floating feature cards. When possible, show actual app capture. Label illustrative previews honestly.
- **Calm, not vacant.** The eye should have a path: headline → notch → explanation → download. Quietness requires hierarchy, not just whitespace.

## What the page should look like

### Homepage, from top to bottom

**1. Navigation**

An unboxed Glance wordmark at the left. A few short text links as appropriate for pages that actually exist (for example, Features and Icon studies); **Get Glance** is the only filled action at the right. No announcement ribbon, floating badges, or double navigation. On small screens, collapse links into a proper disclosure menu while keeping the download action discoverable.

**2. Hero: the Mac's top edge, not a giant laptop mockup**

Keep the headline upright, strong, and short. Working copy:

> **Your Mac's notch, put to work.**
>
> Music, a focus timer, and the updates you choose. Right where you can see them, without another window to manage.

Primary button: **Get Glance** → the project's existing GitHub Releases destination. Beneath or beside it, only verified installation requirements or an unobtrusive GitHub source link if one already exists. Never invent compatibility, pricing, downloads, or release numbers.

The visual is a wide, cropped Mac display edge, not a 3D device floating at an angle. Use a genuine product capture when available. It should show the notch at its real location and one legible app state; the surrounding screen exists for scale, not decoration. Let the ink-black island be the densest thing on the page. If a live demonstration exists, it can move between *Now playing* and *Focus* via explicit tabs. If it is just a representation, don't make the controls appear interactive.

On desktop, let the image take the full content width below the copy (with a deliberate offset or crop). On mobile, show a closer crop of the notch and put the explanation outside the miniature preview. Do not scale down a desktop canvas until its labels become microscopic.

**3. Two feature moments, not a feature-card factory**

Give music and focus each their own scene, with different compositions but one visual language:

- **Music, without changing windows.** A compact, actual now-playing state, perhaps paired with a quiet crop of the album art. Explain the specific available controls. Keep album art/color inside the product UI, not as page background decoration.
- **Keep time in sight.** A clear timer state and a few words on starting, pausing, and resetting a session, but only if those actions are available in the represented surface. The timer digits should do most of the work.

Use asymmetry intentionally: a narrower text column next to a larger product crop; then reverse the balance for the next scene. Separators and whitespace, not boxed backgrounds, should organize the reading. Do not force alternating layout on mobile: stack image and text in a consistent order.

**4. Optional activity, presented as optional**

A short, quieter section explains what an activity update is and when it appears. Show one real supported state if assets exist. Avoid a sprawling integrations grid or implying notifications or services that aren't implemented. Copy should state that updates are optional rather than presenting them as a core prerequisite.

**5. Last invitation**

A compact download section, not a second hero. For example:

> **Make that little space useful.**
>
> Get Glance from GitHub Releases.

Use the same **Get Glance** action and verified destination. The footer is modest: product name, links that work, and only necessary legal text.

### A useful constraint on composition

Most of the page should be flat paper. Allow **one visually rich object per viewport**, usually the product capture. Avoid adding a new card, pill, blur, glow, tiny uppercase eyebrow, and gradient to every section. When the product image is detailed, the surrounding typography should be quieter. When the content is spare, let scale and alignment provide the character.

The page should still be recognizable with every image hidden: good type, a distinct notch motif, a clear CTA, and a considered rhythm.

### Icon study page

Treat this as a design notebook. Begin with a small introduction and display the motion studies at a size large enough to judge them. Each study can have a plain name and one concise note explaining what changed—shape, timing, silhouette, or light—not promotional copy.

The visitor's main task is to **watch or pause the studies**. Offer a clearly labeled Pause motion / Play motion control with a visible state, and let the browser's Reduce Motion preference default to still frames. If separate studies can be controlled independently, their controls must name the study. Use the actual icon artwork, not hand-wavy CSS stand-ins. Keep all controls keyboard-operable. No auto-playing motion that cannot be stopped.

## Visual system

Store website values in `frontend/design-system.css`. The extension uses matching colors but maintains its own tokens in `browser-extension/ui.css`. Shared *intent* matters more than forcing both surfaces into identical layouts.

### Color

These are proposed reference values; use them consistently instead of generating nearby shades ad hoc:

| Token | Value | Use |
| --- | --- | --- |
| `--paper` | `#F8F9F5` | Main canvas |
| `--ink` | `#19251F` | Main text; strongest dark surface |
| `--muted` | `#53645B` | Secondary text; not disabled controls |
| `--forest` | `#274835` | Primary action, links, active accents |
| `--sage` | `#E4ECE3` | Soft surfaces, blocked page background |
| `--line` | `#D7DFD6` | Rules and borders |
| `--white` | `#FFFFFF` | Button contrast, selected fields if needed |
| `--error` | `#8A3C36` | Form error text; use with words, not color alone |

Ink and forest should never be replaced with fashionable saturated green. The grayscale should feel slightly warm, never clinical or icy. Keep gradients inside actual app imagery and icon art. **No gradient content cards.** Shadows are rare: a restrained edge/shadow on a floating header or a product/device preview, never under every section.

The proposed muted, forest, ink, and error text colors clear 4.5:1 against paper and sage; recheck contrast if any token is changed. Disabled states need semantics beyond faded type.

### Type

Website: **Manrope** for display and headings, **DM Sans** for paragraphs, controls, and small text. Use fallbacks and avoid layout shifts as web fonts load. Extension: **system UI fonts**, no external font request. Numerals in timers use tabular lining figures.

| Role | Desktop intent | Notes |
| --- | --- | --- |
| Hero | `clamp(2.5rem, 5.2vw, 4.125rem)` | Upright, weight 650–750, about 1.06 line-height |
| Section heading | `clamp(2rem, 3.5vw, 2.5rem)` | About 1.1 line-height |
| Card / feature title | `1.25rem` | Use sparingly; sections aren't all cards |
| Body | `1rem` | 1.65 line-height; comfortable reading measure |
| Supporting | `0.875rem` | For genuinely secondary information |
| Label | `0.75rem` | Only for nonessential labels, not instructions |

Use negative tracking subtly on large Manrope headings (roughly `-0.025em` to `-0.04em`), never on body copy. Don't make every heading a five-line poem. Aim for line breaks that feel written, but let them wrap naturally on small screens. Avoid an italic hero, a decorative serif word, giant outlined type, typewriter effect, or bright text gradients—the page has enough identity without them.

### Spacing and shape

The underlying spacing steps are `0.25`, `0.5`, `0.75`, `1`, `1.5`, `2`, `3`, `4`, and `6rem` (4–96px at a 16px root). Maximum content width: `70rem`. Gutters: `1.5rem` desktop, `1rem` mobile. Main section spacing can reach `6rem`; tight content groups should usually stay between `0.75` and `1.5rem`.

One rule makes the page feel designed: **whitespace does not need borders to justify its existence**. Use 1px rules when a division helps scanning. Use 0.5rem radius for small controls, 1rem for actual surfaces, and full pills for primary actions. A repeated grid may be appropriate in the dashboard, but not by default on the marketing homepage.

### Components

- **Primary action:** solid forest (or ink where the composition calls for it), white text, pill shape, minimum `2.75rem` height. Solid fill and contrast should make it obvious without a neon glow.
- **Secondary action:** paper, 1px neutral border, ink text, minimum `2.75rem` height. Don't style secondary links as competitors to the download action.
- **Hover / press:** small color adjustment on hover; restrained downshift on press. No bouncing or continuously animated button glint.
- **Focus:** visible, high-contrast `:focus-visible` ring offset from the control. Must work on both paper and sage.
- **Tabs:** selected state visible without relying only on color; follow the WAI-ARIA tabs pattern. Arrow keys move through tabs; Tab exits the tab list; state and displayed panel agree.
- **Mobile menu:** real disclosure button with expanded state; Escape closes it, navigation closes it, and focus returns to the trigger on dismissal when appropriate.
- **Empty / loading / error:** readable inline messages. A failed image or preview isn't an empty rectangle or a permanent spinner.

The small app preview uses its own proportional `--u` coordinate system. That precision is deliberate: screen miniatures should resemble actual native UI rather than a resizable website card. Miniature labels are illustrative. On mobile, put the explanation and any real controls outside the reduced-size mockup.

## Motion rules

The notch can expand because that's the product's signature behavior. The marketing page doesn't need to animate to prove it is modern.

Motion is reserved for state changes that answer a question: *what opened, what closed, which study is playing, which tab is selected?* For website interface transitions, work around 150–250ms with a controlled easing curve; tune by eye and context rather than applying one spring everywhere. The notch demonstration may have its own measured timing to match the real app.

Do not use scroll-jacking, parallax, bobbing mockups, perpetual ambient gradients, staggered reveal on every paragraph, or animating digits solely for spectacle. All nonessential motion should be removed or replaced with a useful still state under `prefers-reduced-motion: reduce`. Explicit animation controls must work independently of that system preference.

A good animation leaves the interface in an understandable state if stopped halfway. A good page needs no animation to communicate its purpose.

## Browser extension: a tool, not a brochure

The extension should share Glance's paper/ink/forest/sage identity but keep the density and directness of a utility. Put these tokens in `browser-extension/ui.css`; use the system font stack to avoid external font requests.

**Popup:** width `380px`; body `0.9375rem` (15px), labels `0.8125rem` (13px), headings `1.125–1.25rem` (18–20px), and a tabular timer around `4rem` (64px). Use 1rem radii on cards, 0.5rem on secondary controls, and a pill for the main action. Every usable control gets at least a 44px target. Keep connection state, permission requirements, empty data, and pending operations visible. An error belongs next to its input **and** in a live status region where appropriate.

**Dashboard:** below `620px`, cards use one column. Above that, density should come from alignment, not tiny type. Show the current source of truth clearly: local extension/browser or paired Mac. Don't suggest both are running separate timers when they're showing the same session.

### Blocked focus page

This is the most intentionally plain surface in Glance. It is a full-viewport **flat sage** page with forest text and no external fonts or decorative animation. The page should say, without preaching: this site is blocked during a focus session, and here's the time remaining.

Composition:

- At the top, the **Glance** wordmark as noninteractive text, no app icon.
- At the center, the timer as the dominant element. Use medium-weight tabular numerals, `letter-spacing: -0.06em`, `line-height: 1.05`, and `font-size: clamp(6rem, 20vw, 16rem)` in the normal layout. At narrow widths with enlarged text, adjust carefully as far down as `3rem` when necessary so the digits fit.
- A concise state label at `0.875rem` and explanation at `1rem` should sit with the timer rather than in separate cards.
- Beneath the timer group, **Manage list** is the **only action**. It is a link, minimum 44px target, 0.5rem radius, and uses the shared forest focus treatment.

Use `1rem` mobile / `2rem` desktop gutters, approximate `4rem` header and footer bands, and `1`, `1.5`, and `3rem` grouping gaps. Allow the page to scroll vertically when zoom or viewport height demands it; never clip the timer or Manage list. Loading, paused, finished, and connection-error conditions keep the same skeleton and honest messages. **Do not expose pause, emergency stop, back, or return-to-site controls on this page.** They stay in popup/dashboard surfaces.

### Extension icon

Use a static outline-notch symbol, centered at the **top** of an opaque sage square, in forest. Export dedicated 16px, 32px, 48px, and 128px PNGs from the vector master. At 16px, simplify details rather than trusting automatic downscaling. Check the icon against both light and dark browser chrome. Keep the original app icon for app branding; the extension mark is a related, more legible tool icon.

### Hosted and packaged dashboard

The hosted route `/extension/dashboard/` and packaged settings view should use the same extension patterns. Both are a window into the **local extension and paired Mac**, never an independent session engine.

Before authorization, show a full-page **connection gate**. Don't reveal blank settings or pretend data is zero. Once connected, name the active owner (Mac or standalone browser) near the relevant settings/timer summary. Place Pomodoro settings in two aligned columns on desktop and one column on mobile. Native validation errors appear inline and are mirrored in the shared live status region.

Keep **Save on Mac** and **Reload from Mac** as explicit, different actions. Preserve unsaved edits. Refuse stale writes with a plain explanation and a path to reload, rather than silently overwriting local changes. Permission requests for new websites must open in packaged extension UI, where Chrome can show its browser permission prompt after a user gesture; don't attempt this from the hosted dashboard.

## Copy should sound like the app

Short, specific, and unforced. Say **“Pause the timer”**, not **“Take control of your productivity journey.”** Say **“See what's playing”**, not **“An immersive music experience.”** Avoid invented metrics, testimonials, claims of being “lightning-fast” or “revolutionary,” and any functionality that the product can't demonstrate today.

Prefer one sentence that explains an interaction over three slogans. Sentence case throughout. Labels use the words people expect from native controls. **Get Glance** remains the product's primary download wording wherever it appears. The icon page uses **Pause motion / Play motion**. The blocked page uses **Manage list**.

## Accessibility and release bar

These aren't polish items to defer until the page looks good. They are part of the design:

- No horizontal overflow at 320px, 375px, or 200% browser text sizing; review intermediate widths rather than just familiar device presets. Let content grow vertically.
- Real controls have at least 44px hit targets (larger than the WCAG 2.2 AA baseline for pointer targets). Check hover, focus, pressed, disabled, and error states separately.
- Body and instructional text stay readable; don't hide essential information in a tiny grey caption or in the mockup.
- Semantic headings, clear link names, visible keyboard focus, working tab order, Escape behavior, and meaningful accessibility status announcements.
- Timer behavior (start, pause, reset, finish) is correct and is reflected consistently across the available surfaces. The marketing demo must not imply it started a real session unless it actually did.
- The preview has a loading status, an actionable failure message if its media cannot load, and a useful static fallback. Animated studies can be paused.
- Every public route has a distinct title, description, and favicon. Check broken downloads, the mobile menu, tab selection, source-of-truth labels, pairing gate, form validation, stale-write rejection, and Chrome permission flow.
- Test with reduced motion, keyboard-only input, enlarged text, and slow or failed media loading. Verify the blocked page at 320px and at large text sizes.

### Review it like a product designer

Before calling a page done, capture the actual browser at **320 / 375 / 768 / 1024 / 1440px**. Put those images next to one another. Check that the notch is still the focal point, headings don't wrap awkwardly, spacings form a rhythm, and there isn't a sudden stretch of anonymous cards. Then test actual interactions in the browser. A beautiful screenshot of a broken control is not a finished design.

If a section feels generic, don't add ornament. Ask whether it proves anything unique about Glance. If not, change the composition, improve the real product footage, sharpen the copy, or remove the section.

## Reference notes

These are references for principles, **not templates to reproduce**:

- [Glancefold](https://glancefold.com/) — particularly the decision to anchor feature explanations to real Mac recordings rather than claim-heavy mockups.
- [Notch — focus timer](https://notch.rocks/) — a focused, ordinary-language explanation of why a notch timer earns its place.
- [Rauno Freiberg, *Invisible Details of Interaction Design*](https://rauno.me/craft/interaction-design) — interactions should match intent and frequency; animation can become a tax on repeated actions.
- [X: Namya on defining a design kit instead of accepting default AI landing-page layouts](https://x.com/namyakhann/status/2036140952767832140).
- [X: Yuwen Lu on recognizable stylistic patterns in generated UIs](https://x.com/yuwen_lu_/status/2041187936738447565).
- [X: Oluwaphilemon on starting with a concrete visual reference](https://x.com/Oluwaphilemon1/status/2062558176814198853).
- [WAI-ARIA Tabs Pattern](https://www.w3.org/WAI/ARIA/apg/patterns/tabs/), [WCAG 2.2 target sizes](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum), [MDN reduced motion](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/At-rules/%40media/prefers-reduced-motion), and [Chrome optional permissions](https://developer.chrome.com/docs/extensions/reference/api/permissions).

**Design review rule:** If a change makes the screenshot busier but doesn't make Glance clearer or nicer to use, it probably doesn't belong.

## Current review scope

The hosted dashboard keeps Pomodoro configuration removed, following the direct product decision made before this document was supplied. Those settings remain in Glance and packaged extension settings. The blocked page retains its existing layout and sole Manage list action; only palette alignment is part of this review. This revision is for local review only, with no commit, push or deployment.

### Local review adjustment
The user explicitly prefers a MacBook in the hero over the cropped display-edge direction. Retain a front-facing MacBook illustration with a centered hardware notch and real app captures; apply the updated palette, typography, feature scenes and restrained motion around it. This direct preference takes precedence over the document’s cropped-edge recommendation.

### Latest local-review decision
The user has requested the earlier landing page back, retaining the browser-extension details. `frontend/index.html`, `frontend/app.js` and `frontend/landing/` restore that earlier design; `landing.css` is its generated bundle. The updated direction remains available for companion pages, but must not override the restored landing page. No push or deployment is authorized for this local review.

### Extension reference direction
Keep the original MacBook homepage and its smooth interactive example. The separate extension marketing page uses the supplied Freedom reference for composition: deep forest, large upright serif display, layered real product captures and a light pill CTA. It retains Glance's original controls, body fonts and restrained palette. No press logos, testimonials, metrics or install availability are invented. Surface grain is a low-opacity background below text, never a text filter. `/extension/connect/` contains the detailed pairing guide. All changes remain local pending review.

#### Extension marketing tokens
`frontend/extension.css` owns three reference-specific colors: forest `#223d2b`, cream `#f0f3e9`, and border `#dce1d8`. Body, muted text, ordinary controls and white surfaces inherit the restored landing tokens. Display headings in the green hero use upright Georgia at 40–66px responsive sizes; section headings inherit Manrope at 32–40px, and body copy uses the landing body font. Spacing follows the landing 4px scale (16, 24, 32, 48, 64, 80, 96px). Capture corners use 16px, code blocks 8px, and primary actions the shared pill shape with a minimum 52px height. Ordinary interactive targets have at least 44px height. Grain never reduces text opacity.
