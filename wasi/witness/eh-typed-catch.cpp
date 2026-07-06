// Step-0 witness for love-wasi: full C++ EH under wasm32-wasi + wasm-EH.
// Proves the three things LÖVE's error path needs (luax_catchexcept):
//   1. a typed catch (RTTI match against a base class) actually catches,
//   2. the exception object is inspectable (what() returns the message),
//   3. destructors run during unwinding.
// Exit code 0 only if all three are witnessed.
#include <cstdio>
#include <stdexcept>
#include <string>

static int g_destructors = 0;

struct Tracker {
  ~Tracker() { ++g_destructors; }
};

struct LoveLikeError : std::runtime_error {
  using std::runtime_error::runtime_error;
};

static void throws_through_a_frame() {
  Tracker t;                                  // must be destroyed by unwind
  throw LoveLikeError("typed message intact");
}

int main() {
  bool typed_caught = false, msg_ok = false;
  try {
    throws_through_a_frame();
  } catch (const std::exception &e) {         // typed catch via base class
    typed_caught = true;
    msg_ok = std::string(e.what()) == "typed message intact";
    std::printf("caught typed: %s\n", e.what());
  }
  std::printf("destructors: %d\n", g_destructors);
  const bool pass = typed_caught && msg_ok && g_destructors == 1;
  std::printf(pass ? "EH-WITNESS: PASS\n" : "EH-WITNESS: FAIL\n");
  return pass ? 0 : 1;
}
