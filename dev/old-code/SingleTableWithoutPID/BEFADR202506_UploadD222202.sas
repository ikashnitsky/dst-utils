dm 'clear log';
dm 'clear out';

options nofmterr missing=' ' obs=max dkricond=warn notes;

/* Angivelse af database og skema i Oracle */
libname DBP oracle path=STATUDV user='[D222202]' PRESERVE_TAB_NAMES=yes;

/* Angivelse af data fra given grundatamappe */
libname temp "\\nas4\FseData\Grunddata\BEFADR";


/* Load the dataset into WORK */
data work.befadr202506;
    set temp.befadr202506;
run;

/* Upload to Oracle */
data DBP.BEFADR202506;
    set work.befadr202506;
run;


