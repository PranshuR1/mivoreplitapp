# Mivo Spot packaging

A flat **Spot Card** in a kraft envelope. The sticker(s) ride on the card's front, so the card is also the first-tap surface: the customer taps the sticker where it sits, then peels it off and places it.

## Why flat, not a box

USPS prices (Notice 123, effective 2026-10-04, confirmed on pe.usps.com 2026-10-23): a 1 oz letter is $0.82 stamped or $0.78 metered ($1.11 / $1.07 at 2 oz), a 1 oz large envelope (flat) is $1.69, and the Pricing Model v2 "Shipping" tab has Ground Advantage at $7.33+. A card and envelope stay a letter (about 0.4 oz, well under the 1 oz tier, my estimate: weigh a real one), so postage is $0.87 below a flat and about $6.50 below a parcel. A box would add cost and weight and push every order into parcel rates.

Per order, packaging only: card $0.21 + envelope $0.08 + seal sticker (get a quote, roughly $0.05 to $0.10 at 500). Card and envelope prices are the Launch Budget placeholders.

## First batch by hand (home printer)

`print/home-print.pdf` (one sticker) and `print/home-print-3pack.pdf` (three stickers, same back): US Letter landscape, two pages each. Page 1 is four identical fronts, page 2 four identical backs. Light design on white paper, nothing within 0.5 in of the sheet edge (except the 3-pack rings, 0.32 in), so a home printer should not clip it. Cut along the dashed centre cross and you get four 5.5 x 4.25 in cards, which fit a kraft A6 envelope (4 3/4 x 6 1/2 in). A #6 3/4 envelope is too short for them.

1. Print on cardstock (65 to 80 lb unless your printer takes heavier), Letter, landscape, **Actual size / 100%** (not "Fit to page"), best quality, two-sided.
2. Test the flip on one sheet first. If the backs come out upside down, switch long-edge and short-edge in the duplex setting. The four cards are identical, so left-right order doesn't matter.
3. Cut on the dashed lines: paper trimmer, or ruler and craft knife.
4. Press a programmed sticker inside the solid amber ring (the ring is a little larger than the 25 mm sticker).
5. Peel-test one: if the sticker tears the card face, use glossy cardstock.

The dark print-shop version (`card-1up.pdf` and the rest) stays for a later bulk run.

### Clear cover over each sticker

Buy clear round labels, 1.5 in (38 mm), permanent adhesive, one per sticker: LabelValue sells a roll of 500 for $9.60 with free US shipping (about $0.02 each, checked 2026-10-23). 1.25 in clear labels aren't sold as cheap stock, which is why the cover is 1.5 in. The rings on the home-print cards are sized for the covered sticker, so the 25 mm sticker sits inside a 1.5 in clear disc. On the 3-pack card the outer rings sit 0.32 in from the sheet edge, so check your printer's minimum margin. See `proofs/cover-diagram.png`: the cover's rim sticks to the surface and holds the sticker's edge down, which is where adhesive stickers start to lift.

1. Leave the sticker on its backing sheet. Peel a clear label off its own backing and lay it sticky side down over the sticker, centred (about 6 mm of rim all round). Press out bubbles.
2. Lift the sticker and cover off the backing together.
3. Press the pair inside the ring on the card.

Test one first: if the sticker stays behind on the backing when you lift, press harder in the middle, or try a different clear label. Also tap a covered sticker with an iPhone to confirm it still reads. A clear film this thin should not matter, but I haven't tested it.

## Files

| File | What | Send to |
| --- | --- | --- |
| `print/card-1up.pdf` | 6 x 4 in card, p1 front, p2 back, one sticker | Card printer |
| `print/card-3up.pdf` | Same, three sticker positions (3-pack and Kit) | Card printer |
| `print/seal.pdf` | 2 in round envelope seal, dark | Sticker printer (die-cut round) |
| `print/sticker-25mm.pdf` | Mivo-printed sticker face, only if TimesKey (or another supplier) does custom print | Tag supplier |
| `proofs/*.png` | Review images with trim (red) and safe (blue) guides, sticker shown in place | You |

Cards carry no per-unit data. The ID lives only in the tag, so there is nothing to print per card and no manual-entry path (see `Mivo/Spots/README.md`).

## The stickers (Amazon B09NXXTXHL, read 2026-10-22)

First sticker order, decided 2026-10-23: the Amazon 10-pack, used for tap, cover and peel tests. If it passes, the second order is Tagstand's 25-pack ($12.50, genuine NXP, 3M adhesive). Details are on the Shopping List tab of the Pricing Model v2 Sheet.

TimesKey NTAG213, 25 mm round, white PET, 0.2 mm thick, 144 bytes, sold in 10 to 1000 packs ($0.80 each at 10). The listing says "not for metal" and "iPhone XS and above", which the card repeats. Three things to know:

- **They are blank white.** The proofs show plain white discs. The Mivo-branded face (`print/sticker-25mm.pdf`) only applies if the seller prints them; the listing says they welcome customization, so ask for a quote on the first real run. Until then the card carries the branding and the stuck-down sticker has none. Set `STICKER_PRINTED = True` to mock the printed face.
- **Reviews are mixed on function.** 9% are 1-star and the summary mentions tags that won't read. Read-test every tag while programming it in Admin, and treat any that fail as a replacement.
- **Adhesive isn't stated.** Test how it peels off the coated card (step 3 below) before ordering cards.

The Pricing Model v2 Landed Cost tab assumed GoToTags or Shenzhen printed tags; Amazon is a third source at retail prices. Update the tab if you stay on it.

## Print spec

- **Card:** 4 x 6 in trim, 0.125 in bleed built into the PDF (page 6.25 x 4.25 in). 16 pt (about 350 gsm) with a silk or gloss coat on the front, so the permanent-adhesive sticker lifts off cleanly. Full-bleed dark front, cream back.
- **Envelope:** stock kraft A6 (4 3/4 x 6 1/2 in), sealed with the round seal. No custom envelope print at launch.
- **Colors:** supplied as RGB. Brand values: dark #161008, cream #FAF3E8, amber #D4872A, light amber #E29A50, ink #3D2313, body #6E5238. Ask for a proof of the dark front, which is the color most likely to shift in CMYK.
- **No metallic, foil or spot-metal ink** on the sticker or on the card behind it: it detunes the NFC antenna.
- **Sticker size:** `STICKER_MM = 25` in `build.py`. The placement rings are sized to it; change the number and rerun for another size.
- **Fonts:** Instrument Serif and Inter, embedded. Inter comes out as Type 3 because Chrome embeds variable fonts that way. If a printer's preflight rejects it, switch to static Inter files.
- **Logo:** keyed from the 1024 px PNG on the website (`make_logo.py`). Replace with the original vector before a large run.

## Before you order

1. Order about 25 cards as a digital proof, not 500.
2. Stick a real sticker on a card, tap it with an iPhone: it should open the claim flow with the sticker on the card.
3. Peel it off the coated front: the card should not tear.
4. Pack one in the envelope, weigh it, and take it to a post office: it should price as a letter with no rigid or lumpy surcharge ($0.49 in the Shipping tab). If it fails, ship as a flat ($1.69 / $1.98) and keep the design.
5. Stick one on a desk, a bedside table and a car dash, then on bare metal, to confirm the "not for bare metal" line.

## Pack-out

Sticker off its liner onto the ring, in CSV order, so the batch stays traceable. Card in envelope, seal on the flap, postage on the front.

## Claims on the card

- "iPhone XS or later on iOS 17": XS is the first iPhone with background tag reading (Tag Spec tab) and the app's deployment target is iOS 17.0.
- "Tap the banner that appears": iOS shows a banner after a background tag read; the app's "Skip the banner" Shortcuts steps remove it.
- "Not for bare metal": standard stickers fail on metal (Tag Spec tab).
- "No Mivo yet? The tap opens a page that links to the App Store": that is the `/s/<ID>` fallback page on usemivo.app.
- Nothing on the card mentions price, Plus or a subscription.

Rebuild after any edit: `python3 make_logo.py` once, then `python3 build.py`. Nothing here is committed to git.
