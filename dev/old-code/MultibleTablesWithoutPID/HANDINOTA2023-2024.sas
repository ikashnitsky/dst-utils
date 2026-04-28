
dm 'clear log';
dm 'clear out';

options nofmterr missing=' ' obs=max dkricond=warn notes;

/* Setup */
%oragenvej(genvej=PSDbef, database=db_psd, projekt=d101200);
%inc 'K:\DSL\Arkiv\Challenge\Konvertering\CPR til person_id\Kode\PNR_PERSONID_MACRO.sas';

/* Angivelse af database og skema i Oracle */
libname DBP oracle path=STATUDV user='[D222202]' PRESERVE_TAB_NAMES=yes;

/* Angivelse af data fra given grundatamappe */
libname temp "\\nas4\FseData\Grunddata\HANDICNOTA";

/* Angivelse af start og slut år for datasættet */
%let startaar = 2023;
%let sluttaar = 2024;
%let base = handicnota;


/* Der skal ikke laves flere ændringer under denne komentar */
/* Makro: læs fra SAS-fil og gem i Oracle                    */
%macro behandle(datanavn=, tablenavn=, sti=temp);
    data work.&datanavn.;
        set &sti..&datanavn.;
    run;
	
	%DSL_personid(&datanavn.);

    data DBP.&tablenavn.;
        set work.&datanavn._id;
		drop pnr;
    run;
%mend;


/* Loop over årene                                           */
%macro loop;
    %do aar = &startaar. %to &sluttaar.;
        %behandle(
            datanavn=&base.&aar., 
            tablenavn=%upcase(&base.)&aar., 
            sti=temp
        )
    %end;
%mend;

%loop;


   


