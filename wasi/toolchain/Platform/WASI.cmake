# Minimal CMake platform description for wasm32-wasi.
# Exists so add_library(SHARED) targets keep a .so identity (excluded from
# builds) instead of degrading to duplicate static archives under Generic.
set(WASI 1)
set(UNIX 1)
set(CMAKE_STATIC_LIBRARY_PREFIX "lib")
set(CMAKE_STATIC_LIBRARY_SUFFIX ".a")
set(CMAKE_SHARED_LIBRARY_PREFIX "lib")
set(CMAKE_SHARED_LIBRARY_SUFFIX ".so")
set(CMAKE_EXECUTABLE_SUFFIX ".wasm")
set(CMAKE_DL_LIBS "")
set(CMAKE_FIND_LIBRARY_PREFIXES "lib")
set(CMAKE_FIND_LIBRARY_SUFFIXES ".a")
set_property(GLOBAL PROPERTY TARGET_SUPPORTS_SHARED_LIBS TRUE)
