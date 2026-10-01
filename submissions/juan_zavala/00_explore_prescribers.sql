-- ============================================================================
-- 00_explore_prescribers.sql  -  first look at the prescribers database
-- [Claude] Written by Claude as a data-profiling checklist. Run in a Query Tool
-- on the  prescribers  database: highlight ONE query, press F5.
-- Numbers in comments are what the class backup returns.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- STEP 1. What tables exist and how big are they?
-- ---------------------------------------------------------------------------

-- 1a. Tables with their on-disk size (8 tables; prescription is by far the biggest)
SELECT relname AS table_name,
       pg_size_pretty(pg_total_relation_size(relid)) AS size
FROM pg_catalog.pg_statio_user_tables
ORDER BY pg_total_relation_size(relid) DESC;

-- 1b. Exact row counts
SELECT 'prescription' AS tbl, COUNT(*) FROM prescription      -- 656,058
UNION ALL SELECT 'zip_fips',        COUNT(*) FROM zip_fips    --  54,181
UNION ALL SELECT 'prescriber',      COUNT(*) FROM prescriber  --  25,050
UNION ALL SELECT 'drug',            COUNT(*) FROM drug        --   3,425
UNION ALL SELECT 'fips_county',     COUNT(*) FROM fips_county --   3,272
UNION ALL SELECT 'cbsa',            COUNT(*) FROM cbsa        --   1,238
UNION ALL SELECT 'overdose_deaths', COUNT(*) FROM overdose_deaths -- 380
UNION ALL SELECT 'population',      COUNT(*) FROM population  --      95
ORDER BY 2 DESC;


-- ---------------------------------------------------------------------------
-- STEP 2. What columns and types does each table have?
-- ---------------------------------------------------------------------------

-- 2a. Every column in the database, grouped by table
SELECT table_name, ordinal_position, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
ORDER BY table_name, ordinal_position;

-- 2b. Are there primary keys / foreign keys / indexes?  (Answer here: none at all.
--     So the database will NOT stop duplicates or bad joins; you must check them.)
SELECT conrelid::regclass AS table_name, conname, contype
FROM pg_constraint
WHERE connamespace = 'public'::regnamespace;


-- ---------------------------------------------------------------------------
-- STEP 3. Look at real rows
-- ---------------------------------------------------------------------------
SELECT * FROM prescriber   LIMIT 10;
SELECT * FROM prescription LIMIT 10;
SELECT * FROM drug         LIMIT 10;


-- ---------------------------------------------------------------------------
-- STEP 4. Find the GRAIN: what makes one row unique?  (most important step)
-- ---------------------------------------------------------------------------

-- 4a. prescriber: one row per npi?   25,050 rows, 25,050 npis -> yes, npi is the key
SELECT COUNT(*) AS rows, COUNT(DISTINCT npi) AS distinct_npi FROM prescriber;

-- 4b. drug: one row per drug_name?   3,425 rows but only 3,253 drug_names -> NO
--     The same drug_name can map to several generic_names.
SELECT COUNT(*) AS rows,
       COUNT(DISTINCT drug_name)    AS distinct_drug_name,
       COUNT(DISTINCT generic_name) AS distinct_generic_name   -- 1,787 (README says 1,727)
FROM drug;

-- 4c. Which drug_names repeat?
SELECT drug_name, COUNT(*) AS rows, STRING_AGG(generic_name, ' | ') AS generics
FROM drug
GROUP BY drug_name
HAVING COUNT(*) > 1
ORDER BY rows DESC;

-- 4d. WHY IT MATTERS: joining prescription to drug on drug_name multiplies rows.
--     656,058 prescription rows become 705,015 after the join, so SUMs of cost
--     would be inflated. Compare these two numbers:
SELECT (SELECT COUNT(*) FROM prescription)                           AS prescription_rows,
       (SELECT COUNT(*) FROM prescription JOIN drug USING (drug_name)) AS rows_after_join;

-- 4e. prescription: one row per npi + drug_name?  Not quite (1,925 pairs repeat,
--     because one drug_name can be several formulations).
SELECT COUNT(*) AS rows, COUNT(DISTINCT (npi, drug_name)) AS distinct_pairs FROM prescription;


-- ---------------------------------------------------------------------------
-- STEP 5. Do the joins line up? (orphans in either direction)
-- ---------------------------------------------------------------------------

-- 5a. Prescriptions whose npi is missing from prescriber (0)
SELECT COUNT(*) FROM prescription p
WHERE NOT EXISTS (SELECT 1 FROM prescriber r WHERE r.npi = p.npi);

-- 5b. Prescriptions whose drug_name is missing from drug (0)
SELECT COUNT(*) FROM prescription p
WHERE NOT EXISTS (SELECT 1 FROM drug d WHERE d.drug_name = p.drug_name);

-- 5c. Prescribers with NO prescriptions at all (4,458) -> matters for Part 1's TRUE/FALSE column
SELECT COUNT(*) FROM prescriber r
WHERE NOT EXISTS (SELECT 1 FROM prescription p WHERE p.npi = r.npi);


-- ---------------------------------------------------------------------------
-- STEP 6. Profile the important columns
-- ---------------------------------------------------------------------------

-- 6a. Scope: every prescriber is in Tennessee
SELECT nppes_provider_state, COUNT(*) FROM prescriber GROUP BY 1;

-- 6b. Specialties (107) and how many providers each has
SELECT specialty_description, COUNT(*) AS providers
FROM prescriber
GROUP BY 1
ORDER BY providers DESC;

-- 6c. NULLs and suppression in prescription.
--     bene_count is NULL on 372,306 rows and is never below 11:
--     CMS hides counts of 1-10 for privacy (Methodology PDF, p.5).
SELECT COUNT(*)                                       AS rows,
       COUNT(*) FILTER (WHERE bene_count IS NULL)     AS bene_count_null,
       MIN(bene_count)                                AS min_bene_count,
       MIN(total_claim_count)                         AS min_claims,
       COUNT(*) FILTER (WHERE total_drug_cost IS NULL) AS cost_null
FROM prescription;

-- 6d. Range and spread of the money / supply columns
SELECT MIN(total_drug_cost), MAX(total_drug_cost), ROUND(AVG(total_drug_cost), 2) AS avg_cost,
       MIN(total_day_supply), MAX(total_day_supply)
FROM prescription;

-- 6e. Drug flags
SELECT opioid_drug_flag, antibiotic_drug_flag, antipsychotic_drug_flag, COUNT(*)
FROM drug
GROUP BY 1, 2, 3
ORDER BY 4 DESC;


-- ---------------------------------------------------------------------------
-- STEP 7. Geography tables: watch the data types
-- ---------------------------------------------------------------------------

-- 7a. overdose_deaths.fipscounty is INTEGER, but fips_county / population / zip_fips
--     store it as TEXT. Join with a cast:
SELECT f.county, o.year, o.overdose_deaths
FROM overdose_deaths AS o
JOIN fips_county     AS f ON f.fipscounty = o.fipscounty::text
ORDER BY o.overdose_deaths DESC
LIMIT 10;

-- 7b. Years covered (2015-2018) and counties (95 = every TN county)
SELECT MIN(year), MAX(year), COUNT(DISTINCT fipscounty) FROM overdose_deaths;
