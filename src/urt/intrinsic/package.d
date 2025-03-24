module urt.intrinsic;

import urt.compiler;
import urt.platform;
import urt.processor;

version (X86) version = Intel;
version (X86_64) version = Intel;

version (Intel)
    public import urt.intrinsic.x86;


version (LDC)
{
    struct RO32 { uint r; bool c; }
    struct RO64 { ulong r; bool c; }

    pragma(LDC_intrinsic, "llvm.uadd.with.overflow.i32")
    RO32 _llvm_add_overflow(uint, uint) pure @safe;
    pragma(LDC_intrinsic, "llvm.uadd.with.overflow.i64")
    RO64 _llvm_add_overflow(ulong, ulong) pure @safe;

    pragma(LDC_intrinsic, "llvm.usub.with.overflow.i32")
    RO32 _llvm_sub_overflow(uint, uint) pure @safe;
    pragma(LDC_intrinsic, "llvm.usub.with.overflow.i64")
    RO64 _llvm_sub_overflow(ulong, ulong) pure @safe;

    pragma(LDC_intrinsic, "llvm.ctlz.i32")
    uint _llvm_ctls(uint, bool) pure @safe;
    pragma(LDC_intrinsic, "llvm.cttz.i32")
    uint _llvm_ctts(uint, bool) pure @safe;

    pragma(LDC_intrinsic, "llvm.ctlz.i64")
    uint _llvm_ctls(ulong, bool) pure @safe;
    pragma(LDC_intrinsic, "llvm.cttz.i64")
    uint _llvm_ctts(ulong, bool) pure @safe;
}
else version (GNU)
{
    import gcc.builtins;
}
