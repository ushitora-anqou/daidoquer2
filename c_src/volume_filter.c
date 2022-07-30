#include "erl_nif.h"

#include <stdint.h>

static ERL_NIF_TERM filter(ErlNifEnv *env, int argc,
                           const ERL_NIF_TERM argv[]) {
  ErlNifBinary src;
  if (!enif_inspect_binary(env, argv[0], &src)) {
    // Not a binary
    return enif_make_badarg(env);
  }
  double scale;
  if (!enif_get_double(env, argv[1], &scale)) {
    int scale_int;
    if (enif_get_int(env, argv[1], &scale_int)) {
      scale = scale_int;
    } else {
      // Neither double nor integer
      return enif_make_badarg(env);
    }
  }

  size_t sz = src.size / 2 * 2;
  ERL_NIF_TERM term_filtered, term_rest;
  unsigned char *filtered = enif_make_new_binary(env, sz, &term_filtered),
                *rest = enif_make_new_binary(env, src.size - sz, &term_rest);

  for (size_t i = 0; i < sz; i += 2) {
    // s16le
    int16_t val = ((uint16_t)src.data[i]) | (((uint16_t)src.data[i + 1]) << 8);
    val *= scale;
    filtered[i] = val & 0xff;
    filtered[i + 1] = (val >> 8) & 0xff;
  }
  for (size_t i = sz; i < src.size; i++) {
    rest[i - sz] = src.data[i];
  }

  return enif_make_tuple3(env, enif_make_atom(env, "ok"), term_filtered,
                          term_rest);
}

static ErlNifFunc nif_funcs[] = {
    // {erl_function_name, erl_function_arity, c_function}
    {"filter", 2, filter}};

ERL_NIF_INIT(Elixir.Daidoquer2.VolumeFilter, nif_funcs, NULL, NULL, NULL, NULL)
