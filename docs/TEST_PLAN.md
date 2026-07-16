# Test Plan

Run this on a new test project before importing the live product master.

## 1. Migration and provisioning

1. Create customer A using one phone number.
2. In Supabase Table Editor verify:
   - one `customers` row exists;
   - exactly two `orders` rows exist;
   - firms are Maitri and Niharika.
3. Registering the same phone again must not create a second customer.

## 2. Mandatory customer-isolation test

Use two separate browser profiles/incognito windows.

1. Register customer A and add/save one Maitri design.
2. Register customer B and add/save a different Maitri design.
3. While logged in as B, open browser DevTools Console and run queries using the page's `sb` client:

```js
await sb.from('customers').select('*')
await sb.from('orders').select('*')
await sb.from('order_items').select('*')
```

Expected: every returned row belongs only to B.

4. Copy customer A's order UUID from the admin dashboard.
5. As B, run:

```js
await sb.from('orders').select('*').eq('id', 'CUSTOMER_A_ORDER_UUID')
await sb.from('order_items').select('*').eq('order_id', 'CUSTOMER_A_ORDER_UUID')
```

Expected: empty arrays, not A's data.

6. As B, try a direct insert/update/delete on `order_items` and `orders`.
Expected: permission denied.

## 3. Concurrent save test

1. Log in as the same customer on two devices/tabs.
2. Load Maitri order version N in both.
3. Save tab 1.
4. Save tab 2 without reloading.
Expected: tab 2 receives `ORDER_VERSION_CONFLICT` and reloads the saved server copy rather than overwriting it.

## 4. Idempotency test

From DevTools, repeat the same `save_my_order` RPC twice with the exact same request UUID.
Expected: the second response equals the first and the order version increments only once.

## 5. Product sync

1. Add three designs in ProductMaster and run full snapshot.
2. Confirm all three appear in `designs`; their base URLs appear only in `design_assets`.
3. Delete one Sheet row and wait for the scheduled snapshot or run it manually.
Expected: the missing design becomes `active=false`.
4. Edit a design's category and verify it changes in Supabase.

## 6. Barcode mapping

1. Map a new barcode and scan it in the customer app.
2. Try scanning it under the wrong firm.
Expected: a clear firm mismatch message.
3. Remap the barcode and verify a `barcode_mapping_log` row is created.
4. Deactivate it and confirm customer lookup stops working.

## 7. Images

1. Open Network tools while loading a design.
2. Verify the browser calls `image-proxy`, not the base ImageKit URL.
3. Inspect customer table responses and confirm no `base_image_url` is present.
4. Generate a PDF and confirm thumbnails are low-resolution but identifiable.

## 8. Dashboard and password reset

1. A normal customer session calling `admin-api` must receive `ADMIN_REQUIRED`.
2. Admin login must show both customers and both firms.
3. Filter and export to Excel.
4. Reset customer A's password; old password must stop working and the temporary password must work.
5. Disable customer A; saving must fail with `CUSTOMER_ACCESS_DISABLED`.

## 9. Camera/device test

Test on the actual phones and browsers used on the exhibition floor:

- HTTPS GitHub Pages link.
- Rear-camera permission.
- Barcode focus distance and lighting.
- Manual barcode fallback.
- Repeated scans.
- Save on slow mobile data/Wi-Fi.
- PDF download on Android Chrome and iPhone Safari.
