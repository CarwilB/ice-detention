### DDP FY25 Facility Summary — Data Dictionary

**Source:** Deportation Data Project daily detainee population data, summarized to one row per facility for Fiscal Year 2025 (Oct 1, 2024 – Sep 30, 2025).

**Unit of observation:** One row per ICE detention facility code (DETLOC).

**Row count:** 853 facilities.

**Temporal coverage:** All facilities have 365 days of observation (the full FY25 window). Daily counts of zero are included; facilities with no detainees on a given day still contribute that day to the averages.

#### Column definitions

| Column | Type | Description |
| --- | --- | --- |
| `detention_facility_code` | character | ICE facility code (DETLOC), e.g. `ADAMSMS`. Unique identifier for each row. |
| `detention_facility` | character | Facility name, cleaned to project standards (title case, abbreviation normalization). |
| `state` | character | Two-letter U.S. state or territory abbreviation. |
| `n_days` | integer | Number of days with a population observation in the FY25 window. All rows are 365 in this file. |
| `adp_total` | double | Average daily population (total detained), computed as `mean(n_detained)` over the `n_days` observation days. |
| `adp_midnight` | double | Average daily population at midnight count, computed as `mean(n_detained_at_midnight)`. The midnight count captures only those physically present at the facility at midnight; `adp_total` includes individuals booked in and out during the day. |
| `adp_male` | double | Average daily population of male detainees, from `mean(n_detained_male)`. |
| `adp_female` | double | Average daily population of female detainees, from `mean(n_detained_female)`. |
| `adp_convicted_criminal` | double | Average daily population of detainees classified as convicted criminals, from `mean(n_detained_convicted_criminal)`. |
| `adp_possibly_under_18` | double | Average daily population of detainees flagged as possibly under 18 years old, from `mean(n_detained_possibly_under_18)`. |
| `peak_population` | integer | Maximum single-day total detained population during FY25. |
| `peak_date` | Date | Date on which `peak_population` occurred. If tied, the first date is used. |
| `adp_non_criminal` | double | Average daily population of detainees not classified as convicted criminals. Derived as `adp_total - adp_convicted_criminal`. |
| `share_non_crim` | double | Share of ADP that is non-criminal: `adp_non_criminal / adp_total`. Ranges from 0 to 1. Undefined (likely 0/0 → NaN) for facilities with zero total ADP, though all 853 facilities in this file have nonzero `adp_total`. |
| `share_female` | double | Share of ADP that is female: `adp_female / adp_total`. Ranges from 0 to 1. |

#### Notes

- **ADP vs. midnight count:** The `adp_total` column reflects the average of the broadest daily detained count, which includes individuals who may have been booked in and out within the same day. The `adp_midnight` count is typically lower and reflects the "snapshot" population at midnight.
- **Criminality classification:** The `adp_convicted_criminal` field reflects ICE's classification of detainees with criminal convictions. The complementary `adp_non_criminal` field captures all others, including those with pending charges, immigration-only violations, or no criminal history.
- **Relationship to ICE annual statistics:** The ICE FY25 spreadsheet covers approximately 225 facilities. This DDP summary covers 853 facility codes, including hold rooms, staging facilities, federal prisons, and other sites where ICE holds detainees but which are excluded from the published annual spreadsheet.
