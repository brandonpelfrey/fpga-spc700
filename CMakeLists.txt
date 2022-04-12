cmake_minimum_required(VERSION 3.0.0)
project(nano_empires VERSION 0.1.0)
set(CPACK_PROJECT_NAME ${PROJECT_NAME})
set(CPACK_PROJECT_VERSION ${PROJECT_VERSION})

set(CMAKE_CXX_STANDARD 17)
include(CPack)

include_directories(src/ gui/ gui/imgui/ gui/imgui/backends)

###############################################
find_package(sdl2 REQUIRED)
include_directories(${SDL2_INCLUDE_DIRS})

find_package(verilator REQUIRED)
include_directories(${VERILATOR_ROOT}/include)

find_package(glfw3 REQUIRED)

###############################################

# Verilog / Verilator
add_library(verilog_TestDSP)
verilate(verilog_TestDSP 
  SOURCES src/TestDSP.v 
  INCLUDE_DIRS src/
)
target_compile_options(verilog_TestDSP PUBLIC -Wno-attributes)
get_target_property(verilog_TestDSP_generated_files verilog_TestDSP VDIR)

file(GLOB module_gui CONFIGURE_DEPENDS 
  gui/*.cpp gui/*.h gui/imgui/*.cpp gui/imgui/*.h
  gui/imgui/backends/imgui_impl_sdl.* gui/imgui/backends/imgui_impl_opengl3.*
)
add_library(gui_lib STATIC ${module_gui} ${verilog_TestDSP}  ${verilog_TestDSP_generated_files}/VTestDSP.h)
target_include_directories(gui_lib PRIVATE ${verilog_TestDSP_generated_files})

# Verilator creates a library, but also creates files. Adding a dependency here to force verilator to compile first.
add_dependencies(gui_lib verilog_TestDSP)

# TODO : This is setup just for Windows at the moment. Make it more generic to work for others as well.
# set(all_libraries mingw32 SDL2main sdl2 PNG opengl32 nano_lib ws2_32 wsock32 gtest)

# For each .cpp in src/targets, create an executable. Link it against everything else.
# file(GLOB_RECURSE all_targets CONFIGURE_DEPENDS src/targets/*.cpp)
# foreach(target_cpp ${all_targets})
#     get_filename_component(target_name ${target_cpp} NAME_WE)
#     add_executable(${target_name} ${target_cpp})
#     target_link_libraries(${target_name} ${all_libraries})
# endforeach()
