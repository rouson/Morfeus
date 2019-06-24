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
!    Adds to PDE the contribution of the time derivative of FLD * PHI.
!    Remark: FLD is optional.
!
SUBMODULE (op_ddt) scalar_pde_ddt_implementation
    IMPLICIT NONE

    CONTAINS

    MODULE PROCEDURE scalar_pde_ddt
    USE class_psblas
    USE class_dimensions
    USE class_scalar_field
    USE class_mesh, ONLY : mesh, check_mesh_consistency
    USE class_scalar_pde
    USE tools_operators
    IMPLICIT NONE
    !
    CHARACTER(len=*), PARAMETER :: op_name = 'SCALAR_PDE_DDT'
    INTEGER :: i, ic, ic_glob, ifirst, info, ncells, nel, nmax
    INTEGER, ALLOCATABLE :: ia(:), ja(:)
    INTEGER, ALLOCATABLE :: iloc_to_glob(:)
    REAL(psb_dpk_), ALLOCATABLE :: A(:), b(:)
    REAL(psb_dpk_), ALLOCATABLE :: fld_x_old(:)
    REAL(psb_dpk_), ALLOCATABLE :: phi_x_old(:)
    REAL(psb_dpk_) :: dtinv, fact, fsign, side_
    TYPE(dimensions) :: dim
    TYPE(mesh), POINTER :: msh => NULL()
    TYPE(mesh), POINTER :: msh_phi => NULL(), msh_fld => NULL()


    CALL tic(sw_pde)

    IF(mypnum_() == 0) THEN
        WRITE(*,*) '* ', TRIM(name_(pde)), ': applying the Time Derivative ',&
            & 'operator to the ', TRIM(name_(phi)), ' field'
    END IF

    ! Possible reinit of PDE
    CALL reinit_pde(pde)

    ! Is PHI cell-centered?
    IF(on_faces_(phi)) THEN
        WRITE(*,100) TRIM(op_name)
        CALL abort_psblas
    END IF

    ! Is FLD cell-centered?
    IF(PRESENT(fld)) THEN
        IF(on_faces_(fld)) THEN
            WRITE(*,100) TRIM(op_name)
            CALL abort_psblas
        END IF
    END IF

    ! Checks mesh consistency PDE vs. PHI
    CALL pde%get_mesh(msh)
    CALL phi%get_mesh(msh_phi)
    BLOCK
        USE class_mesh, ONLY : check_mesh_consistency
        CALL check_mesh_consistency(msh,msh_phi,op_name)
    END BLOCK

    ! Checks mesh consistency PHI vs. FLD
    IF(PRESENT(fld)) THEN
        CALL fld%get_mesh(msh_fld)
        BLOCK
            USE class_mesh, ONLY : check_mesh_consistency
            CALL check_mesh_consistency(msh_phi,msh_fld,op_name)
        END BLOCK
    END IF

    NULLIFY(msh_fld)
    NULLIFY(msh_phi)

    ! Equation dimensional check
    dim = dim_(phi) * volume_ / time_
    IF(PRESENT(fld)) dim = dim_(fld) * dim
    IF(dim /= dim_(pde)) THEN
        CALL debug_dim(dim_(phi))
        CALL debug_dim(dim_(pde))
        CALL debug_dim(dim)
        WRITE(*,200) TRIM(op_name)
        CALL abort_psblas
    END IF

    ! Computes sign factor
    IF(PRESENT(side)) THEN
        side_ = side
    ELSE
        side_ = lhs_ ! Default = LHS
    END IF
    fsign = pde_sign(sign,side_)


    ! Gets PHI "x" internal values
    CALL get_x(phi,phi_x_old)

    ! Gets FLD "x" internal values
    IF(PRESENT(fld)) THEN
        CALL get_x(fld,fld_x_old)
    ELSE
        ncells = SIZE(phi_x_old)
        ALLOCATE(fld_x_old(ncells),stat=info)
        IF(info /= 0) THEN
            WRITE(*,300) TRIM(op_name)
            CALL abort_psblas
        END IF
        fld_x_old(:) = 1.d0
    END IF

    ! Number of strictly local cells
    ncells = psb_cd_get_local_rows(msh%desc_c)

    ! Gets local to global list for cell indices
    CALL psb_get_loc_to_glob(msh%desc_c,iloc_to_glob)

    ! Computes maximum size of blocks to be inserted
    nmax = size_blk(1,ncells)

    ! Checks timestep size
    IF(dt <= 0.d0) THEN
        WRITE(*,400)
        CALL abort_psblas
    END IF

    dtinv = 1.d0 / dt

    ALLOCATE(A(nmax),b(nmax),ia(nmax),ja(nmax),stat=info)
    IF(info /= 0 ) THEN
        WRITE(*,300) TRIM(op_name)
        CALL abort_psblas
    END IF

    ifirst = 1; ic = 0
    insert: DO
        IF(ifirst > ncells) EXIT insert
        nel = size_blk(ifirst,ncells)

        BLOCK: DO i = 1, nel
            ! Local indices
            ic = ic + 1

            fact = fsign * msh%vol(ic) * dtinv * fld_x_old(ic)

            A(i) = fact
            b(i) = fact * phi_x_old(ic)

            ! Global indices in COO format
            ic_glob = iloc_to_glob(ic)
            ia(i)= ic_glob
            ja(i)= ic_glob
        END DO BLOCK

        CALL spins_pde(nel,ia,ja,A,pde)
        CALL geins_pde(nel,ia,b,pde)

        ifirst = ifirst +  nel

    END DO insert

    DEALLOCATE(A,b,ia,ja)
    DEALLOCATE(iloc_to_glob)

    DEALLOCATE(phi_x_old)
    DEALLOCATE(fld_x_old)
    NULLIFY(msh)

    CALL toc(sw_pde)

100 FORMAT(' ERROR! Operands in ',a,' are not cell centered')
200 FORMAT(' ERROR! Dimensional check failure in ',a)
300 FORMAT(' ERROR! Memory allocation failure in ',a)
400 FORMAT(' ERROR! Missing or illegal time advancing parameters')

    END PROCEDURE scalar_pde_ddt

END SUBMODULE scalar_pde_ddt_implementation
