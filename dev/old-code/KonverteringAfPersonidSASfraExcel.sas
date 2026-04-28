dm 'clear log';
dm 'clear out';

options nofmterr missing=' '   obs=max dkricond=warn notes;

/* Bruges til konvertering fra cpr-nummer til personid */
%oragenvej(genvej=PSDbef,database=db_psd, projekt=d101200, options=readbuff=3000 insertbuff=3000 dbcommit=0);
%inc 'K:\DSL\Arkiv\Challenge\Konvertering\CPR til person_id\Kode\PNR_PERSONID_MACRO.sas';

/* stier til data */
libname data "H:\PiaData";
libname mappe "H:\PiaData";  /* mappen som data skal ligge i */

/*filen er gemt som ikke password beskyttet excel og konverteret til sas-dataset med stattransfer*/
data dataset;
	format PNR $11.;
	set data.abhab_ivig_upload_til_dst;
	PNR = compress(pnr,'-');
run;

%DSL_personid(dataset);

data mappe.abhab_ivig_17072025;
	set	dataset_id;
	drop pnr;  /* meget vigtigt */
run;
