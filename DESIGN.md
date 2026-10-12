# Glance website design

## Purpose
Glance puts music, focus timers, and optional activity updates in your Mac's notch. The primary action is Get Glance, linking to GitHub Releases. The icon study page's primary action is viewing or pausing the motion studies. There are no account, checkout, or submission forms.

## Tokens
Use CSS variables in `frontend/design-system.css` for website UI. Keep the palette to white paper, near-black ink, muted gray-green text, forest green emphasis, sage surfaces, and a neutral border. Gradients belong to the product preview and app icon, not content cards.

Typography uses DM Sans for body and Manrope for headings. Hero text is upright. Sizes: 12px labels, 14px supporting copy, 16px body, 20px card titles, 40px section headings, and a fluid 40–66px hero. Use rem units so browser text enlargement is honored. Body line height is 1.65; headings are 1.1. Do not use tiny text for essential information.

Spacing follows 4, 8, 12, 16, 24, 32, 48, 64, and 96px steps, expressed in rem. Content width is 70rem, with 1.5rem desktop and 1rem mobile gutters. Corners: 8px small controls, 16px surfaces, and pill primary buttons. Borders are 1px. Shadows are restrained and reserved for floating navigation and device previews.

The miniature native-app preview uses its own proportional `--u` coordinate system so it accurately represents the app. Its labels are illustrative; full-size accessible controls and explanatory text appear outside it on mobile.

## Components and states
Primary buttons use ink on paper with white text, a 44px minimum height, and consistent padding. Secondary buttons use bordered paper. Hover adds emphasis; pressed lowers the button; disabled removes elevation and reduces opacity. All controls have visible keyboard focus. Cards of the same kind share spacing, borders, and corners.

Tabs expose their selected state and support arrow keys. The mobile menu exposes expansion, closes on Escape and navigation, and returns focus to its trigger. Motion respects Reduce Motion. The preview has an accessible loading status and an image failure message. Native empty states are documented honestly, rather than fabricated into working states.

## Responsive and launch checks
No horizontal overflow at 320px or wider, or at 200% browser text size. Navigation becomes a mobile disclosure. Real controls have at least 44px tap targets. Every page has a title, description, and favicon. Use descriptive links. No placeholder copy or invented signup/checkout flows. Check downloads, menu, tabs, timer start/pause/reset, animation pause, image failure handling, and keyboard navigation before publishing.
