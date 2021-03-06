!
!     (c) 2019 Guide Star Engineering, LLC
!     This Software was developed for the US Nuclear Regulatory Commission (US NRC)
!     under contract "Multi-Dimensional Physics Implementation into Fuel Analysis under
!     Steady-state and Transients (FAST)", contract # NRC-HQ-60-17-C-0007
!
submodule(spherical_1D_solver_module) solver_submodule
  use assertions_interface, only : assert
  use kind_parameters, only : r8k, i4k
  implicit none

contains

  module procedure set_v

    integer i

    allocate(this%v(nr,2), source = constants(1))

    associate( dr => 1._r8k/(nr-1) )
      associate( radial_nodes => [( sqrt((i-1)*dr)*0.2, i = 1, nr )] )
        !! cluster grid points near center and near surface
        this%v(:,1) = radial_nodes
      end associate
    end associate
    this%v(:,2) = constants(2)

  end procedure

  module procedure set_material_properties_size
    call assert( allocated(this%v), "spherical_1D_solver%set_material_properties_size: allocated(this%v)")
    associate( nr => size(this%v,1) )
      allocate(this%rho(nr), this%cp(nr))
    end associate
  end procedure

  module procedure set_expected_solution_size
    call assert( allocated(this%v), "spherical_1D_solver%set_expected_solution_size: allocated(this%v)")
    associate( nr => size(this%v,1) )
      allocate( this%T_analytical(nr) )
    end associate
  end procedure

  module procedure time_advance_heat_equation
    integer(i4k) i
    integer, parameter :: time_steps = 1000

    call assert( allocated(this%v), "spherical_1D_solver%time_advance_heat_equation: allocated(this%v)")

    associate( nr => size(this%v,1), dt => duration/real(time_steps, r8k) )

      call time_advancing(nr, dt)
      call analytical_solution(nr)
      call error_calculation(nr)

    end associate

#ifdef FORD
  end procedure
#else
  contains
#endif

    subroutine time_advancing(nr, dt)
      integer, intent(in) :: nr
      real(r8k), intent(in)  :: dt

      real(r8k), dimension(:), allocatable :: a, b, c, d
      real(r8k) t, dr_m,  rf

      real(r8k), parameter :: h=230      !! heat transfer coefficient
      real(r8k), parameter :: Tb=293.15  !! ambient temperature

      t=0.0

      allocate(a(nr),b(nr),c(nr),d(nr))

      do while(t<1000)

        call this%set_rho()
        call this%set_cp()

        i=1
        associate( &
          e    => 1.0/(this%rho(i)*this%cp(i)), &
          dr_f => this%v(i+1,1) - this%v(i,1), &
          rf   => 0.5*(this%v(i+1,1) + this%v(i,1)) &
        )
          b(i) =  6.0*e*kc(rf)/(dr_f**2) + 1.0/dt
          c(i) = -6.0*e*kc(rf)/(dr_f**2)
          d(i) = this%v(i,2)/dt
        end associate

        do concurrent( i=2:nr-1 )
          associate( &
            e    => 1.0/(this%rho(i)*this%cp(i)), &
            dr_f => this%v(i+1,1) - this%v(i  ,1), &
            dr_b => this%v(i  ,1) - this%v(i-1,1), &
            dr_m => 0.5*(this%v(i+1,1) - this%v(i-1,1)), &
            rf   => 0.5*(this%v(i+1,1) + this%v(i,1)), &
            rb   => 0.5*(this%v(i,1)   + this%v(i-1,1)) &
          )
            a(i) = -e*kc(rb)*rb**2/(dr_b*dr_m*this%v(i,1)**2)
            b(i) =  e*kc(rf)*rf**2/(dr_f*dr_m*this%v(i,1)**2) + &
                    e*kc(rb)*rb**2/(dr_b*dr_m*this%v(i,1)**2) + 1.0/dt
            c(i) = -e*kc(rf)*rf**2/(dr_f*dr_m*this%v(i,1)**2)
            d(i) = this%v(i,2)/dt
          end associate
        end do

        i=nr
        associate( e => 1.0/(this%rho(i)*this%cp(i)), dr_b => this%v(i,1) - this%v(i-1,1), rb => 0.5*(this%v(i,1) + this%v(i-1,1)))
          dr_m = dr_b                  !! ifort 18 bug precludes associate( dr_m => dr_b)
          rf = this%v(i,1) + 0.5*dr_b  !! ifort 18 bug precludes associate( rf => this%v(i,1) + 0.5*dr_b)
            a(i)= -1.0*e*kc(rb)*rb**2/(dr_b*dr_m*this%v(i,1)**2)
            b(i)= e*h*rf**2/(dr_m*this%v(i,1)**2) + e*kc(rb)*rb**2/(dr_b*dr_m*this%v(i,1)**2) + 1.0/dt
            d(i)= this%v(i,2)/dt+e*h*Tb*rf**2/(dr_m*this%v(i,1)**2)
        end associate

        this%v(:,2) = tridiagonal_matrix_algorithm(a,b,c,d)
        t=t+dt
      end do
    end subroutine time_advancing

    subroutine analytical_solution(nr)
      integer, intent(in) :: nr
      integer(i4k) i, n
      real(r8k) t, r_0, R, T0, T_inf
      real(r8k), parameter :: pi = 4.0_r8k*atan(1.0_r8k)
      real(r8k), parameter, dimension(*) :: mu = [(( 2*i-1)*pi/2.0, i = 1, 20 )]

      T0=1073.15
      T_inf=293.15
      t=1000.0
      r_0=0.2

      i=1
      R=this%v(i,1)/r_0
      this%T_analytical = &
        sum( [( 2.0*(sin(mu(n))-mu(n)*cos(mu(n)))/(mu(n)-sin(mu(n))*cos(mu(n)))*exp(-1.0e-5*(mu(n)/r_0)**2*t), n = 1, size(mu))] )
      this%T_analytical(i) = (T0-T_inf)*this%T_analytical(i) + T_inf

      do concurrent(i=2:nr)
        R=this%v(i,1)/r_0
        this%T_analytical(i) = &
          sum( [( 2.0*(sin(mu(n))-mu(n)*cos(mu(n)))/(mu(n)-sin(mu(n))*cos(mu(n)))* &
          sin(mu(n)*R)/(mu(n)*R)*exp(-1.0e-5*(mu(n)/r_0)**2*t), n = 1, 6 )] )
        this%T_analytical(i) = (T0-T_inf)*this%T_analytical(i) + T_inf
      end do
    end subroutine analytical_solution

    subroutine error_calculation(nr)
      integer, intent(in) :: nr
      real(r8k), parameter :: tolerance = 0.2

      associate(avg_err_percentage => sum( [( 100.0*(abs(this%v(i,2)- this%T_analytical(i))/this%T_analytical(i)), i=1,nr)] )/ nr)
        if (avg_err_percentage <= tolerance) print *, "Test passed."
      end associate
    end subroutine error_calculation

#ifndef FORD
  end procedure time_advance_heat_equation
#endif

  function tridiagonal_matrix_algorithm(a,b,c,d) result(x)
    !! Thomas algorithm
    real(r8k), dimension(:), intent(inout)  :: a, b, c, d
    real(r8k), dimension(:), allocatable :: x
    integer(i4k) i, n
    real(r8k)  w
    n= size(b)
    allocate(x(n))
    do i=2,n
      w=a(i)/b(i-1)
      b(i)=b(i)-w*c(i-1)
      d(i)=d(i)-w*d(i-1)
    end do
    x(n)=d(n)/b(n)
    do i=n-1,1,-1
      x(i)=(d(i)-c(i)*x(i+1))/b(i)
    end do
  end function

  pure real(r8k) function kc(x) result(thermal_conductivity)
    !! thermal conductivity (constant for comparison to analytical solution)
    real(r8k), intent(in)   :: x
    thermal_conductivity = 46.0_r8k
  end function

  module procedure set_cp
    this%cp=4600.0_r8k
  end procedure

  module procedure set_rho
    this%rho=1000.0_r8k
  end procedure

end submodule solver_submodule
