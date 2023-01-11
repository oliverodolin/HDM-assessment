-----------------------------  READ ME -------------------------------------------

-- This code was used to pull data, as tables, from the MIMIC-iii database stored on a postgresql server. The output tables of each query (excluding views, 
-- which remained on the database) were downloaded as csv. files and placed into a "data" folder, with subfolders "Q1-5". This data was then used in an 
-- .Rmd file for plot and table generation for the final report. 

----- SETUP ------

--To ensure that the queries below run successfully, copy over all of the code from a question section (e.g., all of the code between
-- "QUERIES TO ANSWER QUESTION 1" and "QUERIES TO ANSWER QUESTION 2", including the optional "COMMENTS" section)

--Make sure that the  --- SET search_path TO mimiciii; --- code is present
--Make sure to create any views (present immediately after setting the search path) before running any of the subsequent queries

-- Running this code is contingent on the ability to create a views in a seperate schema called "public". This was present on my
-- postgreSQL setup but may not be present on yours. Make sure to create a schema called "public" under the same database where the "mimiciii"
-- schema is stored, and then the code should (hopefully!) work.


-- Query outputs needs to be manually saved as .csv files into a data folder. Comments above each query instruct the user on where to 
-- manually save each table, and what to name it. Doing this correctly is CRUCIAL to ensuring that subsequent analysis in the .Rmd file will be successful!

-----------------------------  QUERIES TO ANSWER QUESTION 1 -------------------------------------------

SET search_path TO mimiciii;

-- gets the hadm_id and subject_id for the most recent visit where Simvastatin was prescribed for patient 42130
-- stores this data in a view in the public database
drop view if exists public.query_ids1;
create view public.query_ids1 as 
	(select subject_id, hadm_id from prescriptions
	where subject_id = 42130
		and drug like '%Simvastatin%'
	order by startdate DESC
	limit 1);


-- get demographic data from patients and admissions tables.
-- Save to "~/data/Q1/demographics.csv"
select p.gender,
		-- calculate age from hospital admit time minus dob, cast to integer days and convert to years by dividing by 365
		(cast(a.admittime as date) - cast(p.dob as date)) / 365 as admission_age_years,
		a.language, 
		a.religion, 
		a.marital_status, 
		a.ethnicity 
	from patients p
	right join admissions a
		on p.subject_id = a.subject_id
	where p.subject_id = (select subject_id from public.query_ids1)
		and a.hadm_id = (select hadm_id from public.query_ids1);


-- get stay times for entire hospital stay and for time spent in the icu within that stay.
-- Save to "~/data/Q1/stay_times.csv"
select
		extract(epoch from (a.dischtime - a.admittime)) / 86400 as exact_los_in_hospital_days,
		extract(epoch from (sum(i.outtime - i.intime))) / 86400 as exact_los_in_icu_days
	from admissions a
	right join icustays i
		on a.hadm_id = i.hadm_id
	where a.hadm_id = (select hadm_id from public.query_ids1)
	group by exact_los_in_hospital_days;


-- get list of wards visited grouped by unit.
-- Save to "~/data/Q1/unique_wards_visited_by_careunit.csv"
select curr_careunit, curr_wardid from transfers
	where hadm_id = (select hadm_id from public.query_ids1)
		and curr_wardid is not null
		order by curr_wardid;

-- get list of diagnoses associated with a hospital admission.
-- Save to "~/data/Q1/icd9_codes_in_sequence_order.csv"
select code.icd9_code, dict.long_title from diagnoses_icd code
	inner join d_icd_diagnoses dict
		on code.icd9_code = dict.icd9_code
	where code.hadm_id = (select hadm_id from public.query_ids1)
	order by code.seq_num ASC; -- orders the diagnoses by the priority of the code


-- get a list of all of the prescriptions associated with a hospital admission.
-- Save to "~/data/Q1/prescriptions.csv"
select drug from prescriptions p
	where p.hadm_id = (select hadm_id from public.query_ids1)
	group by drug
	order by drug ASC;



-----------------------------  QUERIES TO ANSWER QUESTION 2 -------------------------------------------
SET search_path TO mimiciii;

-- this stores the most recent hospital admission and subject id (42130) where the patient specifically took simvastatin
-- I need this hadm_id to get the relevant quantitative routine vital signs
drop view if exists public.query_ids2;
create view public.query_ids2 as 
	(select subject_id, hadm_id from prescriptions
	where subject_id = 42130
		and drug like '%Simvastatin%'
	order by startdate DESC -- ensure that the ids associated with the most recent startdate for simvastatin are stored.
	limit 1);


-- grabs several routine vital signs and puts them all in one table, with code/name, timestamp, and value (without units).
-- Save to "~/data/Q2/routine_vital_sign_measures.csv"
select c.charttime, c.valuenum, c.itemid, dict.label from chartevents c
	inner join d_items dict
		on c.itemid = dict.itemid
	where hadm_id = (select hadm_id from public.query_ids2)
		and (c.itemid = 220045
			or c.itemid = 220277
			or c.itemid = 220179
			or c.itemid = 220180
			or c.itemid = 220210
			or c.itemid = 223761
			or c.itemid = 220050
			or c.itemid = 220051)
	order by c.itemid, dict.label, c.charttime;



--------COMMENTS/EXTRA CODE--------

-- this returns the number of unique measurements made for each type of routine vital signs that was taken
-- I used this code to figure out which Routine Vital Signs I needed to pull to a table.

-- select dict.label, count(c.itemid) as unique_measures from chartevents c
-- 		inner join d_items dict
-- 			on c.itemid = dict.itemid
-- 	where hadm_id = (select hadm_id from public.query_ids2)
-- 		and dict.category = 'Routine Vital Signs'
-- 	group by dict.label;


-----------------------------  QUERIES TO ANSWER QUESTION 3 -------------------------------------------
SET search_path TO mimiciii;


-- stores all relevant subject, hadm, and icustay ids -- e.g., all admissions where the patient has a cardiac device, 
-- is between 60 and 65, and has an icu visit.
drop view if exists public.query_ids3;
create view public.query_ids3 as 
	(with age_range_ids --finds subject and hadm id from all patients of the right age
	as
	(select a.subject_id, a.hadm_id from admissions a
		left join patients p
			on a.subject_id = p.subject_id
	where (extract (year from age(a.admittime, p.dob))) between 60 and 65),

	age_range_and_icu_visit_ids -- finds all of the patients from the CTE above who have actually visited the icu and stores their icustay_ids
	as
	(select a.subject_id, a.hadm_id, i.icustay_id from age_range_ids a
		right join icustays i
			on a.hadm_id = i.hadm_id
		where i.icustay_id is not null)

	select distinct a.* from age_range_and_icu_visit_ids a -- if this isn't distinct, then you get repeats because some admissions are associated with multiple qualifying diagnoses
		inner join diagnoses_icd d
			on a.hadm_id = d.hadm_id
		where d.icd9_code like 'V450%'
		order by a.subject_id);


-- Save to "~/data/Q3/visit_lengths_by_gender_and_icu_death.csv"
with total_visit_times as -- finds total visit length for all relevant hospital admissions
	(select distinct a.hadm_id, a.dischtime - a.admittime as total_hospital_visit_length from admissions a
		inner join public.query_ids3 qi
			on a.hadm_id = qi.hadm_id
			order by a.hadm_id),

	total_icu_visit_times as -- finds total (summed) icu visit time for all relevant hospital admissions
		(select i.hadm_id, sum(i.outtime - i.intime) as total_icu_visit_time from icustays i
			inner join public.query_ids3 qi
				on i.icustay_id = qi.icustay_id
				group by i.hadm_id
				order by i.hadm_id),

	gender_data as -- finds the gender of the patient for every relevant hospital admission (so a subject with two distinct admissions would have two rows with their gender logged in each)
		(select distinct qi.hadm_id, p.gender from public.query_ids3 qi
			inner join patients p
				on qi.subject_id = p.subject_id),

	-- need to clean this one up
	-- this creates a CTE which lists the relevant hospital admission and whether the patient died in the ICU (as a boolean value)
	icu_death_flags as
		(with dods as -- this grabs all of the relevant ids and the patient date of death (dod)
			(select qi.*, p.dod from public.query_ids3 qi
			inner join patients p
			on qi.subject_id = p.subject_id
			order by qi.subject_id, qi.hadm_id),

			bounds as -- this establishes the bounds that a dod must fall in for an icu death for every relevant icustay_id
				(select qi.icustay_id, i.intime - interval '6 hours' as lower_bound, i.outtime + interval '6 hours' as upper_bound from public.query_ids3 qi -- criteria for death in the ICU
				inner join icustays i
					on qi.icustay_id = i.icustay_id),

			ticker as -- this flags any relevant icustays (and associated hospital admission ids) where the patient died
				(select d.hadm_id, d.icustay_id,
					case
						when d.dod >= b.lower_bound and d.dod <= b.upper_bound then 1
						else 0
					end as icu_death_ticker
					from dods d
					inner join bounds b
						on d.icustay_id = b.icustay_id
					order by hadm_id)

		select hadm_id, -- this sums together the ticker above for each hospital admission, to determine whether a death occurred in a given hospital admission
			case
				when sum(icu_death_ticker) >= 1 then TRUE
				else FALSE
			end as icu_death
			from ticker
			group by hadm_id),

	all_visit_times as -- this stiches together all of the relevant information (hospital and total icu visit lengths) and the relevant data (gender/icu_death) needed to stratify that data
		(select g.gender, df.icu_death, h.total_hospital_visit_length, i.total_icu_visit_time from total_visit_times h
			inner join total_icu_visit_times i
				on h.hadm_id = i.hadm_id
			inner join gender_data g
				on h.hadm_id = g.hadm_id
			inner join icu_death_flags df
				on h.hadm_id = df.hadm_id)

	select gender, icu_death, -- goes through the CTE above and extracts min/max, Q1, Q3, and median (AKA Q2), stratified by gender and icu_death
		extract(epoch from (percentile_cont(0) within group (order by total_hospital_visit_length))) / 86400 as min_hospital_visit_length,
		extract(epoch from (percentile_cont(0.25) within group (order by total_hospital_visit_length))) / 86400 as Q1_hospital_visit_length,
		extract(epoch from (percentile_cont(0.5) within group (order by total_hospital_visit_length))) / 86400 as median_hospital_visit_length,
		extract(epoch from (percentile_cont(0.75) within group (order by total_hospital_visit_length))) / 86400 as Q3_hospital_visit_length,
		extract(epoch from (percentile_cont(1) within group (order by total_hospital_visit_length))) /86400 as max_hospital_visit_length,

		extract(epoch from (percentile_cont(0) within group (order by total_icu_visit_time))) / 86400 as min_icu_visit_length,
		extract(epoch from (percentile_cont(0.25) within group (order by total_icu_visit_time))) / 86400 as Q1_icu_visit_length,
		extract(epoch from (percentile_cont(0.5) within group (order by total_icu_visit_time))) / 86400 as median_icu_visit_length,
		extract(epoch from (percentile_cont(0.75) within group (order by total_icu_visit_time))) / 86400 as Q3_icu_visit_length,
		extract(epoch from (percentile_cont(1) within group (order by total_icu_visit_time))) / 86400 as max_icu_visit_length
		from all_visit_times
		group by gender, icu_death;



--------COMMENTS--------
-- sometimes the total icustay length is greater than the overall admissions length.
-- As you can see below, this is not an error (or, if it is, it is because of incorrect data entry)
-- select a.admittime, a.dischtime, i.intime, i.outtime from admissions a
-- 	inner join icustays i
-- 		on a.hadm_id = i.hadm_id
-- 	where i.icustay_id = 267089;

-- here's code you can use in the large block above to see which rows have a larger icustay length than admissions length.
-- select tv.*, i.total_icu_visit_time,
-- 	case
-- 	when tv.total_hospital_visit_length < i.total_icu_visit_time then 1
-- 	else 0
-- 	end as sanity_check
-- 	from total_visit_times tv
-- 	inner join total_icu_visit_times i
-- 		on tv.hadm_id = i.hadm_id;

-- select * from all_visit_times	
-- running into an issue, one of the rows has a hospital visit time that is longer than their icu visit times . . .


-----------------------------  QUERIES TO ANSWER QUESTION 4 -------------------------------------------
SET search_path TO mimiciii;

-- finds the subject, hospital admission, and icustay ids where patients were 60-65 years, had a cardiac device, and died in the icu
drop view if exists public.query_ids4;
create view public.query_ids4 as 
	(with age_range_ids -- selects subject and hospital admission ids that meet the age criteria
	as
	(select a.subject_id, a.hadm_id from admissions a
		left join patients p
			on a.subject_id = p.subject_id
		where (extract (year from age(a.admittime, p.dob))) between 60 and 65),

	age_range_and_icu_visit_ids -- adds in the icustay ids associated with these subject/hospital admission ids. Narrows down the current set of sub/hadm ids to those that actually have associated icustays. 
	as
	(select a.subject_id, a.hadm_id, i.icustay_id from age_range_ids a
		right join icustays i
			on a.hadm_id = i.hadm_id
		where i.icustay_id is not null),

	all_ids -- narrows down the subj/hadm ids down to those that are associated with a pacemaker ICD9 code.
	as
	(select distinct a.* from age_range_and_icu_visit_ids a -- if this isn't distinct, then you get repeats because some admissions are associated with multiple qualifying diagnoses (e.g., multiple pacemaking codes)
		inner join diagnoses_icd d
			on a.hadm_id = d.hadm_id
		where d.icd9_code like 'V450%'
		order by a.subject_id),

	icu_death_flags -- simple table with icustay ids and boolean column identifying the icustay ids where the patient died in the icu
	as
	(select
			 qi.icustay_id,
			case
				when p.dod between (i.intime - interval '6 hours') and (i.outtime + interval '6 hours') then TRUE
				else FALSE
			end as icu_death
		from all_ids qi
		inner join patients p
		on qi.subject_id = p.subject_id
		inner join icustays i
			on qi.icustay_id = i.icustay_id
		order by qi.subject_id, qi.hadm_id)

	select qi.* from all_ids qi -- selects relevant subject/hadm/icustay ids where the patient died in the icu
	inner join icu_death_flags i
		on qi.icustay_id = i.icustay_id
	where icu_death = TRUE);


-- grabs subject id, their first careunit, gender, age, total_days in ICU, and a list of the top 3 highest priority icd9 diagnoses and codes from that visit
-- Save to "~/data/Q4/icu_death_patients_data.csv"
select qi.subject_id,
	i.first_careunit,
	p.gender,
	(extract (year from age(a.admittime, p.dob))) as age,
	i.los as total_days_in_ICU, -- could also do this using i.outtime - i.intime
	string_agg(concat(dict.long_title, ' (', d.icd9_code, ')'), ', ') as icd9_diagnoses_and_codes -- adds together code and title in one column, and then clumps together all the rows in that column that match on everything else except for the code+title column
	from public.query_ids4 qi
	inner join icustays i
		on qi.icustay_id = i.icustay_id
	inner join patients p
		on qi.subject_id = p.subject_id
	inner join admissions a
		on qi.hadm_id = a.hadm_id
	inner join diagnoses_icd d
		on qi.hadm_id = d.hadm_id
	inner join d_icd_diagnoses dict
		on d.icd9_code = dict.icd9_code
	where d.seq_num <= 3 -- only grab top 3 priority codes.
	group by qi.subject_id, i.first_careunit, p.gender, age, total_days_in_ICU; -- need to group like this so that array_agg puts all the codes and titles into one row



-----------------------------  QUERIES TO ANSWER QUESTION 5 -------------------------------------------

SET search_path TO mimiciii;


-- Save to "~/data/Q5/mean_icustay_times_by_subgroups.csv"
-- FINDING DATA FOR PATIENT GROUPS
with icu_time_by_admission
-- for every hospital admission id, finds the total time spent at each ICU (even across multiple visits to that ICU within a given hadm_id)
	as
		(select t.hadm_id, t.curr_careunit, extract(epoch from (sum(t.outtime - t.intime))) / 86400 as icustay_per_admission from transfers t
			where t.curr_careunit is not NULL
				and t.curr_careunit not LIKE '%NWARD%'
			group by t.hadm_id, t.curr_careunit),
	
	-- does the same thing as icu_time_by_admission but for the subgroup of hospital admissions where age is 60-65 and the patient has a cardiac device
	cardiac_device_and_age_range
	as
		(select distinct i.* from icu_time_by_admission i
			inner join admissions a
				on i.hadm_id = a.hadm_id
			inner join patients p
				on a.subject_id = p.subject_id
			inner join diagnoses_icd d
				on i.hadm_id = d.hadm_id
			where extract(year from age(a.admittime, p.dob)) between 60 and 65
			and d.icd9_code like 'V450%'),

	-- finds the hadm_ids within cardiac_device_and_age_range that received simvastatin during their hospital admission 
	simvastatin_ids
	as
		(select distinct cd.* from cardiac_device_and_age_range cd
			inner join prescriptions p
				on cd.hadm_id = p.hadm_id
			where drug like '%Simvastatin%'), -- is simvastatin coded/recorded in any other way?

	-- adds a column to cardiac_device_and_age_range to establish which hadm_ids were/weren't given simvastatin.
	simvastatin_boolean
	as
		(select cd.*,
				case
					when hadm_id in (select hadm_id from simvastatin_ids) then TRUE
					else FALSE
				end as simvastatin_boolean
			 from cardiac_device_and_age_range cd),
	


	-- FINDING MEANS
	-- finds the mean time spent at each ICU across admissions
	mean_icu_time_by_admission
	as
		(select curr_careunit,
			avg(icustay_per_admission) as mean_icustay_per_admission
			from icu_time_by_admission
			group by curr_careunit
		union
		select 'All ICUs' as curr_careunit, avg(icustay_per_admission) as mean_icustay_per_admission
			from icu_time_by_admission),

	-- finds the mean time spent at each ICU across admissions, within the subgroup identified in the CTE above
	mean_cardiac_device_and_age_range
	as
		(select curr_careunit,
			avg(icustay_per_admission) as cd_and_age_avg_icustay_per_admission
			from simvastatin_boolean
			group by curr_careunit
		union
		select 'All ICUs' as curr_careunit, avg(icustay_per_admission) as cd_and_age_avg_icustay_per_admission
			from simvastatin_boolean),

	-- finds the mean time spent at each ICU across admissions, within the subgroup identified in the CTE above
	mean_simvastatin_group
	as
		(select curr_careunit,
			avg(icustay_per_admission) as simvastatin_avg_icustay_per_admission
			from simvastatin_boolean
			where simvastatin_boolean = TRUE
			group by curr_careunit
		union
		select 'All ICUs' as curr_careunit, avg(icustay_per_admission) as simvastatin_avg_icustay_per_admission
			from simvastatin_boolean
			where simvastatin_boolean = TRUE),


	-- finds the mean time spent at each ICU across admissions, within the subgroup identified in the CTE above
	mean_no_simvastatin_group
	as
		(select curr_careunit,
			avg(icustay_per_admission) as no_simvastatin_avg_icustay_per_admission
			from simvastatin_boolean
			where simvastatin_boolean = FALSE
			group by curr_careunit
		union
		select 'All ICUs' as curr_careunit, avg(icustay_per_admission) as no_simvastatin_avg_icustay_per_admission
			from simvastatin_boolean
			where simvastatin_boolean = FALSE)


-- grabs all of the mean times per admission spent across the different groups and subgroups of admissions identified in the CTES above and places them in one table.
-- times are in days.
select i.curr_careunit,
	mean_icustay_per_admission,
	cd_and_age_avg_icustay_per_admission,
	simvastatin_avg_icustay_per_admission,
	no_simvastatin_avg_icustay_per_admission
	from mean_icu_time_by_admission i
	full join mean_cardiac_device_and_age_range cd
		on i.curr_careunit = cd.curr_careunit
	full join mean_simvastatin_group s
		on i.curr_careunit = s.curr_careunit
	full join mean_no_simvastatin_group ns
		on i.curr_careunit = ns.curr_careunit;



-----------------------------  END OF CODE -------------------------------------------