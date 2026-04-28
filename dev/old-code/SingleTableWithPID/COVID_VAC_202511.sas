dm 'clear log';
dm 'clear out';

options nofmterr missing=' ' obs=max dkricond=warn notes;

/* Setup */
%oragenvej(genvej=PSDbef, database=db_psd, projekt=d101200);
%inc 'K:\DSL\Arkiv\Challenge\Konvertering\CPR til person_id\Kode\PNR_PERSONID_MACRO.sas';

/* Angivelse af database og skema i Oracle */
libname DBP oracle path=STATPROD user='[D222301]' PRESERVE_TAB_NAMES=yes;

/* Libname til aktuel mappe */
libname temp "\\nas4\FseData\Grunddata\COVID_VAC";

%let datanavn = covid_vac202511;              /* kildenavn i temp      */
%let tablenavn = %upcase(&datanavn.);

/* Læs data */
data work.&datanavn.;
    set temp.&datanavn.;
run;

/* Konverter CPR til person_id */
%DSL_personid(&datanavn.);

/* Gem i Oracle uden CPR */
data DBP.&tablenavn.;
    set work.&datanavn._id;
    drop pnr;
run;

libname temp clear;
   


