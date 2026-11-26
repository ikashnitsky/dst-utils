# generated PL/SQL is stable for every date mode

    Code
      plsql("BEF_OMKOD", "none")
    Output
      DECLARE
        v_resultat   VARCHAR2(200);
        v_koerselsid NUMBER;
      BEGIN
        BEF01_pck_omkodning.BEF_OMKOD(
          p_projektnummer => 'D101200',
          p_bruger        => 'IKX',
          p_ind_tabelnavn => 'BEF_ID_PROC',
          p_resultat      => v_resultat,
          p_koerselsid    => v_koerselsid
        );
        -- Store the OUT values so R can find the output table
        insert into psdmytemp values (v_resultat, v_koerselsid);
        COMMIT;
      END;
    Code
      plsql("BEF_AKTUELLE_PNR", "validity", list(validity = "2021-12-31"))
    Output
      DECLARE
        v_resultat   VARCHAR2(200);
        v_koerselsid NUMBER;
      BEGIN
        BEF01_pck_laes_personnummer.BEF_AKTUELLE_PNR(
          p_projektnummer  => 'D101200',
          p_bruger         => 'IKX',
          p_ind_tabelnavn  => 'BEF_ID_PROC',
          p_gyldighedsdato => TO_DATE('2021-12-31', 'YYYY-MM-DD'),
          p_resultat       => v_resultat,
          p_koerselsid     => v_koerselsid
        );
        -- Store the OUT values so R can find the output table
        insert into psdmytemp values (v_resultat, v_koerselsid);
        COMMIT;
      END;
    Code
      plsql("BEF_HISTORISK_ID", "historic", list(validity = "2021-12-31", registry = "2022-01-16 18:00:00"))
    Output
      DECLARE
        v_resultat   VARCHAR2(200);
        v_koerselsid NUMBER;
      BEGIN
        BEF01_pck_laes_personnummer.BEF_HISTORISK_ID(
          p_projektnummer  => 'D101200',
          p_bruger         => 'IKX',
          p_ind_tabelnavn  => 'BEF_ID_PROC',
          p_gyldighedsdato => TO_DATE('2021-12-31', 'YYYY-MM-DD'),
          p_registerdato   => TO_TIMESTAMP('2022-01-16 18:00:00', 'YYYY-MM-DD HH24:MI:SS.FF'),
          p_resultat       => v_resultat,
          p_koerselsid     => v_koerselsid
        );
        -- Store the OUT values so R can find the output table
        insert into psdmytemp values (v_resultat, v_koerselsid);
        COMMIT;
      END;
    Code
      plsql("BEF_FULD_HIS_KOEN_FOEDSELSDAG", "range", list(start = "2000-12-31 12:03:03.232",
        end = "9999-12-31 23:59:59.999"))
    Output
      DECLARE
        v_resultat   VARCHAR2(200);
        v_koerselsid NUMBER;
      BEGIN
        BEF01_pck_laes_personnummer.BEF_FULD_HIS_KOEN_FOEDSELSDAG(
          p_projektnummer    => 'D101200',
          p_bruger           => 'IKX',
          p_ind_tabelnavn    => 'BEF_ID_PROC',
          p_registerstarttid => TO_TIMESTAMP('2000-12-31 12:03:03.232', 'YYYY-MM-DD HH24:MI:SS.FF'),
          p_registersluttid  => TO_TIMESTAMP('9999-12-31 23:59:59.999', 'YYYY-MM-DD HH24:MI:SS.FF'),
          p_resultat         => v_resultat,
          p_koerselsid       => v_koerselsid
        );
        -- Store the OUT values so R can find the output table
        insert into psdmytemp values (v_resultat, v_koerselsid);
        COMMIT;
      END;
    Code
      plsql("BEF_INVALIDE", "none")
    Output
      DECLARE
        v_resultat   VARCHAR2(200);
        v_koerselsid NUMBER;
      BEGIN
        BEF01_pck_laes_personnummer.BEF_INVALIDE(
          p_projektnummer => 'D101200',
          p_bruger        => 'IKX',
          p_resultat      => v_resultat,
          p_koerselsid    => v_koerselsid
        );
        -- Store the OUT values so R can find the output table
        insert into psdmytemp values (v_resultat, v_koerselsid);
        COMMIT;
      END;
    Code
      plsql("BEF_INVALIDE", "range", list(start = "1900-01-01 00:00:00", end = "2100-01-01 00:00:00"))
    Output
      DECLARE
        v_resultat   VARCHAR2(200);
        v_koerselsid NUMBER;
      BEGIN
        BEF01_pck_laes_personnummer.BEF_INVALIDE(
          p_projektnummer    => 'D101200',
          p_bruger           => 'IKX',
          p_registerstarttid => TO_TIMESTAMP('1900-01-01 00:00:00', 'YYYY-MM-DD HH24:MI:SS.FF'),
          p_registersluttid  => TO_TIMESTAMP('2100-01-01 00:00:00', 'YYYY-MM-DD HH24:MI:SS.FF'),
          p_resultat         => v_resultat,
          p_koerselsid       => v_koerselsid
        );
        -- Store the OUT values so R can find the output table
        insert into psdmytemp values (v_resultat, v_koerselsid);
        COMMIT;
      END;
    Code
      plsql("BEF_IDSKIFT", "none", project_id = "O'Brien", recipient = NULL)
    Output
      DECLARE
        v_resultat   VARCHAR2(200);
        v_koerselsid NUMBER;
      BEGIN
        BEF01_pck_laes_personnummer.BEF_IDSKIFT(
          p_projektnummer => 'O''Brien',
          p_bruger        => '',
          p_ind_tabelnavn => 'BEF_ID_PROC',
          p_resultat      => v_resultat,
          p_koerselsid    => v_koerselsid
        );
        -- Store the OUT values so R can find the output table
        insert into psdmytemp values (v_resultat, v_koerselsid);
        COMMIT;
      END;

