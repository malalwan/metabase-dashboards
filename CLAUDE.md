# Metabase Dashboard Agent — Master Guide

This file is the source of truth for creating Metabase dashboards via Claude Code + MCP.
Keep it updated as new tables, patterns, and learnings are discovered.

---

## MCP Setup

```bash
claude mcp add metabase \
  --env METABASE_URL=http://metabase-production-6394.up.railway.app \
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

## Dashboard Layout Rules

1. **No empty gaps** — every row must be fully filled. If placing cards leaves dead space, stretch the nearest card (preferably a table) to cover it.
2. **Tables get extra height** — any table card with multiple rows should be tall enough to show content without scrolling. Prefer `h=9` or more for tables; increase further if row count warrants it.
3. **Card dimensions follow CX Watch** — scalar: `w=6 h=3`, chart: `w=12 h=6`, table: `w=12–24 h=8+`. Grid is 24 columns wide.
4. **Max 4 scalar cards per row.**
5. After pushing a layout via API, the user may manually adjust card sizes/positions — do not overwrite those adjustments in subsequent updates unless explicitly asked.

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
| `null` | Purchased but not yet placed — item exists in the system but has not been assigned to WIB, PIB, or POB |

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

## Flent Business Model

### Unit Types

| Type | Full Name | Description | Capex | Base Rent (COGS) | GMV | Supply CAC | Demand CAC | Occ. Target | ASD |
|---|---|---|---|---|---|---|---|---|---|
| STD | Standard | Flent furnishes the unit | ₹85k | ₹27k | ₹35k | ₹10k | ₹3k | 95% | 270 days |
| AFF | Already Fully Furnished | Landlord has furnished; Flent manages only | ₹35k | ₹30k | ₹35k | ₹10k | ₹3k | 95% | 270 days |
| DNF | Do Not Furnish | Flent doesn't furnish; emerging micromarkets play (see below) | ₹10k | ₹27k | ₹27k | ₹20k | ₹18k | 100% | 360 days |
| F4B | Flent 4 Business / Expats | Premium corporate/expat product; higher capex, slower to fill | ₹1.2L | ₹32k | ₹50k | ₹10k | ₹10k | 85% | 360 days |

**DNF specifics:** DNF is a market-making product in emerging micromarkets where demand is thin. Flent doesn't furnish but fully manages. Sells to tenant near-cost; charges the landlord a higher PMF (8%) because finding a tenant in a thin-demand market is the real service. Higher Supply CAC because acquiring the best units in a competitive supply pool matters more than just getting any unit — and Flent offers no rental guarantee here, only management. Higher Demand CAC because filling a unit requires outbound effort in thin markets.

**F4B specifics:** Lower occupancy target (85%) because F4B takes longer to find the right corporate/expat tenant, not because demand is weak — it's a new category with intentional room for error in modelling.

---

### P&L Hierarchy

```
Revenue  =  GMV + PMF + OPX Collections + Exit Fee + Pass + other items
− COGS   =  Landlord rent payments
= CM     (Contribution Margin)
− OpEx   =  Salaries + Overhead + Brand + Tech + WnL + Legal + Secured Burn + etc.
= EBT    (Earnings Before Tax)
```

**Take Rate** = GMV − COGS (~21–27% of GMV). Tracked as a standalone metric separate from CM.

---

### Revenue Line Items (Inflow)

| Line Item | What it is |
|---|---|
| Rental Revenue | GMV collected from tenant (monthly rent) |
| PMF | Property Management Fee charged to landlord as % of base rent (STD/AFF/F4B = 1–2%, DNF = 8%) |
| OPX Collections | Fixture/maintenance work done on property billed to landlord at 110% of actual cost; 10% margin is Flent revenue. Improves as procurement costs drop and in-house workforce scales. |
| Token In | Booking token paid by tenant to secure the unit before move-in |
| Pass In | Flent Pass subscription revenue (see Products below) |
| Exit Fee | Charged to tenant on exit (STD/AFF: ₹5k early, ₹10k later; DNF: ₹0; F4B: ₹10k) |
| Move In Fee | Fee at move-in — currently ₹0 across all types |
| Deposits In | Tenant security deposits collected — balance sheet item, not P&L revenue |
| UnOc Loss | Negative item: revenue lost to vacant days between tenants |

---

### Cost Line Items (Outflow)

| Line Item | What it is |
|---|---|
| COGS | Monthly rent paid to landlord |
| LL Depo 1 & 2 | Landlord deposit paid in two installments (25% advance before launch, remainder at setup) |
| Cpx1 & Cpx2 | Capex for furnishing/setup — 50% advance ordered 30 days before launch, 50% on delivery |
| PERISH | Perishable consumables at each move-in (linens, kitchen items, etc.) |
| OPX | Actual operating expenses incurred for fixture/maintenance work (billed to landlord at 110%) |
| REVAMP CPX | Smaller refurbishment capex between tenants |
| CX Costs | Customer experience/support cost per unit per month |
| Dem CAC | Demand acquisition cost — acquiring tenants |
| Sup CAC | Supply acquisition cost — acquiring landlord units |
| WnL | Warehouse and Logistics |
| Secured Burn | 1% discount subsidy for the Secured product (see Products below) |

---

### Key Metrics & Terms

| Term | Definition |
|---|---|
| GMV | Gross rent collected from tenant per month |
| Take Rate | GMV − COGS; Flent's gross spread (~21–27%) |
| ASD | Average Stay Duration (STD/AFF = 270 days, F4B/DNF = 360 days) |
| Deposit Float | Tenant deposits collected − Landlord deposits paid. Positive float = Flent holds net cash from deposits as working capital. |
| TAT | Turnaround Time in days. Negative = before the reference event (usually unit launch date). |
| Rent Free Days | Landlord concession at start of tenancy — days Flent doesn't pay rent while setting up (STD/F4B = 25 days, AFF = 30 days, DNF = 0) |
| Rotation TAT | Days of lost revenue between one tenant moving out and the next moving in (currently 2 days for old portfolio) |
| Left Customers | Churned tenants where the unit stays on the platform — Flent finds a replacement |
| Lost Customers | Units that leave the platform entirely — landlord exits |
| Supply Churn | Monthly rate of landlords/units leaving the platform |
| Customer Churn | Monthly rate of tenant churn |
| OPX Coll % | 110% — Flent charges landlord 10% more than actual OPX cost; the margin is revenue |
| CPX Adv % | 50% capex paid upfront when order is placed, 50% on delivery |
| DEM-CAC-TAT | Days before launch when demand CAC is spent (STD/AFF = −20 days, F4B = −40 days) |
| SUP-CAC-TAT | Days after signing when supply CAC is paid (~10 days) |

---

### Products

**Flent Pass**
Paid membership product (like Swiggy One / Zomato Gold). Tenants pay upfront to unlock discounts, priority access to better properties, community benefits, and better exit terms. Dual purpose: working capital injection upfront + tenant retention incentive. Booked as revenue; mentally earmarked to offset capex.

**Secured**
Fintech product allowing tenants to pay rent via credit card at a 1% discount. Live product. The 1% subsidy is modelled as "Secured Burn" in operating costs.

---

### Financial Model Structure (spreadsheet: `1YiO-e3_J3xGioDQgufAsudU-_b0H-ffCeCk6trEuLv8`)

| Tab | Purpose |
|---|---|
| PnL | P&L summary by month (M1–M12) |
| CFS | Cash flow statement — inflow/outflow waterfall |
| PROPERTIES | Day-level cash event simulation for each unit acquired (one row per unit per day) |
| UNIT | New unit acquisition schedule by type and month — drives PROPERTIES simulation |
| OLD | Existing portfolio assumptions (steady declining tail; not a reporting concept, only a modelling convenience) |
| COGS | Base Rent + Rent Free Days assumptions by unit type |
| LLDEPO | Landlord deposit assumptions (months of deposit, settle TAT, advance %) |
| PMF | PMF % by unit type |
| PROD | Product/setup costs: CPX, PERISH, OPX, REVAMP CPX and associated TATs |
| DEM | Demand assumptions: Occupancy%, GMV/unit, deposits, ASD, TATs, exit/move-in fees |
| CAC | Supply and Demand CAC by unit type with TATs |
| EMP | Employee roster: roles, fixed LPA, variable LPA, ESOPs, joining dates |
| OTHER | Other OpEx: Salaries, Overhead, Bonuses, Debt Repayment, Brand, WnL, Legal, Secured Burn, Tech |
| DEBT | Debt infusion schedule, repayment terms, interest rates — used to model how much debt the business can afford |

**Key modelling convention:** Every cash event is modelled as a day offset from the unit's launch date. Negative TAT = the event happens before launch (e.g. CPX BUY TAT = −30 means capex is ordered 30 days before launch). "Old" vs "New" is only a modelling split — not a reporting dimension. Vintage cohorts are the real reporting concept (to be documented separately).

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
| 2026-04-17 | `"values_query_type": "list"` must be set on a dashboard parameter for the filter to render as a dropdown — without it, it shows as a text field even when `values_source_type` is set |
| 2026-04-17 | For nullable SQL filters with multi-select: use `[[AND col = ANY(STRING_TO_ARRAY({{var}}, ','))]]` — the optional block drops the clause when empty; STRING_TO_ARRAY handles comma-joined multi-values |
