dm 'clear log';
dm 'clear out';

options nofmterr missing=' ' obs=max dkricond=warn notes;

/* Angivelse af database og skema i Oracle */
libname DBP oracle path=STATUDV user='[D222202]' PRESERVE_TAB_NAMES=yes;

/* Angivelse af data fra given grundatamappe */
libname temp "\\nas4\FseData\Grunddata\UDDINST";

/* Angivelse af start og slut år for datasættet */
%let startaar = 2006;
%let sluttaar = 2024;
%let base = uddinst;


/* Der skal ikke laves flere ændringer under denne komentar */
/* Makro: læs fra SAS-fil og gem i Oracle                    */
%macro behandle(datanavn=, tablenavn=, sti=temp);
    data work.&datanavn.;
        set &sti..&datanavn.;
    run;

    data DBP.&tablenavn.;
        set work.&datanavn.;
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

