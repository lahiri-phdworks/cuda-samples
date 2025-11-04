# InstallSamples.cmake
# Configuration for installing CUDA samples to organized directory structure
#
# This module sets up installation paths organized by:
#   - Target Architecture (x86_64, aarch64, etc.)
#   - Target OS (linux, windows, darwin)
#   - Build Type (release, debug)
#
# Default installation path: build/bin/${TARGET_ARCH}/${TARGET_OS}/${BUILD_TYPE}
#
# Installation structure:
#   - Executables: installed to flat root directory only (easy access)
#   - Data files (.ll, .ptx, .fatbin, etc.): installed to subdirectories (preserves relative paths)
#   - run_tests.py handles path resolution automatically for both nested and flat structures
#
# Users can override by setting CMAKE_INSTALL_PREFIX or CUDA_SAMPLES_INSTALL_DIR

# Detect target architecture - use lowercase of CMAKE_SYSTEM_PROCESSOR
string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" TARGET_ARCH)

# Detect target OS
if(WIN32)
    set(TARGET_OS "windows")
elseif(APPLE)
    set(TARGET_OS "darwin")
elseif(UNIX)
    if(CMAKE_SYSTEM_NAME MATCHES QNX)
        set(TARGET_OS "qnx")
    else()
        set(TARGET_OS "linux")
    endif()
else()
    set(TARGET_OS "unknown")
endif()

# Get build type (default to release if not specified)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "release")
endif()
string(TOLOWER "${CMAKE_BUILD_TYPE}" BUILD_TYPE_LOWER)

# Set default install prefix to build/bin if not explicitly set by user
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
    set(CMAKE_INSTALL_PREFIX "${CMAKE_BINARY_DIR}/bin" CACHE PATH "Installation directory" FORCE)
endif()

# Create the installation path: bin/$(TARGET_ARCH)/$(TARGET_OS)/$(BUILD_TYPE)
set(CUDA_SAMPLES_INSTALL_DIR "${CMAKE_INSTALL_PREFIX}/${TARGET_ARCH}/${TARGET_OS}/${BUILD_TYPE_LOWER}" CACHE PATH "Installation directory for CUDA samples")

# Print installation configuration only once
if(NOT CUDA_SAMPLES_INSTALL_CONFIG_PRINTED)
    message(STATUS "CUDA Samples installation configured:")
    message(STATUS "  Architecture: ${TARGET_ARCH}")
    message(STATUS "  OS: ${TARGET_OS}")
    message(STATUS "  Build Type: ${BUILD_TYPE_LOWER}")
    message(STATUS "  Install Directory: ${CUDA_SAMPLES_INSTALL_DIR}")
    set(CUDA_SAMPLES_INSTALL_CONFIG_PRINTED TRUE CACHE INTERNAL "Installation config printed flag")
endif()

# Function to setup installation for regular samples
# This should be called after all targets are defined
function(setup_samples_install)
    # Create an install script that will copy executables and specific file types
    # - Executables: copied to flat root directory (easy access)
    # - Data files: copied to subdirectories (preserves relative paths)
    # - run_tests.py automatically tries flattened paths as fallback
    # This script runs at install time, after the build is complete
    install(CODE "
        
        # Search in the current project's binary directory for built executables
        file(GLOB_RECURSE BINARY_FILES 
             LIST_DIRECTORIES false
             \"${CMAKE_CURRENT_BINARY_DIR}/*\")
        
        # Copy data files from sample's own data directory
        file(GLOB_RECURSE SAMPLE_DATA_FILES
             LIST_DIRECTORIES false
             \"${CMAKE_CURRENT_SOURCE_DIR}/data/*\")
        
        # Copy shared data files from Common/data directory
        # Try both paths: ../../../Common (for regular samples) and ../../../../Common (for Tegra)
        set(COMMON_DATA_FILES \"\")
        if(EXISTS \"${CMAKE_CURRENT_SOURCE_DIR}/../../../Common/data\")
            file(GLOB_RECURSE COMMON_DATA_FILES
                 LIST_DIRECTORIES false
                 \"${CMAKE_CURRENT_SOURCE_DIR}/../../../Common/data/*\")
        elseif(EXISTS \"${CMAKE_CURRENT_SOURCE_DIR}/../../../../Common/data\")
            file(GLOB_RECURSE COMMON_DATA_FILES
                 LIST_DIRECTORIES false
                 \"${CMAKE_CURRENT_SOURCE_DIR}/../../../../Common/data/*\")
        endif()
        
        # Combine all lists
        set(SAMPLE_FILES \${BINARY_FILES} \${SAMPLE_DATA_FILES} \${COMMON_DATA_FILES})
        
        # Filter to include executable files and specific file types
        foreach(SAMPLE_FILE IN LISTS SAMPLE_FILES)
            # Skip non-files
            if(NOT IS_DIRECTORY \"\${SAMPLE_FILE}\")
                get_filename_component(SAMPLE_EXT \"\${SAMPLE_FILE}\" EXT)
                get_filename_component(SAMPLE_NAME \"\${SAMPLE_FILE}\" NAME)
                
                set(SHOULD_INSTALL FALSE)
                
                # Skip build artifacts and CMake files
                if(NOT SAMPLE_EXT MATCHES \"\\\\.(o|a|so|cmake)$\" AND
                   NOT SAMPLE_NAME MATCHES \"^(Makefile|cmake_install\\\\.cmake)$\" AND
                   NOT \"\${SAMPLE_FILE}\" MATCHES \"/CMakeFiles/\")
                    
                    # Check if file has required extension (fatbin, ptx, bc, raw, ppm) or is executable
                    if(SAMPLE_EXT MATCHES \"\\\\.(fatbin|ptx|bc|raw|ppm)$\")
                        set(SHOULD_INSTALL TRUE)
                    else()
                        # Check if file is executable
                        if(IS_SYMLINK \"\${SAMPLE_FILE}\" OR 
                           (EXISTS \"\${SAMPLE_FILE}\" AND NOT IS_DIRECTORY \"\${SAMPLE_FILE}\"))
                            execute_process(
                                COMMAND test -x \"\${SAMPLE_FILE}\"
                                RESULT_VARIABLE IS_EXEC
                                OUTPUT_QUIET ERROR_QUIET
                            )
                            if(IS_EXEC EQUAL 0)
                                set(SHOULD_INSTALL TRUE)
                            endif()
                        endif()
                    endif()
                endif()
                
                if(SHOULD_INSTALL)
                    get_filename_component(FILE_NAME \"\${SAMPLE_FILE}\" NAME)
                    set(DEST_FILE \"${CUDA_SAMPLES_INSTALL_DIR}/\${FILE_NAME}\")
                    
                    # Check if file is executable
                    execute_process(
                        COMMAND test -x \"\${SAMPLE_FILE}\"
                        RESULT_VARIABLE HAS_EXEC_BIT
                        OUTPUT_QUIET ERROR_QUIET
                    )
                    
                    get_filename_component(DEST_DIR \"\${DEST_FILE}\" DIRECTORY)
                    
                    if(HAS_EXEC_BIT EQUAL 0)
                        # File is executable - copy with execute permissions
                        message(STATUS \"Installing executable: \${DEST_FILE}\")
                        file(COPY \"\${SAMPLE_FILE}\"
                             DESTINATION \"\${DEST_DIR}\"
                             FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE 
                                              GROUP_READ GROUP_EXECUTE 
                                              WORLD_READ WORLD_EXECUTE)
                    else()
                        # Regular file - copy without execute permissions
                        message(STATUS \"Installing data file: \${DEST_FILE}\")
                        file(COPY \"\${SAMPLE_FILE}\"
                             DESTINATION \"\${DEST_DIR}\"
                             FILE_PERMISSIONS OWNER_READ OWNER_WRITE
                                              GROUP_READ
                                              WORLD_READ)
                    endif()
                endif()
            endif()
        endforeach()
    ")
endfunction()
