cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)
apply_standard_settings(${BINARY_NAME})
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)
add_dependencies(${BINARY_NAME} flutter_assemble)
# Only the install-generated bundle's copy of the executable will launch
# correctly, since the resources must in the right relative locations. To
# avoid people trying to run the unbundled copy, put it in a subdirectory
# instead of the default top-level location.
set_target_properties(${BINARY_NAME}
  PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}/intermediates_do_not_run"
)
