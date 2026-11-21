# Kadhar Bhavan Billing

A mobile-first billing app starter for multiple shops and multiple staff accounts per shop. Phase 2 (inventory, stock alerts and reports) is deliberately out of scope.

The billing screen follows the supplied Stitch export's textile POS direction: heritage terracotta accents, warm paper-like surfaces, Tamil-first identity, dense product tiles, and a split catalog/cart layout. GST, inventory, returns and reports shown in some Stitch screens are intentionally excluded from this first scope.

## What works in this starter

- Tamil / English interface toggle.
- Add and manage shop items with English and optional Tamil names.
- Create bills with quantities and a bill-level discount.
- Save bill history locally in preview mode or in the shared shop database when connected; print a Tamil-capable receipt.
- Mobile layout and an installable PWA shell.
- Individual staff sign-in in Supabase mode; a preview staff switcher when cloud settings are empty.
- One business with multiple shops, many-to-many user/shop membership, and an active-shop switcher.
- Database-enforced shop isolation, shared per-shop catalog/history, and server-assigned bill numbers in Supabase mode.
- Owner-only shop registration and UPI setup; staff UPI changes require owner approval. UPI payment QR is included on printed receipts when the shop has an approved UPI ID.
- Bills saved offline are queued per signed-in user and shop, then synced with idempotent bill IDs when the connection returns.
- Receipt PDF generation with UPI QR and WhatsApp sharing through the device share sheet. If file sharing is unavailable, the PDF downloads and WhatsApp opens so it can be attached manually.

## Important: local preview vs. shared shop use

Without Supabase configured, this build saves data in the current browser only and the staff switcher is a preview. To test real shared use, configure Supabase in `config.js`, run `supabase/schema.sql`, create a business and its shops, create individual Auth users, and add one `shop_members` row for each user/shop assignment. A user assigned only to Shop B cannot read or write Shop A data; adding a user to multiple shops grants access to each assigned shop. The active-shop selector only switches between shops already assigned to that signed-in user. See `supabase/SETUP.md` for the sequence.

An owner can use the registration screen to create the first business and shop. If email confirmation is enabled in Supabase, confirm the message and sign in again in the same browser to finish shop setup. The app keeps the pending shop details locally until setup completes; it does not store the password. Staff accounts and their shop memberships are provisioned by an owner or project administrator. An existing owner can register additional shops in the app. Staff UPI changes stay pending until an owner approves them.

The app needs a successful sign-in and first shop sync while online. It can then save bills offline and sync them after reconnecting; authentication, item changes, and shop setup still need internet. GST has been left out of this version.

## Run at the lowest cost

For a single shop and three staff accounts, the app itself has no per-user, bill, QR, or WhatsApp fee. Use Cloudflare Pages free hosting (including its `pages.dev` address) and Supabase Free to start: estimated platform cost is **$0/month**. Keep cloud sign-in on HTTPS; the app permits plain HTTP only on `localhost` for development. `_headers` supplies browser security headers on Cloudflare Pages.

Supabase Free is suitable for testing and low-risk trials, but may pause a low-activity project after seven days and does not include downloadable database backups. For daily shop use, Supabase Pro is currently **$25/month** for the first project, including daily backups retained for seven days and no inactivity pause. Cloudflare Pages can remain free; a custom domain is optional and adds its annual registration cost. Prices are USD before any applicable taxes, currency conversion, or usage add-ons. See Supabase’s [current pricing](https://supabase.com/pricing) and [free project pausing rules](https://supabase.com/docs/guides/platform/free-project-pausing).

## Run the preview

1. Unzip the project.
2. Open a terminal in the project folder.
3. Run `python3 -m http.server 5173`.
4. Open `http://localhost:5173` in a browser.

To activate shared mode, put the project's URL and publishable key in `config.js` first. Do not use a Supabase secret/service-role key in browser code. The app uses individual email/password sign-in. Keep any secret/service-role key out of `config.js`.

In local preview mode, add items, create bills, switch to Tamil, and print receipts; data stays in that browser's local storage.

## Before using it for real sales

- Set up the business, shops, UPI IDs, and individual Supabase Auth users; test allowed and denied shop access on separate phones.
- Test offline bill queueing and reconnect sync on the actual phones, including duplicate/retry and storage-clearing cases.
- Test the UPI QR with the shop’s payment app and confirm the merchant name and bill amount before live use.
- Test Tamil PDF receipt text and UPI QR payment details with the actual payment apps and phones.
- Back up and export bills before relying on the app for accounting records.

## Current limitations

- In local preview mode there is no shared data. Cloud mode requires the Supabase project configuration and membership setup. Shop isolation is enforced by Supabase row-level security, not by the browser selector.
- Offline mode needs a successful online sign-in and shop sync first. Pending bills stay on the same device/account until they sync; clearing browser storage can remove them. Catalog and bill history are cached per user and shop.
- The sample names and prices are demonstration data; replace them with the shop catalog.
- PDF receipts are generated on the device. Phones that support file sharing can attach the PDF from the share sheet; on other browsers the PDF downloads and the user attaches it in WhatsApp. Printing remains available through the browser print dialog. The QR library is pinned with Subresource Integrity and cached after the first online load; without it, the receipt shows the UPI ID as text.
- No stock tracking by design; that is Phase 2.
