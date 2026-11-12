cmake_minimum_required(VERSION 3.20)
project(virtuatennis3_vr VERSION 0.1.0 LANGUAGES C)
if(APPLE)
    enable_language(OBJC)       # the runtime's macOS menu bar
endif()

# Virtua Tennis 3 (Sega Lindbergh), statically recompiled from the player's
# own copy and built on the lindberghrecomp runtime (the submodule). The
# game's folder is games/vt3; the layout keeps one folder per game, as in
# the upstream lindbergh-recomp-ports.
#
# A game's target only exists once you have lifted its ELF into
# games/<game>/generated, because the runtime needs two headers generated
# from it. Without any this still configures and builds the toolkit's own
# self-check, so the repo is testable out of the box.
#
#   ./scripts/build-macos.sh vt3 /path/to/disk0        (macOS)
#   quest/build.sh vt3                                  (Meta Quest APK)
#
# LINDBERGH_GAMES=<game;...> builds only those (the Quest build makes one
# game per build tree: each is the app's libmain.so).

set(LINDBERGH_GAMES "" CACHE STRING "games to build (empty: every one with lifted code)")

# OpenGL by default: the renderer Virtua Tennis 3 is built and tested with
# (macOS, and gl4es on the Quest). -DLINDBERGH_RENDERER=VULKAN builds the
# runtime's native Vulkan renderer, untested for this game. (Defined here
# first because C++ must be enabled at this scope.)
set(LINDBERGH_RENDERER "OPENGL" CACHE STRING "Host renderer: OPENGL or VULKAN")
if(LINDBERGH_RENDERER STREQUAL "VULKAN")
    enable_language(CXX)
endif()
add_subdirectory(lindberghrecomp)

function(lindbergh_game id)
    set(src "${CMAKE_CURRENT_SOURCE_DIR}/games/${id}/src")
    set(gen "${CMAKE_CURRENT_SOURCE_DIR}/games/${id}/generated")
    file(GLOB lifted "${gen}/recomp_funcs_*.c")
    if(NOT lifted OR NOT EXISTS "${gen}/recomp_imports.h")
        message(STATUS "${id}: no lifted code in ${gen} yet, not built. See the README.")
        return()
    endif()
    if(ANDROID)
        # Meta Quest: SDL's Java side loads libmain.so and calls SDL_main
        # (android_main.c), which runs host.c's main.
        add_library(${id} SHARED "${src}/host.c" "${src}/android_main.c" ${lifted})
        set_target_properties(${id} PROPERTIES OUTPUT_NAME main)
        set_source_files_properties("${src}/host.c" PROPERTIES COMPILE_DEFINITIONS main=game_main)
        if(EXISTS "${src}/splash_art.c")
            # the headset's start-up screen (quest/tools/<game>_splash.py)
            target_sources(${id} PRIVATE "${src}/splash_art.c")
        endif()
    else()
        add_executable(${id} "${src}/host.c" ${lifted})
    endif()
    if(NOT WIN32 OR CMAKE_SIZEOF_VOID_P EQUAL 8)
        # Typed GL thunks for a 64-bit host, generated from the host's GL
        # headers (lindberghrecomp/tools/gen_gl_thunks.py): on the Quest from
        # gl4es' when the game has its own set for them
        if(LINDBERGH_RENDERER STREQUAL "VULKAN")
            set(vk_thunks "${CMAKE_CURRENT_BINARY_DIR}/vulkan-thunks-${id}.c")
            execute_process(COMMAND "${LINDBERGH_VULKAN_PYTHON}"
                "${CMAKE_CURRENT_SOURCE_DIR}/lindberghrecomp/tools/gen_gl_thunks.py"
                "${gen}/recomp_imports.h" ${LINDBERGH_GL_HEADERS}
                OUTPUT_FILE "${vk_thunks}.tmp" COMMAND_ERROR_IS_FATAL ANY)
            execute_process(COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${vk_thunks}.tmp" "${vk_thunks}" COMMAND_ERROR_IS_FATAL ANY)
            file(REMOVE "${vk_thunks}.tmp")
            set(LINDBERGH_VULKAN_THUNKS_${id} "${vk_thunks}" CACHE INTERNAL "Vulkan guest thunks" FORCE)
            target_sources(${id} PRIVATE "${vk_thunks}")
        elseif(WIN32)
            target_sources(${id} PRIVATE "${gen}/recomp_gl_thunks_windows.c")
        elseif(ANDROID AND EXISTS "${gen}/recomp_gl_thunks_android.c")
            target_sources(${id} PRIVATE "${gen}/recomp_gl_thunks_android.c")
        else()
            target_sources(${id} PRIVATE "${gen}/recomp_gl_thunks.c")
        endif()
        # libraries the game dlopens, lifted by lindberghrecomp/tools/recomp/solib.py:
        # their code, and their relocation table - their bytes are read at
        # start-up from the player's files (solib.c). An older lift embedded the
        # whole library (recomp_solib_img.c): never build that into the app.
        if(EXISTS "${gen}/recomp_solib_img.c")
            message(FATAL_ERROR "${gen}/recomp_solib_img.c embeds the game's library bytes; "
                "delete it and lift again (scripts/build-macos.sh) - the app reads them from the player's files")
        endif()
        file(GLOB solib "${gen}/recomp_solib_*.c")
        target_sources(${id} PRIVATE ${solib})
    endif()
    lindbergh_runtime(${id} "${gen}")
    message(STATUS "${id}: building against lifted code in ${gen}")
endfunction()

file(GLOB game_dirs LIST_DIRECTORIES true "${CMAKE_CURRENT_SOURCE_DIR}/games/*")
foreach(dir ${game_dirs})
    if(IS_DIRECTORY "${dir}" AND EXISTS "${dir}/src/host.c")
        get_filename_component(id "${dir}" NAME)
        if(NOT LINDBERGH_GAMES OR id IN_LIST LINDBERGH_GAMES)
            lindbergh_game(${id})
        endif()
    endif()
endforeach()
