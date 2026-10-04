cmake_minimum_required(VERSION 3.25)
if(POLICY CMP0207)
  cmake_policy(SET CMP0207 NEW)
endif()
foreach(required STAGING DEPENDENCY_BIN)
  if(NOT IS_DIRECTORY "${${required}}")
    message(FATAL_ERROR "Missing runtime deployment directory: ${required}")
  endif()
endforeach()
file(GLOB_RECURSE plugins "${STAGING}/*.dll")
file(GET_RUNTIME_DEPENDENCIES
  EXECUTABLES "${STAGING}/scadmaxx.exe"
  LIBRARIES ${plugins}
  DIRECTORIES "${STAGING}" "${DEPENDENCY_BIN}"
  RESOLVED_DEPENDENCIES_VAR resolved
  UNRESOLVED_DEPENDENCIES_VAR unresolved
  PRE_EXCLUDE_REGEXES "[Aa][Pp][Ii]-[Mm][Ss]-.*" "[Ee][Xx][Tt]-[Mm][Ss]-.*"
  POST_EXCLUDE_REGEXES ".*[/\\][Ww][Ii][Nn][Dd][Oo][Ww][Ss][/\\][Ss][Yy][Ss][Tt][Ee][Mm]32[/\\].*")
if(unresolved)
  message(FATAL_ERROR "Unresolved runtime dependencies: ${unresolved}")
endif()
foreach(dependency IN LISTS resolved)
  get_filename_component(name "${dependency}" NAME)
  if(NOT EXISTS "${STAGING}/${name}")
    file(COPY_FILE "${dependency}" "${STAGING}/${name}")
  endif()
endforeach()
