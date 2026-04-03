# ICE Detention Facilities Data Pipeline

A reproducible [targets](https://docs.ropensci.org/targets/)-based R pipeline for importing, cleaning, harmonizing, and analyzing U.S. Immigration and Customs Enforcement (ICE) detention facility data. The pipeline integrates multiple ICE data sources spanning fiscal years 2010–2026, as well as facility data from Deportation Data Project more producing a unified facility roster with canonical identifiers, geocoded locations, and facility type classifications. Location data is coordinated across sources from the ICE data, Deportation Data Project, Vera Institute, and the Marshall Project.

Currently there are two stages of the data merge, the first focused on the ICE spreadsheets covering 2010-2026, and the second integrating DDP data and thereby adding new items to our registry of facilities. In our future development strategy, we plan to add new facilities to these lists as detention population data becomes available, drawing in location data from prior researchers (Vera, Marshall).

## Data sources

| Source | Coverage | Description |
|-------------------|-----------------------|------------------------------|
| **ICE Annual Detention Statistics** | FY 2019–FY 2026 | Facility-level average daily population (ADP) by security classification, criminality, threat level, and gender; inspection records and guaranteed minimums. Published annually as XLSX spreadsheets. |
| **ICE DMCP Facility Authorization Listings** | FY 2010–FY 2017 | Two snapshots (2015 XLSX, 2017 PDF) of authorized detention facilities with contract details, per diem rates, and single-value ADP. Provides historical coverage for FY10–FY17 (FY18 unavailable). |
| **Deportation Data Project (DDP)** | Sep 2023–Oct 2025 | Daily detainee counts by facility, obtained via FOIA. Covers \~850 facility codes including jails, hold rooms, staging facilities, medical facilities, and ERO field offices not reported in ICE annual stats. |
| **Vera Institute of Justice** | FY2009-Oct 2025; \~1,460 facilities | Geocoded facility metadata with addresses, county, Area of Responsibility (AOR), and type classifications. From the [ICE Detention Trends](https://github.com/vera-institute/ice-detention-trends) project. See their [Technical Appendix](https://vera-institute.files.svdcdn.com/production/downloads/dashboard_appendix.pdf). |
| **The Marshall Project** | 1978–2017 | Historical facility locations (1,479 facilities) with DETLOC codes, addresses, and geocoded coordinates. From [themarshallproject/dhs_immigration_detention](https://github.com/themarshallproject/dhs_immigration_detention). |

## What the pipeline produces

The pipeline assigns a stable **canonical ID** to every facility encountered across all sources, then builds these from the ICE annual data (\<400 facilities):

-   **`facilities_panel`** — Long-format panel dataset: one row per facility per fiscal year (FY10–FY26, minus FY18), with \~30 measurement variables including ADP breakdowns, inspection records, and derived shares.
-   **`facility_roster`** — One row per canonical facility with address, facility type, DETLOC code, and Vera type classification.
-   **`facility_crosswalk`** — Maps every observed (name, city, state) variant to its canonical ID and name.
-   **`facility_presence`** — Boolean presence matrix (FY10–FY26) with trajectory labels: continuous, persistent with gaps, closed, new, or transient.

And these for the larger list (\~960 facilities so far):

-   **`facility_roster`** — One row per canonical facility with address, facility type, DETLOC code, and Vera type classification.
-   **`source_presence`** — Boolean flags indicating which data sources cover each facility.
-   **`facilities_geocoded_all`** — Geocoded coordinates from Google Maps API, Vera, and Marshall Project, with divergence flags.
-   **`detloc_lookup`** — Unified mapping from ICE facility codes (DETLOCs) to canonical IDs.

All primary outputs are saved as both RDS and CSV in `data/`.

-   **Wikipedia integration** — Matched facilities to Wikipedia articles; generates MediaWiki table markup for the [List of immigration detention facilities in the United States](https://en.wikipedia.org/wiki/List_of_immigration_detention_facilities_in_the_United_States).

## Facility types

The pipeline classifies \~960 facilities across all sources into a unified type vocabulary:

| Type | Description |
|-----------------------|-------------------------------------------------|
| Jail | County/city jails with ICE intergovernmental agreements (IGSA, USMS IGA) |
| Dedicated Migrant Detention Center | Jails or private facilities dedicated to ICE use (DIGSA) |
| Private Migrant Detention Center | Privately operated contract detention facilities (CDF) |
| ICE Migrant Detention Center | ICE-owned Service Processing Centers (SPC) |
| ICE Short-Term Migrant Detention Center | Staging facilities for short-term processing |
| Federal Prison | Bureau of Prisons facilities (BOP) |
| Family Detention Center | Family residential centers |
| Juvenile Detention Center | Facilities for unaccompanied minors |
| State Migrant Detention Center | State-operated facilities |
| Military Detention Center | Department of Defense facilities |
| Hold/Staging | Hold rooms at ERO field offices and short-term staging (DDP/Vera) |
| Medical | Hospitals, clinics, and medical transport (DDP/Vera) |

## Canonical ID ranges

| Range     | Purpose                                              |
|-----------|------------------------------------------------------|
| 1–398     | FY19–FY26 panel facilities (frozen registry)         |
| 1001–1053 | DMCP-only facilities (2015/2017 authorization lists) |
| 1054–1203 | DDP non-medical, non-hold facilities                 |
| 2001–2025 | ERO field offices                                    |
| 2026–2186 | Hold/staging facilities                              |
| 3001–3226 | Medical facilities                                   |

## Quarto reports

The pipeline renders analytical reports as HTML documents:

| Report | Description |
|----------------------------|--------------------------------------------|
| `facility-summary.qmd` | Facility counts by ID range, source coverage, and trajectory statistics |
| `geocoding-divergence.qmd` | Maps and tables comparing geocoded coordinates across sources |
| `ddp-comparison.qmd` | DDP daily population vs. ICE FY25 annual statistics; unreported facility analysis |
| `missing-addresses.qmd` | Identifies roster facilities missing address information |
| `dmcp-listings.qmd` | Documentation of the 2015/2017 DMCP facility authorization data |
| `ero-field-offices.qmd` | ERO field offices as informal detention sites |

Two additional reports are published separately as blog posts:

-   [DDP vs ICE FY25 annual statistics](https://example.com) — comparison of daily vs. annual population counts
-   [Interactive Map of ICE Detention Facilities](https://example.com) — Leaflet map of \~390 panel facilities colored by type and sized by ADP

Data for these posts is exported via `export-ddp-comparison-data.R`.

## Project structure

```         
├── _targets.R              # Pipeline definition (~70 targets)
├── R/                      # Pipeline functions (13 modules, ~4,500 lines)
│   ├── metadata.R          # Spreadsheet metadata
│   ├── download.R          # File downloads
│   ├── import.R            # Excel/PDF import
│   ├── clean.R             # Name standardization, type coercion
│   ├── aggregate.R         # ADP sums, facility type classification
│   ├── crosswalk.R         # Canonical ID assignment, panel construction
│   ├── integrate.R         # DMCP/DDP/DETLOC integration
│   ├── ddp.R               # DDP daily population processing
│   ├── geocode.R           # Google Maps API geocoding
│   ├── wiki-match.R        # Wikipedia article matching
│   ├── wikipedia.R         # MediaWiki markup generation
│   ├── vera-institute.R    # Vera Institute data
│   ├── themarshallproject-locations.R  # Marshall Project locations
│   ├── catalog.R           # Auto-generated targets catalog
│   └── str-equivalent.R    # String comparison utilities
├── data/                   # Raw inputs and derived outputs
│   ├── ice/                # ICE annual stats XLSX (FY19–FY26)
│   ├── ddp/                # Deportation Data Project feather file
│   ├── vera-institute/     # Vera Institute facilities CSV
│   ├── marshall/           # Marshall Project locations CSV
│   └── [derived outputs]   # RDS/CSV panel, roster, crosswalk, etc.
├── scripts/                # Standalone utility scripts
├── *.qmd                   # Quarto analytical reports
├── renv.lock               # Package dependency lockfile
└── AGENTS.md               # Detailed project memory for AI assistants
```

## Getting started

### Prerequisites

-   R ≥ 4.5
-   [renv](https://rstudio.github.io/renv/) for package management
-   targets for the reproducible pipeline
-   Java runtime (for `tabulapdf` PDF extraction)
-   Google Maps API key (for geocoding; set `GOOGLE_API_KEY` in `.Renviron`)

### Setup

``` r
# Restore package dependencies
renv::restore()

# Run the full pipeline
targets::tar_make()

# View the pipeline dependency graph
targets::tar_visnetwork()
```

Most download targets use `cue = tar_cue("never")` so they run only once. Re-downloading requires `tar_invalidate()` on the specific target.

## Key R packages

`targets`, `readxl`, `dplyr`, `tidyr`, `stringr`, `purrr`, `arrow`, `tabulapdf`, `ggmap`, `rvest`, `stringdist`, `glue`

## Author

Carwil Bjork-James

## License

TBD
