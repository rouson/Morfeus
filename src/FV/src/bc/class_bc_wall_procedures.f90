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
! $Id: class_bc_wall.f90 8157 2014-10-09 13:02:44Z sfilippo $
!
! Description:
!    WALL boundary condition class.
!
SUBMODULE(class_bc_wall) class_bc_wall_procedures

    USE class_psblas
    USE class_bc_math

    IMPLICIT NONE

CONTAINS

    ! REMARK: the implementation of run-time polymorphism requires
    ! specific BC object as POINTERS!

    MODULE PROCEDURE nemo_bc_wall_sizeof
        USE psb_base_mod

        INTEGER(kind=nemo_int_long_)   :: val

        val = 2 * nemo_sizeof_int
        val = val + bc%temp%nemo_sizeof() + SUM(bc%vel%nemo_sizeof())
        nemo_bc_wall_sizeof = val

    END PROCEDURE nemo_bc_wall_sizeof

    ! ----- Constructor -----

    MODULE PROCEDURE create_bc_wall
        IMPLICIT NONE
        !
        INTEGER :: info

        ! Alloc bc_wall target on every process

        IF(ASSOCIATED(bc)) THEN
            WRITE(*,100)
            CALL abort_psblas
        ELSE
            ALLOCATE(bc,stat=info)
            IF(info /= 0) THEN
                WRITE(*,200)
                CALL abort_psblas
            END IF
        END IF

        ! Allocates and sets BC class members, according to the parameters
        ! get from the input file.
        CALL rd_inp_bc_wall(input_file,sec,nbf,bc%id,bc%temp,bc%conc,bc%vel,bc%stress)

100     FORMAT(' ERROR! Illegal call to CREATE_BC_WALL: pointer already associated')
200     FORMAT(' ERROR! Memory allocation failure in CREATE_BC_WALL')

    END PROCEDURE create_bc_wall


    ! ----- Destructor -----

    MODULE PROCEDURE free_bc_wall
        IMPLICIT NONE
        !
        INTEGER :: info

        IF(is_allocated(bc%temp)) CALL dealloc_bc_math(bc%temp)
        IF(ANY(is_allocated(bc%vel)))  THEN
            CALL dealloc_bc_math(bc%vel(1))
            CALL dealloc_bc_math(bc%vel(2))
            CALL dealloc_bc_math(bc%vel(3))
        END IF

        DEALLOCATE(bc,stat=info)
        IF(info /= 0) THEN
            WRITE(*,100)
            CALL abort_psblas
        END IF

100     FORMAT(' ERROR! Memory allocation failure in FREE_BC_WALL')

    END PROCEDURE free_bc_wall


    ! ----- Getter -----

    MODULE PROCEDURE get_abc_wall_s
        USE class_dimensions
        IMPLICIT NONE

        IF(dim == temperature_) THEN
            CALL get_abc_math(bc%temp,id,a,b,c)
        ELSEIF(dim == density_) THEN
            CALL get_abc_math(bc%temp,id,a,b,c)
        ELSE

            WRITE(*,100)
            CALL abort_psblas
        END IF

100     FORMAT(' ERROR! Unsupported field dimensions in GET_ABC_WALL_S')

    END PROCEDURE get_abc_wall_s


    MODULE PROCEDURE get_abc_wall_v
        USE class_dimensions
        USE class_vector
        IMPLICIT NONE

        IF(dim == velocity_) THEN
            CALL get_abc_math(bc%vel,id,a,b,c)
        ELSE IF(dim == length_) THEN
            CALL get_abc_math(bc%vel,id,a,b,c)
        ELSE IF(dim == pressure_) THEN
            CALL get_abc_math(bc%stress,id,a,b,c)
        ELSE
            WRITE(*,100)
            CALL abort_psblas
        END IF

        ! REMARK: BC(:) elements are supposed to differ only in "C" term

100     FORMAT(' ERROR! Unsupported field dimensions in GET_ABC_WALL_V')

    END PROCEDURE get_abc_wall_v

    ! ----- Setter -----

    MODULE PROCEDURE set_bc_wall_map_s
        USE class_vector
        USE tools_bc
        USE class_bc_math
        IMPLICIT NONE

        SELECT CASE(bc%id(1))
        CASE(bc_temp_convection_map_)
            CALL set_bc_math_map(bc%temp,i,a,b,c)
        CASE default
            WRITE(*,100)
            CALL abort_psblas
        END SELECT

100     FORMAT(' ERROR! Unsupported BC type in SET_BC_WALL_MAP')

    END PROCEDURE set_bc_wall_map_s


    MODULE PROCEDURE set_bc_wall_map_v
        USE class_vector
        USE tools_bc
        USE class_bc_math
        IMPLICIT NONE

        SELECT CASE(bc%id(2))
        CASE(bc_vel_free_sliding_)
            CALL set_bc_math_map(bc%vel(1),i,a,b,x_(c))
            CALL set_bc_math_map(bc%vel(2),i,a,b,y_(c))
            CALL set_bc_math_map(bc%vel(3),i,a,b,x_(c))
        CASE default
            WRITE(*,100)
            CALL abort_psblas
        END SELECT

100     FORMAT(' ERROR! Unsupported BC type in SET_BC_WALL_MAP')

    END PROCEDURE set_bc_wall_map_v

    ! ----- Boundary Values Updater -----

    MODULE PROCEDURE update_boundary_wall_s
        USE class_dimensions
        USE class_face
        USE class_material
        USE class_mesh
        USE tools_bc
        IMPLICIT NONE
        !
        INTEGER :: i, id, IF, info, ib_offset, n
        REAL(psb_dpk_), ALLOCATABLE :: a(:), b(:), c(:)

        ! WARNING!
        ! - Use intent(inout) for BX(:).

        ! Number of boundary faces with flag < IB
        ib_offset = COUNT(flag_(msh%faces) > 0 .AND. flag_(msh%faces) < ib)

        n = COUNT(flag_(msh%faces) == ib)

        ALLOCATE(a(n),b(n),c(n),stat=info)
        IF(info /= 0) THEN
            WRITE(*,100)
            CALL abort_psblas
        END IF

        IF(dim == temperature_) THEN
            CALL get_abc_math(bc%temp,id,a,b,c)
            IF(  id == bc_neumann_flux_ .OR. &
                id == bc_robin_convection_) THEN
                DO i = 1, n
                    IF = ib_offset + i
                    CALL matlaw(mats,im(i),bx(IF),conductivity_,b(i))
                END DO
            END IF
        ELSEIF(dim == density_) THEN
            CALL get_abc_math(bc%temp,id,a,b,c)
            IF(  id == bc_neumann_flux_ .OR. &
                id == bc_robin_convection_) THEN
                DO i = 1, n
                    IF = ib_offset + i
                    CALL matlaw(mats,im(i),bx(IF),conductivity_,b(i))
                END DO
            END IF
        ELSE

            WRITE(*,200)
            CALL abort_psblas
        END IF

        CALL apply_abc_to_boundary(id,a,b,c,ib,msh,x,bx)

        DEALLOCATE(a,b,c,stat=info)
        IF(info /= 0) THEN
            WRITE(*,300)
            CALL abort_psblas
        END IF

100     FORMAT(' ERROR! Memory allocation failure in UPDATE_BOUNDARY_WALL_S')
200     FORMAT(' ERROR! Unsupported field dimensions in UPDATE_BOUNDARY_WALL_S')
300     FORMAT(' ERROR! Memory deallocation failure in UPDATE_BOUNDARY_WALL_S')

    END PROCEDURE update_boundary_wall_s


    MODULE PROCEDURE update_boundary_wall_v
        USE class_dimensions
        USE class_face
        USE class_mesh
        USE class_vector
        USE tools_bc
        IMPLICIT NONE
        !
        INTEGER :: id, info, ib_offset, n
        REAL(psb_dpk_), ALLOCATABLE :: a(:), b(:)
        TYPE(vector),     ALLOCATABLE :: c(:)

        ! WARNING!
        ! - Use intent(inout) for BX(:).

        ! Number of boundary faces with flag < IB
        ib_offset = COUNT(flag_(msh%faces) > 0 .AND. flag_(msh%faces) < ib)

        n = COUNT(flag_(msh%faces) == ib)

        ALLOCATE(a(n),b(n),c(n),stat=info)
        IF(info /= 0) THEN
            WRITE(*,100)
            CALL abort_psblas
        END IF

        IF(dim == velocity_ .OR. dim == length_) THEN
            CALL get_abc_math(bc%vel,id,a,b,c)
            CALL apply_abc_to_boundary(id,a,b,c,ib,msh,x,bx)
        ELSE IF(dim == pressure_) THEN
            CALL get_abc_math(bc%stress,id,a,b,c)
            CALL apply_abc_to_boundary(id,a,b,c,ib,msh,x,bx)
        ELSE
            WRITE(*,200)
            CALL abort_psblas
        END IF

        DEALLOCATE(a,b,c,stat=info)
        IF(info /= 0) THEN
            WRITE(*,300)
            CALL abort_psblas
        END IF

100     FORMAT(' ERROR! Memory allocation failure in UPDATE_BOUNDARY_WALL_V')
200     FORMAT(' ERROR! Unsupported field dimensions in UPDATE_BOUNDARY_WALL_V')
300     FORMAT(' ERROR! Memory deallocation failure in UPDATE_BOUNDARY_WALL_V')

    END PROCEDURE update_boundary_wall_v

SUBROUTINE rd_inp_bc_wall(input_file,sec,nbf,id,bc_temp,bc_conc,bc_vel,bc_stress)
    USE class_psblas
    USE class_bc_math
    USE tools_bc
    USE tools_input

    IMPLICIT NONE
    !
    CHARACTER(len=*), INTENT(IN) :: input_file
    CHARACTER(len=*), INTENT(IN) :: sec
    INTEGER, INTENT(IN) :: nbf
    INTEGER, INTENT(OUT) :: id(:)
    TYPE(bc_math), INTENT(OUT) :: bc_temp
    TYPE(bc_math), INTENT(OUT) :: bc_conc
    TYPE(bc_math), INTENT(OUT) :: bc_vel(3)
    TYPE(bc_math), INTENT(OUT) :: bc_stress(3)
    !
    LOGICAL, PARAMETER :: debug = .FALSE.
    !
    INTEGER :: mypnum, icontxt
    INTEGER :: id_sec, inp
    REAL(psb_dpk_) :: work(3,5)
    CHARACTER(len=15) :: par

    icontxt = icontxt_()
    mypnum  = mypnum_()

    id   = -1 ! DEFAULT value
    work = 0.d0

    IF(mypnum == 0) THEN

        CALL open_file(input_file,inp)

        CALL find_section(sec,inp)

        WRITE(*,*) '- Reading ', TRIM(sec), ' section: type WALL'

        READ(inp,'()')

        seek_bc: DO
            READ(inp,'(a)') par
            par = TRIM(par)
            BACKSPACE(inp)
            IF(par == 'temperature') THEN
                READ(inp,100,advance='no') par, id_sec

                id(bc_temp_) = id_sec

                SELECT CASE(id_sec)
                CASE(bc_temp_fixed_)      ! Fixed temperature
                    READ(inp,*) work(1,bc_temp_)

                CASE(bc_temp_adiabatic_)  ! Adiabatic wall
                    READ(inp,'()')

                CASE(bc_temp_flux_)       ! Fixed heat flux
                    READ(inp,*) work(1,bc_temp_)

                CASE(bc_temp_convection_) ! Convection
                    READ(inp,*) work(1,bc_temp_), work(2,bc_temp_)

                CASE(bc_temp_convection_map_) ! Convection map
                    READ(inp,'()')         ! To be actually set at the first mapping

                CASE default
                    WRITE(*,210)
                    CALL abort_psblas
                END SELECT

            ELSEIF(par == 'concentration') THEN
                READ(inp,100,advance='no') par, id_sec

                id(bc_conc_) = id_sec

                SELECT CASE(id_sec)
                CASE(bc_conc_fixed_)      ! Fixed temperature
                    READ(inp,*) work(1,bc_temp_)

                CASE(bc_conc_adiabatic_)  ! Adiabatic wall
                    READ(inp,'()')

                CASE default
                    WRITE(*,210)
                    CALL abort_psblas
                END SELECT

            ELSEIF(par == 'velocity') THEN
                READ(inp,100,advance='no') par, id_sec
                id(bc_vel_) = id_sec

                SELECT CASE(id_sec)
                CASE(bc_vel_no_slip_, bc_vel_free_slip_, bc_vel_free_sliding_)
                    READ(inp,'()')
                CASE(bc_vel_sliding_)
                    READ(inp,*) work(1:3,bc_vel_)
                    WRITE(0,*) 'rd_inp_bc_wall: Debug: work', work(1:3,bc_vel_)
                CASE(bc_vel_moving_)
                    READ(inp,'()')
                CASE default
                    WRITE(*,220)
                    CALL abort_psblas
                END SELECT

            ELSEIF(par == 'stress') THEN
                READ(inp,100,advance='no') par, id_sec
                id(bc_stress_) = id_sec

                SELECT CASE(id_sec)
                CASE(bc_stress_free_)
                    READ(inp, '()')
                CASE(bc_stress_prescribed_)
                    READ(inp,*) work(1:3,bc_stress_)
                CASE default
                    WRITE(*,230)
                    CALL abort_psblas
                END SELECT

            ELSEIF(par == 'END OF SECTION') THEN
                EXIT seek_bc

            ELSE
                READ(inp,'()')
            END IF
        END DO seek_bc

        CLOSE(inp)
    END IF


    ! Broadcast
    CALL psb_bcast(icontxt,id)
    CALL psb_bcast(icontxt,work)


    ! TEMPERATURE section
    SELECT CASE(id(bc_temp_))
    CASE(bc_temp_fixed_)      ! Fixed temperature
        CALL alloc_bc_math(bc_temp,bc_dirichlet_,nbf,&
            & a=(/1.d0/),b=(/0.d0/),c=(/work(1,bc_temp_)/))

    CASE(bc_temp_adiabatic_)  ! Adiabatic wall
        CALL alloc_bc_math(bc_temp,bc_neumann_,nbf,&
            & a=(/0.d0/),b=(/1.d0/),c=(/0.d0/))

    CASE(bc_temp_flux_)       ! Fixed heat flux
        CALL alloc_bc_math(bc_temp,bc_neumann_flux_,nbf,&
            & a=(/0.d0/),b=(/1.d0/),c=(/work(1,bc_temp_)/))

    CASE(bc_temp_convection_) ! Convection
        CALL alloc_bc_math(bc_temp,bc_robin_convection_,nbf,&
            & a=(/work(1,bc_temp_)/),b=(/1.d0/),&
            & c=(/work(1,bc_temp_)*work(2,bc_temp_)/))

    CASE(bc_temp_convection_map_) ! Convection map
        CALL alloc_bc_math(bc_temp,bc_robin_map_,nbf,&
            & a=(/(0.d0, inp=1,nbf)/),b=(/(1.d0, inp=1,nbf)/),&
            & c=(/(0.d0, inp=1,nbf)/))

    END SELECT


    ! VELOCITY section
    SELECT CASE(id(bc_vel_))
    CASE(bc_vel_no_slip_)

        CALL alloc_bc_math(bc_vel(1),bc_dirichlet_,nbf,&
            & a=(/1.d0/),b=(/0.d0/),c=(/0.d0/))
        CALL alloc_bc_math(bc_vel(2),bc_dirichlet_,nbf,&
            & a=(/1.d0/),b=(/0.d0/),c=(/0.d0/))
        CALL alloc_bc_math(bc_vel(3),bc_dirichlet_,nbf,&
            & a=(/1.d0/),b=(/0.d0/),c=(/0.d0/))

    CASE(bc_vel_free_slip_)

        CALL alloc_bc_math(bc_vel(1),bc_neumann_,nbf,&
            & a=(/0.d0/),b=(/1.d0/),c=(/0.d0/))
        CALL alloc_bc_math(bc_vel(2),bc_neumann_,nbf,&
            & a=(/0.d0/),b=(/1.d0/),c=(/0.d0/))
        CALL alloc_bc_math(bc_vel(3),bc_neumann_,nbf,&
            & a=(/0.d0/),b=(/1.d0/),c=(/0.d0/))

    CASE(bc_vel_sliding_)
        WRITE(0,*) 'rd_inp_bc_wall: Debug: setting', work(1:3,bc_vel_)
        CALL alloc_bc_math(bc_vel(1),bc_dirichlet_,nbf,&
            & a=(/1.d0/),b=(/0.d0/),c=(/work(1,bc_vel_)/))
        CALL alloc_bc_math(bc_vel(2),bc_dirichlet_,nbf,&
            & a=(/1.d0/),b=(/0.d0/),c=(/work(2,bc_vel_)/))
        CALL alloc_bc_math(bc_vel(3),bc_dirichlet_,nbf,&
            & a=(/1.d0/),b=(/0.d0/),c=(/work(3,bc_vel_)/))
        WRITE(0,*) 'rd_inp_bc_wall: Debug: set'

    CASE(bc_vel_free_sliding_)

        CALL alloc_bc_math(bc_vel(1),bc_dirichlet_map_,nbf,&
            & a=(/1.d0/),b=(/0.d0/),c=(/(0.d0, inp=1,nbf)/))
        CALL alloc_bc_math(bc_vel(2),bc_dirichlet_map_,nbf,&
            & a=(/1.d0/),b=(/0.d0/),c=(/(0.d0, inp=1,nbf)/))
        CALL alloc_bc_math(bc_vel(3),bc_dirichlet_map_,nbf,&
            & a=(/1.d0/),b=(/0.d0/),c=(/(0.d0, inp=1,nbf)/))
    CASE(-1)
    CASE default
        WRITE(0,*) 'Fix here unimplemented BC setup !!'

    END SELECT

    ! Stress section
    SELECT CASE(id(bc_stress_))
    CASE(bc_stress_free_)
        CALL alloc_bc_math(bc_stress(1),bc_neumann_,nbf,&
            & a=(/0.d0/),b=(/1.d0/),c=(/0.d0/))
        CALL alloc_bc_math(bc_stress(2),bc_neumann_,nbf,&
            & a=(/0.d0/),b=(/1.d0/),c=(/0.d0/))
        CALL alloc_bc_math(bc_stress(3),bc_neumann_,nbf,&
            & a=(/0.d0/),b=(/1.d0/),c=(/0.d0/))

    CASE(bc_stress_prescribed_)
        CALL alloc_bc_math(bc_stress(1),bc_dirichlet_,nbf,&
            & a=(/1.d0/),b=(/0.d0/),c=(/work(1,bc_stress_)/))
        CALL alloc_bc_math(bc_stress(2),bc_dirichlet_,nbf,&
            & a=(/1.d0/),b=(/0.d0/),c=(/work(2,bc_stress_)/))
        CALL alloc_bc_math(bc_stress(3),bc_dirichlet_,nbf,&
            & a=(/1.d0/),b=(/0.d0/),c=(/work(3,bc_stress_)/))

    CASE default
        WRITE(0,*) 'Fix here unimplemented BC setup !!', id(bc_stress_)

    END SELECT


    ! ***
    ! If ID = -1 (Default)  the corresponding BC will not be allocated
    ! ***

    IF(debug) THEN
        WRITE(*,*)
        WRITE(*,400) mypnum
        WRITE(*,500) TRIM(sec),' - Type: Wall'

        WRITE(*,600) ' * TEMPERATURE Section *'
        WRITE(*,700) '  BC%id(bc_temp_) = ', id(bc_temp_)
        IF (id(bc_temp_) > 0) CALL debug_bc_math(bc_temp)

        WRITE(*,600) ' * VELOCITY Section *'
        WRITE(*,700) '  BC%id(bc_vel_) = ', id(bc_vel_)
        IF (id(bc_vel_) > 0) THEN
            CALL debug_bc_math(bc_vel(1))
            CALL debug_bc_math(bc_vel(2))
            CALL debug_bc_math(bc_vel(3))
            WRITE(*,*)
        END IF
    END IF


100 FORMAT(a,i1)
210 FORMAT(' ERROR! Unsupported ID(BC_TEMP_) in RD_INP_BC_WALL')
220 FORMAT(' ERROR! Unsupported ID(BC_VEL_) in RD_INP_BC_WALL')
230 FORMAT(' ERROR! Unsupported ID(BC_STRESS_) in RD_INP_BC_WALL')

400 FORMAT(' ----- Process ID = ',i2,' -----')
500 FORMAT(1x,a,a)
600 FORMAT(1x,a)
700 FORMAT(1x,a,i2)

END SUBROUTINE rd_inp_bc_wall

END SUBMODULE class_bc_wall_procedures
