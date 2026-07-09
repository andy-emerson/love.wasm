#ifndef __CONFIG_TYPES_H__
#define __CONFIG_TYPES_H__
/* love-wasi: generated from config_types.h.in for wasm32-wasi (stdint path).
 * Not upstream-verbatim — this is the build product configure/cmake would emit. */
#define INCLUDE_INTTYPES_H 0
#define INCLUDE_STDINT_H 1
#define INCLUDE_SYS_TYPES_H 0
#if INCLUDE_STDINT_H
#  include <stdint.h>
#endif
typedef int16_t  ogg_int16_t;
typedef uint16_t ogg_uint16_t;
typedef int32_t  ogg_int32_t;
typedef uint32_t ogg_uint32_t;
typedef int64_t  ogg_int64_t;
typedef uint64_t ogg_uint64_t;
#endif
