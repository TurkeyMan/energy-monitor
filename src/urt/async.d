module urt.async;

import urt.fibre;
import urt.lifetime;
import urt.mem.allocator;
import urt.mem.freelist;
import urt.meta.tuple;
import urt.traits;

public import urt.fibre : yield, sleep;

nothrow @nogc:


Promise!(ReturnType!Fun)* async(alias Fun, size_t stackSize = DefaultStackSize, Args...)(auto ref Args args)
    if (is(typeof(&Fun) == R function(auto ref Args) @nogc, R))
{
    return async!stackSize(&Fun, forward!args);
}

// TODO: nice to rework this; maybe make stackSize a not-template-arg, and receive a function call/closure object which stores the args
Promise!(ReturnType!Fun)* async(size_t stackSize = DefaultStackSize, Fun, Args...)(Fun fun, auto ref Args args)
    if (isSomeFunction!Fun)
{
    alias Result = ReturnType!Fun;
    Promise!Result* r = cast(Promise!Result*)defaultAllocator().alloc(Promise!Result.sizeof, Promise!Result.alignof);

    struct Shim
    {
        Promise!Result* promise = void;
        Fun fn = void;
        Tuple!Args tup = void;

        static void entry(void* userData)
        {
            Shim* this_ = cast(Shim*)userData;

            // store promise and args to the stack, since the context will become invalid when the fibre yields...
            ref Promise!Result r = *this_.promise;
            Tuple!Args args = this_.tup.move;
            static if (is(Result == void))
                this_.fn(args.expand);
            else
                r.value = this_.fn(args.expand);
        }
    }
    auto shim = Shim(r, fun, Tuple!Args(forward!args));

    new(*r) Promise!Result(&shim.entry, &shim, stackSize);
    return r;
}

void freePromise(T)(ref Promise!T* promise)
{
    assert(promise.state() != Promise!T.State.Pending, "Promise still pending!");
    defaultAllocator().freeT(promise);
    promise = null;
}

void asyncUpdate()
{
    AsyncWait* wait = waiting;
    while (wait)
    {
        AsyncWait* t = wait;
        wait = wait.next;

        t.event.update();
        if (t.event.ready())
            t.call.fibre.resume();
    }
}


struct Promise(Result)
{
    enum State
    {
        Pending,
        Ready,
        Failed,
    }

    // construct using `async()` functions...
    this() @disable;
    this(ref typeof(this)) @disable; // disable copy constructor
    this(typeof(this)) @disable;     // disable move constructor

    ~this()
    {
        assert(async, "How did we destruct one of these with no construction?");
        assert(async.fibre.isFinished());
        async.next = freeList;
        freeList = async;
    }

    State state() const
    {
        if (async.fibre.wasAborted())
            return State.Failed;
        else if (async.fibre.isFinished())
            return State.Ready;
        else
            return State.Pending;
    }

    bool finished() const
        => state() != State.Pending;

    ref Result result()
    {
        assert(state() == State.Ready, "Promise not fulfilled!");
        static if (!is(Result == void))
            return value;
    }

    void abort()
    {
        assert(state() == State.Pending, "Promise already fulfilled!");
        async.fibre.abort();
    }

private:
    AsyncCall* async;
    static if (!is(Result == void))
        Result value;

    this(void function(void*) @nogc entry, void* userData, size_t stackSize = DefaultStackSize) nothrow @nogc
    {
        if (freeList)
        {
            async = freeList;
            freeList = async.next;

            // TODO: if we end up with a pool of mixed stack sizes; maybe we want to find the smallest one that fits the requested stack...
            assert(async.fibre.stackSize >= stackSize, "Stack size too small!");
            async.fibre.reset();
        }
        else
            async = defaultAllocator().allocT!AsyncCall(stackSize);
        async.setEntry(entry, userData);

        // TODO: HACK, this should be void-init, and then result emplaced at the assignment
        //       ...but palcement new doesn't work with default initialisation yet!
        static if (!is(Result == void))
            value = Result.init;

        async.fibre.resume();
    }
}


unittest
{
    static int fun(int a, int b) @nogc
    {
        return a + b;
    }

    auto p = async!fun(1, 2);
    assert(p.state() == p.State.Ready);
    assert(p.result() == 3);
    freePromise(p);
    p = async!fun(10, 20);
    assert(p.state() == p.State.Ready);
    assert(p.result() == 30);
    freePromise(p);
}


private:

import urt.util : InPlace, Default;

struct AsyncCall
{
    Fibre fibre = void;
    AsyncCall* next;
    void function(void*) @nogc userEntry;

@nogc:
    this() @disable;
    this(ref typeof(this)) @disable; // disable copy constructor
    this(typeof(this)) @disable;     // disable move constructor

    void setEntry(void function(void*) @nogc entry, void* userData) nothrow
    {
        userEntry = entry;
        next = cast(AsyncCall*)userData;
    }

    this(size_t stackSize) nothrow
    {
        new(fibre) Fibre(&this.entry, &doYield, cast(void*)&this, stackSize);
    }

    static void entry(void* p)
    {
        AsyncCall* this_ = cast(AsyncCall*)p;
        this_.userEntry(this_.next);
    }
}

struct AsyncWait
{
    AsyncCall* call;
    AwakenEvent event;
    AsyncWait* next;

    void resume() nothrow @nogc
    {
        if (waiting == &this)
            waiting = this.next;
        else
        {
            for (AsyncWait* t = waiting; t; t = t.next)
            {
                if (t.next == &this)
                {
                    t.next = this.next;
                    break;
                }
            }
        }
        waitingPool.free(&this);
    }
}

AsyncCall* freeList;
AsyncWait* waiting;

__gshared FreeList!AsyncWait waitingPool;

shared static ~this()
{
    while (freeList)
    {
        AsyncCall* t = freeList;
        freeList = freeList.next;
        defaultAllocator().freeT(t);
    }
}

ResumeHandler doYield(ref Fibre yielding, AwakenEvent awakenEvent)
{
    AsyncWait* wait = waitingPool.alloc();
    wait.call = cast(AsyncCall*)yielding.userData;
    wait.event = awakenEvent;
    wait.next = waiting;
    waiting = wait;

    return &wait.resume;
}
