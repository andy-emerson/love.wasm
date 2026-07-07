// Single-threaded love::thread backend for wasm32-wasi — build-order step 3.
//
// wasm32-wasi has no threads; real love.thread arrives as Web Workers at
// build-order step 7 (readme.md, seam 3). But love's *core* consumes the
// love::thread factory surface unconditionally (common/Data.cpp lazily
// creates a member mutex; common/deprecation.cpp guards its list with one),
// so the seam needs an implementation, not just an absent module.
//
// On a single thread these are semantically exact, not fakes: an
// uncontendable mutex is a no-op, and waiting on a conditional with no
// other thread to signal it can only time out. Starting a Thread is the
// one thing that cannot be honest here, so it fails (start() == false),
// loudly matching Threadable::start's failure path — nothing in the
// step-3 module set starts threads.
#include "thread/Thread.h"
#include "thread/threads.h"

namespace love
{
namespace thread
{

namespace
{

class NullMutex final : public Mutex
{
public:
	void lock() override {}
	void unlock() override {}
};

class NullConditional final : public Conditional
{
public:
	void signal() override {}
	void broadcast() override {}
	bool wait(Mutex *, int) override { return false; }  // nobody can signal
};

class NullThread final : public Thread
{
public:
	bool start() override { return false; }  // no second thread exists
	void wait() override {}
	bool isRunning() override { return false; }
};

} // anonymous namespace

Mutex *newMutex()
{
	return new NullMutex();
}

Conditional *newConditional()
{
	return new NullConditional();
}

Thread *newThread(Threadable *)
{
	return new NullThread();
}

} // thread
} // love
