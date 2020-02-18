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
! $Id: tools_operators.f90 3093 2008-04-22 14:51:09Z sfilippo $
!
! Description:
!    To be added...
!
SUBMODULE(tools_operators) tools_operators_procedures

    IMPLICIT NONE

CONTAINS

    MODULE PROCEDURE pde_sign
        USE class_psblas

        REAL(psb_dpk_) :: dsign

        SELECT CASE(sign)
        CASE('+')
            dsign = 1.d0
        CASE('-')
            dsign = -1.d0
        CASE DEFAULT
            WRITE(*,100)
            CALL abort_psblas
        END SELECT

        IF(side /= lhs_ .AND. side /=rhs_) THEN
            WRITE(*,200)
            CALL abort_psblas
        END IF

        ! By default FSIGN refers to the implicit contributions of the PDE
        ! discretization (to be inserted into PDE%A).

        pde_sign = dsign * side

100     FORMAT(' ERROR! Unsupported operator sign in PDE_SIGN')
200     FORMAT(' ERROR! Illegal value of SIDE argument in PDE_SIGN')

    END PROCEDURE pde_sign


    MODULE PROCEDURE size_blk
        INTEGER, PARAMETER :: nbmax = 40
        INTEGER :: nb

        nb = imax - ifirst + 1
        IF(nb > nbmax) THEN
            size_blk = nbmax
        ELSE
            size_blk = nb
        END IF

    END PROCEDURE size_blk

END SUBMODULE tools_operators_procedures
