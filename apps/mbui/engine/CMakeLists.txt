# The still.fail core's engine for the mbui app on Windows and Linux (engine.cpp, its C API engine.h), built in Hermes's
# own tree (scripts/native.ts, part `engine` win32-x64, linux-x64 and linux-arm64, puts this directory there and adds
# it): Hermes's libhermes linked in statically, the Rust shell (client/shell) by name. Windows: with clang-cl, as Hermes
# is (MSVC's own fails on Hermes at this tag), on Windows or cross from a Mac, through an import library made from the
# shell's C ABI (stillfail_shell.def, by the librarian: lib or llvm-lib). Linux: a shared library whose shell symbols
# are left for the loader, which finds libstillfail_shell.so beside it (the app links both). The app calls it in C.
add_library(stillfail_engine SHARED engine.cpp)
target_compile_definitions(stillfail_engine PRIVATE SF_ENGINE_BUILD)
set_target_properties(stillfail_engine PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
  ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
  LIBRARY_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR})

if(WIN32)
  add_custom_command(
    OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/stillfail_shell.lib
    COMMAND ${CMAKE_AR} /nologo /machine:x64 /def:${CMAKE_CURRENT_SOURCE_DIR}/stillfail_shell.def /out:${CMAKE_CURRENT_BINARY_DIR}/stillfail_shell.lib
    DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/stillfail_shell.def
    VERBATIM)
  add_custom_target(stillfail_shell_lib DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/stillfail_shell.lib)
  add_dependencies(stillfail_engine stillfail_shell_lib)
  target_compile_definitions(stillfail_engine PRIVATE NOMINMAX WIN32_LEAN_AND_MEAN)
  # the JSI's errors are C++ exceptions, caught in the loop
  target_compile_options(stillfail_engine PRIVATE /EHsc /GR)
  target_link_libraries(stillfail_engine PRIVATE libhermes ${CMAKE_CURRENT_BINARY_DIR}/stillfail_shell.lib bcrypt)
else()
  # (its own symbols alone exported: Hermes's, linked in, stay inside; named by its file, as the shell is)
  set_target_properties(stillfail_engine PROPERTIES CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON)
  target_link_options(stillfail_engine PRIVATE -Wl,-soname,libstillfail_engine.so -Wl,--exclude-libs,ALL)
  target_link_libraries(stillfail_engine PRIVATE libhermes pthread)
endif()
