DECLARE
    v_resultat   VARCHAR2(200);
    v_koerselsid NUMBER;
BEGIN
    BEF01_pck_laes_personnummer.bef_idskift
    (p_projektnummer => 'JOC',
     p_bruger => 'JOC',
     p_ind_tabelnavn => 'PERSON_ID_OPDATERING_TEST_20240802',
     p_resultat => v_resultat,
     p_koerselsid => v_koerselsid);
end;
