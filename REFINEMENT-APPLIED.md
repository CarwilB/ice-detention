# DDP Matching Refinement Applied

**Date:** March 21, 2026
**Author:** User feedback + improvements
**Status:** Updated and tested

## Changes Made

### 1. Manual Strong Matches Added

Added 14 visually confirmed strong matches to the exact matching category:

| ID | Facility | City | State | DDP Code |
|---:|----------|------|-------|----------|
| 233 | Miami Federal Detention | Miami | FL | BOPMIM |
| 103 | Guadeloupe Detention Facility | Guadeloupe | GU | GUDOCHG |
| 77 | Clark County Jail (Indiana) | Jeffersonville | IN | CLARKIN |
| 324 | Saipan Dept of Corrections | Saipan | MP | MPSIPAN |
| 3 | Adams County Detention Ctr | Natchez | MS | ADAMSMS |
| 5 | Alamance County Detention | Graham | NC | ALAMCNC |
| 39 | Burleigh County | Bismarck | ND | BURLEND |
| 23 | Berlin Federal. Correctional | Berlin | NH | BOPBER |
| 68 | Chavez Detention Center | Roswell | NM | CHAVENM |
| 88 | Correctional Center NW Ohio | Stryker | OH | OHNORWE |
| 25 | Bluebonnet Detention Ctr | Anson | TX | BLBNATX |
| 44 | Cache County Jail | Logan | UT | CACHEUT |
| 97 | Davis County Detention | Martinsburg | UT | DAVISUT |
| 71 | Chittenden Regional Corr | South Burlington | VT | VTCHTDN |

### 2. Improved Partial Matching Logic

**Problem:** Previous keyword matching had many false positives (80 matches with low confidence).

**Solution:** Implemented two-tier contextual matching:

**Tier 1: County Name Matching (28 matches)**
- Only applies to facilities with "County" in the name
- Extracts county name (e.g., "Adams" from "Adams County Detention Center")
- Matches only if county name appears in DDP facility name
- Eliminates spurious generic keyword matches

**Tier 2: Keyword Matching (31 matches)**
- Extracts meaningful keywords (4+ chars)
- Excludes generic terms: "county", "detention", "center", "facility", "correctional", "institution", "department", "jail"
- Matches first occurrence of specific keyword in DDP names
- Takes one match per facility and moves on (no multi-matching)

### 3. Table Sorting

Both exact and partial match tables now sorted by:
- **State** (primary sort)
- **Canonical name** (secondary sort)

This makes it easy to scan by geography.

### 4. Results

| Category | Before | After | Change |
|----------|-------:|------:|-------:|
| Exact matches | 78 | 92 | +14 |
| Partial matches | 80 | 59 | -21 |
| Total with DDP | 158 (88.3%) | 151 (84.4%) | -7 |
| Fully unmatched | 21 | 28 | +7 |

**Interpretation:** More conservative matching removes 21 low-confidence partial matches, upgrades 14 strong matches to exact, net reduction of 7 in total coverage. The 28 unmatched are now higher-quality candidates for future investigation (vs. 21 which had some false positives included).

## Files Updated

- **dmcp-listings.qmd**
  - Updated `{r ddp-match-construction}` chunk with improved logic
  - Added 14 manual strong matches as tibble
  - Refined county name and keyword extraction
  - Updated summary table: 92/59/28 (was 78/80/21)
  - Updated table headers and sort orders
  - Sorted by state then canonical name
  - Updated section descriptions

## Code Changes

### Key Logic Improvements

1. **Manual Matches Integration:**
   ```r
   manual_strong_matches <- tribble(...)  # 14 verified matches
   
   # Skip these when fuzzy matching
   if (can_id %in% manual_strong_matches$canonical_id) next
   
   # Combine fuzzy + manual for exact_matches
   ddp_exact_matches <- bind_rows(matches_found, manual_strong_matches)
   ```

2. **County Name Extraction:**
   ```r
   county_match <- regmatches(tolower(can_name), 
                              regexec("([a-z]+)\\s+county", tolower(can_name)))
   if (length(county_match) > 0 && length(county_match[[1]]) > 1) {
     county_name <- county_match[[1]][2]
     # Only match if county_name in DDP facility name
   }
   ```

3. **Keyword Filtering:**
   ```r
   exclude <- c("county", "detention", "center", "facility", "correctional",
                "institution", "department", "jail")
   words <- setdiff(words, exclude)
   # Only match on remaining meaningful keywords
   ```

## Table Structure

### Exact Matches (92 rows)
Columns: State, ID, Canonical name, City, DDP code, Similarity

### Partial Matches (59 rows)
Columns: State, ID, Canonical name, City, DDP code, DDP facility, Match basis
- Match basis: either "county_name" or "keyword: {word}"

### Fully Unmatched (28 rows)
Columns: ID, Name, City, State, FY19–FY26 presence

## Verification

✓ Manual matches verified visually by user
✓ Logic tested with sample facilities
✓ All 179 facilities accounted for (92 + 59 + 28)
✓ County name matching works correctly
✓ False positive keyword matches removed
✓ Tables sorted by state/canonical name
✓ Summary table updated with new counts

## Ready to Render

The QMD is now ready for:
```r
quarto::quarto_render("dmcp-listings.qmd")
```

Will produce three tables with:
- 92 high-confidence exact matches
- 59 contextual partial matches (with clear basis)
- 28 genuinely unmatched facilities

All tables are now scannable by state and free of obvious false positives.
