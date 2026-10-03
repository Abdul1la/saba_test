# Design changes — Home redesign (2026-09-22)

The shopper Home screen, redesigned from the user's reference screenshot, in two parts. Part A covered the data, the city chips, the product grid and the flash sale. Part B covered the top bar, the search row and the fonts. The details are in `WORK-LOG.md`.

## Home, top to bottom

1. **Top bar:** the greeting, then 🌐 language, messages and notifications. The globe is new; messages and notifications are as they were. "Deliver to …" is removed.
2. **Banner:** looks as it did. At the largest text size on a small phone its words now wrap and shrink to fit, instead of being cut (see below).
3. **Search bar:** as it was, without the heart beside it.
4. **City chips:** All cities, then each city that has a store. The chosen chip is orange with an icon.
5. **Categories:** unchanged, except that its title uses the new heading font like every other section title (see below). The user confirmed this, for consistency.
6. **Flash sale:** a daily sale of real discounts until midnight in Iraq. Its cards are unchanged.
7. **Coupons for you:** unchanged.
8. **Featured stores:** all 8 stores, scrolling sideways.
9. **All products:** a Filters button, "N found", and a two-column grid of the new showcase card.
10. **Bottom navigation:** unchanged.

## Fonts

| Use | English | Arabic |
|---|---|---|
| Home headings (the greeting name, section titles) | DM Serif Display | Amiri Bold |
| Everything else: body, labels, prices, cards | IBM Plex Sans Arabic (unchanged) | IBM Plex Sans Arabic (unchanged) |

- **Bundled in the app** (`mobile/assets/fonts/`), so they work offline. Their SIL Open Font License texts are beside them. The app is about 480 KB bigger.
- **Coverage, checked with fontTools:**
  - Amiri has every Arabic character the app uses anywhere, including the vowel marks, Arabic punctuation and Persian/Kurdish letters (پ چ ڤ گ ی ک), and it has English letters.
  - DM Serif Display has every English letter and common punctuation.
- **Fallback:** each heading font has the other one behind it, then IBM Plex Sans Arabic, so a name in the other alphabet still draws in a proper font.
- **One place to change:** `AppTypography` in `mobile/lib/core/theme/app_typography.dart`. To set Arabic headings in **Cairo Bold** instead of Amiri:
  1. Add `Cairo-Bold.ttf` to `pubspec.yaml` as family `Cairo`, weight 700.
  2. Change `headingFamilyArabic` to `'Cairo'`, and `headingHeightArabic` to about `1.35`.

  Nothing else refers to the font names.

## Effect on the store (merchant) and admin screens

**Admin:** none. The app has no admin screens; admins use the web.

**Store screens:** no visible change. Every shared piece that changed only gained something optional, with the old behaviour as the default:

| Shared code | What changed | Store screens |
|---|---|---|
| `SectionHeader` | Optional `titleStyle`, and `titleMaxLines` (default 1) | "What you owe Saba" uses the defaults and looks the same |
| `DarkHeaderGreeting` | Optional `nameStyle`, and `shrinkToFit` (default off) | No store screen uses it |
| `ShopHeader` | Optional `showWishlist` (default on) | Not used on store screens. Categories keeps its heart |
| `iconForName` | Also knows Arabic words (هاتف, سماع, ساعة, كاميرا, منزل …) | Not used on store screens; English matching is unchanged |
| `AppTypography` | New heading constants and `heading()`; existing styles unchanged | Unchanged |
| `ProductQuery`, `ProductSummary` | Optional `governorate`, `deliverTo` and `deliveryAvailable` (part A) | The store screens use other models |
| Demo data | 6 new stores and 28 new products (part A) | Nova and Atlas have the same 12 products, orders and bills |

**Shopper-wide (not Home only):** where the shopper is delivered to (`shopperCityProvider`) now uses the **profile city first** when signed in. The city kept on the phone is only a fallback for a signed-out shopper. Before this change, a city picked with the old "Deliver to" button would have overridden the profile for good, and nothing on screen could change it any more.

## Banner at the largest text size (fixed after Part B)

The demo banners have no photograph yet (`assets/images/stores/` is empty), so the phone draws each one as a coloured card with its words. The card keeps its 2.4 : 1 shape, so on a 320 px phone at the largest text size (1.4):
- the Arabic title's second line was cut in half;
- the subtitle, held to one line, lost its end ("Up to 40% off selected electr…").

Now the subtitle may take two lines like the title. When the words are taller than the card, they shrink together. Their width and wrapping stay the same. At normal text size nothing moves: the 320 px picture of Home is pixel-identical to the one before the fix.

## Known limits

- **Greeting on small phones:** on a 320 px phone the greeting shrinks to fit one line instead of being cut off. A very long name there is drawn small.
- **Other screens after a language switch:** they still show the server's words in the old language until they are opened again, for example a search results list that is still open. Home reloads itself. The user decided not to fix this now; it is on the bug list (`BUGS.md`).

# One card design everywhere (2026-09-23)

Shared components, so a product, a store, an order or a section title looks the same on every screen.

| Component | Where it lives | Used by |
|---|---|---|
| **Product card** (`ProductCard`) | `mobile/lib/features/catalog/presentation/widgets/product_card.dart` | Home's grid and rails, Browse, categories, search, a store's page, the related rail on a product page, favourites |
| **Store card** (`StoreCard`) | `mobile/lib/core/widgets/store_card.dart` | Home's Featured stores rail, the seller card on a product page |
| **Order card** (`OrderCard`) | `mobile/lib/features/orders/presentation/widgets/order_card.dart` | My Orders, the store's orders list |
| **Section header** (`SectionHeader`) | `mobile/lib/core/widgets/section_header.dart` | every section title, "See all" at the end of the row |
| **Card shadow** (`AppElevation.card`) | `mobile/lib/core/theme/app_dimensions.dart` | all three cards: a soft shadow, no border |

- **Product card:** a square photo with rounded corners; the heart on it; the discount or "Out of stock" badge in its corner; the name on two lines; the store; the price, with the original struck through above it; "Delivery available" when the store delivers to the shopper's city. Every card is the same height.
- **Flash sale:** keeps its own card, unchanged, so the sale stands out.
- **Store card:** logo, name, rating and city. The product page adds "Sold by", whether it delivers to you, and the Message button.
- **Order card:** number and status badge, a line of facts, the total. The shopper's side adds a photo; the store's adds the lines to pack and its buttons.
- **Status colours:** one map for both sides. Waiting on the store (New / Pending) is amber everywhere.
- **Section titles:** every section title on every screen uses the heading font (DM Serif Display / Amiri Bold) at 21, up to two lines.

## What looks different

- Cards have a soft shadow instead of a grey border.
- No "add to cart" button on product cards; adding is on the product page. The flash-sale card keeps its button.
- No "Only a few left" badge on cards; the product page still says it.
- The discount badge is the dark one on every card; Home's was orange.
- Home's cards now show the store's name. Other screens' cards now show "Delivery available".
- Featured stores are wider cards laid out like the product page's seller card; the product count is gone from them.
- A store's pending order badge is amber (was blue for the shopper); a refunded order is amber on both sides.
- Home's "All products" has a heading. Section titles outside Home (admin, cart, payouts, related products) now use the heading font too.

# Design pass (2026-09-24)

Colours, type and button levels, across the shopper and store screens. The structure, features and wording don't change.

## 1. Colours

The orange is gone. Three colours carry meaning; everything else is navy, white and warm neutrals.

- **Purple** is anything a person taps: buttons, links, selected chips, the active tab, focus rings.
- **Amber** is heat: the flash sale (its card, countdown and "Add to cart"), discount badges, a running sale on the store's list, stars.
- **Green and red** keep success and error.

All colours are set in one place, `mobile/lib/core/theme/app_colors.dart`. Screens read them only through the theme.

### Palette

| Token | Light | Dark | Used for |
|---|---|---|---|
| Primary (`primary`, `accent`) | `#7B3FD4` | `#A57BE8` | buttons, links, selected chips, highlights |
| Pressed | `#6B2FC9` | `#9467DD` | a main button while held |
| Ink on primary | `#FFFFFF` | `#0F131C` | words on a purple button |
| Soft lavender (`selected`) | `#CCA3FF` | `#352B4D` | selected backgrounds, the active tab's pill (light) |
| Very soft tint (`accentSoft`) | `#F3ECFF` | `#221C33` | coupon tickets, icon tiles, sections with a hint of purple |
| Text | `#1C2536` navy | `#F2F5F8` | all main text and prices |
| Secondary text | `#55677D` | `#A2B0C0` | |
| Muted text (`textMuted`) | `#626D79` | `#8795A6` | a store's name on a card, crossed-out prices, dates, "Step 2 of 4", field hints |
| Page | `#FAF8F5` warm off-white | `#0F131C` deep navy | |
| Card | `#FFFFFF` | `#181E2A` | |
| Input fill, neutral tiles | `#F1EEE9` | `#131823` | |
| Hairline border | `#E8E3DC` | `#2A3242` | |
| Dark surface (`surfaceDark`) | `#1C2536` navy | `#222A3A` (rises above the page) | navigation bar, snack bar, the store's "What you owe" panel |
| On the dark surface (`onDarkAccent`) | `#CCA3FF` lavender | `#A57BE8` | the active tab's pill, a snack bar's action |
| Amber (`heat`) | `#F0A22E` | `#F5B04A` | flash sale, discount badges, countdowns, stars |
| Ink on amber (`onHeat`) | `#1C2536` | `#0F131C` | |
| Amber words (`warning`, "only a few left") | `#9A6208` | `#E8A33D` | amber's meaning as text |
| Green (success, delivery) | `#127346` | `#34C77B` | unchanged |
| Red (error, destructive) | `#B32D1C` | `#FF7A66` | unchanged |

### Dark mode, and why it isn't the light values darkened

- **The purple gets lighter** (`#A57BE8`). `#7B3FD4` is too dim on a dark page. White on the lighter purple is only 3.2:1, so dark-mode buttons carry **dark ink** (5.8:1).
- **The tints become dark purple surfaces.** Lavender becomes `#352B4D` and the soft tint `#221C33`. A light tint on a dark page would glare.
- **The navy stops being text.** Light-mode text is `#1C2536`. Dark mode's page is a separate, deeper navy (`#0F131C`), and its text is near-white.
- **The amber lifts** to `#F5B04A`, so it stays warm. In dark mode it can also be text (8.9:1 on a card).
- **The navigation bar rises** to `#222A3A`, above the page, as before. Its active pill is the purple itself there (4.5:1 against the bar).

### Contrast

Every pairing the app draws is checked with the WCAG formula in both modes, in `test/core/design_tokens_test.dart`. The rule is 4.5:1 for words and 3:1 for the active pill against the bar. Some values:

| Pair | Light | Dark |
|---|---|---|
| Words on a purple button | 6.0 | 5.8 |
| Purple link on the page | 5.7 | 5.8 |
| Navy on amber | 7.3 | 9.9 |
| Text on lavender / selected | 7.5 | 12.0 |
| Purple on the soft tint | 5.2 | 5.2 |
| Active tab: navy on its pill | 7.5 | 4.5 |

What the palette rules out, and why:
- **White on amber** (2.1:1) and **amber words on a light page** (2.0:1). Amber is always a fill with navy on it. Amber's meaning as text uses the darker `#9A6208`.
- **Purple or white on lavender** (2.9:1 and 2.0:1). Lavender always carries navy.
- **The purple on the navy bar** (2.6:1). That is why the active tab's pill is lavender in light mode, not the purple.

### What looks different

- Main buttons are purple instead of near-black. Outlined buttons, text buttons, "See all", "Change" and "Read more" are purple.
- The **flash sale** is built on amber: an amber outline, an amber "Add to cart" pill with navy words, an amber ring on the heart and an amber countdown. Its layout is unchanged. The store's "Flash sale until …" chip is amber too.
- **Discount badges** are amber with navy words (they were near-black).
- The **navigation bar** is navy with a lavender pill on the active tab (was near-black with a white pill). The cart count badge is lavender.
- **Stars** are amber (were orange).
- The store's **"What you owe this month"** panel is navy, a dark surface, instead of the button colour.
- The page is **warm off-white**, and the input fills and hairlines are warmed to match. The old cool grey read blue against the warm page.

### Readability problems found and fixed

These existed before the purple and were made worse or exposed by it:
- **Snack bars in dark mode.** White words on the dark-mode green, blue and red were 2.0 to 2.6:1. They now carry dark ink in dark mode (7.3 to 8.5:1).
- **"Added to cart" in dark mode.** White on the green was 2.0:1. It now has dark ink (8.5:1).
- **Words on purple fills** (the coupon "Copy" button, the chosen city chip, the store's coupon pill, avatar initials) were fixed white. They were unreadable on dark mode's lighter purple (3.2:1) and now follow the theme's ink.
- **Home's banner and the store's coupon stubs in dark mode.** White on the dark-mode tones was 2.5 to 3.2:1. In dark mode those gradients now start a third darker, so white is 4.7:1 or more on every tone.

## 2. Typography everywhere

The heading fonts were on Home only. Now one hierarchy is used on every screen, shopper and store, in both languages. It is set in `AppTypography` (`mobile/lib/core/theme/app_typography.dart`).

| Level | Size (English) | Font | Where |
|---|---|---|---|
| Screen title | 30 | DM Serif Display / Amiri Bold | a tab's title ("My cart", "Orders", "My products"), "Account", sign-in and sign-up steps, "Order placed" |
| Bar title | 20 | heading font | a pushed screen's title beside the back button; the store's name on its dashboard |
| Name title | 24 | heading font | a store's name on its page |
| Section | 21 | heading font | a section on a page ("Shop by category", "Description", "Needs you today"), an empty list's title |
| Section in a card or sheet | 18 | heading font | "Deliver to", "Order items", checkout's steps, every sheet's and dialog's title |
| Card titles, labels, body, prices | as before | IBM Plex Sans Arabic | |

- **Arabic headings are set 18% larger** than the English size. At the same size, Amiri draws smaller and lighter than DM Serif, so Arabic titles looked timid beside the English ones. Bold is Amiri's heaviest weight, so size is what is left to give them presence. The Cairo alternative is still one constant away (see "Fonts" above).
- **Numbers stay in the body font** even where they are a title: an order number, an invoice number, revenue, what is owed. A heading is words.
- **Prices:** the price style (navy, bold, tabular figures) is used wherever a price is shown. The store's product list printed its prices as small grey captions; they now use the price style. Struck-through original prices stay grey, since they are the old price.
- **Checked** at 411 px and at 320 px with the largest text size (1.4), in both languages and both modes, with the design-shots test.

### Readability problems found at 320 px and the largest text

- **The product name broke mid-word** ("Smartpho / ne") at the name size, because it shares its row with the quantity stepper. Until part 4 gives it its own line, it uses the section size.
- **The store's name on its dashboard** was cut to "N…" beside the switch and two buttons. It now shrinks to fit, like Home's greeting.
- **Already broken, not from this pass (BUGS.md 137):** the product page's seller card falls apart at this size, with "Sold by" one letter per line. Left for part 4, which rebuilds that card.

## 3. Button hierarchy

Three levels, set in `AppButton` (`mobile/lib/core/widgets/app_button.dart`) and the button themes:

| Level | Look | Use |
|---|---|---|
| Primary | solid purple, white words (dark ink in dark mode) | one per screen: the thing the person came to do |
| Secondary | purple outline and purple words on white | the other real actions |
| Tertiary | purple words only | quiet actions and links |
| Destructive | red: a filled bar, or red words when rare | only removing or cancelling |

- The old tonal "secondary" and the separate "outline" were two looks for one level; they are now one (`AppButtonVariant.secondary`). The variants are primary, secondary, text, danger and dangerText.
- **Product page:** "Buy now" is primary, "Add to cart" is secondary.
- **Cart:** "Proceed to checkout" is the one filled button. "Apply" (coupon) and "Save for later" are outlined; "Remove" stays red.
- **Home and cart coupons:** "Copy" is outlined. A rail of them sat on Home as filled buttons.
- **Addresses:** "Edit" and "Set as default" are outlined purple (they were blue and green fills); "Delete" stays red.
- **Language choice:** العربية and English are two equal answers, so neither is the one filled button. Both are outlined.
- **Store:** "Add product" is the product list's main action; "Restock" on a sold-out row and "Flash sale" are outlined. On the orders queue "Decline" cancels the order, so it is red words beside "Confirm".
- **Chips that can't be changed** (the store's own city in its delivery list) are grey with readable grey words. Material drew them purple with the words faded to about 2:1.

### "One per screen" means hierarchy, not counting (the user's decision)

- **The store's orders queue keeps a filled "Confirm" on every waiting order.** Confirming is that screen's whole job, and each row is its own unit of work. An outlined Confirm would make the merchant's main task look optional. The rule is that nothing competes with the main action, not that a screen has exactly one filled button.

## Also found in this pass

- **Muted text was too light to read** (found by the admin web session). `textMuted` was `#8A99AB`, 2.9:1 on white, and it carries words people read: the store under every product's name, crossed-out prices, dates, "Step 2 of 4", "No reviews", the "Ended" coupon badge. It is now `#626D79`, the value the admin web chose: 5.3:1 on white, 4.6:1 on a field. Dark mode's `#6E7C8C` was 3.9:1 on a card, and is now `#8795A6` (5.5:1). Field hints use it too, so they are a little darker; they are still grey against navy typed text.

- The product form's section titles ("The basics", "Price and stock") and the empty and error screens' titles were missed in part 2. They now use the heading font too.

# The new logo (2026-09-25)

The seven files in `logo/` were screenshot crops: the app icon 221 x 222
(not square, and a phone icon needs 1024), the lockups 312 to 426 px wide,
blurred, each with the page it was cut from baked in around it. None could
be used sharp, so **all seven were rebuilt**, matched to the files:

- **The mark** is SVG paths in `lib/core/widgets/saba_logo.dart`
  (`SabaMark`): a rounded square in #6B3FA0, the white bag drawn as an S
  with its keyhole, and the amber #F0A22E diamond. Traced from the icon;
  overlaid on it, the edges agree to about 1 px in 220.
- **The name** is live text, so it follows the app's language by itself:
  "Saba" in DM Serif Display, "سبأ" in IBM Plex Sans Arabic Bold, the two
  faces the lockups use. The mark stays on the left in both, as drawn.
- **Three tones**, as in the files: purple (purple square, white bag),
  white (white square, purple bag: on purple, and on a dark page, where
  a purple name is 2.5:1), navy (navy square, white bag, a pale diamond).
- `AppPalette.brand` is the logo's purple. The buttons keep #7B3FD4.

Where it is now:

| Place | Version |
|---|---|
| Android, iOS and web app icons, favicon | the mark, purple |
| Phone launch screen (Android 12+, iOS) | the mark, white, on purple |
| Splash screen | the white lockup on purple, in the app's language |
| Sign-in, phone step | the lockup: purple, white in dark mode |
| Language screen | the mark with both names |
| Home header | the mark, where the initial's circle was; signed out, "Saba" set as the logo sets it |
| A store with no logo of its own (store cards, cart, store page, the store's dashboard and account) | the mark |
| Invoice | the navy lockup; white in dark mode |

`tool/app_icons.py` draws every app icon from the same paths (Android's as
vectors). Change the paths and run it; `saba_logo_test.dart` fails if the
Android icon no longer matches them. The old logo is gone: the storefront
glyph in a purple tile, the "س" tile, the Android launch tile, Flutter's
own icons, and eight unused bag and store icon files.
The storefront glyph itself stays where it means "a store" (the store's
tab, its buttons), not Saba.

# Fixes before part 4 (2026-09-25)

- **Settings**: the lines between choices start at the words, not 50 px
  in where an icon would be; every option is in the text colour, the
  chosen one bold with its tick.
- **City on products**: a pin and the store's city, small and purple, on
  every product card (after the store's name) and on each cart line; not
  on flash-sale cards. On the product page it is a pill (part 4).
- **Cards tighter**: the crossed-out price sits beside the price instead
  of on a line every card kept empty for it.
- **Nothing centred but the logo and the step bar**: sign-in (the logo on
  top, the heading and words at the start), the number and code steps
  (from the top, not floating in the middle), the language screen, and the
  notes under buttons at checkout, in the cart and on the store's product
  form. Screens that are an icon and a message in the middle, and "Order
  placed", stay centred (the user's decision). Screen titles in the top
  bar stay centred between the back button and its balance.
- **Policy pages**: section headings in the heading serif with room above,
  15 px text at 1.7 line height, paragraphs apart, lines no wider than
  620 px, "Last updated" small and grey.
- **Greeting**: "Welcome to Saba" / "أهلاً بك في سبأ", right for a first
  visit and a return.
- **Rejected products**: "Needs you today" says how many Saba did not
  approve; the edit form opens with Saba's reason in a red note.
- **Store logo**: Store settings opens with the logo the store has; the
  dashboard and account tiles show it.

# Part 4: the product page (2026-09-25)

Nine blocks, each a white card with 18 px inside, a soft shadow and 12 px
between them, in this order:

1. **Pictures**: square, the full width, filling it (cover), dots on a
   small pill over the bottom; back, favourite and share over the top.
2. **Name and price**: the name in the name heading on its own line, the
   brand under it; the price at 30 px in navy, the original struck
   through beside it, the discount a small amber pill.
3. **Fact pills**: in stock (green) / only a few left (amber) / out of
   stock (red); the category; the store's city (purple); "Free delivery"
   or the fee to the shopper's city (only when the store goes there); the
   warranty, when there is one. A pill only for a fact that is there. The
   owner's preview leaves out stock, as it did.
4. **Options**: each option's name above its choices, the chosen value
   beside the name; colours as swatches in a row, no longer on the photo;
   the size guide link where there is one; "Please choose the product
   options first." until all are chosen; then the quantity.
5. **Description**: four lines, "Read more" only when there is more.
6. **Delivery**: green when the store comes to the shopper's city, with
   fee and time; red and plain when it does not; Saba's return rule.
7. **Seller**: logo (Saba's mark without one), name, rating, city; Message
   on its own line (BUGS 137).
8. **Related products**, the rail.
9. **Sticky bar**: total, Add to cart (secondary), Buy now (primary).

Nothing was added or taken away: the warranty and return rule moved from
the two tiles into a pill and the delivery block.
