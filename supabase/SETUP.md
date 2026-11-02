# Configure multiple shops and staff accounts

This checklist is for a test Supabase project. The schema supports one business with multiple shops and users assigned to one or more shops. Keep the project URL and publishable key in `config.js`; never put a secret/service-role key in browser code.

1. Create a Supabase project. In **Project Settings → API Keys**, copy the project URL and publishable key into `config.js`.
2. Open **SQL Editor** and run `schema.sql`.
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
4. In **Authentication → Users**, create three test users with separate email/password logins. Record each user's UUID. Keep these credentials private and share them with the intended staff securely.
5. Add a membership row for each user/shop assignment. Here the owner can access both shops; Staff 1 and Staff 2 each access only one. Replace the example values with the returned UUIDs:

   ```sql
   insert into public.shop_members (shop_id, user_id, display_name, role) values
     ('MAIN_SHOP_UUID', 'OWNER_USER_UUID', 'Thangavel', 'owner'),
     ('MAIN_SHOP_UUID', 'STAFF_1_USER_UUID', 'Staff 1', 'staff'),
     ('MARKET_SHOP_UUID', 'OWNER_USER_UUID', 'Thangavel', 'owner'),
     ('MARKET_SHOP_UUID', 'STAFF_2_USER_UUID', 'Staff 2', 'staff');
   ```

6. Start the app over HTTP for local testing (use HTTPS when hosted). Each signed-in user sees only shops listed for their user UUID in `shop_members`. Owners can be assigned to every shop; staff can be assigned only to the shop(s) they work in. The selector switches among those allowed shops.
7. Verify isolation with two test users: assign one only to Main shop and one only to Market Road shop. Add an item in Main shop. The Market Road user must not see it. Using that user’s signed-in session, a direct REST request for `items?shop_id=eq.MAIN_SHOP_UUID` should return no rows; attempting to insert/update with that shop UUID must be rejected by RLS. Do the reverse check as well.
8. Verify shared use by signing into the same shop on separate browsers or phones, adding an item on one, and confirming it appears on the others. Create a bill and check that it appears in that shop’s history.
9. Verify UPI ownership: as a staff user submit a new UPI ID request, then confirm the current ID and payment QR remain unchanged. Sign in as owner and approve it; verify the receipt now uses the approved ID. Repeat and reject a request. Confirm staff cannot register shops or call the owner-only UPI RPCs.
10. Verify offline billing: sign in and load the shop online once, disconnect the network, create a bill, and confirm it appears with an `OFF-` number and pending status. Reconnect and confirm it syncs once with a server bill number, including after a refresh/retry.
11. Test UPI QR payment using the shop’s actual payment app and confirm merchant, amount, and note before any real transaction. Test PDF and WhatsApp sharing on all three phones.
12. Before going live, remove test records or create a fresh production project and accounts.

## What shared mode does today

- Individual Supabase email/password sign-in.
- Shop-membership check on sign-in.
- Shared item catalog and bill history, refreshed every 20 seconds and on browser focus.
- Database-enforced shop isolation on business, shop, membership, catalog, and bill data. A user can access only shops with an explicit membership row; filtering in the app is not the security boundary.
- A user assigned to multiple shops can switch among those memberships. Bill numbers are allocated independently for each shop.
- Atomic, idempotent bill creation with a server-allocated unique bill number, including retry-safe offline sync.
- Device-generated PDF receipts that include a bill-specific UPI payment QR when the shop has an approved UPI ID. The share sheet sends the file where supported; otherwise download it and attach it in WhatsApp.
- Per-user/per-shop offline catalog and bill-history cache; unsynced bills stay queued on the device/account.
- Owner-only shop registration with required UPI ID; staff UPI changes go to an owner approval queue.

The first business/shop and owner membership are bootstrapped by a project administrator in SQL. After that, only an owner can register another shop in the app, and the form requires its UPI ID. A shop user can request an UPI change, but the live UPI ID changes only after an owner approves it. Owners can set or update their shop UPI directly. Staff shop memberships are still provisioned by a project administrator in SQL. For offline tests, sign in and load each shop online once on the device first. Turn off the network, save a bill, reconnect, and verify it syncs once with the server bill number. The generated PDF includes the approved shop UPI QR. Use the phone share sheet to send it via WhatsApp; unsupported browsers download the PDF for manual attachment.
