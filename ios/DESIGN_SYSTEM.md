# Shared Space design system

The single source of truth for how Shared Space looks: colors, type, spacing and components. It covers visual style only, not the app's flow or screen layouts. Every screen and component follows these rules. When building or changing anything visual, read this file first.

## Look and feel

Calm, warm and simple, for older adults and their adult children. Soft gradient backgrounds, white cards, lots of space, large titles, no heavy header bars. Strong color appears only on icons, progress and selected states. Readability always beats decoration.

## Color tokens (light mode)

### Neutrals

| Token | Hex | Use |
|---|---|---|
| `surface` (White) | `#FFFFFF` | Cards, buttons, sheets |
| `surfaceMuted` (Mist) | `#F2F2F2` | Card fill when the background is white |
| `track` (Cloud) | `#EBEBEB` | Progress tracks, pressed rows |
| `outline` | `#D0D0D0` | Button and chip outlines, 1.5pt |
| `divider` | `#E2E2E2` | Decorative lines only |
| `textPrimary` (Ink) | `#2A221C` | Main text |
| `textSecondary` (Graphite) | `#555555` | Secondary text; never use anything lighter for text |

### Brand

| Token | Hex | Use |
|---|---|---|
| `brand` (Brown) | `#7A6352` | Brand areas; only white or Cream `#F6F1EC` text on it |
| `iconNeutral` (Deep brown) | `#5C4A3D` | Icons and neutral button labels on light backgrounds |
| `tintBrown` | `#E8DDD2` | Avatar and icon circles |
| `accent` (Sage) | `#4E6B53` | Main accent: primary icons, progress fill, Keep, the floating action circle |
| `tintSage` | `#DCE5D7` | Icon circles, highlight fills |
| `tintSlate` | `#E3EAF0` | Icon circles, room tiles |

### Decisions

Always icon + word + color, never color alone.

| Decision | Color | Icon circle |
|---|---|---|
| Keep | `keep` Sage `#4E6B53` | `#DCE5D7` |
| Send to owner | `send` Slate `#3E5A70` | `#E3EAF0` |
| Let go | `letGo` Brick `#8E2F2A` | `#F3E3E1` |

Brick is also used for destructive actions (removing an item). Keep red off friendly actions.

### Backgrounds (main screens)

- **Default, brown gradient:** top to bottom `#E9DED3` → `#F3EDE7` (at 45%) → `#FAF8F6`
- **Alternative, sage gradient:** `#D9E4D3` → `#EDF2EA` (at 45%) → `#F8FAF7`

The background is a single theme setting so the app can switch between the two. No flat beige backgrounds. No gold anywhere in the app.

### Selected state and tags (soft gradient, 135°)

| Color | Text | Gradient | Outline (selected buttons only) |
|---|---|---|---|
| Sage | `#3D5642` | `#EEF3EB` → `#D5E1CF` | `#B7C8B1` |
| Slate | `#3E5A70` | `#EEF3F7` → `#D8E3EC` | `#B5C6D4` |
| Brick | `#8E2F2A` | `#FAEFEE` → `#F0DAD7` | `#DDB4AF` |
| Brown | `#5C4A3D` | `#F5EFE9` → `#E6DACD` | `#CDBBA9` |

Sage text on the sage gradient uses the darker `#3D5642`, because `#4E6B53` fails contrast on the deeper end of the gradient.

## Typography

SF Pro, the iOS system font. Use the built-in Dynamic Type text styles so everything scales with the iPhone's text size setting. Nothing to bundle.

| Style | Size (default) | Weight | Color |
|---|---|---|---|
| Large title | 32–34pt | Semibold | Ink |
| Title | 24pt | Semibold | Ink |
| Headline | 20pt | Medium | Ink |
| Body | 17pt | Regular | Ink |
| Secondary | 16pt | Regular | Graphite |

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
- **Tap targets:** at least 44 × 44pt; main buttons 52pt tall.

## Components

Each is built once in `Shared/UI` and reused everywhere.

1. **Button (default).** White fill, 1.5pt `outline`, capsule. Color lives in the label and icon: Deep brown for neutral actions, Sage for main ones, Brick for destructive. No hover; use the pressed state. Actions are always buttons with labels, never plain text links.
2. **Selected state (buttons, chips, filters, segmented choices).** Becomes the soft gradient tag in its color, with the thin matching outline and darker text. Selected decision buttons also show a checkmark at the end.
3. **Chips.** Default buttons in a scrolling row, used for filters, areas, categories and options (instead of underlined tabs or grey segmented controls). Selected chip = gradient tag.
4. **Tag.** Soft gradient, 32pt tall, capsule, icon + medium-weight word, no outline. For owners ("Mine", "Sam's") and decided status ("Keeping", "Sending to Sam", "Letting go"). Not tappable.
5. **Decision buttons.** One-at-a-time view: three full-width buttons stacked vertically, each with a 40pt tinted icon circle on the left and the label on one line ("Keep", "Send to owner", "Let go"). List view: three compact buttons side by side in each item card ("Keep", "Send", "Let go").
6. **Floating action button (where a screen has one main action).** Bottom right, 20pt from the edge. White capsule, 60pt tall, with a 44pt Sage circle holding a white icon, then a label (for example "New room"). Floating shadow. Stays put while content scrolls; lists get enough bottom padding to scroll fully clear of it.
7. **Room card.** Wide white card, 24–28pt radius. Name (headline) and status (secondary) on the left, optional progress bar under them, and an 88pt rounded tile on the right in the room's tint (Sage tint, Brown tint or Slate tint) holding the room's illustration or photo. Rooms rotate through the tints.
8. **Progress bar.** 8–10pt tall, rounded, Sage fill on a Cloud track (or `#DDDDDD` on Mist cards).
9. **Back button.** 48pt circle, white fill, 1.5pt `outline`, Deep brown chevron, with a VoiceOver label.
10. **Avatar.** Circle with the person's initial (medium weight) on Brown tint, Sage tint or Slate tint.
11. **Switch.** On: Sage track, white knob. Off: Cloud track with a Deep brown outline and knob, so it stays visible.
12. **Floor plan.** Room outline in Ink. Existing furniture: Brown tint fill with a Deep brown outline. New or proposed furniture: Sage tint fill with a dashed Sage outline. Windows in Slate tint.
13. **Bottom bar (if used).** White capsule with the floating shadow; the selected item shown as the sage gradient tag.

## Applying it to the app

This file defines the visual style only. Keep the app's existing screens, flow, navigation and content as they are, and restyle them with these tokens and components. Don't add, remove or reorder screens or features to match this file.

## Accessibility (required)

- Every text and background pair meets WCAG AA: 4.5:1 for text, 3:1 for large text, icons and essential outlines. All tokens above already pass in the combinations described; check any new pair.
- Dynamic Type up to the largest accessibility sizes: text wraps, buttons grow, nothing gets cut off.
- Dark mode variants of every color token, following the same rules and passing AA.
- Increase Contrast support: darker text and outlines.
- Every icon-only button has a VoiceOver label.

## Building it so it's easy to change

- **One source of truth.** Every color, font, size, radius, spacing value and shadow lives only in `Theme` (and the asset catalog). Components and screens read from `Theme` and never contain hex codes, point sizes or font names. Changing a value in `Theme` updates the whole app.
- **Name tokens by role, not by color.** Use the token names in this file (`accent`, `textPrimary`, `surface`, `outline`, `keep`, `send`, `letGo`…), not `sage` or `brick`, so the palette can be swapped without renaming anything.
- **Components take variants, not styles.** For example `AppButton(role: .neutral / .primary / .destructive)`, `DecisionButton(decision: .keep, layout: .full / .compact)`, `AppTag(kind: .keep)`, `RoomCard(tint: ...)`. Screens pick a variant; they never restyle a component.
- **Asset catalog.** Every color is a named color with light, dark and high-contrast variants.
- **Component gallery.** `#Preview`s for every component in every state (default, pressed, selected, disabled, large text, dark mode), plus a hidden "Design system" screen in debug builds that shows them all on one page.
- **No stray styling.** Feature folders (Rooms, Scanning, Sort, Redesign) contain no `Color(`, hex values, `.font(.system(size:` or hard-coded padding numbers.

## Project rules for anyone (or any assistant) changing the code

- The Xcode project is generated from `ios/project.yml` with XcodeGen. After adding, moving or deleting files, update `project.yml` if needed and run `xcodegen generate` in `ios/`. Quit Xcode before regenerating.
- Don't commit personal `PRODUCT_BUNDLE_IDENTIFIER`, `DEVELOPMENT_TEAM` or signing changes in `project.yml`.
- Work on a branch, not main. Build for an iPhone Simulator after each step and fix any errors or warnings.
- Visual reference images live in `ios/design/`.