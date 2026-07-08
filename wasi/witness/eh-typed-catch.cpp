// Step-0 witness for love-wasi: full C++ EH under wasm32-wasi + wasm-EH.
// Proves the behaviors LÖVE's error path needs (luax_catchexcept):
//   1. a typed catch (RTTI match against a base class) actually catches,
//   2. the exception object is inspectable (what() returns the message),
//   3. a thrown payload survives the throw/catch (the caught object is the one
//      that was thrown, not a reconstruction),
//   4. a non-matching handler is skipped so an OUTER matching handler wins
//      (the personality routine's type-mismatch path — a shim-grade EH runtime
//      can pass 1–3 and still botch this, and LÖVE's nested luax_catchexcept
//      sites rely on it),
//   5. destructors run during unwinding.
// Exit code 0 only if all are witnessed.
#include <cstdio>
#include <stdexcept>
#include <string>

static int g_destructors = 0;

struct Tracker {
  ~Tracker() { ++g_destructors; }
};

// A LÖVE-shaped error that also carries a payload, so a check can prove the
// caught object still holds what was thrown rather than a clobbered copy.
struct LoveLikeError : std::runtime_error {
  int tag;
  LoveLikeError(const char *msg, int t) : std::runtime_error(msg), tag(t) {}
};

// Unrelated type used only as a catch clause that must never match.
struct WrongType {};

static void throws_through_a_frame() {
  Tracker t;                                  // must be destroyed by unwind
  throw LoveLikeError("typed message intact", 42);
}

// A LoveLikeError thrown past a catch(WrongType&) must skip that wrong handler
// and be caught by the outer catch(std::exception&). The throw is behind a
// function call, so the mismatch is resolved at run time, not folded away.
static bool nonmatching_skipped() {
  bool inner_ran = false, outer_ran = false;
  try {
    try {
      throws_through_a_frame();
    } catch (const WrongType &) {             // unrelated type: must be skipped
      inner_ran = true;
    }
  } catch (const std::exception &) {          // correct outer handler wins
    outer_ran = true;
  }
  return outer_ran && !inner_ran;
}

int main() {
  int fails = 0;
  auto check = [&](const char *name, bool ok) {
    std::printf("%s %s\n", ok ? "ok  " : "FAIL", name);
    if (!ok) ++fails;
  };

  // 1–3 + 5: typed catch via base class, what() intact, carried payload
  // survived, destructor ran during unwind.
  g_destructors = 0;
  bool typed_caught = false, msg_ok = false, tag_ok = false;
  try {
    throws_through_a_frame();
  } catch (const std::exception &e) {         // typed catch via base class
    typed_caught = true;
    msg_ok = std::string(e.what()) == "typed message intact";
    const auto *le = dynamic_cast<const LoveLikeError *>(&e);
    tag_ok = le && le->tag == 42;             // payload survived throw/catch
  }
  check("typed catch via base class", typed_caught);
  check("what() message intact", msg_ok);
  check("carried payload (tag) intact", tag_ok);
  check("destructor ran during unwind", g_destructors == 1);

  // 4: non-matching handler skipped, outer typed handler wins.
  check("non-matching catch skipped", nonmatching_skipped());

  const bool pass = fails == 0;
  std::printf(pass ? "EH-WITNESS: PASS\n" : "EH-WITNESS: FAIL\n");
  return pass ? 0 : 1;
}
