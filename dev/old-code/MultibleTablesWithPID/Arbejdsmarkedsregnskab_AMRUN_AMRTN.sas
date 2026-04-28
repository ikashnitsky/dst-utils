dm 'clear log';
dm 'clear out';

options nofmterr missing=' ' obs=max dkricond=warn notes;

/* Setup */
%oragenvej(genvej=PSDbef, database=db_psd, projekt=d101200);
%inc 'K:\DSL\Arkiv\Challenge\Konvertering\CPR til person_id\Kode\PNR_PERSONID_MACRO.sas';

/* Libname til Oracle */
libname DBP oracle path=STATPROD user='[D222505]' PRESERVE_TAB_NAMES=yes;

/* Makro der tager et mappenavn og et ønsket outputnavn */
%macro behandle(datanavn=, tablenavn=, sti=);

    /* Libname til aktuel mappe */
    libname temp "\\nas4\FseData\Grunddata\&sti.";

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

%mend;


%macro loop(start=2019, slut=2019);
    %do aar = &start. %to &slut.;
        %behandle(datanavn=amrun&aar., tablenavn=amrun&aar., sti=AMRUN)
    %end;
%mend;

%loop(start=2019, slut=2019);

/* 
%macro loop(start=2008, slut=2023);
    %do aar = &start. %to &slut.;
        %behandle(datanavn=amrtn&aar., tablenavn=amrtn&aar., sti=AMRTN)
    %end;
%mend;

%loop(start=2008, slut=2023);
 */
