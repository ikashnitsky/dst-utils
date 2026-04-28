dm 'clear log';
dm 'clear out';

options nofmterr missing=' ' obs=max dkricond=warn notes;

/* Setup */
%oragenvej(genvej=PSDbef, database=db_psd, projekt=d101200);
%inc 'K:\DSL\Arkiv\Challenge\Konvertering\CPR til person_id\Kode\PNR_PERSONID_MACRO.sas';

/* Angivelse af database og skema i Oracle */
libname DBP oracle path=STATUDV user='[D222601]' PRESERVE_TAB_NAMES=yes;

/* Libname til aktuel mappe */
libname temp "H:\Daniel_Vigild";

%let datanavn = Small;              /* kildenavn i temp      */
%let tablenavn = %upcase(&datanavn.);

data work.&datanavn.;
    set temp.&datanavn.;
    length PNR_char $10;
    PNR_char = put(PNR, z10.);
    drop PNR;
    rename PNR_char = PNR;
run;


/* Konverter CPR til person_id */
%DSL_personid(&datanavn.);

/* Gem i Oracle uden CPR */
data DBP.&tablenavn.;
    set work.&datanavn._id;
    drop pnr;
run;

libname temp clear;
   


