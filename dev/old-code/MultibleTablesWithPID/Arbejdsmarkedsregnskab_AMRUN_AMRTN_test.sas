dm 'clear log';
dm 'clear out';

options nofmterr missing=' ' obs=max dkricond=warn notes;

/* Libname til Oracle */
libname DBP oracle path=STATPROD user='[D222505]' PRESERVE_TAB_NAMES=yes;

/* Sæt sti */
%let sti=AMRUN;  

/* Libname til NAS-mappen */
libname temp "\\nas4\FseData\Grunddata\&sti.";


proc contents data=temp.amrun2012;
run;

/* Tæl unikke non-missing værdier */
proc sql;
    select count(distinct PNR) as unik_count
    from temp.amrun2012
    where PNR is not missing;
quit;

/* Ryd op */
libname temp clear;
