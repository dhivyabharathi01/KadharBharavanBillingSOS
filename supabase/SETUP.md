# Configure multiple shops and staff accounts

This checklist is for a test Supabase project. The schema supports one business with multiple shops and users assigned to one or more shops. Keep the project URL and publishable key in `config.js`; never put a secret/service-role key in browser code.

1. Create a Supabase project. In **Project Settings → API Keys**, copy the project URL and publishable key into `config.js`.
2. Open **SQL Editor** and run `schema.sql`. For an existing installation, run `shop-owner-controls.sql` instead to restrict catalog edits to owners and enable owner-managed staff assignment.
3. Create the business in SQL Editor:

   ```sql
   insert into public.businesses (name) values ('Kadhar Bhavan') returning id;
   ```

   Copy the business UUID, then create each shop under it:

   ```sql
   insert into public.shops (business_id, name, upi_id) values
     ('BUSINESS_UUID', 'Main shop', 'mainshop@bank'),
     ('BUSINESS_UUID', 'Market Road shop', 'marketshop@bank')
   returning id, name, upi_id;
   ```

   Enter each shop’s UPI ID here; the app uses it to create a bill amount QR. Copy each returned shop UUID.
4. Configure email delivery in **Authentication → SMTP Settings** and set the app URL under **Authentication → URL Configuration** so staff invitation links return to the hosted app. Create the first owner account through the app registration or **Authentication → Users**, and record its user UUID for the membership setup below.
5. Add the owner membership(s) in SQL Editor. Replace the example values with the returned UUIDs:

   ```sql
   insert into public.shop_members (shop_id, user_id, display_name, role) values
     ('MAIN_SHOP_UUID', 'OWNER_USER_UUID', 'Thangavel', 'owner'),
     ('MARKET_SHOP_UUID', 'OWNER_USER_UUID', 'Thangavel', 'owner');
   ```

   Link the project if this checkout is not already linked, then deploy the staff invitation function from the repository root:

   ```sh
   supabase link ztxbygqqtibgnsepjmzf
   supabase functions deploy invite-shop-staff
   ```

   Supabase provides the function's URL, anon, and service-role environment variables. Never copy the service-role key into `config.js` or the browser. The shop owner can then use **Shop setup → Staff access** to enter a name and email. The app invites a new user by email and assigns the account to the current shop; an existing account can be assigned directly. The staff member sets their own password through the invitation and signs in with that email. Each signed-in user sees only shops listed for their user UUID in `shop_members`.
   To enable private bill PDF links, run `bill-pdf-storage.sql` in the SQL Editor. Deploy the cleanup function and set a random cleanup secret:

   ```sh
   supabase functions deploy cleanup-bill-receipts --no-verify-jwt
   supabase secrets set BILL_RECEIPT_CLEANUP_SECRET=YOUR_RANDOM_SECRET
   ```

   In `schedule-bill-receipt-cleanup.sql`, replace the cleanup-secret placeholder with the same secret, then run that SQL once in the SQL Editor. The project URL and publishable key are prefilled for this project. Do not commit the filled-in SQL or share the cleanup secret. The daily job removes PDFs older than 14 days; WhatsApp links expire after 7 days. Bill records remain in the database. The cleanup function uses the service-role key only on the server and checks the separate cleanup secret.
6. Start the app over HTTP for local testing (use HTTPS when hosted). The shop selector switches among shops assigned to the signed-in user. Staff can create bills and view the item catalog; catalog changes and direct UPI updates are owner-only. Staff UPI requests remain subject to owner approval.
7. Verify isolation with two test users: assign one only to Main shop and one only to Market Road shop. Add an item in Main shop. The Market Road user must not see it. Using that user’s signed-in session, a direct REST request for `items?shop_id=eq.MAIN_SHOP_UUID` should return no rows; attempting to insert/update with that shop UUID must be rejected by RLS. Also confirm a staff member cannot change an assigned shop's catalog or UPI directly, but can create a bill.
8. Verify shared use by signing into the same shop on separate browsers or phones, adding an item on one, and confirming it appears on the others. Create a bill and check that it appears in that shop’s history.
9. Verify UPI ownership: as a staff user submit a new UPI ID request, then confirm the current ID and payment QR remain unchanged. Sign in as owner and approve it; verify the receipt now uses the approved ID. Repeat and reject a request. Confirm staff cannot register shops or call the owner-only UPI RPCs.
10. Verify offline billing: sign in and load the shop online once, disconnect the network, create a bill, and confirm it appears with an `OFF-` number and pending status. Reconnect and confirm it syncs once with a server bill number, including after a refresh/retry.
11. Test UPI QR payment using the shop’s actual payment app and confirm merchant, amount, and note before any real transaction. Test PDF and WhatsApp sharing on all three phones.
12. Before going live, remove test records or create a fresh production project and accounts.

## What shared mode does today

- Individual Supabase email/password sign-in.
- Shop-membership check on sign-in.
- Shared item catalog and bill history, refreshed every 60 seconds while visible and on browser focus.
- Database-enforced shop isolation on business, shop, membership, catalog, and bill data. A user can access only shops with an explicit membership row; filtering in the app is not the security boundary.
- A user assigned to multiple shops can switch among those memberships. Bill numbers are allocated independently for each shop.
- Atomic, idempotent bill creation with a server-allocated unique bill number, including retry-safe offline sync.
- Device-generated PDF receipts that include a bill-specific UPI payment QR when the shop has an approved UPI ID. WhatsApp messages include a **Pay now** HTTPS link that attempts to open a compatible mobile UPI app and provides a fallback button. Supabase mode uploads PDFs to a private per-shop bucket, sends 7-day signed links, and deletes files after 14 days; local preview shares or downloads the PDF directly.
- Per-user/per-shop offline catalog and bill-history cache; unsynced bills stay queued on the device/account.
- Owner-only shop registration with required UPI ID; owners can invite new staff logins or assign existing Auth users through the `invite-shop-staff` Edge Function; staff UPI changes go to an owner approval queue.

The first business/shop and owner membership are bootstrapped by a project administrator in SQL. After that, only an owner can register another shop in the app, and the form requires its UPI ID. A shop user can request an UPI change, but the live UPI ID changes only after an owner approves it. Owners can set or update their shop UPI directly and add existing Auth accounts as staff. Staff catalog changes and direct UPI updates are rejected by database policies. For offline tests, sign in and load each shop online once on the device first. Turn off the network, save a bill, reconnect, and verify it syncs once with the server bill number. The generated PDF includes the approved shop UPI QR. Use the phone share sheet to send it via WhatsApp; unsupported browsers download the PDF for manual attachment.
