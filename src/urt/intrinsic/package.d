module urt.intrinsic;

import urt.compiler;
import urt.platform;
import urt.processor;

version (X86) version = Intel;
version (X86_64) version = Intel;

version (Intel)
    public import urt.intrinsic.x86;

pure nothrow @nogc:


version (LDC)
{
    public import ldc.llvmasm;

    struct RO32 { uint r; bool c; }
    struct RO64 { ulong r; bool c; }

    pragma(LDC_intrinsic, "llvm.uadd.with.overflow.i32")
    RO32 _llvm_add_overflow(uint, uint) @safe;
    pragma(LDC_intrinsic, "llvm.uadd.with.overflow.i64")
    RO64 _llvm_add_overflow(ulong, ulong) @safe;

    pragma(LDC_intrinsic, "llvm.usub.with.overflow.i32")
    RO32 _llvm_sub_overflow(uint, uint) @safe;
    pragma(LDC_intrinsic, "llvm.usub.with.overflow.i64")
    RO64 _llvm_sub_overflow(ulong, ulong) @safe;

    pragma(LDC_intrinsic, "llvm.ctlz.i32")
    uint _llvm_ctls(uint, bool) @safe;
    pragma(LDC_intrinsic, "llvm.cttz.i32")
    uint _llvm_ctts(uint, bool) @safe;

    pragma(LDC_intrinsic, "llvm.ctlz.i64")
    uint _llvm_ctls(ulong, bool) @safe;
    pragma(LDC_intrinsic, "llvm.cttz.i64")
    uint _llvm_ctts(ulong, bool) @safe;
}
else version (GNU)
{
    public import gcc.builtins;
}
