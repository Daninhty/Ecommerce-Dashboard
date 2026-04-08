-- cek database
select * from dbo.ecs

-- unique customer
select
	count(distinct CustomerID) as 'Unique Customer'
from dbo.ecs

-- revenue
select
	sum(Total) as Revenue
from dbo.ecs

-- spending per customer
select top 10
	CustomerID,
	sum(Total) as Spending
from dbo.ecs
group by CustomerID
order by sum(Total) desc

-- average order value
select top 10
	CustomerID,
	sum(Total)/count(InvoiceNo) as 'Average Order Value'
from dbo.ecs
group by CustomerID
order by sum(Total)/count(InvoiceNo) desc

-- RFM analysis
with base as (
	select
		CustomerID,
		InvoiceNo,
		Date,
		Total as Revenue
	from dbo.ecs
),
rfm as (
	select
		CustomerID,
		max(Date) as LastPurchaseDate,
		count(distinct InvoiceNo) as Frequency,
		sum(Revenue) as Monetary,
		datediff(day, max(date), (select max(date) from base)) as Recency
	from base
	group by CustomerID
)
select * 
into RFM_Table
from rfm

select * from RFM_Table

-- RFM scoring
with scored as (
	select *,
		ntile(5) over (order by recency desc) as R_Score,
		ntile(5) over (order by Frequency) as F_Score,
		ntile(5) over (order by Monetary) as M_Score
	from RFM_Table
)
select *,
	concat(R_score, F_Score, M_Score) as RFM_Score
into RFM_Scored
from scored

select * from RFM_Scored

-- customer segmentation
select *,
    case
		when R_Score >= 4 and F_Score <= 2 then 'New Customer'
        when R_Score = 5 and F_Score >= 4 and M_Score >= 4 then 'Champions'
        when R_Score >= 4 and F_Score >= 4 and M_Score >= 3 then 'Loyal Customers'
		when R_Score >= 3 and F_Score >= 2 and M_Score >= 3 then 'Potential Loyalist'
		when R_Score <= 2 and M_Score >= 4 then 'Cant Lose Them'
		when R_Score = 3 and F_Score >= 3 then 'Need Attention'
		when R_Score <= 2 and F_Score >= 3 then 'At Risk'
		when R_Score = 2 and F_Score <= 2 then 'About to Sleep'
        when R_Score = 1 and F_Score <= 2 then 'Lost Customers'
        else 'Others'
    end as Segment
into RFM_Final
from RFM_Scored

select * from RFM_Final
drop table RFM_Final

-- customer per segment
select
	segment,
	count(*) as 'Total Customer'
from RFM_Final
group by Segment
order by 'Total Customer' desc

-- revenue per segment
select
	segment,
	sum(monetary) as 'Total Revenue'
from RFM_Final
group by segment
order by 'Total Revenue' desc

-- RFM per segment
select 
	segment,
	avg(recency) as 'Average Recency',
	avg(frequency) as 'Average Frequency',
	avg(monetary) as 'Average Monetary'
from RFM_Final
group by segment
order by 'Average Monetary' desc

-- Cohort --
create view dbo.CohortRetention as
with first_purchase as (
    select 
        CustomerID,
        min(Date) as FirstPurchaseDate
    from dbo.ecs
    where Quantity > 0
    group by CustomerID
),

cohort_base as (
    select 
        t.CustomerID,
        datefromparts(year(fp.FirstPurchaseDate), month(fp.FirstPurchaseDate), 1) as CohortMonth,
        datefromparts(year(t.Date), month(t.Date), 1) as TransactionMonth
    from dbo.ecs t
    join first_purchase fp 
        on t.CustomerID = fp.CustomerID
    where t.Quantity > 0
),

cohort_index as (
    select
        CustomerID,
        CohortMonth,
        TransactionMonth,
        datediff(month, CohortMonth, TransactionMonth) as MonthIndex
    from cohort_base
),

filtered_cohort as (
    select *
    from cohort_index
    where MonthIndex <= 13
),

cohort_agg as (
    select
        CohortMonth,
        MonthIndex,
        count(distinct CustomerID) as TotalCustomer
    from filtered_cohort
    group by CohortMonth, MonthIndex
),

cohort_size as (
    select
        CohortMonth,
        count(distinct CustomerID) as CohortSize
    from filtered_cohort
    where MonthIndex = 0
    group by CohortMonth
)

select
    c.CohortMonth,
    c.MonthIndex,
    c.TotalCustomer,
    s.CohortSize,
    cast(c.TotalCustomer * 1.0 / s.CohortSize as decimal(5,2)) as RetentionRate
from cohort_agg c
join cohort_size s 
    on c.CohortMonth = s.CohortMonth

select * into dbo.Cohort
from dbo.CohortRetention