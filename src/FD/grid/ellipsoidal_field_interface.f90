!
!     (c) 2019 Guide Star Engineering, LLC
!     This Software was developed for the US Nuclear Regulatory Commission (US NRC)
!     under contract "Multi-Dimensional Physics Implementation into Fuel Analysis under
!     Steady-state and Transients (FAST)", contract # NRC-HQ-60-17-C-0007
!
module ellipsoidal_field_interface
  use differentiable_field_interface, only : differentiable_field
  use cartesian_grid_interface, only : cartesian_grid
  implicit none

  private
  public :: ellipsoidal_field

  type, extends(differentiable_field) :: ellipsoidal_field
  contains
    procedure evaluate
    procedure laplacian
  end type

  interface

    module function evaluate(this, grid_points) result(f)
      implicit none
      class(ellipsoidal_field), intent(in)  :: this
      type(cartesian_grid), intent(in)  :: grid_points
      type(cartesian_grid f
    end function

    module function laplacian(this, grid_points) result(laplacian_f)
      implicit none
      class(ellipsoidal_field), intent(in)  :: this
      type(cartesian_grid), intent(in)  :: grid_points
      type(cartesian_grid) laplacian_f
    end function

  end interface

end module ellipsoidal_field_interface
