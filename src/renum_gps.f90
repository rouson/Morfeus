!
!     (c) 2019 Guide Star Engineering, LLC
!     This Software was developed for the US Nuclear Regulatory Commission (US NRC)
!     under contract "Multi-Dimensional Physics Implementation into Fuel Analysis under
!     Steady-state and Transients (FAST)", contract # NRC-HQ-60-17-C-0007
!
!
!    NEMO - Numerical Engine (for) Multiphysics Operators
! Copyright (c) 2007, Stefano Toninel
!                     Gian Marco Bianchi  University of Bologna
!              David P. Schmidt    University of Massachusetts - Amherst
!              Salvatore Filippone University of Rome Tor Vergata
! All rights reserved.
!
! Redistribution and use in source and binary forms, with or without modification,
! are permitted provided that the following conditions are met:
!
!     1. Redistributions of source code must retain the above copyright notice,
!        this list of conditions and the following disclaimer.
!     2. Redistributions in binary form must reproduce the above copyright notice,
!        this list of conditions and the following disclaimer in the documentation
!        and/or other materials provided with the distribution.
!     3. Neither the name of the NEMO project nor the names of its contributors
!        may be used to endorse or promote products derived from this software
!        without specific prior written permission.
!
! THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
! ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
! WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
! DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
! ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
! (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
! LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
! ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
! (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
! SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
!
!---------------------------------------------------------------------------------
!
! $Id: renum_gps.f90 2469 2007-10-08 10:34:43Z sfilippo $
!
! Description:
!    Routines for Gibbs-Poole-Stockmeyer matrix bandwidth and profile
!    reduction. Originally released in ACM-TOMS no. 508 written in
!    Fortran77. Now revised and ported to Fortran90.
!
MODULE renum_gps

    USE psb_base_mod
    PUBLIC :: reduce

    PRIVATE ! Default

    ! COMMON /GRA/ N, IDPTH, IDEG
    INTEGER :: n,  idpth, ideg

    ! COMMON /CC/ XCC,SIZEG,STPT
    INTEGER :: xcc
    INTEGER, ALLOCATABLE  :: sizeg(:), stpt(:)

    ! COMMON /LVLW/ NHIGH,NLOW,NACUM
    INTEGER, ALLOCATABLE, TARGET  :: nhigh(:), nlow(:), nacum(:), aux(:)
    INTEGER, PARAMETER :: init = 500

CONTAINS

    SUBROUTINE reduce(ndstk,nr,d1,iold,renum,ndeg,ibw2,ipf2,idpth)
        !  SUBROUTINE REDUCE DETERMINES A ROW AND COLUMN PERMUTATION WHICH,
        !  WHEN APPLIED TO A GIVEN SPARSE MATRIX, PRODUCES A PERMUTED
        !  MATRIX WITH A SMALLER BANDWIDTH AND PROFILE.
        !  THE INPUT ARRAY IS A CONNECTION TABLE WHICH REPRESENTS THE
        !  INDICES OF THE NONZERO ELEMENTS OF THE MATRIX, A.  THE ALGO-
        !  RITHM IS DESCRIBED IN TERMS OF THE ADJACENCY GRAPH WHICH
        !  HAS THE CHARACTERISTIC THAT THERE IS AN EDGE (CONNECTION)
        !  BETWEEN NODES I AND J IF A(I,J) /= 0 AND I /= J.
        !  DIMENSIONING INFORMATION--THE FOLLOWING INTEGER ARRAYS MUST BE
        !  DIMENSIONED IN THE CALLING ROUTINE.
        !    NDSTK(NR,D1)        D1 IS >= MAXIMUM DEGREE OF ALL NODES.
        !    IOLD(D2)            D2 AND NR ARE >= THE TOTAL NUMBER OF
        !    RENUM(D2+1)         NODES IN THE GRAPH.
        !    NDEG(D2)            STORAGE REQUIREMENTS CAN BE SIGNIFICANTLY
        !    LVL(D2)             DECREASED FOR IBM 360 AND 370 COMPUTERS
        !    LVLS1(D2)           BY REPLACING INTEGER NDSTK BY
        !    LVLS2(D2)           INTEGER*2 NDSTK IN SUBROUTINES REDUCE,
        !    CCSTOR(D2)          DGREE, FNDIAM, TREE AND NUMBER.
        !  COMMON INFORMATION--THE FOLLOWING COMMON BLOCK MUST BE IN THE
        !  CALLING ROUTINE.
        !    COMMON/GRA/N,IDPTH,IDEG
        !  EXPLANATION OF INPUT VARIABLES--
        !    NDSTK-     CONNECTION TABLE REPRESENTING GRAPH.
        !               NDSTK(I,J)=NODE NUMBER OF JTH CONNECTION TO NODE
        !               NUMBER I.  A CONNECTION OF A NODE TO ITSELF IS NOT
        !               LISTED.  EXTRA POSITIONS MUST HAVE ZERO FILL.
        !    NR-        ROW DIMENSION ASSIGNED NDSTK IN CALLING PROGRAM.
        !    IOLD(I)-   NUMBERING OF ITH NODE UPON INPUT.
        !               IF NO NUMBERING EXISTS THEN IOLD(I)=I.
        !    N-         NUMBER OF NODES IN GRAPH (EQUAL TO ORDER OF MATRIX).
        !    IDEG-      MAXIMUM DEGREE OF ANY NODE IN THE GRAPH.
        !  EXPLANATION OF OUTPUT VARIABLES--
        !    RENUM(I)-  THE NEW NUMBER FOR THE ITH NODE.
        !    NDEG(I)-   THE DEGREE OF THE ITH NODE.
        !    IBW2-      THE BANDWIDTH AFTER RENUMBERING.
        !    IPF2-      THE PROFILE AFTER RENUMBERING.
        !    IDPTH-     NUMBER OF LEVELS IN REDUCE LEVEL STRUCTURE.
        !  THE FOLLOWING ONLY HAVE MEANING IF THE GRAPH WAS CONNECTED--
        !    LVL(I)-    INDEX INTO LVLS1 TO THE FIRST NODE IN LEVEL I.
        !               LVL(I+1)-LVL(I)= NUMBER OF NODES IN ITH LEVEL
        !    LVLS1-     NODE NUMBERS LISTED BY LEVEL.
        !    LVLS2(I)-  THE LEVEL ASSIGNED TO NODE I BY REDUCE.
        !  WORKING STORAGE VARIABLE--
        !    CCSTOR
        !  LOCAL STORAGE--
        !    COMMON/CC/-SUBROUTINES REDUCE, SORT2 AND PIKLVL ASSUME THAT
        !               THE GRAPH HAS AT MOST 50 CONNECTED COMPONENTS.
        !               SUBROUTINE FNDIAM ASSUMES THAT THERE ARE AT MOST
        !               100 NODES IN THE LAST LEVEL.
        !    COMMON/LVLW/-SUBROUTINES SETUP AND PIKLVL ASSUME THAT THERE
        !               ARE AT MOST 100 LEVELS.
        ! USE INTEGER*2 NDSTK  WITH AN IBM 360 OR 370.
        ! COMMON /GRA/ N, IDPTH, IDEG
        ! IT IS ASSUMED THAT THE GRAPH HAS AT MOST 50 CONNECTED COMPONENTS.
        ! COMMON /CC/ XCC, SIZEG(50), STPT(50)
        ! COMMON /LVLW/ NHIGH(100), NLOW(100), NACUM(100)
        !
        INTEGER :: d1
        INTEGER :: stnode, rvnode, stnum, sbnum
        INTEGER :: ndstk(nr,d1), iold(nr), renum(nr+1), ndeg(nr)
        INTEGER :: lvl(nr), lvls1(nr), lvls2(nr), ccstor(nr)

        n = nr
        idpth = 0
        ideg = d1

        ALLOCATE(SIZEG(NR),STPT(NR), STAT=INFO)
        IF(INFO /= 0) THEN
            WRITE(*,*) 'ERROR! Memory allocation # 1 failure in GPS'
            STOP
        END IF
        !
        ALLOCATE(NHIGH(INIT), NLOW(INIT), NACUM(INIT), AUX(INIT), STAT=INFO)
        IF(INFO /= 0) THEN
            WRITE(*,*) 'ERROR! Memory allocation # 2 failure in GPS'
            STOP
        END IF
        !
        IBW2 = 0
        IPF2 = 0
        ! SET RENUM(I)=0 FOR ALL I TO INDICATE NODE I IS UNNUMBERED
        DO 10 I=1,N
            RENUM(I) = 0
10      END DO
        ! COMPUTE DEGREE OF EACH NODE AND ORIGINAL BANDWIDTH AND PROFILE
        CALL DGREE(NDSTK, NR, NDEG, IOLD, IBW1, IPF1)
        ! SBNUM= LOW END OF AVAILABLE NUMBERS FOR RENUMBERING
        ! STNUM= HIGH END OF AVAILABLE NUMBERS FOR RENUMBERING
        SBNUM = 1
        STNUM = N
        ! NUMBER THE NODES OF DEGREE ZERO
        DO 20 I=1,N
            IF (NDEG(I)>0) CYCLE
            RENUM(I) = STNUM
            STNUM = STNUM - 1
20      END DO
        ! FIND AN UNNUMBERED NODE OF MIN DEGREE TO START ON
30      LOWDG = IDEG + 1
        NFLG = 1
        ISDIR = 1
        DO 40 I=1,N
            IF (NDEG(I)>=LOWDG) CYCLE
            IF (RENUM(I)>0) CYCLE
            LOWDG = NDEG(I)
            STNODE = I
40      END DO
        ! FIND PSEUDO-DIAMETER AND ASSOCIATED LEVEL STRUCTURES.
        ! STNODE AND RVNODE ARE THE ENDS OF THE DIAM AND LVLS1 AND LVLS2
        ! ARE THE RESPECTIVE LEVEL STRUCTURES.
        CALL FNDIAM(STNODE, RVNODE, NDSTK, NR, NDEG, LVL, LVLS1,LVLS2, CCSTOR, IDFLT)
        IF (NDEG(STNODE) <= NDEG(RVNODE)) GO TO 50
        ! NFLG INDICATES THE END TO BEGIN NUMBERING ON
        NFLG = -1
        STNODE = RVNODE
50      CALL SETUP(LVL, LVLS1, LVLS2)
        ! FIND ALL THE CONNECTED COMPONENTS  (XCC COUNTS THEM)
        XCC = 0
        LROOT = 1
        LVLN = 1
        DO 60 I=1,N
            IF (LVL(I)/=0) CYCLE
            XCC = XCC + 1
            STPT(XCC) = LROOT
            CALL TREE(I, NDSTK, NR, LVL, CCSTOR, NDEG, LVLWTH, LVLBOT,LVLN, MAXLW, N)
            SIZEG(XCC) = LVLBOT + LVLWTH - LROOT
            LROOT = LVLBOT + LVLWTH
            LVLN = LROOT
60      END DO
        IF (SORT2() == 0) GO TO 70
        CALL PIKLVL(LVLS1, LVLS2, CCSTOR, IDFLT, ISDIR)
        ! ON RETURN FROM PIKLVL, ISDIR INDICATES THE DIRECTION THE LARGEST
        ! COMPONENT FELL.  ISDIR IS MODIFIED NOW TO INDICATE THE NUMBERING
        ! DIRECTION.  NUM IS SET TO THE PROPER VALUE FOR THIS DIRECTION.
70      ISDIR = ISDIR*NFLG
        NUM = SBNUM
        IF (ISDIR < 0) NUM = STNUM
        CALL NUMBER(STNODE, NUM, NDSTK, LVLS2, NDEG, RENUM, LVLS1,LVL,&
            & NR, NFLG, IBW2, IPF2, CCSTOR, ISDIR)
        ! UPDATE STNUM OR SBNUM AFTER NUMBERING
        IF (ISDIR < 0) STNUM = NUM
        IF (ISDIR>0) SBNUM = NUM
        IF (SBNUM <= STNUM) GO TO 30
        IF (IBW2 <= IBW1) GO TO 90
        ! IF ORIGINAL NUMBERING IS BETTER THAN NEW ONE, SET UP TO RETURN IT
        DO 80 I=1,N
            RENUM(I) = IOLD(I)
80      END DO
        IBW2 = IBW1
        IPF2 = IPF1
        !
90      DEALLOCATE(SIZEG,STPT)
        DEALLOCATE(NHIGH,NLOW,AUX,NACUM)
        RETURN
    END SUBROUTINE REDUCE
    !
    SUBROUTINE DGREE(NDSTK, NR, NDEG, IOLD, IBW1, IPF1)
        !  DGREE COMPUTES THE DEGREE OF EACH NODE IN NDSTK AND STORES
        !  IT IN THE ARRAY NDEG.  THE BANDWIDTH AND PROFILE FOR THE ORIGINAL
        !  OR INPUT RENUMBERING OF THE GRAPH IS COMPUTED ALSO.
        ! USE INTEGER*2 NDSTK  WITH AN IBM 360 OR 370.
        INTEGER NDSTK
        ! COMMON /GRA/ N, IDPTH, IDEG
        DIMENSION NDSTK(NR,IDEG), NDEG(N), IOLD(N)

        IBW1 = 0
        IPF1 = 0
        DO 40 I=1,N
            NDEG(I) = 0
            IRW = 0
            DO 20 J=1,IDEG
                ITST = NDSTK(I,J)
                IF(ITST <= 0) EXIT
                NDEG(I) = NDEG(I) + 1
                IDIF = IOLD(I) - IOLD(ITST)
                IF (IRW < IDIF) IRW = IDIF
20          END DO
            IPF1 = IPF1 + IRW
            IF (IRW>IBW1) IBW1 = IRW
40      END DO
        RETURN
    END SUBROUTINE DGREE
    !
    SUBROUTINE FNDIAM(SND1, SND2, NDSTK, NR, NDEG, LVL, LVLS1,LVLS2, IWK, IDFLT)
        !  FNDIAM IS THE CONTROL PROCEDURE FOR FINDING THE PSEUDO-DIAMETER OF
        !  NDSTK AS WELL AS THE LEVEL STRUCTURE FROM EACH END
        !  SND1-        ON INPUT THIS IS THE NODE NUMBER OF THE FIRST
        !               ATTEMPT AT FINDING A DIAMETER.  ON OUTPUT IT
        !               CONTAINS THE ACTUAL NUMBER USED.
        !  SND2-        ON OUTPUT CONTAINS OTHER END OF DIAMETER
        !  LVLS1-       ARRAY CONTAINING LEVEL STRUCTURE WITH SND1 AS ROOT
        !  LVLS2-       ARRAY CONTAINING LEVEL STRUCTURE WITH SND2 AS ROOT
        !  IDFLT-       FLAG USED IN PICKING FINAL LEVEL STRUCTURE, SET
        !               =1 IF WIDTH OF LVLS1  <=  WIDTH OF LVLS2, OTHERWISE =2
        !  LVL,IWK-     WORKING STORAGE
        ! USE INTEGER*2 NDSTK  WITH AN IBM 360 OR 370.
        INTEGER NDSTK
        INTEGER FLAG, SND, SND1, SND2
        ! COMMON /GRA/ N, IDPTH, IDEG
        ! IT IS ASSUMED THAT THE LAST LEVEL HAS AT MOST 100 NODES.
        ! COMMON /CC/ NDLST(100)
        INTEGER,POINTER :: NDLST(:)
        DIMENSION NDSTK(NR,IDEG), NDEG(1), LVL(N), LVLS1(N), LVLS2(N),IWK(N)
        !
        NDLST => AUX
        !
        FLAG = 0
        MTW2 = N
        SND = SND1
        ! ZERO LVL TO INDICATE ALL NODES ARE AVAILABLE TO TREE
10      DO 20 I=1,N
            LVL(I) = 0
20      END DO
        LVLN = 1
        ! DROP A TREE FROM SND
        CALL TREE(SND, NDSTK, NR, LVL, IWK, NDEG, LVLWTH, LVLBOT,LVLN, MAXLW, MTW2)
        IF (FLAG>=1) GO TO 50
        FLAG = 1
30      IDPTH = LVLN - 1
        MTW1 = MAXLW
        ! COPY LEVEL STRUCTURE INTO LVLS1
        DO 40 I=1,N
            LVLS1(I) = LVL(I)
40      END DO
        NDXN = 1
        NDXL = 0
        MTW2 = N
        ! SORT LAST LEVEL BY DEGREE  AND STORE IN NDLST
        CALL SORTDG(NDLST, IWK(LVLBOT), NDXL, LVLWTH, NDEG)
        SND = NDLST(1)
        GO TO 10
50      IF (IDPTH>=LVLN-1) GO TO 60
        ! START AGAIN WITH NEW STARTING NODE
        SND1 = SND
        GO TO 30
60      IF (MAXLW>=MTW2) GO TO 80
        MTW2 = MAXLW
        SND2 = SND
        ! STORE NARROWEST REVERSE LEVEL STRUCTURE IN LVLS2
        DO 70 I=1,N
            LVLS2(I) = LVL(I)
70      END DO
80      IF (NDXN == NDXL) GO TO 90
        ! TRY NEXT NODE IN NDLST
        NDXN = NDXN + 1
        SND = NDLST(NDXN)
        GO TO 10
90      IDFLT = 1
        IF (MTW2 <= MTW1) IDFLT = 2
        NULLIFY(NDLST)
        RETURN
    END SUBROUTINE FNDIAM
    !
    SUBROUTINE TREE(IROOT, NDSTK, NR, LVL, IWK, NDEG, LVLWTH, LVLBOT, LVLN, MAXLW, IBORT)
        !  TREE DROPS A TREE IN NDSTK FROM IROOT
        !  LVL-         ARRAY INDICATING AVAILABLE NODES IN NDSTK WITH ZERO
        !               ENTRIES. TREE ENTERS LEVEL NUMBERS ASSIGNED
        !               DURING EXECUTION OF THIS PROCEDURE
        !  IWK-         ON OUTPUT CONTAINS NODE NUMBERS USED IN TREE
        !               ARRANGED BY LEVELS (IWK(LVLN) CONTAINS IROOT
        !               AND IWK(LVLBOT+LVLWTH-1) CONTAINS LAST NODE ENTERED)
        !  LVLWTH-      ON OUTPUT CONTAINS WIDTH OF LAST LEVEL
        !  LVLBOT-      ON OUTPUT CONTAINS INDEX INTO IWK OF FIRST
        !               NODE IN LAST LEVEL
        !  MAXLW-       ON OUTPUT CONTAINS THE MAXIMUM LEVEL WIDTH
        !  LVLN-        ON INPUT THE FIRST AVAILABLE LOCATION IN IWK
        !               USUALLY ONE BUT IF IWK IS USED TO STORE PREVIOUS
        !               CONNECTED COMPONENTS, LVLN IS NEXT AVAILABLE LOCATION.
        !               ON OUTPUT THE TOTAL NUMBER OF LEVELS + 1
        !  IBORT-       INPUT PARAM WHICH TRIGGERS EARLY RETURN IF
        !               MAXLW BECOMES >= IBORT
        ! USE INTEGER*2 NDSTK  WITH AN IBM 360 OR 370.
        INTEGER NDSTK
        DIMENSION NDSTK(NR,IDEG), LVL(N), IWK(N), NDEG(N)
        MAXLW = 0
        ITOP = LVLN
        INOW = LVLN
        LVLBOT = LVLN
        LVLTOP = LVLN + 1
        LVLN = 1
        LVL(IROOT) = 1
        IWK(ITOP) = IROOT
10      LVLN = LVLN + 1
20      IWKNOW = IWK(INOW)
        NDROW = NDEG(IWKNOW)
        DO 30 J=1,NDROW
            ITEST = NDSTK(IWKNOW,J)
            IF (LVL(ITEST)/=0) CYCLE
            LVL(ITEST) = LVLN
            ITOP = ITOP + 1
            IWK(ITOP) = ITEST
30      END DO
        INOW = INOW + 1
        IF (INOW < LVLTOP) GO TO 20
        LVLWTH = LVLTOP - LVLBOT
        IF (MAXLW < LVLWTH) MAXLW = LVLWTH
        IF (MAXLW>=IBORT) RETURN
        IF (ITOP < LVLTOP) RETURN
        LVLBOT = INOW
        LVLTOP = ITOP + 1
        GO TO 10
    END SUBROUTINE TREE
    !
    SUBROUTINE SORTDG(STK1, STK2, X1, X2, NDEG)
        ! SORTDG SORTS STK2 BY DEGREE OF THE NODE AND ADDS IT TO THE END
        ! OF STK1 IN ORDER OF LOWEST TO HIGHEST DEGREE.  X1 AND X2 ARE THE
        ! NUMBER OF NODES IN STK1 AND STK2 RESPECTIVELY.
        INTEGER X1, X2, STK1, STK2, TEMP
        ! COMMON /GRA/ N, IDPTH, IDEG
        DIMENSION NDEG(N), STK1(X1+X2), STK2(X2)
        IND = X2
10      ITEST = 0
        IND = IND - 1
        IF (IND < 1) GO TO 30
        DO 20 I=1,IND
            J = I + 1
            ISTK2 = STK2(I)
            JSTK2 = STK2(J)
            IF (NDEG(ISTK2) <= NDEG(JSTK2)) CYCLE
            ITEST = 1
            TEMP = STK2(I)
            STK2(I) = STK2(J)
            STK2(J) = TEMP
20      END DO
        IF (ITEST == 1) GO TO 10
30      DO 40 I=1,X2
            X1 = X1 + 1
            STK1(X1) = STK2(I)
40      END DO
        RETURN
    END SUBROUTINE SORTDG
    !
    SUBROUTINE SETUP(LVL, LVLS1, LVLS2)
        ! SETUP COMPUTES THE REVERSE LEVELING INFO FROM LVLS2 AND STORES
        ! IT INTO LVLS2.  NACUM(I) IS INITIALIZED TO NODES/ITH LEVEL FOR NODES
        ! ON THE PSEUDO-DIAMETER OF THE GRAPH.  LVL IS INITIALIZED TO NON-
        ! ZERO FOR NODES ON THE PSEUDO-DIAM AND NODES IN A DIFFERENT
        ! COMPONENT OF THE GRAPH.
        !      COMMON /GRA/ N, IDPTH, IDEG
        ! IT IS ASSUMED THAT THERE ARE AT MOST 100 LEVELS.
        ! COMMON /LVLW/ NHIGH(100), NLOW(100), NACUM(100)
        DIMENSION LVL(N), LVLS1(N), LVLS2(N)
        INTEGER :: SZ
        !----------------------------------------------------------
        SZ=SIZE(NACUM)
        IF(SZ  <  IDPTH) THEN
            WRITE(*,*) 'GPS_SETUP: on the fly reallocation of NACUM'
            CALL psb_realloc(idpth,nacum,info) !CALL REALLOC(NACUM,SZ,IDPTH)
        END IF
        !----------------------------------------------------------
        DO 10 I=1,IDPTH
            NACUM(I) = 0
10      END DO
        DO 30 I=1,N
            LVL(I) = 1
            LVLS2(I) = IDPTH + 1 - LVLS2(I)
            ITEMP = LVLS2(I)
            IF (ITEMP>IDPTH) CYCLE
            IF (ITEMP/=LVLS1(I)) GO TO 20
            NACUM(ITEMP) = NACUM(ITEMP) + 1
            CYCLE
20          LVL(I) = 0
30      END DO
        RETURN
    END SUBROUTINE SETUP
    !
    INTEGER FUNCTION SORT2()
        ! SORT2 SORTS SIZEG AND STPT INTO DESCENDING ORDER ACCORDING TO
        ! VALUES OF SIZEG. XCC=NUMBER OF ENTRIES IN EACH ARRAY
        INTEGER TEMP
        ! IT IS ASSUMED THAT THE GRAPH HAS AT MOST 50 CONNECTED COMPONENTS.
        !COMMON /CC/ XCC, SIZEG(50), STPT(50)

        SORT2 = 0
        IF (XCC == 0) RETURN
        SORT2 = 1
        IND = XCC
10      ITEST = 0
        IND = IND - 1
        IF (IND < 1) RETURN
        DO 20 I=1,IND
            J = I + 1
            IF (SIZEG(I)>=SIZEG(J)) CYCLE
            ITEST = 1
            TEMP = SIZEG(I)
            SIZEG(I) = SIZEG(J)
            SIZEG(J) = TEMP
            TEMP = STPT(I)
            STPT(I) = STPT(J)
            STPT(J) = TEMP
20      END DO
        IF (ITEST == 1) GO TO 10
        RETURN
    END FUNCTION SORT2
    !
    SUBROUTINE PIKLVL(LVLS1, LVLS2, CCSTOR, IDFLT, ISDIR)
        ! PIKLVL CHOOSES THE LEVEL STRUCTURE  USED IN NUMBERING GRAPH
        ! LVLS1-       ON INPUT CONTAINS FORWARD LEVELING INFO
        ! LVLS2-       ON INPUT CONTAINS REVERSE LEVELING INFO
        !              ON OUTPUT THE FINAL LEVEL STRUCTURE CHOSEN
        ! CCSTOR-      ON INPUT CONTAINS CONNECTED COMPONENT INFO
        ! IDFLT-       ON INPUT =1 IF WDTH LVLS1 <= WDTH LVLS2, =2 OTHERWISE
        ! NHIGH        KEEPS TRACK OF LEVEL WIDTHS FOR HIGH NUMBERING
        ! NLOW-        KEEPS TRACK OF LEVEL WIDTHS FOR LOW NUMBERING
        ! NACUM-       KEEPS TRACK OF LEVEL WIDTHS FOR CHOSEN LEVEL STRUCTURE
        ! XCC-         NUMBER OF CONNECTED COMPONENTS
        ! SIZEG(I)-    SIZE OF ITH CONNECTED COMPONENT
        ! STPT(I)-     INDEX INTO CCSTORE OF 1ST NODE IN ITH CON COMPT
        ! ISDIR-       FLAG WHICH INDICATES WHICH WAY THE LARGEST CONNECTED
        !              COMPONENT FELL.  =+1 IF LOW AND -1 IF HIGH
        INTEGER CCSTOR, ENDC
        ! COMMON /GRA/ N, IDPTH, IDEG
        ! IT IS ASSUMED THAT THE GRAPH HAS AT MOST 50 COMPONENTS AND
        ! THAT THERE ARE AT MOST 100 LEVELS.
        ! COMMON /LVLW/ NHIGH(100), NLOW(100), NACUM(100)
        ! COMMON /CC/ XCC, SIZEG(50), STPT(50)
        DIMENSION LVLS1(N), LVLS2(N), CCSTOR(N)
        INTEGER :: SZ
        ! FOR EACH CONNECTED COMPONENT DO
        DO 80 I=1,XCC
            J = STPT(I)
            ENDC= SIZEG(I) + J - 1
            ! SET NHIGH AND NLOW EQUAL TO NACUM
            !-----------------------------------------------------------
            SZ=SIZE(NHIGH)
            IF(SZ  <  IDPTH) THEN
                WRITE(*,*) 'GPS_PIKLVL: on the fly reallocation of NHIGH'
                CALL psb_realloc(idpth,nhigh,info) !CALL REALLOC(NHIGH,SZ,IDPTH)
            END IF
            SZ=SIZE(NLOW)
            IF(SZ  <  IDPTH) THEN
                WRITE(*,*) 'GPS_PIKLVL: on the fly reallocation of NLOW'
                CALL psb_realloc(idpth,nlow,info) !CALL REALLOC(NLOW,SZ,IDPTH)
            END IF
            !-----------------------------------------------------------
            DO 10 K=1,IDPTH
                NHIGH(K) = NACUM(K)
                NLOW(K) = NACUM(K)
10          END DO
            ! UPDATE NHIGH AND NLOW FOR EACH NODE IN CONNECTED COMPONENT
            DO 20 K=J,ENDC
                INODE = CCSTOR(K)
                LVLNH = LVLS1(INODE)
                NHIGH(LVLNH) = NHIGH(LVLNH) + 1
                LVLNL = LVLS2(INODE)
                NLOW(LVLNL) = NLOW(LVLNL) + 1
20          END DO
            MAX1 = 0
            MAX2 = 0
            ! SET MAX1=LARGEST NEW NUMBER IN NHIGH
            ! SET MAX2=LARGEST NEW NUMBER IN NLOW
            DO 30 K=1,IDPTH
                IF (2*NACUM(K) == NLOW(K)+NHIGH(K)) CYCLE
                IF (NHIGH(K)>MAX1) MAX1 = NHIGH(K)
                IF (NLOW(K)>MAX2) MAX2 = NLOW(K)
30          END DO
            ! SET IT= NUMBER OF LEVEL STRUCTURE TO BE USED
            IT = 1
            IF (MAX1>MAX2) IT = 2
            IF (MAX1 == MAX2) IT = IDFLT
            IF (IT == 2) GO TO 60
            IF (I == 1) ISDIR = -1
            ! COPY LVLS1 INTO LVLS2 FOR EACH NODE IN CONNECTED COMPONENT
            DO 40 K=J,ENDC
                INODE = CCSTOR(K)
                LVLS2(INODE) = LVLS1(INODE)
40          END DO
            ! UPDATE NACUM TO BE THE SAME AS NHIGH
            DO 50 K=1,IDPTH
                NACUM(K) = NHIGH(K)
50          END DO
            CYCLE
            ! UPDATE NACUM TO BE THE SAME AS NLOW
60          DO 70 K=1,IDPTH
                NACUM(K) = NLOW(K)
70          END DO
80      END DO
        RETURN
    END SUBROUTINE PIKLVL
    !
    SUBROUTINE NUMBER(SND, NUM, NDSTK, LVLS2, NDEG, RENUM, LVLST,LSTPT,&
        & NR, NFLG, IBW2, IPF2, IPFA, ISDIR)
        !  NUMBER PRODUCES THE NUMBERING OF THE GRAPH FOR MIN BANDWIDTH
        !  SND-         ON INPUT THE NODE TO BEGIN NUMBERING ON
        !  NUM-         ON INPUT AND OUTPUT, THE NEXT AVAILABLE NUMBER
        !  LVLS2-       THE LEVEL STRUCTURE TO BE USED IN NUMBERING
        !  RENUM-       THE ARRAY USED TO STORE THE NEW NUMBERING
        !  LVLST-       ON OUTPUT CONTAINS LEVEL STRUCTURE
        !  LSTPT(I)-    ON OUTPUT, INDEX INTO LVLST TO FIRST NODE IN ITH LVL
        !               LSTPT(I+1) - LSTPT(I) = NUMBER OF NODES IN ITH LVL
        !  NFLG-        =+1 IF SND IS FORWARD END OF PSEUDO-DIAM
        !               =-1 IF SND IS REVERSE END OF PSEUDO-DIAM
        !  IBW2-        BANDWIDTH OF NEW NUMBERING COMPUTED BY NUMBER
        !  IPF2-        PROFILE OF NEW NUMBERING COMPUTED BY NUMBER
        !  IPFA-        WORKING STORAGE USED TO COMPUTE PROFILE AND BANDWIDTH
        !  ISDIR-       INDICATES STEP DIRECTION USED IN NUMBERING(+1 OR -1)
        ! USE INTEGER*2 NDSTK  WITH AN IBM 360 OR 370.
        INTEGER NDSTK
        INTEGER SND, XA, XB, XC, XD, CX, ENDC,RENUM, TEST
        ! COMMON /GRA/ N, IDPTH, IDEG
        ! THE STORAGE IN COMMON BLOCKS CC AND LVLW IS NOW FREE AND CAN
        ! BE USED FOR STACKS.
        !COMMON /LVLW/ STKA(100), STKB(100), STKC(100)
        !COMMON /CC/ STKD(100)
        DIMENSION IPFA(N)
        DIMENSION NDSTK(NR,IDEG), LVLS2(N), NDEG(N), RENUM(N+1), LVLST(N),LSTPT(N)
        INTEGER,POINTER ::STKA(:),STKB(:),STKC(:),STKD(:)
        INTEGER :: SZ1,SZ2
        !
        STKA => NHIGH
        STKB => NLOW
        STKC => NACUM
        STKD => AUX
        !
        ! SET UP LVLST AND LSTPT FROM LVLS2
        DO 10 I=1,N
            IPFA(I) = 0
10      END DO
        NSTPT = 1
        DO 30 I=1,IDPTH
            LSTPT(I) = NSTPT
            DO 20 J=1,N
                IF (LVLS2(J)/=I) CYCLE
                LVLST(NSTPT) = J
                NSTPT = NSTPT + 1
20          END DO
30      END DO
        LSTPT(IDPTH+1) = NSTPT
        ! STKA, STKB, STKC AND STKD ARE STACKS WITH POINTERS
        ! XA,XB,XC, AND XD.  CX IS A SPECIAL POINTER INTO STKC WHICH
        ! INDICATES THE PARTICULAR NODE BEING PROCESSED.
        ! LVLN KEEPS TRACK OF THE LEVEL WE ARE WORKING AT.
        ! INITIALLY STKC CONTAINS ONLY THE INITIAL NODE, SND.
        LVLN = 0
        IF (NFLG < 0) LVLN = IDPTH + 1
        XC = 1
        STKC(XC) = SND
40      CX = 1
        XD = 0
        LVLN = LVLN + NFLG
        LST = LSTPT(LVLN)
        LND = LSTPT(LVLN+1) - 1
        ! BEGIN PROCESSING NODE STKC(CX)
50      IPRO = STKC(CX)
        RENUM(IPRO) = NUM
        NUM = NUM + ISDIR
        ENDC = NDEG(IPRO)
        XA = 0
        XB = 0
        ! CHECK ALL ADJACENT NODES
        DO 80 I=1,ENDC
            TEST = NDSTK(IPRO,I)
            INX = RENUM(TEST)
            ! ONLY NODES NOT NUMBERED OR ALREADY ON A STACK ARE ADDED
            IF (INX == 0) GO TO 60
            IF (INX < 0) CYCLE
            ! DO PRELIMINARY BANDWIDTH AND PROFILE CALCULATIONS
            NBW = (RENUM(IPRO)-INX)*ISDIR
            IF (ISDIR>0) INX = RENUM(IPRO)
            IF (IPFA(INX) < NBW) IPFA(INX) = NBW
            CYCLE
60          RENUM(TEST) = -1
            ! PUT NODES ON SAME LEVEL ON STKA, ALL OTHERS ON STKB
            IF (LVLS2(TEST) == LVLS2(IPRO)) GO TO 70
            XB = XB + 1
            STKB(XB) = TEST
            CYCLE
70          XA = XA + 1
            STKA(XA) = TEST
80      END DO
        ! SORT STKA AND STKB INTO INCREASING DEGREE AND ADD STKA TO STKC
        ! AND STKB TO STKD
        IF (XA == 0) GO TO 100
        IF (XA == 1) GO TO 90
        !---------------------------------------------------------------------
        SZ1=SIZE(STKC)
        SZ2=XC+XA
        IF(SZ1 < SZ2) THEN
            WRITE(*,*) 'GPS_NUMBER - Check #1: on the fly reallocation of STKC'
            CALL psb_realloc(sz2,nacum,info) !CALL REALLOC(NACUM,SZ1,SZ2)
            STKC => NACUM
        END IF
        !---------------------------------------------------------------------
        CALL SORTDG(STKC, STKA, XC, XA, NDEG)
        GO TO 100
90      XC = XC + 1
        !---------------------------------------------------------------------
        SZ1=SIZE(STKC)
        SZ2=XC
        IF(SZ1 < SZ2) THEN
            WRITE(*,*) 'GPS_NUMBER - Check #2: on the fly reallocation of STKC'
            SZ2=SZ2+INIT
            CALL psb_realloc(sz2,nacum,info) !CALL REALLOC(NACUM,SZ1,SZ2)
            STKC => NACUM
        END IF
        !---------------------------------------------------------------------
        STKC(XC) = STKA(XA)
100     IF (XB == 0) GO TO 120
        IF (XB == 1) GO TO 110
        !---------------------------------------------------------------------
        SZ1=SIZE(STKD)
        SZ2=XD+XB
        IF(SZ1 < SZ2) THEN
            WRITE(*,*) 'GPS_NUMBER - Check #3: on the fly reallocation of STKD'
            CALL psb_realloc(sz2,aux,info) !CALL REALLOC(AUX,SZ1,SZ2)
            STKD => AUX
        END IF
        !---------------------------------------------------------------------
        CALL SORTDG(STKD, STKB, XD, XB, NDEG)
        GO TO 120
110     XD = XD + 1
        !---------------------------------------------------------------------
        SZ1=SIZE(STKD)
        SZ2=XD
        IF(SZ1 < SZ2) THEN
            WRITE(*,*) 'GPS_NUMBER - Check #4: on the fly reallocation of STKD'
            SZ2=SZ2+INIT
            CALL psb_realloc(sz2,aux,info) ! CALL REALLOC(AUX,SZ1,SZ2)
            STKD => AUX
        END IF
        !---------------------------------------------------------------------
        STKD(XD) = STKB(XB)
        ! BE SURE TO PROCESS ALL NODES IN STKC
120     CX = CX + 1
        IF (XC>=CX) GO TO 50
        ! WHEN STKC IS EXHAUSTED LOOK FOR MIN DEGREE NODE IN SAME LEVEL
        ! WHICH HAS NOT BEEN PROCESSED
        MAX = IDEG + 1
        SND = N + 1
        DO 130 I=LST,LND
            TEST = LVLST(I)
            IF (RENUM(TEST)/=0) CYCLE
            IF (NDEG(TEST)>=MAX) CYCLE
            RENUM(SND) = 0
            RENUM(TEST) = -1
            MAX = NDEG(TEST)
            SND = TEST
130     END DO
        IF (SND == N+1) GO TO 140
        XC = XC + 1
        !---------------------------------------------------------------------
        SZ1=SIZE(STKC)
        SZ2=XC
        IF(SZ1 < SZ2) THEN
            WRITE(*,*) 'GPS_NUMBER - Check #5: on the fly reallocation of STKC'
            SZ2=SZ2+INIT
            CALL psb_realloc(sz2,nacum,info) !CALL REALLOC(NACUM,SZ1,SZ2)
            STKC => NACUM
        END IF
        !---------------------------------------------------------------------
        STKC(XC) = SND
        GO TO 50
        ! IF STKD IS EMPTY WE ARE DONE, OTHERWISE COPY STKD ONTO STKC
        ! AND BEGIN PROCESSING NEW STKC
140     IF (XD == 0) GO TO 160
        !---------------------------------------------------------------------
        SZ1=SIZE(STKC)
        SZ2=XD
        IF(SZ1 < SZ2) THEN
            WRITE(*,*) 'GPS_NUMBER - Check #6: on the fly reallocation of STKC'
            SZ2=SZ2+INIT
            CALL psb_realloc(sz2,nacum,info) !CALL REALLOC(NACUM,SZ1,SZ2)
            STKC => NACUM
        END IF
        !---------------------------------------------------------------------
        DO 150 I=1,XD
            STKC(I) = STKD(I)
150     END DO
        XC = XD
        GO TO 40
        ! DO FINAL BANDWIDTH AND PROFILE CALCULATIONS
160     DO 170 I=1,N
            IF (IPFA(I)>IBW2) IBW2 = IPFA(I)
            IPF2 = IPF2 + IPFA(I)
170     END DO
        !
        RETURN
    END SUBROUTINE NUMBER

    ! -----------------------------------------------------------------------
!!$
!!$  subroutine realloc(vet,sz1,sz2)
!!$    ! Performs on the fly reallocation of pointer VET changing its
!!$    ! size from SZ1 to SZ2
!!$    implicit none
!!$    !
!!$    integer, pointer :: vet(:), tmp(:)
!!$    integer, intent(in) :: sz1, sz2
!!$    !
!!$    integer :: info
!!$
!!$    allocate(tmp(sz2),stat=info)
!!$    if(info /= 0) then
!!$       write(*,*) 'ERROR! Memory allocation failure in REALLOC'
!!$       stop
!!$    end if
!!$
!!$    tmp(1:sz1) = vet(1:sz1)
!!$
!!$    deallocate(vet)
!!$    vet => tmp
!!$
!!$  end subroutine realloc

END MODULE renum_gps
