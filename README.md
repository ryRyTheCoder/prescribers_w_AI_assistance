# AI-Assisted Prescribers Project

In this exercise, you'll be working with Claude.  At the end of the Project you will push up your SQL file.  Use comments to distinguish your code from Claude's.  Also, use comments to cite anything interesting or surprising.  IMPORTANT:  This is not a SQL assessment.  I will not be looking for errors in your SQL queries.  I will be looking for how Claude was used to assist you in finding a solution.

### Part 1

We will provide Claude the documentation that would best equip Claude to be helpful.

* Send the "Prescriber_Methodology" and "ERD" to Claude as an attachment and explain which version of SQL you are using.  Also describe how you would like Claude to verify the query it provides. (Remember, LLMs do not know if they are confident in their answer until they provide it.)  You verification statement can be something like this: "For each answer you provide immediately follow it up with a verification of your logic using the support documentation I provided.  Answer clearly either confirming you are confident or not confident that your query will answer the question correctly. A simple sentence is all that is needed for this final confirmation."

* We will start with a simple query to test Claude's understanding of the database.  
  * I suggest you write the code first for each of these and then have Claude attempt it.  Compare answers to verify.

- Which specialty has the highest prescription cost per day?  Which has the lowest?

* Was Claude confident in its ability to answer this?
* Did your results match?

- How many providers are assigned to each specialty.
- Next, add an additional "TRUE/FALSE" column that states if that specialty has written any prescriptions.
- Finally, find the specialty that has written a prescription with the most providers.  Then find the specialty with the most providers where none has written a prescription.

* Was the verification step able to tell you which queries Claude was confident in?
* Was Claude able to match your code for each of these?


* Read the Prescriber_Methodology section on bene_count (Page 5).  It will describe the limitations on available data.

- Are we able to find which prescribers who have written prescriptions for a drug to only a single beneficiary?
- Does Claude provide a query?
- Did the verification step confirm confidence?


### Part 2

- Write a query to get a list of each distinct generic_name on the drug table (1727 distinct drugs).
- Save this output as a .csv
- Provide Claude with this .csv
- Ask Claude to categorize these drugs into 10 or fewer categories and provide you with a csv.  If it wants an API key, just say you only want a .csv with each generic_name and which category in which it belongs. (This step will take some time.  Make a coffee.  ~5 mins)
- Download the csv


### Part 3

* Ask Claude how you can incorporate your csv into the prescribers database.  Follow the directions to create a table and load the .csv.

- Write a query that uses the table you just created to find out the total_day_supply and total_cost(in money) for each specialty/drug_category combination that has results.
- Now, describe the new table you created to Claude and ask it to provide you with a query the provided the same result.

- Did the results match?


Push up your SQL script.
