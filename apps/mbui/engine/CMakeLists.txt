# The still.fail core's engine for the mbui app on Windows (engine.cpp, its C API engine.h), built in Hermes's own tree
# (scripts/native.ts, part `engine` win32-x64, puts this directory there and adds it): Hermes's libhermes linked in
# statically, the Rust shell (client/shell, stillfail_shell.dll) by name, through an import library made from its C ABI
# (stillfail_shell.def). With clang-cl, as Hermes is (MSVC's own fails on Hermes at this tag); the app calls it in C.
add_custom_command(
  OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/stillfail_shell.lib
  COMMAND lib /nologo /machine:x64 /def:${CMAKE_CURRENT_SOURCE_DIR}/stillfail_shell.def /out:${CMAKE_CURRENT_BINARY_DIR}/stillfail_shell.lib
  DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/stillfail_shell.def
  VERBATIM)
add_custom_target(stillfail_shell_lib DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/stillfail_shell.lib)

add_library(stillfail_engine SHARED engine.cpp)
add_dependencies(stillfail_engine stillfail_shell_lib)
target_compile_definitions(stillfail_engine PRIVATE SF_ENGINE_BUILD NOMINMAX WIN32_LEAN_AND_MEAN)
# the JSI's errors are C++ exceptions, caught in the loop
target_compile_options(stillfail_engine PRIVATE /EHsc /GR)
target_link_libraries(stillfail_engine PRIVATE libhermes ${CMAKE_CURRENT_BINARY_DIR}/stillfail_shell.lib bcrypt)
set_target_properties(stillfail_engine PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
  ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
  LIBRARY_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR})
