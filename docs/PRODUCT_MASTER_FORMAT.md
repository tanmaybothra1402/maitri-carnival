# Product Master Format

Use the sheet name **ProductMaster** and keep these eight columns in this exact order.

| Column | Required | Rules |
|---|---:|---|
| DesignNo | Yes | Unique across both firms. Do not reuse a design number. |
| Firm | Yes | `Maitri`, `Niharika`, or `Both`. |
| ImageURL | Recommended | Base ImageKit URL only; no `tr`, `ik-s`, or `ik-t` parameters. |
| Category | No | Display and dashboard grouping. |
| Fabric | No | Display and dashboard grouping. |
| Color | No | Display and dashboard grouping. |
| Description | No | Short customer-facing identification text. |
| Active | Yes | `TRUE` or `FALSE`. Inactive designs cannot be newly scanned or saved. |

Example:

```csv
DesignNo,Firm,ImageURL,Category,Fabric,Color,Description,Active
MT-1001,Maitri,https://ik.imagekit.io/YOUR_ID/exhibition/MT-1001.jpg,Kurta Set,Cotton,Blue,Printed three-piece set,TRUE
NH-2001,Niharika,https://ik.imagekit.io/YOUR_ID/exhibition/NH-2001.jpg,Suit Set,Viscose,Pink,Embroidered suit set,TRUE
SH-3001,Both,https://ik.imagekit.io/YOUR_ID/exhibition/SH-3001.jpg,Co-ord Set,Linen,Beige,Shared design,TRUE
```

## Sheet behavior

`apps-script/Sync.gs` appends four operational columns:

- `SyncStatus`
- `LastSyncedAt`
- `SyncError`
- `SyncVersion`

Do not manually edit those four columns.

An edited row is pushed immediately. A full snapshot runs every five minutes so a row deleted from Google Sheets becomes inactive in Supabase.
