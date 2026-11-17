# Shared Space design system

The single source of truth for how Shared Space looks: colors, type, spacing and components. It covers visual style only, not the app's flow or screen layouts. Every screen and component follows these rules. When building or changing anything visual, read this file first.

## Look and feel

Calm, warm and simple, for older adults and their adult children. Soft gradient backgrounds, white cards, lots of space, large titles, no heavy header bars. Strong color appears only on icons, progress and selected states. Readability always beats decoration.

## Color tokens

Every token is a named color in the asset catalog with light, dark and Increase Contrast variants. Light and dark values are listed here; the Debug "Design system" screen shows all four, read live from the catalog.

### Neutrals

| Token | Light | Dark | Use |
|---|---|---|---|
| `surface` (White) | `#FFFFFF` | `#2B2521` | Cards, buttons, sheets |
| `surfaceMuted` (Mist) | `#F2F2F2` | `#36302B` | Card fill when the background is white |
| `track` (Cloud) | `#EBEBEB` | `#4A423C` | Progress tracks, pressed rows |
| `trackOnMuted` | `#DDDDDD` | `#564D46` | Progress tracks on Mist cards |
| `outline` | `#8A7C71` | `#9A8D84` | Button, chip and toggle borders, 1.5pt; 3:1 on the page, white and Mist |
| `outlineStrong` | `#858585` | `#988D85` | Text field borders and tick rings (outlines that must be seen) |
| `divider` | `#E2E2E2` | `#403833` | Decorative lines only |
| `textPrimary` (Ink) | `#2A221C` | `#F4EEE8` | Main text |
| `textSecondary` (Graphite) | `#555555` | `#CFC6BE` | Secondary text and placeholders; never use anything lighter for text |

### Brand

| Token | Light | Dark | Use |
|---|---|---|---|
| `brand` (Brown) | `#7A6352` | `#7A6352` | Brand areas; only `onBrand` text on it |
| `onBrand` | `#FFFFFF` | `#FFFFFF` | Text on `brand` |
| `iconNeutral` (Deep brown) | `#5C4A3D` | `#DCCCBD` | Icons and neutral button labels |
| `accent` (Sage) | `#4E6B53` | `#9DC2A4` | Main accent: primary icons and labels, progress fill, Keep, the floating action circle |
| `onAccent` | `#FFFFFF` | `#16241A` | Text and icons on `accent` (selected number badge, the + circle) |
| `tintBrown` | `#E8DDD2` | `#4B3F36` | Avatar and icon circles |
| `tintSage` | `#DCE5D7` | `#304236` | Icon circles, highlight fills |
| `tintSlate` | `#E3EAF0` | `#2F3C47` | Icon circles, room tiles |
| `tintBrick` | `#F3E3E1` | `#4C2C29` | Icon circles for letting go and throwing out |

### Photos and 3D

| Token | Value (both modes) | Use |
|---|---|---|
| `photoBadge` | `#FFFFFF` | Number badges on photos, always white |
| `onPhoto` | `#2A221C` | Numbers on photo badges; the dark backing (86%) behind pin labels |
| `roomFloor`, `roomWall`, `roomWindow`, `roomDoor` | `#C9A178`, `#EFE9DF`, `#B9CCDA`, `#F6F2EA` | Materials in the 3D room |
| `shadow` | `#2A221C` (dark `#000000`) | Shadow colour |

### Decisions

Always colour + symbol + words, never colour alone. There are three decision colours: Throw out shares Brick with Donate or sell, and Not sure and Undecided use the neutral Brown. The symbol and the words always tell them apart.

| Decision | Button / short label | Status words | Colour (tone) | SF Symbol |
|---|---|---|---|---|
| Keep | Keep ("Keep it here") | Staying | `accent` Sage `#4E6B53` | `checkmark` |
| Send to owner | Send ("Send it to me") | Going to owner / Going to Sam | `send` Slate `#3E5A70` | `shippingbox` |
| Donate or sell | Donate or sell ("Donate or sell it") | Donating or selling | `letGo` Brick `#8E2F2A` | `xmark` |
| Throw out | Throw out ("Throw it out") | Throwing out | `letGo` Brick `#8E2F2A` | `trash` |
| Not sure | Not sure | Not sure yet (counts as undecided) | `iconNeutral` Brown `#5C4A3D` | `questionmark.circle` |
| Undecided | — | Not decided yet / Waiting for Sam | `iconNeutral` Brown `#5C4A3D` | `circle` |
| Keep but move (older items only) | Keep, move it | Moving elsewhere in the house | `send` Slate `#3E5A70` | `arrow.right.square` |

The owner picks from Keep, Send, Donate or sell, Throw out and Not sure. Someone who doesn't own the thing can suggest the first four. Keep but move is no longer offered; it's only shown on items decided before Nov 2026.

Brick is also used for destructive actions (Delete, Remove). Keep red off friendly actions.

### Backgrounds (main screens)

- **Default, brown gradient:** top to bottom `#E9DED3` → `#F3EDE7` (at 45%) → `#FAF8F6`
- **Alternative, sage gradient:** `#D9E4D3` → `#EDF2EA` (at 45%) → `#F8FAF7`

The background is a single theme setting so the app can switch between the two. No flat beige backgrounds. No gold anywhere in the app.

### Selected state and tags (soft gradient, 135°)

| Color | Text | Gradient | Outline (selected states only) |
|---|---|---|---|
| Sage | `#3D5642` | `#EEF3EB` → `#D5E1CF` | `#5A7656` |
| Slate | `#3E5A70` | `#EEF3F7` → `#D8E3EC` | `#577086` |
| Brick | `#8E2F2A` | `#FAEFEE` → `#F0DAD7` | `#955A53` |
| Brown | `#5C4A3D` | `#F5EFE9` → `#E6DACD` | `#80694F` |

Dark mode: Sage `#CFE6D4` on `#35473A` → `#27362B`, outline `#7FA287`; Slate `#D2E2EF` on `#334250` → `#26323D`, outline `#7D96AB`; Brick `#FFD2CC` on `#4D302D` → `#3C2421`, outline `#B5776F`; Brown `#EEE0D3` on `#473B32` → `#382E26`, outline `#9C8571`.

Sage text on the sage gradient uses the darker `#3D5642`, because `#4E6B53` fails contrast on the deeper end of the gradient.

The selected outline is what tells a selected chip, button or tab apart from the others, so it must reach 3:1 against the page, white and Mist, and against its own gradient (Nov 2026: the earlier pale outlines `#B7C8B1`, `#B5C6D4`, `#DDB4AF`, `#CDBBA9` were about 1.3:1).

## Typography

SF Pro, the iOS system font. Use the built-in Dynamic Type text styles so everything scales with the iPhone's text size setting. Nothing to bundle.

| Style | Text style (default size) | Weight | Color | In `Theme` |
|---|---|---|---|---|
| Large title | Large Title (34pt) | Semibold | Ink | `largeTitleText` |
| Title | Title 2 (22pt) | Semibold | Ink | `screenTitle` |
| Section title | Title 3 (20pt) | Semibold | Ink | `sectionTitle` |
| Headline | Title 3 (20pt) | Medium | Ink | `cardTitle` |
| Body | Body (17pt) | Regular, or Medium for names and labels | Ink | `bodyText`, `bodyStrong` |
| Button | Body (17pt), compact Callout (16pt) | Medium | Label colour | `button`, `buttonCompact` |
| Secondary | Callout (16pt) | Regular, Medium for tags | Graphite | `detail`, `detailStrong` |
| Badge | Footnote (13pt) | Medium | — | `badge` (numbers on pins and plans) |
| Room code | Large Title (34pt), small Title 2 | Semibold, letters spaced 6pt | Ink | `code`, `codeSmall` |

- **Semibold** only for screen and section titles and big numbers.
- **Medium** for buttons, names, labels and tags.
- **Regular** for everything else.
- Never thin or light weights. Sentence case everywhere; no all-caps labels.
- Room codes: space the letters out, since letters like I and l look alike in SF Pro.

## Shape, spacing and depth

- **Corner radius:** sheets 32pt, cards 24–28pt, tiles 20pt, buttons, chips and tags fully rounded (capsule).
- **Spacing steps:** 4, 8, 12, 16, 20, 24, 32. Screen side padding 24pt.
- **Card shadow:** two layers of Ink `#2A221C`: 6% opacity, 2pt blur, 1pt down; plus 7% opacity, 18pt blur, 6pt down.
- **Floating elements:** same, with the larger layer at 14%.
- **Cards on a gradient or Mist background:** white fill with the card shadow.
- **Cards on a white background:** Mist fill, no shadow.
- Never a grey outline on cards.
- **Tap targets:** at least 44 × 44pt; main buttons and text fields 52pt tall, compact buttons and chips 44pt, list rows 60pt, tags 32pt.
- **Fixed sizes:** icon circles 40pt, tick circles 26pt, photo pins 30pt (with a 44pt tap area), back button 48pt, floating button 60pt with a 44pt circle, room tile 88pt, progress bar 8pt.

## Components

Each is built once in `Shared/UI` and reused everywhere.

1. **Button (default).** White fill, 1.5pt `outline`, capsule. Color lives in the label and icon: Deep brown for neutral actions, Sage for main ones, Brick for destructive. No hover; use the pressed state. Actions are always buttons with labels, never plain text links.
2. **Selected state (buttons, chips, filters, segmented choices).** Becomes the soft gradient tag in its color, with the thin matching outline and darker text. Selected decision buttons also show a checkmark at the end.
3. **Chips.** Default buttons in a scrolling row, used for filters, areas, categories and options (instead of underlined tabs or grey segmented controls). Selected chip = gradient tag.
4. **Tag.** Soft gradient, 32pt tall, capsule, icon + medium-weight word, no outline. For owners ("Mine", "Sam's") and decided status ("Keeping", "Sending to Sam", "Letting go"). Not tappable.
5. **Decision buttons.** One-at-a-time view: the five decisions as full-width buttons stacked vertically, each with a 40pt tinted icon circle on the left and the label on one line ("Keep it here", "Send it to me", "Donate or sell it", "Throw it out", "Not sure"). Item sheet and list: compact buttons that wrap ("Keep", "Send", "Donate or sell", "Throw out", "Not sure"). Selected: the decision's gradient, outline and a checkmark at the end.
6. **Floating action button (where a screen has one main action).** Bottom right, 20pt from the edge. White capsule, 60pt tall, with a 44pt Sage circle holding a white icon, then a label (for example "New room"). Floating shadow. Stays put while content scrolls; lists get enough bottom padding to scroll fully clear of it.
7. **Room card.** Wide white card, 28pt radius. Name (headline), planned use and status (secondary) on the left, and an 88pt rounded tile on the right in the room's tint (Sage tint, Brown tint or Slate tint) holding the room's photo. Below, one full-width row per goal: a tag ("Sorting" with `checklist` in Sage, "Planning" with `cube` in Slate) and its status on the same line ("3 of 7 decided", "No layouts yet"); the status moves under the tag at accessibility text sizes. Then the progress bar, only while sorting is on. A ⋯ button in the tile's corner and touch and hold both open the Archive and Delete menu. Rooms rotate through the tints.
8. **Progress bar.** 8–10pt tall, rounded, Sage fill on a Cloud track (or `#DDDDDD` on Mist cards).
9. **Back button.** 48pt circle, white fill, 1.5pt `outline`, Deep brown chevron, with a VoiceOver label.
10. **Avatar.** Circle with the person's initial (medium weight) on Brown tint, Sage tint or Slate tint.
11. **Switch.** On: Sage track, white knob. Off: Cloud track with a Deep brown outline and knob, so it stays visible.
12. **Floor plan.** Room outline in Ink. Existing furniture: Brown tint fill with a Deep brown outline. New or proposed furniture: Sage tint fill with a dashed Sage outline. Windows in Slate tint.
13. **Bottom bar (room tabs).** White capsule with the floating shadow; the selected tab shown as the sage gradient tag with its outline. Tabs: Room (`house`) and People (`person.2`) always, Sort (`checklist`) and Redesign (`cube`) only while their goal is on. With three or more tabs the icon sits above a smaller label; at accessibility text sizes only icons show, and touch and hold shows the name large.
14. **Decisions.** Always colour + symbol + words (see the Decisions table). Things leaving are drawn see-through with a label in the 3D view, and with a dashed outline in the decision's colour and their symbol before the name on the floor plan.
15. **Photo pin.** A 30pt white number badge (`photoBadge`, `onPhoto` number) with a ring in the decision's colour and the decision's symbol on a small badge at its corner. Selected, it fills with `accent` and shows a label under it: "Chair · Undecided", white text on a dark backing (`onPhoto` at 86%). Every pin has a 44 × 44pt tap area; pins closer than that are drawn apart on screen (the saved position doesn't change). VoiceOver reads "1, Chair, undecided".
16. **Room goals selector.** Two choice rows ("Sort things", "Plan the room"), each with a one-line explanation and a tick; either or both, never neither. Used in New room ("What do you want to do with this room?", with the hint "You can change this anytime. Nothing has to leave the room.") and in the "Room goals…" sheet, which explains that turning a goal off only hides it and offers "Archive this room" when both are off.
17. **Archive and Delete menu.** The system context menu (touch and hold) and the same items under the card's ⋯ button, with short labels only: "Archive" (`archivebox`) and "Delete" (`trash`, destructive, so red). Guests get "Leave Room" instead of Delete; archived rooms show "Unarchive". Delete asks first in a confirmation dialog ("Delete this room?", with "Delete Room" in red and "Cancel"); Archive doesn't ask and shows an undo banner ("Room archived", Undo).
18. **Undo and activity banner.** A floating white card at the top with a tinted icon circle, one line of text and, for undo, a compact button. Goes away after a few seconds (longer with VoiceOver on) and is announced to VoiceOver.
19. **Consent sheet ("Before you scan").** Shown before the first scan or photo in a room: a Sage icon circle (`person.2`), the title, three short lines (who can see the scan, photo and items; leave people and private things out of view; the room can be deleted), then "Continue" (primary) and "Not now" (neutral, compact). "Who can see this?" (a compact neutral button) opens it again.
20. **"How this works" pop-up.** A small ⓘ button (`info.circle`, Sage, 44pt tap area, VoiceOver "How this works") beside the photo step's lead line. Opens a system alert, "How we find things in your photo", with three short paragraphs and "Got it".
21. **Suggestion label.** Things found in a photo show the tag "Suggested — check this" (Sage gradient, `questionmark.circle`) until the person confirms, renames or removes them; confirmed ones show "Confirmed" with `checkmark`. Next to it: a note bar with `lock.iphone`, "Detection runs on your iPhone. Your photo isn't uploaded for this."
22. **Note bar, key-value row, choice tile.** Note bar: a tinted rounded bar with an icon and one or two lines (Sage for information, Brick for warnings), optionally with a button. Key-value row: a label and a value on one line (room code, size) with an optional action. Choice tile: a large tappable card with an icon circle, a title and a detail ("Take a photo", "Scan with LiDAR").

## Applying it to the app

This file defines the visual style only. Keep the app's existing screens, flow, navigation and content as they are, and restyle them with these tokens and components. Don't add, remove or reorder screens or features to match this file.

## Accessibility (required)

- Every text and background pair meets WCAG AA: 4.5:1 for text, 3:1 for large text, icons and essential outlines. All tokens above already pass in the combinations described; check any new pair.
- Dynamic Type up to the largest accessibility sizes: text wraps, buttons grow, nothing gets cut off.
- Dark mode variants of every color token, following the same rules and passing AA.
- Increase Contrast support: darker text and outlines.
- Every icon-only button has a VoiceOver label.
- Every item row, photo pin, floor-plan thing and 3D thing says its status to VoiceOver ("Desk, staying", "Guitar, going to Sam").
- Every control is at least 44 × 44 points; small markers keep a 44-point touch area around them.
- Reduce Motion: nothing slides, scales or springs. Screens and cards that appear fade in; everything else changes at once (`Motion.animation`, `Motion.transition`, `withMotion` in `Theme`). Sheets and pushes appear without sliding, a decision moves the card on instantly, and the 3D camera has no inertia.
- Text field placeholders use `textSecondary`, not the system grey.
- Number badges on photos always use the light palette, because the badge is white in both modes.

## Building it so it's easy to change

- **One source of truth.** Every color, font, size, radius, spacing value and shadow lives only in `Theme` (and the asset catalog). Components and screens read from `Theme` and never contain hex codes, point sizes or font names. Changing a value in `Theme` updates the whole app.
- **Name tokens by role, not by color.** Use the token names in this file (`accent`, `textPrimary`, `surface`, `outline`, `keep`, `send`, `letGo`…), not `sage` or `brick`, so the palette can be swapped without renaming anything.
- **Components take variants, not styles.** For example `AppButton(role: .neutral / .primary / .destructive)`, `DecisionButton(decision: .keep, layout: .full / .compact)`, `AppTag(kind: .keep)`, `RoomCard(tint: ...)`. Screens pick a variant; they never restyle a component.
- **Asset catalog.** Every color is a named color with light, dark and high-contrast variants.
- **Component gallery.** `#Preview`s for every component in every state (default, pressed, selected, disabled, large text, dark mode), plus a hidden "Design system" screen in debug builds that shows them all on one page, in the same sections as this file: room ⋯ menu → Design system (or long-press the logo on Rooms, or launch with `-designSystem`). A control at the top previews light mode, dark mode and larger text. Screenshots of each section are in `ios/design/screenshots/`; a public copy is at https://project3-advancedixd.netlify.app/designsystem.
- **No stray styling.** Feature folders (Rooms, Scanning, Sort, Redesign) contain no `Color(`, hex values, `.font(.system(size:` or hard-coded padding numbers.

## Project rules for anyone (or any assistant) changing the code

- The Xcode project is generated from `ios/project.yml` with XcodeGen. After adding, moving or deleting files, update `project.yml` if needed and run `xcodegen generate` in `ios/`. Quit Xcode before regenerating.
- Don't commit personal `PRODUCT_BUNDLE_IDENTIFIER`, `DEVELOPMENT_TEAM` or signing changes in `project.yml`.
- Work on a branch, not main. Build for an iPhone Simulator after each step and fix any errors or warnings.
- Visual reference images live in `ios/design/`.

## Changes

Nov 16, 2026: checked this file against `Theme.swift`, the asset catalog and `Shared/UI`, and updated the file where it no longer matched the app. The app's look didn't change.

- **Color tokens:** added the dark value of every token, and the tokens that were in the app but not here: `trackOnMuted`, `outlineStrong`, `onBrand`, `onAccent`, `tintBrick`, and the photo and 3D colours (`photoBadge`, `onPhoto`, `roomFloor`, `roomWall`, `roomWindow`, `roomDoor`, `shadow`). Removed "Cream `#F6F1EC`", which isn't a token; `onBrand` is white.
- **Decisions:** replaced the three-decision table (Keep, Send to owner, Let go) with the app's set: Keep, Send, Donate or sell, Throw out, Not sure and Undecided, plus Keep but move for older items. Each has its words, colour and SF Symbol, and the table notes which colours are shared.
- **Selected state and tags:** added the dark-mode values.
- **Typography:** Title is 22pt (Title 2), not 24pt. Added the section title, button, badge and room code styles the app uses, with their names in `Theme`.
- **Sizes:** added the compact button, chip, row, tag and fixed component sizes from `Size`.
- **Components:**
  - Updated decision buttons (five decisions, not three), the room card (goal rows, ⋯ button, touch and hold), the bottom bar (room tabs) and the floor plan (things leaving).
  - Added components that existed in the app but weren't documented: photo pin with status label, room goals selector, Archive and Delete menu, undo banner, consent sheet, "How this works" pop-up, suggestion label, and note bar, key-value row and choice tile.
- **Accessibility:** added the Reduce Motion details (sheets, decisions, the 3D camera) and the placeholder colour.
- **Component gallery:** where to find the Design system screen, its screenshots and the public page.
