# Version 2.0+
# Public Domain, originally written by Lasse Kärkkäinen <tronic>
# Maintained at https://github.com/Tronic/cmake-modules
# Please send your improvements as pull requests on Github.

# Works the same as find_package, but forwards the "REQUIRED" argument used for
# the current package and always uses the "QUIET" flag. For this to work, the
# first parameter must be the prefix of the current package, then the prefix of
# the new package etc, which are passed to find_package.
macro (libfind_package PREFIX PKG)
  set (LIBFIND_PACKAGE_ARGS ${PKG} ${ARGN} QUIET)
  if (${PREFIX}_FIND_REQUIRED)
    set (LIBFIND_PACKAGE_ARGS ${LIBFIND_PACKAGE_ARGS} REQUIRED)
  endif()
  find_package(${LIBFIND_PACKAGE_ARGS})
  unset(LIBFIND_PACKAGE_ARGS)
  list(APPEND ${PREFIX}_DEPENDENCIES ${PKG})
endmacro (libfind_package)

# A simple wrapper to make pkg-config searches a bit easier.
# Works the same as CMake's internal pkg_check_modules but is always quiet.
macro (libfind_pkg_check_modules)
  find_package(PkgConfig QUIET)
  if (PKG_CONFIG_FOUND)
    pkg_check_modules(${ARGN} QUIET)
  endif()
endmacro()

# Extracts a version #define from a version.h file, output stored to <PREFIX>_VERSION.
# Usage: libfind_version_header(Foobar foobar/version.h FOOBAR_VERSION_STR)
# Fourth argument "QUIET" may be used for silently testing different define names.
# This function does nothing if the version variable is already defined.
function (libfind_version_header PREFIX VERSION_H DEFINE_NAME)
  # Skip processing if we already have a version or if the include dir was not found
  if (${PREFIX}_VERSION OR NOT ${PREFIX}_INCLUDE_DIR)
    return()
  endif()
  set(quiet ${${PREFIX}_FIND_QUIETLY})
  # Process optional arguments
  foreach(arg ${ARGN})
    if (arg STREQUAL "QUIET")
      set(quiet TRUE)
    else()
      message(AUTHOR_WARNING "Unknown argument ${arg} to libfind_version_header ignored.")
    endif()
  endforeach()
  # Read the header and parse for version number
  set(filename "${${PREFIX}_INCLUDE_DIR}/${VERSION_H}")
  if (NOT EXISTS ${filename})
    if (NOT quiet)
      message(AUTHOR_WARNING "Unable to find ${${PREFIX}_INCLUDE_DIR}/${VERSION_H}")
    endif()
    return()
  endif()
  file(READ "${filename}" header)
  string(REGEX REPLACE ".*#[ \t]*define[ \t]*${DEFINE_NAME}[ \t]*\"([^\n]*)\".*" "\\1" match "${header}")
  # No regex match?
  if (match STREQUAL header)
    if (NOT quiet)
      message(AUTHOR_WARNING "Unable to find \#define ${DEFINE_NAME} \"<version>\" from ${${PREFIX}_INCLUDE_DIR}/${VERSION_H}")
    endif()
    return()
  endif()
  # Export the version string
  set(${PREFIX}_VERSION "${match}" PARENT_SCOPE)
endfunction()

# Do the final processing once the paths have been detected.
# If include dirs are needed, ${PREFIX}_PROCESS_INCLUDES should be set to contain
# all the variables, each of which contain one include directory.
# Ditto for ${PREFIX}_PROCESS_LIBS and library files.
# Will set ${PREFIX}_FOUND, ${PREFIX}_INCLUDE_DIRS and ${PREFIX}_LIBRARIES.
# Also handles errors in case library detection was required, etc.
function (libfind_process PREFIX)
  # Skip processing if already processed during this configuration run
  if (${PREFIX}_FOUND)
    return()
  endif()

  set(found TRUE)  # Start with the assumption that the package was found

  # Did we find any files? Did we miss includes? These are for formatting better error messages.
  set(some_files FALSE)
  set(missing_headers FALSE)

  # Shorthands for some variables that we need often
  set(quiet ${${PREFIX}_FIND_QUIETLY})
  set(required ${${PREFIX}_FIND_REQUIRED})
  set(exactver ${${PREFIX}_FIND_VERSION_EXACT})
  set(findver "${${PREFIX}_FIND_VERSION}")
  set(version "${${PREFIX}_VERSION}")

  # Lists of config option names (all, includes, libs)
  unset(configopts)
  set(includeopts ${${PREFIX}_PROCESS_INCLUDES})
  set(libraryopts ${${PREFIX}_PROCESS_LIBS})

  # Process deps to add to 
  foreach (i ${PREFIX} ${${PREFIX}_DEPENDENCIES})
    if (DEFINED ${i}_INCLUDE_OPTS OR DEFINED ${i}_LIBRARY_OPTS)
      # The package seems to export option lists that we can use, woohoo!
      list(APPEND includeopts ${${i}_INCLUDE_OPTS})
      list(APPEND libraryopts ${${i}_LIBRARY_OPTS})
    else()
      # If plural forms don't exist or they equal singular forms
      if ((NOT DEFINED ${i}_INCLUDE_DIRS AND NOT DEFINED ${i}_LIBRARIES) OR
          ({i}_INCLUDE_DIR STREQUAL ${i}_INCLUDE_DIRS AND ${i}_LIBRARY STREQUAL ${i}_LIBRARIES))
        # Singular forms can be used
        if (DEFINED ${i}_INCLUDE_DIR)
          list(APPEND includeopts ${i}_INCLUDE_DIR)
        endif()
        if (DEFINED ${i}_LIBRARY)
          list(APPEND libraryopts ${i}_LIBRARY)
        endif()
      else()
        # Oh no, we don't know the option names
        message(FATAL_ERROR "We couldn't determine config variable names for ${i} includes and libs. Aieeh!")
      endif()
    endif()
  endforeach()
  
  if (includeopts)
    list(REMOVE_DUPLICATES includeopts)
  endif()
  
  if (libraryopts)
    list(REMOVE_DUPLICATES libraryopts)
  endif()

  # Include/library names separated by spaces (notice: not CMake lists)
  unset(includes)
  unset(libs)

  # Process all includes and set found false if any are missing
  foreach (i ${includeopts})
    list(APPEND configopts ${i})
    if (NOT "${${i}}" STREQUAL "${i}-NOTFOUND")
      set(includes ${includes} ${${i}})
    else()
      set(found FALSE)
      set(missing_headers TRUE)
    endif()
  endforeach()

  # Process all libraries and set found false if any are missing
  foreach (i ${libraryopts})
    list(APPEND configopts ${i})
    if (NOT "${${i}}" STREQUAL "${i}-NOTFOUND")
      set(libs ${libs} ${${i}})
    else()
      set (found FALSE)
    endif()
  endforeach()

  # Version checks
  if (found AND findver)
    if (NOT version)
      message (AUTHOR_WARNING "Find${PREFIX}.cmake does not provide version information. Either fix the module or remove any find_package() version requirements.")
      set(found FALSE)
    elseif (version VERSION_LESS findver OR (exactver AND NOT version VERSION_EQUAL findver))
      set(found FALSE)
      set(version_unsuitable TRUE)
    endif()
  endif()

  # If all-OK, hide all config options, export variables, print status and exit
  if (found)
    foreach (i ${configopts})
      mark_as_advanced(${i})
    endforeach()
    set (${PREFIX}_INCLUDE_OPTS ${includeopts} PARENT_SCOPE)
    set (${PREFIX}_LIBRARY_OPTS ${libraryopts} PARENT_SCOPE)
    set (${PREFIX}_INCLUDE_DIRS ${includes} PARENT_SCOPE)
    set (${PREFIX}_LIBRARIES ${libs} PARENT_SCOPE)
    set (${PREFIX}_FOUND TRUE PARENT_SCOPE)
    if (NOT quiet)
      message(STATUS "Found ${PREFIX} ${${PREFIX}_VERSION}")
    endif()
    return()    
  endif()

  # Format messages for debug info and the type of error
  set(vars "Relevant CMake configuration variables:\n")
  foreach (i ${configopts})
    mark_as_advanced(CLEAR ${i})
    set(val ${${i}})
    if ("${val}" STREQUAL "${i}-NOTFOUND")
      set (val "<not found>")
    elseif (val AND NOT EXISTS ${val})
      set (val "${val}  (does not exist)")
    else()
      set(some_files TRUE)
    endif()
    set(vars "${vars}  ${i}=${val}\n")
  endforeach()
  set(vars "${vars}You may use CMake GUI, cmake -D or ccmake to modify the values. Delete CMakeCache.txt to discard all values and force full re-detection if necessary.\n")
  if (version_unsuitable)
    set(msg "${PREFIX} ${${PREFIX}_VERSION} was found but")
    if (exactver)
      set(msg "${msg} only version ${findver} is acceptable.")
    else()
      set(msg "${msg} version ${findver} is the minimum requirement.")
    endif()
  else()
    if (missing_headers)
      set(msg "We could not find development headers for ${PREFIX}. Do you have the necessary dev package installed?")
    elseif (some_files)
      set(msg "We only found some files of ${PREFIX}, not all of them. Perhaps your installation is incomplete or maybe we just didn't look in the right place?")
      if(findver)
        set(msg "${msg} This could also be caused by incompatible version (if it helps, at least ${PREFIX} ${findver} should work).")
      endif()
    else()
      set(msg "We were unable to find package ${PREFIX}.")
    endif()
  endif()

  # Fatal error out if REQUIRED
  if (required)
    set(msg "REQUIRED PACKAGE NOT FOUND\n${msg} This package is REQUIRED and you need to install it or adjust CMake configuration in order to continue building ${CMAKE_PROJECT_NAME}.")
    message(FATAL_ERROR "${msg}\n${vars}")
  endif()
  # Otherwise just print a nasty warning
  if (NOT quiet)
    message(WARNING "WARNING: MISSING PACKAGE\n${msg} This package is NOT REQUIRED and you may ignore this warning but by doing so you may miss some functionality of ${CMAKE_PROJECT_NAME}. \n${vars}")
  endif()
endfunction()

