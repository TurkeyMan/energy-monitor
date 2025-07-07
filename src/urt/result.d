module urt.result;

nothrow @nogc:


struct Result
{
nothrow @nogc:
    enum success = Result();

    uint systemCode = 0;

    bool opCast(T : bool)() const
        => systemCode == 0;

    bool succeeded() const
        => systemCode == 0;
    bool failed() const
        => systemCode != 0;
}


version (Windows)
{
    import core.sys.windows.windows;

    enum InternalResult : Result
    {
        success =           Result.success,
        buffer_too_small =  Result(ERROR_INSUFFICIENT_BUFFER),
        invalid_parameter = Result(ERROR_INVALID_PARAMETER),
        data_error =        Result(ERROR_INVALID_DATA),
        unsupported =       Result(ERROR_INVALID_FUNCTION),
    }

    Result win32_result(uint err)
        => Result(err);
    Result getlasterror_result()
        => Result(GetLastError());
}
else version (Posix)
{
    import core.stdc.errno;

    enum InternalResult : Result
    {
        success =           Result.success,
        buffer_too_small =  Result(ERANGE),
        invalid_parameter = Result(EINVAL),
        data_error =        Result(EILSEQ),
        unsupported =       Result(ENOTSUP),
    }

    Result posix_result(int err)
        => Result(err);
    Result errno_result()
        => Result(errno);
}
