#
#     (c) 2019 Guide Star Engineering, LLC
#     This Software was developed for the US Nuclear Regulatory Commission (US NRC)
#     under contract "Multi-Dimensional Physics Implementation into Fuel Analysis under 
#     Steady-state and Transients (FAST)", contract # NRC-HQ-60-17-C-0007
#
if (METIS_INCLUDES AND METIS_LIBRARIES)
  set(METIS_FIND_QUIETLY TRUE)
endif (METIS_INCLUDES AND METIS_LIBRARIES)

if( DEFINED ENV{METISDIR} )
  if( NOT DEFINED METIS_ROOT )
    set(METIS_ROOT "$ENV{METISDIR}")
  endif()
endif()

if( (DEFINED ENV{METIS_ROOT}) OR (DEFINED METIS_ROOT) )
  if( NOT DEFINED METIS_ROOT)
    set(METIS_ROOT "$ENV{METIS_ROOT}")
  endif()
  set(METIS_HINTS "${METIS_ROOT}")
endif()

find_path(METIS_INCLUDES
  NAMES
  metis.h
  HINTS
  ${METIS_HINTS}
  PATHS
  "${INCLUDE_INSTALL_DIR}"
  /usr/local/opt
  /usr/local
  PATH_SUFFIXES
  include
  )

if(METIS_INCLUDES)
  foreach(include IN_LISTS METIS_INCLUDES)
    get_filename_component(mts_include_dir "${include}" DIRECTORY)
    get_filename_component(mts_abs_include_dir "${mts_include_dir}" ABSOLUTE)
    get_filename_component(new_mts_hint "${include_dir}/.." ABSOLUTE )
    list(APPEND METIS_HINTS "${new_mts_hint}")
    break()
  endforeach()
endif()

if(METIS_HINTS)
  list(REMOVE_DUPLICATES METIS_HINTS)
endif()

macro(_metis_check_version)
  file(READ "${METIS_INCLUDES}/metis.h" _metis_version_header)

  string(REGEX MATCH "define[ \t]+METIS_VER_MAJOR[ \t]+([0-9]+)" _metis_major_version_match "${_metis_version_header}")
  set(METIS_MAJOR_VERSION "${CMAKE_MATCH_1}")
  string(REGEX MATCH "define[ \t]+METIS_VER_MINOR[ \t]+([0-9]+)" _metis_minor_version_match "${_metis_version_header}")
  set(METIS_MINOR_VERSION "${CMAKE_MATCH_1}")
  string(REGEX MATCH "define[ \t]+METIS_VER_SUBMINOR[ \t]+([0-9]+)" _metis_subminor_version_match "${_metis_version_header}")
  set(METIS_SUBMINOR_VERSION "${CMAKE_MATCH_1}")
  if(NOT METIS_MAJOR_VERSION)
    message(STATUS "Could not determine Metis version. Assuming version 4.0.0")
    set(METIS_VERSION 4.0.0)
  else()
    set(METIS_VERSION ${METIS_MAJOR_VERSION}.${METIS_MINOR_VERSION}.${METIS_SUBMINOR_VERSION})
  endif()
  if(${METIS_VERSION} VERSION_LESS ${Metis_FIND_VERSION})
    set(METIS_VERSION_OK FALSE)
  else()
    set(METIS_VERSION_OK TRUE)
  endif()

  if(NOT METIS_VERSION_OK)
    message(STATUS "Metis version ${METIS_VERSION} found in ${METIS_INCLUDES}, "
                   "but at least version ${Metis_FIND_VERSION} is required")
  endif(NOT METIS_VERSION_OK)
endmacro(_metis_check_version)

if(METIS_INCLUDES AND Metis_FIND_VERSION)
  _metis_check_version()
else()
  set(METIS_VERSION_OK TRUE)
endif()


find_library(METIS_LIBRARIES metis
  HINTS
  ${METIS_HINTS}
  PATHS
  "${LIB_INSTALL_DIR}"
  /usr/local/
  /usr/local/opt
  PATH_SUFFIXES
  lib
  lib64
  metis/lib)

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(METIS DEFAULT_MSG
  METIS_INCLUDES METIS_LIBRARIES METIS_VERSION_OK)

mark_as_advanced(METIS_INCLUDES METIS_LIBRARIES)
