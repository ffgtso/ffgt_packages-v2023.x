cmake_minimum_required(VERSION 2.8.8)

project(GETIMAGENAME C)

set_property(DIRECTORY PROPERTY COMPILE_DEFINITIONS _GNU_SOURCE)

find_library(PLATFORMINFO_LIBRARY NAMES platforminfo)

find_package(PkgConfig REQUIRED QUIET)


add_executable(get_image_name
  get_image_name.c
)
set_property(TARGET get_image_name PROPERTY COMPILE_FLAGS "-std=c99 -Wall")
#set_property(TARGET get_image_name PROPERTY LINK_FLAGS "")
target_link_libraries(get_image_name
    m
    ${PLATFORMINFO_LIBRARY}
)

install(TARGETS get_image_name RUNTIME DESTINATION sbin)
