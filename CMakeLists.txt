cmake_minimum_required(VERSION 2.6)
project(uri)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE "Debug")
endif(NOT CMAKE_BUILD_TYPE)

find_program(RAGEL "ragel")

function(ragel_gen in_rl)
  add_custom_command(OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/${in_rl}.c
    COMMAND ${RAGEL} -o ${CMAKE_CURRENT_BINARY_DIR}/${in_rl}.c ${CMAKE_CURRENT_SOURCE_DIR}/${in_rl}.rl -I ${CMAKE_CURRENT_SOURCE_DIR} ${ARGN}
    DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/${in_rl}.rl
    )
endfunction(ragel_gen)

if (CMAKE_BUILD_TYPE STREQUAL "Release")
  set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -std=gnu99 -Wall -Wextra -pedantic")
else (CMAKE_BUILD_TYPE STREQUAL "Release")
  set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -std=gnu99 -g3 -ggdb -Wall -Wextra -pedantic")
endif (CMAKE_BUILD_TYPE STREQUAL "Release")

add_definitions(-DURI_USE_GLIB -D_GNU_SOURCE)

include_directories(/usr/include/glib-2.0/ /usr/lib/glib-2.0/include/)

if(RAGEL)
    message("ragel found at: ${RAGEL}")
    include_directories(${CMAKE_CURRENT_SOURCE_DIR})
    if (CMAKE_BUILD_TYPE STREQUAL "Release")
        ragel_gen(uri_parser -G2)
    else (CMAKE_BUILD_TYPE STREQUAL "Release")
        ragel_gen(uri_parser)
    endif (CMAKE_BUILD_TYPE STREQUAL "Release")

    add_library(uri STATIC ${CMAKE_CURRENT_BINARY_DIR}/uri_parser.c)
    target_link_libraries(uri glib-2.0)

    add_executable(test-uri-parse test-uri-parse.c)
    target_link_libraries(test-uri-parse uri)

    add_executable(uri-parse-speed uri-parse-speed.c)
    target_link_libraries(uri-parse-speed uri)
else(RAGEL)
    message("ragel not found. not building libhttp11")
endif(RAGEL)

