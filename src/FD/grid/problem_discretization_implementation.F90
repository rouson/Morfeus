!
!     (c) 2019-2020 Guide Star Engineering, LLC
!     This Software was developed for the US Nuclear Regulatory Commission (US NRC) under contract
!     "Multi-Dimensional Physics Implementation into Fuel Analysis under Steady-state and Transients (FAST)",
!     contract # NRC-HQ-60-17-C-0007
!
submodule(problem_discretization_interface) define_problem_discretization
  !! author: Damian Rouson and Karla Morris
  !! date: 9/9/2019
  use assertions_interface, only : assert, assertions, max_errmsg_len
  use iso_fortran_env, only : error_unit
  use kind_parameters, only : i4k, r8k
  implicit none

  integer, parameter :: success=0

contains

  module procedure get_surface_packages
    this_surface_packages = this%block_surfaces%get_halo_outbox()
  end procedure

  module procedure get_block_surfaces
    this_block_surfaces = this%block_surfaces
  end procedure

  module procedure get_global_block_shape
    if (assertions) &
      call assert(allocated(this%block_map), "problem_discretization%get_global_block_shape: allocated(this%block_map)")
    block_shape = this%block_map%get_global_block_shape()
  end procedure

  module procedure write_output
    use string_functions_interface, only : file_extension, base_name
    implicit none
    !! author: Ian Porter
    !! date: 11/25/2019
    !!
    !! This is a generic procedure for writing output files. This procedure eliminates the DTIO
    !! to allow for linking to external libraries that handle all of the file output
    !!
    character(len=:), allocatable :: extension, basename
    integer :: iostat
    iostat = 0

    basename = base_name(filename)
    extension = file_extension(filename)

    select case (extension)
    case ('vtu')
      call vtk_output (this, basename, iostat)
    case ('csv')
      call csv_output( this, filename, iostat)
   case default
     error stop "problem_discretization%write_output: unsupported file type" // &
#ifdef HAVE_NON_CONSTANT_ERROR_STOP
     & filename ! Fortran 2018
#else
     & "."       ! Fortran 2008
#endif
   end select

  end procedure write_output

  subroutine csv_output (this, filename, iostat)
    class(problem_discretization), intent(in) ::this
    character(len=*), intent(in) :: filename
    integer, intent(inout), optional :: iostat
    character(len=132) :: iomsg
    integer, dimension(0) :: v_list
    integer  :: file_unit
    integer ib

    open(newunit=file_unit, file=filename)
    write(file_unit,'(4("      ",a,:,",",5x))') "x","y","z","layer (phony)"
    do ib=lbound(this%vertices,1), ubound(this%vertices,1)
      call this%vertices(ib)%write_formatted(file_unit,'DT', v_list, iostat, iomsg)
    end do
  end subroutine

  subroutine vtk_output (this, filename, iostat)
    use vtk_datasets,   only : unstruct_grid
    use vtk,            only : vtk_serial_write
    use vtk_cells,      only : voxel, vtkcell_list
    use vtk_attributes, only : attributes
    use array_functions_interface, only : OPERATOR(.catColumns.), OPERATOR(.columnVectors.)
    implicit none
    type vtk_data
      real(r8k), dimension(:), allocatable :: point_scalars, point_div_flux
    end type
    type(vtk_data), dimension(:), allocatable :: vtk_data_
    class(problem_discretization), intent(in) ::this
    character(LEN=*), intent(in), optional :: filename
    integer, intent(out) :: iostat
    type(voxel) :: voxel_cell  !! Voxel cell type
    type(vtkcell_list), dimension(:), allocatable :: cell_list !! Full list of all cells
    integer(i4k) :: ip, jp, kp !! block-local point id
    integer(i4k) :: ic, jc, kc !! block-local cell id
    real(r8k), dimension(:,:), allocatable :: points
    integer(i4k), dimension(:), allocatable :: block_cell_material, point_block_id
    type(attributes) :: grid_point_attributes, cell_attributes
    integer :: b, s, first_point_in_block, first_cell_in_block

    if (assertions) call assert(allocated(this%vertices), "problem_discretization%vtk_output: allocated(this%vertices())")

    allocate( cell_list(sum( this%vertices%num_cells())) )
    associate(my_first_block => lbound(this%vertices,1))
      allocate( points(this%vertices(my_first_block)%space_dimension(),0), block_cell_material(0), point_block_id(0) )
    end associate
    allocate( vtk_data_(this%num_scalars()) )
    do s = 1, this%num_scalars()
      allocate( vtk_data_(s)%point_scalars(0), vtk_data_(s)%point_div_flux(0) )
    end do

    first_point_in_block = 0
    first_cell_in_block = 1

    loop_over_grid_blocks: do b=lbound(this%vertices,1), ubound(this%vertices,1)

      associate( vertex_positions => this%vertices(b)%vectors() ) !! 4D array of nodal position vectors
        associate( npoints => shape(vertex_positions(:,:,:,1)) )  !! shape of 1st 3 dims specifies # points in ea. direction
          associate( ncells => npoints-1 )

            if (allocated(this%scalar_fields)) then
              loop_over_sclar_fields: &
              do s = 1, this%num_scalars()
                vtk_data_(s)%point_scalars = [vtk_data_(s)%point_scalars, this%scalar_fields(b,s)%get_scalar()]
              end do loop_over_sclar_fields
              if (allocated(this%scalar_flux_divergence)) then
                call assert(shape(this%scalar_fields)==shape(this%scalar_flux_divergence), "vtk_output: consistent scalar data")
                loop_over_flux_divergences: &
                do s = 1, this%num_scalars()
                  vtk_data_(s)%point_div_flux = [vtk_data_(s)%point_div_flux, this%scalar_flux_divergence(b,s)%get_scalar()]
                end do loop_over_flux_divergences
              end if
            end if

            points = points .catColumns. ( .columnVectors. vertex_positions )
            block_cell_material = [ block_cell_material, (this%vertices(b)%get_tag(), ic=1,PRODUCT(ncells)) ]
            point_block_id = [ point_block_id, [( b, ip=1, PRODUCT(npoints) )] ]

            do ic=1,ncells(1)
              do jc=1,ncells(2)
                do kc=1,ncells(3)
                  associate( block_local_point_id => & !! 8-element array of block-local IDs for voxel corners
                    [( [( [( kp*PRODUCT(npoints(1:2)) + jp*npoints(1) + ip, ip=ic,ic+1 )], jp=jc-1,jc )], kp=kc-1,kc )] &
                  )
                    call voxel_cell%setup ( first_point_in_block + block_local_point_id-1 )
                  end associate
                  associate( local_cell_id => (kc-1)*PRODUCT(ncells(1:2)) + (jc-1)*ncells(1) + ic )
                    associate(  cell_id => first_cell_in_block + local_cell_id - 1 )
                      allocate(cell_list(cell_id)%cell, source=voxel_cell)!GCC8 workaround for cell_list(i)%cell= voxel_cell
                    end associate
                  end associate
                end do
              end do
            end do

            first_cell_in_block  = first_cell_in_block  + PRODUCT( ncells  )
            first_point_in_block = first_point_in_block + PRODUCT( npoints )
          end associate
        end associate
      end associate
    end do loop_over_grid_blocks

    call assert( SIZE(point_block_id,1) == SIZE(points,2), "VTK block point data set & point set size match" )
    call assert( SIZE(block_cell_material,1) == SIZE(cell_list,1), "VTK cell data set & cell set size match" )

    call define_scalar(  cell_attributes, REAL( block_cell_material, r8k),  'material' )
    call define_scalar(  grid_point_attributes, REAL( point_block_id, r8k),  'block' )

    block
      type(unstruct_grid) vtk_grid
      type(attributes), dimension(:), allocatable :: scalar_attributes, flux_divergence_attributes, point_attributes
      character(len=*), parameter :: max_num_scalars='999'
      character(len=len(max_num_scalars)) scalar_number

      point_attributes = [grid_point_attributes]

      allocate( scalar_attributes(this%num_scalars()) )
      do s=1,size(scalar_attributes)
        write(scalar_number,'(i3)') s
        call define_scalar( scalar_attributes(s), vtk_data_(s)%point_scalars, 'scalar '//adjustl(trim(scalar_number)) )
        point_attributes = [point_attributes, scalar_attributes]
      end do

      allocate( flux_divergence_attributes(this%num_scalar_flux_divergences()) )
      do s=1,size(flux_divergence_attributes)
        write(scalar_number,'(i3)') s
        call define_scalar(flux_divergence_attributes(s), vtk_data_(s)%point_div_flux, 'divergence '//adjustl(trim(scalar_number)))
        point_attributes = [point_attributes, flux_divergence_attributes]
      end do

      call vtk_grid%init (points=points, cell_list=cell_list )
      call vtk_serial_write( &
        filename=filename, geometry=vtk_grid, multiple_io=.TRUE., celldatasets=[cell_attributes], pointdatasets=point_attributes)
    end block

    iostat = 0

#ifdef FORD
  end subroutine vtk_output
#else
  contains
#endif

    subroutine define_scalar( s, vals, dataname )
      use vtk_attributes, only : scalar, attributes
      implicit none
      class(attributes), intent(INOUT) :: s
      real(r8k),         intent(in)    :: vals(:)
      character(LEN=*),  intent(in)    :: dataname

      if (.NOT. allocated(s%attribute)) allocate(scalar::s%attribute)
      call s%attribute%init (dataname, numcomp=1, real1d=vals)
    end subroutine

#ifndef FORD
  end subroutine vtk_output
#endif

  pure function evenly_spaced_points( boundaries, resolution, direction ) result(grid_nodes)
    !! Define grid point coordinates with uniform spacing in the chosen block
    real(r8k), intent(in) :: boundaries(:,:)
      !! block boundaries of each coordinate direction
    integer(i4k), intent(in) :: resolution(:)
      !! number of grid points in each direction
    integer(i4k), intent(in) :: direction
      !! coordinate direction to define
    real(r8k), allocatable :: grid_nodes(:,:,:)
      !! grid node locations and spacing in each coordination direction
    real(r8k), allocatable :: dx(:)
    integer alloc_status
    character(len=max_errmsg_len) :: alloc_error

    integer(i4k), parameter :: lo_bound=1, up_bound=2, num_boundaries=2
    integer(i4k) ix,iy,iz

    allocate(grid_nodes(resolution(1),resolution(2),resolution(3)), stat=alloc_status, errmsg=alloc_error )
    call assert( alloc_status==success, "evenly_spaced_points allocation ("//alloc_error//")", PRODUCT(resolution) )

    associate( num_intervals => resolution - 1 )
      dx = ( boundaries(:,up_bound) - boundaries(:,lo_bound) ) / num_intervals(:)
    end associate

    associate( nx=>resolution(1), ny=>resolution(2), nz=>resolution(3) )

    select case(direction)
      case(1)
        do concurrent(iy=1:ny,iz=1:nz)
          associate( internal_points => boundaries(direction,lo_bound) + [(ix*dx(direction),ix=1,nx-num_boundaries)] )
            grid_nodes(:,iy,iz) = [ boundaries(direction,lo_bound), internal_points , boundaries(direction,up_bound) ]
          end associate
        end do
      case(2)
        do concurrent(ix=1:nx,iz=1:nz)
          associate( internal_points => boundaries(direction,lo_bound) + [(iy*dx(direction),iy=1,ny-num_boundaries)] )
            grid_nodes(ix,:,iz) = [ boundaries(direction,lo_bound), internal_points , boundaries(direction,up_bound) ]
          end associate
        end do
      case(3)
        do concurrent(ix=1:nx,iy=1:ny)
          associate( internal_points => boundaries(direction,lo_bound) + [(iz*dx(direction),iz=1,nz-num_boundaries)] )
            grid_nodes(ix,iy,:) = [ boundaries(direction,lo_bound), internal_points, boundaries(direction,up_bound) ]
          end associate
        end do
      case default
        error stop "evenly_spaced_points: invalid direction"
    end select

    end associate

  end function

  module procedure initialize_from_plate_3D
    use cartesian_grid_interface, only : cartesian_grid
    integer, parameter :: lo_bound=1, up_bound=2 !! array indices corresponding to end points on 1D spatial interval
    integer, parameter :: nx_min=2, ny_min=2, nz_min=2
    integer n
    type(cartesian_grid) prototype
      !! used only for dynamic type information about the grid type in the partitioning procedure

    call this%partition( plate_3D_geometry%get_block_metadata_shape(), prototype )
      !! partition a block-structured grids across images

    associate( my_blocks => this%my_blocks() )

      do n = my_blocks(lo_bound) , my_blocks(up_bound) ! TODO: make concurrent after Intel supports co_sum

        call this%vertices(n)%set_block_identifier(n)

        associate( ijk => this%block_map%block_indicial_coordinates(n) )

          associate( metadata => plate_3D_geometry%get_block_metadatum(ijk))

            call this%vertices(n)%set_metadata( metadata  )

            associate( &
              block => plate_3D_geometry%get_block_domain(ijk), &
              max_spacing => metadata%get_max_spacing() &
            )
              associate( &
                nx => max( nx_min, floor( abs(block(1,up_bound) - block(1,lo_bound))/max_spacing ) + 1 ), &
                ny => max( ny_min, floor( abs(block(2,up_bound) - block(2,lo_bound))/max_spacing ) + 1 ), &
                nz => max( nz_min, floor( abs(block(3,up_bound) - block(3,lo_bound))/max_spacing ) + 1 ) &
              )
                associate( &
                  x => evenly_spaced_points(  block, [nx,ny,nz], direction=1 ), &
                  y => evenly_spaced_points(  block, [nx,ny,nz], direction=2 ), &
                  z => evenly_spaced_points(  block, [nx,ny,nz], direction=3 ) )
                  call this%set_vertices(x,y,z,block_identifier=n)
                end associate
              end associate
            end associate
          end associate
        end associate
      end do

    end associate

    this%problem_geometry = plate_3D_geometry

  end procedure

  module procedure initialize_from_cylinder_2D
    use cylindrical_grid_interface, only : cylindrical_grid
    integer, parameter :: lo_bound=1, up_bound=2 !! array indices corresponding to end points on 1D spatial interval
    integer, parameter :: nx_min=2, ny_min=2, nz_min=2
    integer n
    type(cylindrical_grid) prototype
      !! used only for dynamic type information about the grid type in the partitioning procedure

    call this%partition( cylinder_2D_geometry%get_block_metadata_shape(), prototype )
      !! partition a block-structured grids across images

    associate( my_blocks => this%my_blocks() )

      do n = my_blocks(lo_bound) , my_blocks(up_bound) ! TODO: make concurrent after Intel supports co_sum

        call this%vertices(n)%set_block_identifier(n)

        associate( ijk => this%block_map%block_indicial_coordinates(n) )

          associate( metadata => cylinder_2D_geometry%get_block_metadatum(ijk))

            call this%vertices(n)%set_metadata( metadata  )

            associate( &
              block => cylinder_2D_geometry%get_block_domain(ijk), &
              max_spacing => metadata%get_max_spacing() &
            )
              associate( &
                nx => max( nx_min, floor( abs(block(1,up_bound) - block(1,lo_bound))/max_spacing ) + 1 ), &
                ny => max( ny_min, floor( abs(block(2,up_bound) - block(2,lo_bound))/max_spacing ) + 1 ), &
                nz => max( nz_min, floor( abs(block(3,up_bound) - block(3,lo_bound))/max_spacing ) + 1 ) &
              )
                associate( &
                  x => evenly_spaced_points(  block, [nx,ny,nz], direction=1 ), &
                  y => evenly_spaced_points(  block, [nx,ny,nz], direction=2 ), &
                  z => evenly_spaced_points(  block, [nx,ny,nz], direction=3 ) )
                  call this%set_vertices(x,y,z,block_identifier=n)
                end associate
              end associate
            end associate
          end associate
        end associate
      end do

    end associate

    this%problem_geometry = cylinder_2D_geometry

  end procedure

  module procedure initialize_from_sphere_1D
    use spherical_grid_interface, only : spherical_grid
    integer, parameter :: lo_bound=1, up_bound=2 !! array indices corresponding to end points on 1D spatial interval
    integer, parameter :: nr_min=2, ntheta_min=2, nphi_min=2
    integer n
    type(spherical_grid) prototype
      !! used only for dynamic type information about the grid type in the partitioning procedure

    call this%partition( sphere_1D_geometry%get_block_metadata_shape(), prototype )
      !! partition a block-structured grids across images

    associate( my_blocks => this%my_blocks() )

      do n = my_blocks(lo_bound) , my_blocks(up_bound) ! TODO: make concurrent after Intel supports co_sum

        call this%vertices(n)%set_block_identifier(n)

        associate( ijk => this%block_map%block_indicial_coordinates(n) )

          associate( metadata => sphere_1D_geometry%get_block_metadatum(ijk))

            call this%vertices(n)%set_metadata( metadata  )

            associate( &
              block => sphere_1D_geometry%get_block_domain(ijk), &
              max_spacing => metadata%get_max_spacing() &
            )
              associate( &
                nr =>     max( nr_min, floor( abs(block(1,up_bound) - block(1,lo_bound))/max_spacing ) + 1 ), &
                ntheta => 1, &
                nphi =>   1 &
              )
                associate( &
                  r =>     evenly_spaced_points(  block, [nr,ntheta,nphi], direction=1 ), &
                  theta => evenly_spaced_points(  block, [nr,ntheta,nphi], direction=2 ), &
                  phi =>   evenly_spaced_points(  block, [nr,ntheta,nphi], direction=3 ) )
                  call this%set_vertices(r,theta,phi,block_identifier=n)
                end associate
              end associate
            end associate
          end associate
        end associate
      end do

    end associate

    this%end_time = sphere_1D_geometry%get_end_time()
    this%problem_geometry = sphere_1D_geometry

  end procedure

  module procedure partition

    integer alloc_status, image, num_blocks
    character(len=max_errmsg_len) alloc_error

    allocate( this%block_map, stat=alloc_status, errmsg=alloc_error, mold=prototype )
    call assert(alloc_status==0, "problem_discretization%partition: allocate(this%block_map)", alloc_error)

    call this%block_map%set_global_block_shape( global_block_shape )

    associate( me => this_image(), ni => num_images(), num_blocks => product(global_block_shape) )

      this%block_partitions = [ [(first_block(image, num_blocks), image=1,ni)], last_block(ni, num_blocks) + 1 ]

      associate( my_first => this%block_partitions(me), my_last =>  this%block_partitions(me+1)-1)

        allocate( this%vertices(my_first:my_last), stat=alloc_status, errmsg=alloc_error, mold=prototype )
        call assert(alloc_status==success, "partition: allocate(this%vertices(...)", alloc_error)

        if (assertions) then
          block
#ifndef HAVE_COLLECTIVE_SUBROUTINES
            use emulated_intrinsics_interface, only : co_sum
#endif
            integer total_blocks
            total_blocks = size(this%vertices)
            call co_sum(total_blocks,result_image=1)
            if (me==1) call assert(total_blocks==num_blocks,"all blocks have been distributed amongst the images")
            sync all
          end block
        end if
      end associate
    end associate

    ! Assures
    call this%mark_as_defined

#ifndef FORD
  contains
#else
  end procedure
#endif

    pure function overflow(image,remainder) result(filler)
      integer, intent(in) :: image,remainder
      integer :: filler
      filler = merge(1,0,image<=remainder)
    end function

    pure function first_block( image, num_blocks ) result(block_id)
      integer, intent(in) :: image, num_blocks
      integer block_id, i
      associate( ni => num_images() )
        associate( remainder => mod(num_blocks,ni), quotient => num_blocks/ni )
          block_id = 1 + sum([(quotient + overflow(i, remainder), i= 1, image-1)])
        end associate
      end associate
    end function

    pure function last_block( image, num_blocks ) result(block_id)
      integer, intent(in) :: image, num_blocks
      integer block_id
      associate( ni => num_images() )
        associate( remainder => mod(num_blocks,ni), quotient => num_blocks/ni )
           block_id = first_block(image, num_blocks) + quotient + overflow(image, remainder) - 1
        end associate
      end associate
    end function

#ifndef FORD
  end procedure
#endif

  module procedure my_blocks
    character(len=128) error_data

    block_identifier_range = [ lbound(this%vertices), ubound(this%vertices) ]

    if (assertions) then
      associate(me=>this_image())
        call assert( allocated(this%block_partitions), "problem%discretization%my_blocks: allocated(this%block_partitions)" )
        write(error_data,*) block_identifier_range, "/=", [this%block_partitions(me), this%block_partitions(me+1)-1]
        call assert( all(block_identifier_range == [this%block_partitions(me), this%block_partitions(me+1)-1]), &
        "problem_discretization%my_blocks: all(blocks_identifer_range==[this%block_partitions(me),this%block_partitions(me+1)-1])",&
        error_data)
      end associate
    end if

  end procedure

  module procedure block_identifier

    call assert( allocated(this%block_map), "problem_discretization%block_identifier: allocated(this%block_map)")
    n = this%block_map%block_identifier(ijk)

  end procedure

  module procedure block_indicial_coordinates

    call assert( allocated(this%block_map), "problem_discretization%block_indicial_coordinates: allocated(this%block_map)")
    ijk = this%block_map%block_indicial_coordinates(n)

  end procedure

  module procedure block_load

    ! Requires
    call assert(this%user_defined(),"block_load: this object defined")

    if (allocated(this%vertices)) then
      num_blocks = size(this%vertices)
    else
      num_blocks = 0
    end if

  end procedure

  module procedure user_defined_vertices

    ! Requires
    call assert( &
      block_identifier>=lbound(this%vertices,1) .and. block_identifier<=ubound(this%vertices,1), &
      "set_vertices: block identifier in bounds" &
    )

    associate(n=>block_identifier)
      call this%vertices(n)%set_vector_components(x_nodes,y_nodes,z_nodes)
    end associate

  end procedure

  module procedure set_scalar_flux_divergence
    integer b, f, alloc_status
    character(len=128) alloc_error
    class(structured_grid), allocatable :: exact_flux_div
    type(package), allocatable, dimension(:,:,:) :: surface_packages

    call assert(allocated(this%scalar_fields), "set_scalar_flux_divergence: allocated(this%scalar_fields)")
    if (allocated(this%scalar_flux_divergence)) deallocate(this%scalar_flux_divergence)

    associate(num_fields => this%num_scalars())

      if (.not. allocated(this%scalar_flux_divergence)) then
        allocate(this%scalar_flux_divergence(lbound(this%vertices,1) : ubound(this%vertices,1), num_fields ), &
          stat=alloc_status, errmsg=alloc_error, mold=this%vertices(lbound(this%vertices,1)) )
        call assert( alloc_status==success, "set_scalar_flux_divergence: allocation", alloc_error )
        do b = lbound(this%vertices,1), ubound(this%vertices,1)
          do f = 1, num_fields
            call this%scalar_flux_divergence(b,f)%set_scalar_identifier(f)
            call this%scalar_flux_divergence(b,f)%set_block_identifier(b)
          end do
        end do
      end if

      if (present(exact_result)) &
        call assert(size(exact_result)==num_fields, "problem_discretization%set_scalar_flux_divergence: size(exact_result)")

        internal_values: &
        do b = lbound(this%vertices,1), ubound(this%vertices,1)
          do f = 1, num_fields
            call this%scalar_fields(b,f)%set_up_div_scalar_flux( &
              this%vertices(b), this%block_surfaces, this%scalar_flux_divergence(b,f) )
          end do
        end do internal_values

        sync all !! the above loop sets normal-flux data just inside each block boundary for communication in the loop below

        halo_exchange: &
        do concurrent( b = lbound(this%vertices,1): ubound(this%vertices,1), f = 1: num_fields )
          call this%scalar_fields(b,f)%div_scalar_flux( this%vertices(b), this%block_surfaces, this%scalar_flux_divergence(b,f) )
        end do halo_exchange

        verify_result: &
        if (present(exact_result)) then
          loop_over_blocks: &
          do  b = lbound(this%vertices,1), ubound(this%vertices,1)
          loop_over_scalar_fields: &
            do  f = 1, num_fields
              select type (my_flux_div => exact_result(f)%laplacian(this%vertices(b)))
              class is (structured_grid)
                exact_flux_div = my_flux_div
              class default
                error stop 'Error: the type of exact_result(f)%laplacian(this%vertices(b)) is not structured_grid.'
              end select
              call this%scalar_flux_divergence(b,f)%compare( exact_flux_div, tolerance=1.E-06_r8k )
            end do loop_over_scalar_fields
          end do loop_over_blocks
        end if verify_result

    end associate

  end procedure

  module procedure set_analytical_scalars
    integer b, f, alloc_status
    character(len=max_errmsg_len) :: alloc_error

    if (assertions) call assert(allocated(this%vertices), "problem_discretization%set_analytical_scalars: allocated(this%vertices)")

    associate( num_scalars => size(scalar_setters) )

      if (.not. allocated(this%scalar_fields)) then
        allocate( this%scalar_fields(lbound(this%vertices,1) : ubound(this%vertices,1), num_scalars), &
          stat=alloc_status, errmsg=alloc_error, mold=this%vertices(lbound(this%vertices,1)) )
        call assert( alloc_status==success, "set_analytical_scalars: scalar_field allocation", alloc_error)

        do b = lbound(this%vertices,1), ubound(this%vertices,1)
          do f = 1, num_scalars
            call this%scalar_fields(b,f)%set_scalar_identifier(f)
            call this%scalar_fields(b,f)%set_block_identifier(b)
          end do
        end do
      end if

      loop_over_blocks: &
      do b = lbound(this%vertices,1), ubound(this%vertices,1)
        loop_over_functions: &
        do f = 1, num_scalars
          select type( scalar_values => scalar_setters(f)%evaluate( this%vertices(b) ) )
            class is( structured_grid )
              call this%scalar_fields(b,f)%clone( scalar_values )
            class default
              error stop "problem_discretization%set_analytical_scalars: unsupported scalar_values grid type"
          end select
        end do loop_over_functions
      end do loop_over_blocks

      call assert( allocated(this%problem_geometry), &
        "problem_discretization%set_analytical_scalars: allocated(this%problem_geometry)")

      call this%block_map%build_surfaces( &
        this%problem_geometry, this%vertices, this%block_surfaces, this%block_partitions, num_scalars)
    end associate

  end procedure

  module procedure  num_scalars
    if (allocated(this%scalar_fields)) then
      num_scalar_fields = size(this%scalar_fields,2)
    else
      num_scalar_fields = 0
    end if
  end procedure

  module procedure  num_scalar_flux_divergences
    if (allocated(this%scalar_flux_divergence)) then
      num_divergences = size(this%scalar_flux_divergence,2)
    else
      num_divergences = 0
    end if
  end procedure

  module procedure solve_governing_equations
    use spherical_1D_solver_module, only : spherical_1D_solver
    use kind_parameters, only : r8k

    type(spherical_1D_solver) conducting_sphere

    call conducting_sphere%set_v( nr = 101, constants = [0._r8k, 1073.15_r8k] )
    call conducting_sphere%set_expected_solution_size()
    call conducting_sphere%set_material_properties_size()
    call conducting_sphere%time_advance_heat_equation( duration = this%end_time )

  end procedure

end submodule define_problem_discretization
