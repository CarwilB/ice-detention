## **ICE Detention Data Pipeline: Comprehensive Summary (FY2019–FY2026 + DMCP + DDP Integration)**

### **Project Overview**

The **ice-detention** project is a `targets`-based R pipeline for importing, cleaning, harmonizing, and analyzing 8 years of U.S. ICE detention facility statistics (FY 2019–FY 2026), plus historical authorization rosters (DMCP 2015–2017) and operational daily population data (DDP Sep 2023–Oct 2025). The project maintains a **canonical facility identification system** that deduplicates and standardizes facility names across all sources.

### **Canonical Facility System**

**347 canonical facilities** (IDs 1–398) represent the FY19–FY26 universe, derived from exact name matching and fuzzy address-based merging across 398 initial variants. An additional **53 DMCP-only facilities** (IDs 1001–1053) appear in the 2015–2017 authorization rosters but not in the annual statistics panel. One recent merge: **canonical IDs 318/319** (Robert A. Deyton, Lovejoy GA) were consolidated after discovering they share the same address but have slightly different names across fiscal years.

**Key ID ranges:**

-   1–347: FY19–FY26 facilities (frozen in `data/canonical_id_registry.csv`)

-   399–1000: Reserved for future annual stats (FY27+)

-   1001–1053: DMCP-only facilities (recent reduction from 1001–1060 after merging 7 duplicates)

### **DMCP Integration (Complete)**

**Data sources:** Two point-in-time ICE authorization rosters:

-   **faclist17** (Jul 2017, PDF): 201 facilities

-   **faclist15** (Dec 2015, XLSX): 209 facilities

-   **Total unique:** 230 DETLOCs (facility codes)

**Matching against FY19–FY26 canonical list (3-pass):**

1.  **164 exact** — name+city+state match against facility_crosswalk variants

2.  **13 manual** — confirmed by street address (6 original renames/truncations + 7 retitled facilities initially assigned IDs 1001+)

3.  **53 new** — IDs 1001–1053; unmatched DMCP facilities; 27 had zero ADP in their most recent two fiscal years

**Recently resolved duplicates:** 7 DMCP facilities were assigned IDs 1001+ but later confirmed as the same physical location as existing canonical facilities via street address matching:

-   1004 (CACFMES) = canonical 231 (Mesa Verde)

-   1043 (GRYDCKY) = canonical 153 (Grayson County)

-   1002 (MONTGTX) = canonical 182 (Joe Corley)

-   1003 (PINEPLA) = canonical 292 (Pine Prairie)

-   1059 (TRICOIL) = canonical 304 (Pulaski County/Tri-County)

-   1001 (STCDFTX) = canonical 343 (South Texas ICE Processing Center)

-   1031 (CCADCAZ) = canonical 61 (Central Arizona Florence)

**Two facilities with adjacent-building discrepancies** (separate DETLOC codes in different buildings of the same complex, pending confirmation):

-   JAMESGA (ID 1002 in pipeline, references canonical 138/139/225 cluster in Folkston, GA)

-   OTROPNM (ID 1005 in pipeline, references canonical 283 in Chaparral, NM)

**All 230 DMCP detloc codes are mapped** — no unmapped facilities.

### **DDP Integration (Complete)**

**Data source:** Deportation Data Project daily detention facility counts, Sep 2023–Oct 2025 (776 days), 853 distinct facility codes imported as feather file.

**Matching against non-DMCP canonical facilities (3-tier):**

-   **114 exact:** 92 fuzzy OSA ≥0.85 + 22 manually verified strong matches

-   **19 partial: county-name** — word before "county" required in DDP name

-   **6 partial: keyword** — confirmed non-county matches (25 low-confidence rejected)

-   **39 fully unmatched** — 26 jails (mostly unactive in DDP era), 11 hotels/staging, 2 state MDCs, 4 CDF, and miscellaneous specialized facilities

**Special case: Guantánamo Bay (canonical 176, JTF Camp Six)**

-   Maps to **3 DDP codes** (one-to-many):

    -   GTMOACU (Windward Holding Facility, \~9/day)

    -   GTMODCU (Migrant Ops Center Main, \~5/day)

    -   GTMOBCU (Migrant Ops Center East, \~0.003/day)

-   Combined average \~4.6/day aligns with FY25–FY26 ADP of \~8–9

-   Handled with `ddp_role` column (primary/component) in pipeline

**DDP code coverage:** 139 of 178 non-DMCP canonical facilities have DDP representation.

### **DETLOC (Facility Code) Unification (Complete)**

**Both DMCP and DDP use the same DETLOC system.** Of 4 facilities appearing in both sources, 3 have identical codes; 1 (canonical 182, Joe Corley) changed from MONTGTX (2017) to JCRLYTX (2023) on rename.

**Pipeline targets built:**

-   `ddp_canonical_map` — 135 facilities matched via DDP matching logic

-   `detloc_lookup` — unified 1:1 lookup: 361 unique (226 DMCP + 135 DDP)

-   `detloc_lookup_full` — multi-row reference preserving all variants

-   Priority: **DDP takes precedence over DMCP** for currency (handles reassignments)

**Coverage:** 308 of 347 canonical facilities (1–398) now have a DETLOC; 39 remain unmatched (NA).

### **Geocoding**

**Current:** 348 existing + 53 DMCP-only = **401 total geocoded facilities** (all with lon/lat via Google Maps API).

-   Pre-existing geocoded canonical facilities (FY19–FY26): 348 rows

-   Extended geocoding for DMCP-only (IDs 1001–1053): 53 rows

-   Total includes 1 stale ID 319 (pre-merge cache entry, harmless)

-   Target: `facilities_geocoded_full` (cue = "never")

### **Data Cleaning & Quality Fixes**

**DMCP data quality corrections:**

-   ZIP zero-padding (both faclist15/17)

-   City name corrections: "Kearney"→"Kearny" (NJ), "Colorado Spring"→"Colorado Springs" (truncation fix)

-   State bleed fix: strip non-alpha prefixes in `facility_state` (PDF overflow)

-   PDF column boundary adjustments for accurate zip/type parsing

**DDP name cleaning:**

-   Title case standardization

-   Abbreviation expansion (e.g., "Dept" → "Department")

-   Acronym restoration

### **Pipeline Architecture**

**Main targets:**

-   `facilities_raw` → `facilities_clean` → `facilities_aggregated` (8 fiscal years of annual stats)

-   `facility_crosswalk` (exact + fuzzy address merging → canonical IDs)

-   `facilities_keyed` (aggregated data with canonical_id + canonical_name + **detloc** columns)

-   `facilities_panel` (long format: one row per facility per year)

-   `facility_presence` (binary presence matrix + trajectory: continuous/closed/new/transient/persistent_gaps)

-   `canonical_facilities` (one row per canonical facility, most recent addresses + geocoding columns)

-   `saved_files` (RDS + CSV exports to `data/`)

**DMCP integration targets:**

-   `dmcp_canonical_map` (230 facilities with match_type: exact/manual/new)

-   `faclist15_keyed`, `faclist17_keyed` (DMCP rosters with canonical_id attached)

**DDP integration targets:**

-   `ddp_codes` (853 distinct facility codes, name-cleaned)

-   `ddp_canonical_map` (137 rows: 135 unique canonical IDs × fuzzy/county/keyword match tiers)

-   `detloc_lookup`, `detloc_lookup_full` (unified facility code lookups)

### **Key Recent Decisions & Fixes**

1.  **Idempotent registry writes:** Fixed `build_dmcp_canonical_map()` to check for existing IDs by (name, city, state) before appending, avoiding re-duplication on pipeline rebuild.

2.  **DDP matching ported to pipeline:** Moved all matching logic from `dmcp-listings.qmd` inline code into `build_ddp_canonical_map()` in `R/ddp.R`, with manual matches extracted to `ddp_manual_strong_matches()` function. Resolved circular dependency by using `id_registry` instead of `canonical_facilities` as input.

3.  **DETLOC column propagation:** Updated `attach_canonical_ids()` to accept and join `detloc_lookup`, adding facility codes to `facilities_keyed` → `facilities_panel` → `canonical_facilities` → saved outputs.

4.  **County-name matching strictness:** Require county word to appear in DDP name (reduces false positives); keyword matching is confirmed-only (6 IDs: 211, 207, 253, 310, 268, 316).

5.  **Addressed 39 fully unmatched facilities:** Classified by type (26 jails, 11 hotels/staging, 2 state MDCs, 4 CDF, misc.). Year-presence analysis shows many were active in FY24–FY26 but have no DDP counterpart.

### **Documentation**

**Primary documents:**

-   **`AGENTS.md`** — project memory: file system conventions, data sources, pipeline targets, key variables, ID space, integration status, coverage stats

-   **`dmcp-listings.qmd`** — DMCP and DDP matching tables, Section 4 (13 manual DMCP matches, 53 new), Section 5 (114 exact DDP + 19 county + 6 keyword DDP matches + 39 unmatched)

-   **`_targets.R`** — pipeline definition with 31 targets

-   **`R/`** — modular function libraries: `metadata.R`, `download.R`, `import.R`, `clean.R`, `aggregate.R`, `crosswalk.R`, `integrate.R` (DMCP), `ddp.R` (DDP + geocoding utilities), `geocode.R`

### **Utility Functions**

**`ddp_average_population(dp, code, from, to, population_col)`** — computes mean daily population for one or more DDP facility codes across a date range. Handles vectorized input; returns tibble with date range, n_days, mean_population.

### **Open Questions & Next Steps**

1.  **39 fully unmatched facilities:** Classify reason for absence in DDP (closed, de-authorized, specialized, non-traditional). Check year-presence to see active years vs. DDP coverage window (Sep 2023–Oct 2025).

2.  **Multi-facility complexes:** Folkston (3 canonical IDs, 3 DMCP detlocs, 3 DDP codes) and Otero (2 canonical, 2 DMCP, adjacent buildings) are correct as separate entries; confirm operational distinction in DDP.

3.  **Facility code time-series:** Build join of DDP daily population to canonical facilities via `detloc_lookup` for continuous monitoring capability.

4.  **Wikipedia harmonization:** Original `import-ice-detention.qmd` (wiki-graph project) includes `add_wikipedia_matches()` function for fuzzy matching to Wikipedia article. Not yet ported to pipeline.

5.  **Visualizations:** Treemaps (by type, by state×type) and interactive Leaflet maps not yet built for this codebase.
