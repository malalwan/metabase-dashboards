# Metabase Dashboard Agent — Master Guide

This file is the source of truth for creating Metabase dashboards via Claude Code + MCP.
Keep it updated as new tables, patterns, and learnings are discovered.

---

## MCP Setup

```bash
claude mcp add metabase \
  --env METABASE_URL=https://metabase-production-6394.up.railway.app \
  --env METABASE_API_KEY=<api_key> \
  -- npx @cognitionai/metabase-mcp-server --all
```

> Note: The Metabase instance redirects HTTP → HTTPS. Always use `https://` in direct API calls.

---

## Instance Details

| Property | Value |
|---|---|
| URL | `https://metabase-production-6394.up.railway.app` |
| Primary database | `postgres` (Database ID: **2**) |
| Schema for source tables | `public` (raw/transactional) |
| Schema for views | `views` (aggregated/derived — see caveats below) |

---

## Source Tables (use these, not views)

These are the authoritative tables with unique, row-level data. **Always prefer these as query sources.**

| Table | Table ID | Description |
|---|---|---|
| `ims_fsins` | 53 | **Primary key source for FSINs.** One row per unique FSIN. Contains `fsin_code`, `vendor_code`, `name`, `category`, `uom`, `track_method`, `reorder_point`, etc. |
| `ims_vendors` | 57 | One row per vendor. Contains `vendor_code`, `vendor_name`, contact info, bank details. |
| `ims_items` | 51 | Item-level records. |
| `ims_po` | 52 | Purchase orders. |
| `ims_polines` | 55 | Line items within purchase orders. |
| `ims_movements` | 54 | Stock movement records. |

### Key Field IDs (ims_fsins — Table 53)

| Field | Field ID | Type |
|---|---|---|
| `fsin_code` | 2760 | Text |
| `vendor_code` | 2761 | Text |
| `name` | 2762 | Text |
| `category` | 2763 | Text |
| `uom` | 2764 | Text |
| `track_method` | 2765 | Text |
| `reorder_point` | 2766 | Integer |

### Key Field IDs (ims_vendors — Table 57)

| Field | Field ID | Type |
|---|---|---|
| `vendor_code` | 2846 | Text |
| `vendor_name` | 2847 | Text |
| `phone_number` | 2848 | Text |
| `poc_name` | 2849 | Text |
| `address` | 2850 | Text |
| `email` | 2851 | Text |

---

## Views (use with caution)

Views in the `views` schema are pre-aggregated and **do not guarantee unique rows per FSIN**. Do not use them as a source when counting or grouping by FSINs — you will get inflated or duplicate counts.

| View | Table ID | Caveat |
|---|---|---|
| `fsin_purchases` | 12 | Aggregated by vendor+FSIN — not unique per FSIN |
| `vendor_purchases` | 16 | Aggregated by vendor+month — not unique per vendor |

---

## Question Creation Rules

### 1. Always prefer GUI (MBQL) questions over SQL

GUI questions:
- Wire up to dashboard dropdown filters automatically
- Are easier for teammates to edit without writing SQL
- Are created via the Metabase API using `"type": "query"` in `dataset_query`

SQL questions (`"type": "native"`):
- Do **not** auto-connect to dashboard filters — require `{{field_filter}}` variables
- Use only when the GUI query builder cannot express the logic (e.g. complex CTEs, window functions, conditional aggregations)

### 2. GUI question structure (MBQL)

```json
{
  "name": "Chart Name",
  "display": "pie",
  "collection_id": <id>,
  "dataset_query": {
    "type": "query",
    "database": 2,
    "query": {
      "source-table": <table_id>,
      "joins": [
        {
          "fields": "all",
          "alias": "<join_alias>",
          "source-table": <joined_table_id>,
          "condition": ["=",
            ["field", <left_field_id>, {"base-type": "<type>"}],
            ["field", <right_field_id>, {"base-type": "<type>", "join-alias": "<join_alias>"}]
          ]
        }
      ],
      "aggregation": [["count"]],
      "breakout": [
        ["field", <field_id>, {"base-type": "<type>", "join-alias": "<join_alias>"}]
      ],
      "filter": ["=", ["field", <field_id>, null], "{{variable}}"]
    }
  },
  "visualization_settings": {}
}
```

### 3. Dashboard filter compatibility

| Question type | Auto-wires to dashboard filter? |
|---|---|
| GUI (MBQL) | Yes — map filter to any field in the breakout/dimension |
| SQL (native) | No — must add `{{field_filter}}` variable inside the SQL and set type to "Field Filter" |

---

## Collections

| Collection | ID | Use for |
|---|---|---|
| Inventory | 12 | Inventory-related charts (FSINs, vendors, stock) |

---

## Common Patterns

### Count of FSINs per vendor (pie chart)
- Source: `ims_fsins` (53)
- Join: `ims_vendors` (57) on `vendor_code` (field 2761 → 2846)
- Aggregation: `count`
- Breakout: `vendor_name` (field 2847, join-alias: `ims_vendors`)
- Display: `pie`

---

## API Quick Reference

All direct API calls must use HTTPS and the header `x-api-key: <key>`.

```bash
# List all tables in the postgres DB
GET /api/database/2/metadata

# Get field IDs for a table
GET /api/table/<table_id>/query_metadata

# Create a card
POST /api/card

# Archive a card
PUT /api/card/<id>   body: {"archived": true}

# List collections
GET /api/collection
```

---

## Item States (`ims_items.state`)

| State | Meaning |
|---|---|
| `PIB` | Deployed — item is active at a PID (location format: `PID{n}-{suffix}`) |
| `WIB` | In warehouse — available stock |
| `POB` | In transit — on an open purchase order, not yet received |
| `null` | Inactive / dead — retired or consumed |

`location` for PIB items contains the PID string (e.g. `PID138-LRD`). Group by `location` to get per-PID inventory breakdown.

---

## Vendors Dashboard (Dashboard ID: 22)

Live at: `https://metabase-production-6394.up.railway.app/dashboard/22`

Filter: Vendor Code (`string/=`, parameter ID `b3f9a1c2`)

| Card | ID | Type | Source | Notes |
|---|---|---|---|---|
| Total Purchase Amount | 228 | scalar | `ims_po` | sum(amount), ₹ prefix |
| Items Deployed (PIB) | 229 | scalar | `ims_items` + `ims_fsins` | state = PIB |
| In Warehouse (WIB) | 230 | scalar | `ims_items` + `ims_fsins` | state = WIB |
| Inactive Items | 231 | scalar | `ims_items` + `ims_fsins` | state IS NULL |
| Total FSINs | 232 | scalar | `ims_fsins` | count |
| In Transit (POB) | 233 | scalar | `ims_items` + `ims_fsins` | state = POB |
| Items by State | 234 | bar | `ims_items` + `ims_fsins` | count breakout by state |
| PIDs with Vendor Inventory | 235 | table | SQL (3-table join) | PIB items grouped by location, with count + value |
| Purchase Order History | 236 | table | `ims_po` | sorted by date desc |

**Filter wiring:**
- Cards sourced from `ims_po`: target `["dimension", ["field", 2799, ...]]` (vendor_code on ims_po)
- Cards sourced from `ims_items` + `ims_fsins` join: target `["dimension", ["field", 2761, {"join-alias": "ims_fsins"}]]`
- Cards sourced from `ims_fsins` directly: target `["dimension", ["field", 2761, ...]]`
- SQL cards: target `["variable", ["template-tag", "vendor_code"]]` — use `[[AND f.vendor_code = {{vendor_code}}]]` optional syntax

---

## Learnings Log

| Date | Learning |
|---|---|
| 2026-04-16 | Views (`fsin_purchases`, `vendor_purchases`) are not unique per FSIN — use `ims_fsins` as the primary FSIN source |
| 2026-04-16 | MCP sub-agents do not inherit MCP tools from the parent session — use direct API calls or main-thread MCP tool calls |
| 2026-04-16 | Metabase instance redirects HTTP to HTTPS — always use `https://` |
| 2026-04-16 | GUI questions auto-wire to dashboard dropdown filters; SQL questions require field filter variables |
| 2026-04-16 | For 3-table joins with aggregation (e.g. items + fsins + polines), fall back to SQL — GUI join chaining gets unwieldy |
| 2026-04-16 | Dashboard filter parameter_mappings must use join-alias when the filtered field comes from a joined table in a GUI question |
