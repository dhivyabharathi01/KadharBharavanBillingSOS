# Kadhar Bhavan Billing

A mobile-first billing app starter for multiple shops and multiple staff accounts per shop. Phase 2 (inventory, stock alerts and reports) is deliberately out of scope.

The billing screen follows the supplied Stitch export's textile POS direction: heritage terracotta accents, warm paper-like surfaces, Tamil-first identity, dense product tiles, and a split catalog/cart layout. GST, inventory, returns and reports shown in some Stitch screens are intentionally excluded from this first scope.

## What works in this starter

- Tamil-first interface with a saved Tamil / English toggle across billing, catalog, history and shop setup.
- Add and manage shop items with English and optional Tamil names.
- Create bills with quantities and a bill-level discount.
- Show the five most recently used catalog items on the billing screen; search to find any other item.
- Save bill history locally in preview mode or in the shared shop database when connected; print a Tamil-capable receipt.
- Mobile layout and an installable PWA shell.
- Individual staff sign-in in Supabase mode; a preview staff switcher when cloud settings are empty.
- One business with multiple shops, many-to-many user/shop membership, and an active-shop switcher.
- Database-enforced shop isolation, shared per-shop catalog/history, and server-assigned bill numbers in Supabase mode.
- Owner/admin-only shop profile and catalog changes, and direct UPI updates; staff UPI changes require owner approval. Owners can update shop name, address, and phone from **Shop setup → Shop details**, create staff logins by email invitation, or assign an existing account. UPI payment QR is included on printed receipts when the shop has an approved UPI ID.
- Bills saved offline are queued per signed-in user and shop, then synced with idempotent bill IDs when the connection returns.
- Receipt PDFs include a bill-specific UPI QR. In Supabase mode, WhatsApp sharing uploads the PDF to a private per-shop bucket and uses short, secure redirect links for the PDF and UPI payment page; links expire after 7 days, while a scheduled cleanup deletes stored PDFs after 14 days. Local preview continues to share or download the PDF directly.
- Mark **Collected in cash** on the billing screen when cash has been received. The bill stores this payment method, and its receipt/WhatsApp message states the cash amount without UPI links or QR. Other bills retain the bill-specific UPI payment link.
- When a bill has a customer number, WhatsApp opens with the receipt summary and short payment/PDF links addressed to that number. WhatsApp messages are plain text, so the short URLs remain visible rather than being hidden behind custom link labels. For unpaid bills, the payment page attempts to open a compatible UPI app on mobile and provides a fallback button; the customer must confirm payment in the app. Bill history offers the same option. Review the message and tap Send in WhatsApp. Bills without a customer number can share a link or print the receipt.

## Important: local preview vs. shared shop use

Without Supabase configured, this build saves data in the current browser only and the staff switcher is a preview. To test real shared use, configure Supabase in `config.js`, run `supabase/schema.sql`, create a business and its shops, and create the owner Auth account. Deploy `supabase/functions/invite-shop-staff` to invite staff from **Shop setup → Staff access**; configure Supabase Auth email delivery and the app redirect URL first. New staff receive an invitation to set their own password, while existing accounts can also be assigned. Edge Functions use Supabase's server-side service-role environment and never expose that key in browser code. Staff can create bills and view the catalog; only the shop owner can update shop details, add/edit/remove catalog items, or directly update the UPI ID. Staff UPI changes still require owner approval. For existing projects, run `supabase/shop-owner-controls.sql` and `supabase/update-shop-profile.sql` in the SQL Editor. See `supabase/SETUP.md` for the sequence.

An owner can use the registration screen to create the first business and shop. If email confirmation is enabled in Supabase, confirm the message and sign in again in the same browser to finish shop setup. The app keeps the pending shop details locally until setup completes; it does not store the password. Staff accounts can be invited by email from Shop setup after deploying the `invite-shop-staff` Edge Function. An existing owner can register additional shops in the app. Staff UPI changes stay pending until an owner approves them.

After signing in, shop users can choose bilingual textile and devotional item presets from **Shop setup → Item catalog**, **Items → Choose from default list**, or **Add new item → Choose from default list**. The single-item flow fills the item form so its price can be entered before saving; bulk selection adds presets at ₹0. The setup tab also lists current shop items with an **Edit** action. Set each item's price before billing.

For an existing Supabase project, run [`supabase/fix-bill-id.sql`](./supabase/fix-bill-id.sql) in the Supabase SQL Editor before creating bills. It updates the bill RPC and adds payment-method storage; existing bills default to UPI. Run [`supabase/update-shop-profile.sql`](./supabase/update-shop-profile.sql) to enable owner-managed shop profile edits. To enable secure short bill links, run [`supabase/bill-pdf-storage.sql`](./supabase/bill-pdf-storage.sql), deploy `bill-receipt-short-link` with JWT verification disabled, and set the `BILLING_APP_ORIGIN` function secret to `https://kadharbharavanbillingsos.divyabharathithangavel.workers.dev`. Redeploy `cleanup-bill-receipts` so its scheduled job also removes expired link records. If you see `null value in column "id" of relation "bills" violates not-null constraint`, the deployed bill RPC is outdated; running the bill migration replaces it without requiring the full schema to be rerun. Reload the hosted app after the migrations complete.

The app needs a successful sign-in and first shop sync while online. It can then save bills offline and sync them after reconnecting; authentication, item changes, and shop setup still need internet. GST has been left out of this version.

## Run at the lowest cost

For a single shop and three staff accounts, the app itself has no per-user, bill, QR, or WhatsApp fee. Use Cloudflare Pages free hosting (including its `pages.dev` address) and Supabase Free to start: estimated platform cost is **$0/month**. Keep cloud sign-in on HTTPS; the app permits plain HTTP only on `localhost` for development. `_headers` supplies browser security headers on Cloudflare Pages.

Supabase Free is suitable for testing and low-risk trials, but may pause a low-activity project after seven days and does not include downloadable database backups. For daily shop use, Supabase Pro is currently **$25/month** for the first project, including daily backups retained for seven days and no inactivity pause. Cloudflare Pages can remain free; a custom domain is optional and adds its annual registration cost. Prices are USD before any applicable taxes, currency conversion, or usage add-ons. See Supabase’s [current pricing](https://supabase.com/pricing) and [free project pausing rules](https://supabase.com/docs/guides/platform/free-project-pausing).

Supabase Free currently includes 1 GB of file storage and 5 GB of egress. Bill PDFs are removed after 14 days; at an average of 250 KB each, 1 GB holds about 4,000 PDFs at once. Actual usage depends on receipt size and downloads, so monitor the project’s Storage and Egress usage.

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
- PDF receipts are generated on the device. In Supabase mode, sharing stores the PDF privately for up to 14 days and sends a short redirect link that expires in 7 days; the link opens or downloads the PDF rather than attaching it as a WhatsApp document. Local preview can use the device share sheet or download the PDF. Printing remains available through the browser print dialog. The UPI QR is bill-specific because it includes the bill amount.
- No stock tracking by design; that is Phase 2.
