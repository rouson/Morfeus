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
! $Id$
!
! Description:
!    To be added...
!
SUBMODULE(op_field) scalar_fld_vector_mul_implementation

    IMPLICIT NONE

    CONTAINS

        MODULE PROCEDURE scalar_fld_vector_mul
            USE class_dimensions
            USE class_field
            USE class_scalar_field
            USE class_vector_field
            USE class_vector
            USE class_psblas, ONLY : psb_dpk_

            IMPLICIT NONE
            !
            REAL(psb_dpk_), ALLOCATABLE :: x_s(:), bx_s(:)
            TYPE(dimensions) :: dim
            TYPE(field) :: base_s

            CALL get_base(fld_s,base_s)

            dim = dim_(fld_s)

            ! Sets DIM member in the base field object
            CALL set_field_dim(base_s,dim)

            ! Gets X and BX members of operands
            CALL get_x(fld_s,x_s)
            CALL get_bx(fld_s,bx_s)

            ! Construct the result object
            res = vector_field_(base_s, &
                &            x = x_s  * v, &
                &            bx = bx_s * vector_(0.d0,0.d0,0.d0))

            DEALLOCATE(bx_s,x_s)
            CALL free_field(base_s)

        END PROCEDURE scalar_fld_vector_mul

END SUBMODULE scalar_fld_vector_mul_implementation
