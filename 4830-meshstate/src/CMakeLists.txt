cmake_minimum_required(VERSION 2.8.8)
project(MESHSTATE_VERIFY C)

find_package(PkgConfig REQUIRED QUIET)
pkg_check_modules(ECDSAUTIL REQUIRED ecdsautil)

include_directories(${ECDSAUTIL_INCLUDE_DIRS})

add_executable(4830-meshstate-verify 4830-meshstate-verify.c)
set_property(TARGET 4830-meshstate-verify PROPERTY COMPILE_FLAGS "-std=c99 -Wall -Wextra")
target_link_libraries(4830-meshstate-verify ${ECDSAUTIL_LIBRARIES})

install(TARGETS 4830-meshstate-verify RUNTIME DESTINATION lib/4830-meshstate)
