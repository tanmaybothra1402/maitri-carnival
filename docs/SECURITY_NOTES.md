# Security Notes

## Customer isolation

- Every customer profile uses the same UUID as its Supabase Auth user.
- The database creates both firm orders during registration.
- RLS permits customers to select only their own customer and order rows.
- Direct browser writes to orders and order items are not granted.
- `save_my_order` obtains `auth.uid()`, locks that user's firm order, validates products, replaces the cart atomically and increments the version.

## Admin isolation

- Admins use normal email/password Supabase Auth accounts.
- Their `app_metadata.role` must equal `admin`.
- `admin-api` verifies the Auth access token server-side before using service-role access.
- An unguessable dashboard filename is only an extra obscurity layer; authentication remains mandatory.

## Images

- Base ImageKit URLs live only in `design_assets`, which has no customer grant or RLS policy.
- The browser asks `image-proxy` for a design number and approved variant.
- The proxy fetches a transformed image server-side and streams only the bytes back.
- CSS right-click, drag and long-press blocking is a deterrent, not perfect copy prevention. A user can always photograph or screenshot a displayed image.
- For stronger protection, configure ImageKit named transformations, private files or signed delivery and set `IMAGEKIT_PRIVATE_KEY`.

## Secrets

Never place these in `web/*.html` or GitHub:

- Supabase service-role/secret key
- ImageKit private key
- `SHEET_SYNC_SECRET`
- Admin passwords

The Supabase URL and publishable/anon key are intentionally public; RLS is the protection layer.
