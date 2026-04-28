/* HNL - 29.10.2020 */ /*Dette program er skrevet af Helene og lånt af LLZ og rettet til*/
/* Upload LMDB til Oracle (STATPROD.D221919) */
/*Opdateret LMDB 21.09.2023 så data er ultimo 2022*/
/*Opdateret LMDB 15.01.2024 så data er ultimo juni 2023*/
/*Opdateret LMDB 12.07.2024 så data er ultimo december 2023*/
/*Opdateret LMDB 19.01.2026 så data er ultimo december 2024 gemt i LMDB_ALL2024*/

/*Udfordringer med at tømme LMDB_ALL tabellen via explicit passthrough, så dette gjort via datagrib med 'truncate table' query.*/
option SPOOL;

%oragenvej(genvej=ORA, database=STATPROD, projekt=D221919, proxylogon=ja);
libname LMDB '\\nas4\fsedata\Grunddata\LMDB';

/* macro til upload af LMDB */
%macro upload_LMDB;                                                                                                                                                                                     
  %do year = 1995 %to 2024;     
* - laver en nøgle fra pnr12 til cpr til person_id;

/* Hent LMDB */
data lmdb_&year.12;
	set lmdb.lmdb&year.12;
	rename pnr12= pnr;
run;

/* PNR12 -> PNR */
%let infile = lmdb_&year.12;
%let outfile = lmdb_cpr_&year.12;
%inc "K:\FSE_LMDB\706437_gendan_pnr.sas";

proc sql;
	create table cpr as select distinct pnr from lmdb_cpr_&year.12;
quit;

/* PNR -> PERSON_ID */
%bef_personnummer(projektid=D101200, procedure=bef_omkod, ind_tabelnavn=cpr, ud_tabelnavn=cpr_pid);

/* - Tilføjer person_id til LMDB-tabellen */
proc sql;
	create table LMDB_id_&year.12(drop=pnr) as
	select A.*, B.person_id, B.status, &year. as aar 
	from lmdb_cpr_&year.12 A
	left join cpr_pid B
	on A.pnr = B.pnr;
quit;


data ora.LMDB_ALL2024;
  set work.LMDB_id_&year.12(obs=0);
run;

/* Uploader til Oracle */
%oracleappend(oratabel=ora.LMDB_ALL2024, data=LMDB_id_&year.12, FORCE=YES);

/* Sletter de årsspecifikke datasæt */
proc datasets nolist;
	delete lmdb_&year.12 lmdb_cpr_&year.12 cpr cpr_pid LMDB_id_&year.12;
run;


%end;
%mend;

/* Upload data */
%upload_lmdb;


