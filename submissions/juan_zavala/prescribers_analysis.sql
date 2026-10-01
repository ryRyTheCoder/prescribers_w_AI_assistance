-- ============================================================================
--  AI-Assisted Prescribers Project
--  Author:   Juan Zavala, working with Claude (Anthropic)
--  Database: prescribers (CMS Medicare Part D Prescriber data, Tennessee prescribers)
--  Engine:   PostgreSQL 15, run in pgAdmin 4
--
--  HOW THIS FILE IS LABELED (the README asks us to tell our code from Claude's)
--    -- [ME]      a query I wrote myself, before asking Claude
--    -- [CLAUDE]  a query Claude provided
--    -- [CHECK]   a query that proves two answers match (0 rows back = identical)
--    -- [NOTE]    something interesting or surprising
--
--  Prompt given to Claude at the start, with Prescriber_Methodology.pdf and ERD.png attached:
--    "I'm using PostgreSQL 15 in pgAdmin 4. For each answer you provide, immediately
--     follow it up with a verification of your logic using the support documentation
--     I provided. Answer clearly either confirming you are confident or not confident
--     that your query will answer the question correctly. A simple sentence is all
--     that is needed for this final confirmation."
--
--  Run one query at a time: highlight it, then press F5.
-- ============================================================================



-- ############################################################################
-- ############################################################################
--  PART 1: Testing Claude's understanding of the database
-- ############################################################################
-- ############################################################################


-- ============================================================================
-- Q1. Which specialty has the highest prescription cost per day? Which has the lowest?
-- ============================================================================

-- [ME] Highest
SELECT p2.specialty_description,
       ROUND(SUM(p1.total_drug_cost) / SUM(p1.total_day_supply), 2) AS cost_per_day
FROM prescription AS p1
INNER JOIN prescriber AS p2 USING (npi)
GROUP BY p2.specialty_description
ORDER BY SUM(p1.total_drug_cost) / SUM(p1.total_day_supply) DESC   -- sort unrounded: two specialties round to 0.25
LIMIT 1;
-- Hematology-Oncology   35.31

-- [ME] Lowest
SELECT p2.specialty_description,
       ROUND(SUM(p1.total_drug_cost) / SUM(p1.total_day_supply), 2) AS cost_per_day
FROM prescription AS p1
INNER JOIN prescriber AS p2 USING (npi)
GROUP BY p2.specialty_description
ORDER BY SUM(p1.total_drug_cost) / SUM(p1.total_day_supply) ASC    -- sort unrounded: two specialties round to 0.25
LIMIT 1;
-- Psychologist, Clinical   0.25

-- [CLAUDE] Every specialty, ranked. Cost per day = total cost / total days supplied.
--          The drug table is NOT joined: drug_name repeats in drug, so the join would
--          double-count cost (see Part 3).
WITH specialty_totals AS (
    SELECT r.specialty_description,
           SUM(p.total_drug_cost)  AS total_cost,
           SUM(p.total_day_supply) AS total_days
    FROM prescription AS p
    INNER JOIN prescriber AS r ON r.npi = p.npi
    GROUP BY r.specialty_description
)
SELECT specialty_description,
       ROUND(total_cost / total_days, 2) AS cost_per_day,
       ROUND(total_cost, 2)              AS total_cost,
       total_days
FROM specialty_totals
ORDER BY total_cost / total_days DESC;     -- unrounded, so near-ties sort correctly
-- 92 rows. Top:    Hematology-Oncology     $35.31/day  ($171.5M over 4.86M days)
--          Bottom: Psychologist, Clinical   $0.25/day  ($76 over 309 days)
-- [CLAUDE] Verification: total_drug_cost and total_day_supply are both defined on the same
--          NPI + drug row (Methodology p.5-6), and specialty comes from prescriber joined on
--          npi (ERD). CONFIDENT.
-- [NOTE] Results matched. The lowest is a near-tie: Psychologist, Clinical is $0.2455/day
--        and Surgery $0.2511. Both come from tiny samples (1 and 3 prescription rows).
--        The AVERAGE of each row's cost/day gives the same top and bottom:
SELECT r.specialty_description,
       ROUND(AVG(p.total_drug_cost / p.total_day_supply), 2) AS avg_row_cost_per_day,
       COUNT(*) AS prescription_rows
FROM prescription AS p
INNER JOIN prescriber AS r ON r.npi = p.npi
GROUP BY r.specialty_description
ORDER BY avg_row_cost_per_day DESC;


-- ============================================================================
-- Q2. How many providers are assigned to each specialty?
-- Q3. Add a TRUE/FALSE column: has that specialty written any prescriptions?
-- ============================================================================

-- [ME] Q2
SELECT specialty_description,
       COUNT(npi) AS provider_count
FROM prescriber
GROUP BY specialty_description
ORDER BY provider_count DESC;
-- 107 specialties, 25,050 providers. Nurse Practitioner is the largest with 6,282.

-- [ME] Q3
SELECT specialty_description,
       COUNT(npi) AS provider_count,
       specialty_description IN (SELECT DISTINCT p2.specialty_description      -- specialties that
                                 FROM prescriber AS p2                         -- appear at least once
                                 INNER JOIN prescription AS p1 ON p1.npi = p2.npi) AS has_prescriptions
FROM prescriber
GROUP BY specialty_description
ORDER BY provider_count DESC;

-- [CLAUDE] Q2 + Q3 in one query. The LEFT JOIN keeps providers with no prescriptions.
WITH prescribing_npis AS (
    SELECT DISTINCT npi FROM prescription          -- every provider with at least one prescription
)
SELECT r.specialty_description,
       COUNT(*)         AS providers,
       COUNT(x.npi)     AS providers_with_rx,
       COUNT(x.npi) > 0 AS has_written_rx           -- TRUE / FALSE
FROM prescriber AS r
LEFT JOIN prescribing_npis AS x ON x.npi = r.npi
GROUP BY r.specialty_description
ORDER BY providers DESC;
-- 107 specialties: 92 TRUE, 15 FALSE.
-- [CLAUDE] Verification: each prescriber row is one NPI with one specialty_description
--          (Methodology p.4-5). A specialty is TRUE when at least one of its NPIs appears
--          in prescription. CONFIDENT.

-- [CHECK] My Q3 and Claude's Q3 agree, row for row (0 rows back = identical)
WITH mine AS (
    SELECT specialty_description, COUNT(npi) AS providers,
           specialty_description IN (SELECT DISTINCT p2.specialty_description
                                     FROM prescriber AS p2
                                     INNER JOIN prescription AS p1 ON p1.npi = p2.npi) AS has_rx
    FROM prescriber GROUP BY specialty_description
),
claude AS (
    SELECT r.specialty_description, COUNT(*) AS providers, COUNT(x.npi) > 0 AS has_rx
    FROM prescriber AS r
    LEFT JOIN (SELECT DISTINCT npi FROM prescription) AS x ON x.npi = r.npi
    GROUP BY r.specialty_description
)
(SELECT * FROM mine EXCEPT ALL SELECT * FROM claude)
UNION ALL
(SELECT * FROM claude EXCEPT ALL SELECT * FROM mine);
-- 0 rows: they match.
-- [NOTE] The database has NO indexes or keys. A correlated
--        EXISTS (SELECT 1 FROM prescription WHERE npi = r.npi) version ran for over
--        2 minutes, while both versions above finish in under a second.


-- ============================================================================
-- Q4. The specialty WITH prescriptions that has the most providers, and the
--     specialty with the most providers where NONE has written a prescription.
-- ============================================================================

-- [ME]
WITH specialty_rx AS (
    SELECT specialty_description,
           COUNT(npi) AS provider_count,
           specialty_description IN (SELECT DISTINCT p2.specialty_description
                                     FROM prescriber AS p2
                                     INNER JOIN prescription AS p1 ON p1.npi = p2.npi) AS has_prescriptions
    FROM prescriber
    GROUP BY specialty_description
)
SELECT * FROM specialty_rx WHERE has_prescriptions = TRUE  ORDER BY provider_count DESC LIMIT 1;
-- Nurse Practitioner   6,282   TRUE

WITH specialty_rx AS (
    SELECT specialty_description,
           COUNT(npi) AS provider_count,
           specialty_description IN (SELECT DISTINCT p2.specialty_description
                                     FROM prescriber AS p2
                                     INNER JOIN prescription AS p1 ON p1.npi = p2.npi) AS has_prescriptions
    FROM prescriber
    GROUP BY specialty_description
)
SELECT * FROM specialty_rx WHERE has_prescriptions = FALSE ORDER BY provider_count DESC LIMIT 1;
-- Undefined Physician type   3   FALSE

-- [CLAUDE] Both answers in one query. RANK() would also show any ties.
WITH prescribing_npis AS (
    SELECT DISTINCT npi FROM prescription
),
specialty_counts AS (
    SELECT r.specialty_description,
           COUNT(*)         AS providers,
           COUNT(x.npi) > 0 AS has_written_rx
    FROM prescriber AS r
    LEFT JOIN prescribing_npis AS x ON x.npi = r.npi
    GROUP BY r.specialty_description
),
ranked AS (
    SELECT *, RANK() OVER (PARTITION BY has_written_rx ORDER BY providers DESC) AS rnk
    FROM specialty_counts
)
SELECT has_written_rx, specialty_description, providers
FROM ranked
WHERE rnk = 1
ORDER BY has_written_rx DESC;
-- TRUE   Nurse Practitioner         6,282
-- FALSE  Undefined Physician type       3
-- [CLAUDE] Verification: builds on Q2/Q3 and ranks within the TRUE and FALSE groups.
--          CONFIDENT for the question as worded.
-- [NOTE] "Most providers" could also mean most providers who actually prescribed. Claude
--        answered the literal wording; on that other reading Nurse Practitioner still wins (5,234).
-- [NOTE] Results matched. The 15 non-prescribing specialties are all tiny (3 or fewer
--        providers): mostly roles that cannot prescribe, such as physical therapists and LPNs.


-- ============================================================================
-- Q5. Can we find prescribers who wrote a prescription for a drug to a SINGLE beneficiary?
-- ============================================================================

-- [ME] First try: look for bene_count = 1
SELECT npi, drug_name, bene_count, total_claim_count
FROM prescription
WHERE bene_count = 1;
-- 0 rows. Why?

SELECT MIN(bene_count)                          AS smallest_bene_count,   -- 11
       COUNT(*) FILTER (WHERE bene_count IS NULL) AS blank_bene_count       -- 372,306
FROM prescription;

-- [CLAUDE] Answer: NO, this data cannot answer the question.
--   * Methodology p.5: "bene_count ... Counts fewer than 11 are suppressed and are
--     indicated by a blank."
--   * Methodology p.4 and p.18: rows from fewer than 11 claims are dropped entirely.
--   So one beneficiary looks exactly like 2-10 beneficiaries: bene_count is NULL either way.
--   The closest we can get is prescriber-drug rows with 1-10 beneficiaries:
SELECT r.npi,
       r.nppes_provider_first_name,
       r.nppes_provider_last_org_name,
       r.specialty_description,
       p.drug_name,
       p.total_claim_count,
       p.bene_count                         -- NULL = suppressed, somewhere from 1 to 10
FROM prescription AS p
INNER JOIN prescriber AS r ON r.npi = p.npi
WHERE p.bene_count IS NULL
ORDER BY r.npi, p.drug_name;
-- 372,306 rows across 16,509 prescribers. These are CANDIDATES only.
-- [CLAUDE] Verification: the smallest visible bene_count is 11, as the Methodology says.
--          CONFIDENT that the question cannot be answered exactly.
-- [NOTE] Claude did provide a query, but it is honest about what the query cannot do.



-- ############################################################################
-- ############################################################################
--  PART 2: Distinct generic drugs, and having Claude categorize them
-- ############################################################################
-- ############################################################################

-- [ME]
SELECT COUNT(DISTINCT generic_name) AS distinct_generic_names
FROM drug;
-- 1,787

SELECT generic_name
FROM drug
GROUP BY generic_name
ORDER BY generic_name;
-- Saved from pgAdmin as  data/generic_names.csv  (Data Output toolbar, "Save results to file")

-- [CLAUDE]
SELECT DISTINCT generic_name
FROM drug
ORDER BY generic_name;
-- 1,787 rows, the same list.
-- [NOTE] The README says there should be 1,727. The data has 1,787. Trimming spaces and
--        ignoring case still gives 1,787, so they are not hidden duplicates:
SELECT COUNT(DISTINCT generic_name)              AS as_stored,             -- 1,787
       COUNT(DISTINCT UPPER(TRIM(generic_name))) AS trimmed_and_upper      -- 1,787
FROM drug;

-- [CLAUDE] Claude returned  data/drug_categories.csv  (generic_name, drug_category):
--          1,787 rows, 10 categories, no API key needed.
--   Anti-infectives & Vaccines 270 | Oncology, Hematology & Immunology 222 | Neurology & Psychiatry 212
--   Endocrine & Metabolic 206 | Nutrition, Fluids & Supplies 195 | Cardiovascular 185
--   Dermatology, Eye & Ear 184 | Gastrointestinal, Renal & Urologic 133
--   Pain, Anesthesia & Musculoskeletal 101 | Respiratory & Allergy 79
-- [NOTE] How Claude checked its own categories:
--   1. The drug table's own flags were used as an answer key:
--      (counts are rows in the drug table)
--      * all 91 opioid_drug_flag = 'Y' rows: Pain 90, Neurology & Psychiatry 1 (BELBUCA, a brand of buprenorphine HCl, which is
--        otherwise mainly used to treat opioid addiction)
--      * all 179 antibiotic_drug_flag = 'Y' rows: Anti-infectives 176, Dermatology/Eye 3 (topical clindamycin, ofloxacin eye/ear drops)
--      * all 59 antipsychotic_drug_flag = 'Y' rows: Neurology & Psychiatry 59
SELECT c.drug_category,
       COUNT(*) FILTER (WHERE d.opioid_drug_flag = 'Y')        AS opioids,
       COUNT(*) FILTER (WHERE d.antibiotic_drug_flag = 'Y')    AS antibiotics,
       COUNT(*) FILTER (WHERE d.antipsychotic_drug_flag = 'Y') AS antipsychotics
FROM drug AS d
INNER JOIN drug_category AS c ON c.generic_name = d.generic_name
GROUP BY c.drug_category
ORDER BY c.drug_category;
-- (Run this one after Part 3 Step 1, once the drug_category table exists.)
--   2. Two review passes found and fixed 15 mistakes before the final load:
--      * 5 caught by a test load. Example: diabetic PEN NEEDLEs had landed in Anti-infectives,
--        because the word "PEN" matched penicillin.
--      * 10 caught by an independent second Claude review of all 1,787 rows. Examples:
--        GATIFLOXACIN is only sold as an eye drop; BCG LIVE treats bladder cancer, it is not a vaccine.
--   3. Disputed rows were settled with the data itself: which specialties actually prescribe
--      each drug. For example, FLUOROURACIL is mostly prescribed by Dermatology, so it is the
--      skin cream:
SELECT r.specialty_description, COUNT(*) AS prescription_rows
FROM prescription AS p
INNER JOIN prescriber AS r ON r.npi = p.npi
WHERE p.drug_name IN (SELECT drug_name FROM drug WHERE generic_name = 'FLUOROURACIL')
GROUP BY r.specialty_description
ORDER BY prescription_rows DESC
LIMIT 3;
-- Dermatology 107, Physician Assistant 36, Nurse Practitioner 30



-- ############################################################################
-- ############################################################################
--  PART 3: Loading the CSV, then specialty x drug_category totals
-- ############################################################################
-- ############################################################################

-- ============================================================================
-- Step 1. Create the table (Claude's directions)
-- ============================================================================
-- [CLAUDE] generic_name is the key: one row per drug, exactly as in the CSV.
DROP TABLE IF EXISTS drug_category;

CREATE TABLE drug_category (
    generic_name  TEXT PRIMARY KEY,   -- matches drug.generic_name exactly
    drug_category TEXT NOT NULL
);

-- [CLAUDE] Step 2. Load the CSV in pgAdmin (no command line needed):
--   1. In the Object Explorer: prescribers > Schemas > public > Tables, then right-click (refresh
--      first if needed) drug_category > Import/Export Data...
--   2. Switch to Import, and set Filename to .../data/drug_categories.csv
--   3. Set Format to csv, Encoding to UTF8.
--   4. On the Options tab: Header ON, Delimiter ",", Quote '"'
--      (some category names contain commas, so they are quoted in the file).
--   5. Click OK. The message should read  "Successfully completed".
--
--   Command-line alternative, in pgAdmin's PSQL Tool:
--   \copy drug_category FROM '/full/path/to/drug_categories.csv' WITH (FORMAT csv, HEADER true)

-- [CLAUDE] Step 3. Check the load
SELECT COUNT(*) FROM drug_category;                       -- 1,787

SELECT COUNT(*) AS drugs_without_a_category               -- 0: every drug matched
FROM drug AS d
LEFT JOIN drug_category AS c ON c.generic_name = d.generic_name
WHERE c.generic_name IS NULL;

SELECT drug_category, COUNT(*) AS drugs
FROM drug_category
GROUP BY drug_category
ORDER BY drugs DESC;                                      -- 10 categories


-- ============================================================================
-- Step 4. total_day_supply and total_cost (as money) for each specialty / drug_category
--         combination that has results
-- ============================================================================

-- [ME] First attempt: join all four tables and group
SELECT p2.specialty_description,
       c.drug_category,
       SUM(p1.total_day_supply)        AS total_day_supply,
       SUM(p1.total_drug_cost)::MONEY  AS total_cost
FROM prescription AS p1
INNER JOIN prescriber    AS p2 ON p2.npi = p1.npi
INNER JOIN drug          AS d  ON d.drug_name = p1.drug_name
INNER JOIN drug_category AS c  ON c.generic_name = d.generic_name
GROUP BY p2.specialty_description, c.drug_category
ORDER BY p2.specialty_description, c.drug_category;
-- 697 rows. The grand total of total_cost is $3,116,214,457.86.


-- ============================================================================
-- Step 5. Described the new table to Claude and asked for the same result
-- ============================================================================
-- Prompt: "I created a table drug_category(generic_name TEXT PRIMARY KEY, drug_category TEXT)
--          loaded from the CSV you gave me. Write a query for total_day_supply and total_cost
--          (as money) for each specialty / drug_category combination that has results."

-- [CLAUDE] prescription has only drug_name, and drug_name is NOT unique in drug: 3,425 rows
--          but only 3,253 drug_names. So first reduce drug to ONE category per drug_name, then
--          join. Otherwise every prescription for a repeated drug_name is counted 2-7 times.
WITH drug_name_category AS (
    SELECT d.drug_name,
           MIN(c.drug_category) AS drug_category   -- one category per drug_name (see note on 3 names below)
    FROM drug AS d
    INNER JOIN drug_category AS c ON c.generic_name = d.generic_name
    GROUP BY d.drug_name
)
SELECT r.specialty_description,
       dc.drug_category,
       SUM(p.total_day_supply)        AS total_day_supply,
       SUM(p.total_drug_cost)::MONEY  AS total_cost
FROM prescription AS p
INNER JOIN prescriber         AS r  ON r.npi = p.npi
INNER JOIN drug_name_category AS dc ON dc.drug_name = p.drug_name
GROUP BY r.specialty_description, dc.drug_category
ORDER BY r.specialty_description, dc.drug_category;
-- 696 rows. The grand total of total_cost is $3,033,110,804.42.
-- [CLAUDE] Verification: the grand totals must equal the prescription table's own totals,
--          because every prescription row should be counted exactly once. CONFIDENT:
SELECT SUM(total_drug_cost)::MONEY AS prescription_table_cost,   -- $3,033,110,804.42  matches Claude's
       SUM(total_day_supply)       AS prescription_table_days    -- 1,523,661,845      matches Claude's
FROM prescription;
-- [NOTE] Only 3 drug_names have generics in two different categories: ERYTHROMYCIN (oral vs gel),
--        HYDROCORTISONE (tablets/rectal vs topical) and SODIUM CHLORIDE (IV vs inhaled). prescription
--        cannot tell those forms apart, so MIN() puts each one in a single category
--        (alphabetically first) instead of counting it twice.


-- ============================================================================
-- Step 6. Did the results match?  NO, and the difference is the lesson of this project.
-- ============================================================================

-- [CHECK] Side-by-side grand totals
WITH mine AS (
    SELECT SUM(p1.total_drug_cost) AS cost, SUM(p1.total_day_supply) AS days, COUNT(*) AS rows_summed
    FROM prescription AS p1
    INNER JOIN prescriber    AS p2 ON p2.npi = p1.npi
    INNER JOIN drug          AS d  ON d.drug_name = p1.drug_name
    INNER JOIN drug_category AS c  ON c.generic_name = d.generic_name
),
truth AS (
    SELECT SUM(total_drug_cost) AS cost, SUM(total_day_supply) AS days, COUNT(*) AS rows_summed
    FROM prescription
)
SELECT 'my first attempt' AS version, cost::MONEY, days, rows_summed FROM mine
UNION ALL
SELECT 'prescription table (truth)', cost::MONEY, days, rows_summed FROM truth;
-- my first attempt             $3,116,214,457.86   1,607,115,938   705,015
-- prescription table (truth)   $3,033,110,804.42   1,523,661,845   656,058
-- My first attempt overcounts by $83,103,653.44 (2.7%) and 83.5 million days, because the
-- drug join turned 656,058 prescription rows into 705,015.

-- [CHECK] Where the two versions disagree
WITH mine AS (
    SELECT p2.specialty_description, c.drug_category, SUM(p1.total_drug_cost) AS cost
    FROM prescription AS p1
    INNER JOIN prescriber    AS p2 ON p2.npi = p1.npi
    INNER JOIN drug          AS d  ON d.drug_name = p1.drug_name
    INNER JOIN drug_category AS c  ON c.generic_name = d.generic_name
    GROUP BY 1, 2
),
claude AS (
    SELECT r.specialty_description, dc.drug_category, SUM(p.total_drug_cost) AS cost
    FROM prescription AS p
    INNER JOIN prescriber AS r ON r.npi = p.npi
    INNER JOIN (SELECT d.drug_name, MIN(c.drug_category) AS drug_category
                FROM drug AS d INNER JOIN drug_category AS c ON c.generic_name = d.generic_name
                GROUP BY d.drug_name) AS dc ON dc.drug_name = p.drug_name
    GROUP BY 1, 2
)
SELECT COALESCE(m.specialty_description, c.specialty_description) AS specialty_description,
       COALESCE(m.drug_category, c.drug_category)                 AS drug_category,
       m.cost::MONEY                                              AS my_cost,
       c.cost::MONEY                                              AS claude_cost,
       (COALESCE(m.cost, 0) - COALESCE(c.cost, 0))::MONEY         AS overcount
FROM mine AS m
FULL JOIN claude AS c USING (specialty_description, drug_category)
WHERE m.cost IS DISTINCT FROM c.cost
ORDER BY COALESCE(m.cost, 0) - COALESCE(c.cost, 0) DESC;
-- 359 of 697 combinations differ. The largest overcounts are on diabetic supplies:
--   Internal Medicine / Nutrition, Fluids & Supplies   $19.8M vs $7.3M
--   Family Practice   / Nutrition, Fluids & Supplies   $19.3M vs $7.0M
-- That is because drug_names like INSULIN SYRINGE map to 7 generic_names each.
-- One combination (Surgical Oncology / Dermatology, Eye & Ear) appears ONLY in my version:
-- a single ERYTHROMYCIN prescription row was counted under BOTH erythromycin generics
-- (tablets and gel), so it showed up in two categories.

-- [CHECK] The cause, in one query: drug_names that appear more than once in drug
SELECT drug_name, COUNT(*) AS rows_in_drug_table
FROM drug
GROUP BY drug_name
HAVING COUNT(*) > 1
ORDER BY rows_in_drug_table DESC;
-- 120 drug_names. Top: SODIUM CHLORIDE 7, INSULIN SYRINGE 7, ULTICARE 6, then several at 5

-- [NOTE] FINAL ANSWER for Part 3 = Claude's query in Step 5. It is the version whose totals
--        reconcile exactly with the prescription table.


-- ============================================================================
-- Bonus: what the final table says
-- ============================================================================
-- [CLAUDE] Biggest specialty / category combinations by cost
WITH drug_name_category AS (
    SELECT d.drug_name, MIN(c.drug_category) AS drug_category
    FROM drug AS d INNER JOIN drug_category AS c ON c.generic_name = d.generic_name
    GROUP BY d.drug_name
)
SELECT r.specialty_description,
       dc.drug_category,
       SUM(p.total_day_supply)       AS total_day_supply,
       SUM(p.total_drug_cost)::MONEY AS total_cost
FROM prescription AS p
INNER JOIN prescriber         AS r  ON r.npi = p.npi
INNER JOIN drug_name_category AS dc ON dc.drug_name = p.drug_name
GROUP BY r.specialty_description, dc.drug_category
ORDER BY SUM(p.total_drug_cost) DESC
LIMIT 10;
-- Top 5:
-- Neurology / Neurology & Psychiatry                       $165.8M
-- Hematology-Oncology / Oncology, Hematology & Immunology  $163.4M
-- Internal Medicine / Endocrine & Metabolic                $155.8M
-- Family Practice / Endocrine & Metabolic                  $149.9M
-- Cardiology / Cardiovascular                              $123.2M
