# Direct Product Image Patch

This patch changes the product-image flow to:

`ProductMaster.ImageURL → designs.image_url → website <img> → PDF thumbnail`

It removes the browser dependency on the `image-proxy` Edge Function. The Google Sheet continues to use the existing `ImageURL` header.

Apply the patch over the repository root, push the new migration, redeploy `admin-api`, then remove the unused `image-proxy` function and ImageKit transformation secrets.
