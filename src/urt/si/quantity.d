module urt.si.quantity;

import urt.si.unit;

nothrow @nogc:


alias VarQuantity = Quantity!(double);
alias Scalar = Quantity!(double, ScaledUnit());
alias Metres = Quantity!(double, ScaledUnit(Metre));
alias Seconds = Quantity!(double, ScaledUnit(Second));


struct Quantity(T, ScaledUnit _unit = ScaledUnit(uint.max))
{
nothrow @nogc:

    enum Dynamic = _unit.pack == uint.max;
    alias This = Quantity!(T, _unit);

    T value;

    static if (Dynamic)
        ScaledUnit unit;
    else
        alias unit = _unit;

    this(T value) pure
    {
        static if (Dynamic)
            this.unit = ScaledUnit();
        this.value = value;
    }

    this(U, ScaledUnit _U)(Quantity!(U, _U) b) pure
        if (is(U : T))
    {
        static if (Dynamic)
            unit = b.unit;
        else
        {
            static if (b.Dynamic)
                assert(unit == b.unit, "Incompatible unit!");
            else
                static assert(unit == b.unit, "Incompatible unit: ", unit, " and ", b.unit);
        }
        // get scaling factor...
        value = b.value;
    }

    void opAssign()(T value) pure
    {
        static if (Dynamic)
            unit = Scalar;
        else
            static assert(unit == Unit(), "Incompatible unit: ", unit, " and Scalar");
        this.value = value;
    }

    void opAssign(U, ScaledUnit _U)(Quantity!(U, _U) b) pure
        if (is(U : T))
    {
        static if (Dynamic)
            unit = b.unit;
        else
        {
            static if (b.Dynamic)
                assert(unit == b.unit, "Incompatible unit!");
            else
                static assert(unit == b.unit, "Incompatible unit: ", unit, " and ", b.unit);
        }
        value = b.value;
    }

    auto opBinary(string op, U)(U value) const pure
        if ((op == "+" || op == "-") && is(U : T))
    {
        assert(unit == Scalar);
        return mixin("this.value " ~ op ~ " value");
    }

    auto opBinary(string op, U, ScaledUnit _U)(Quantity!(U, _U) b) const pure
        if ((op == "+" || op == "-") && is(U : T))
    {
        static if (!Dynamic && !b.Dynamic && unit == Unit() && b.unit == Unit())
            return mixin("value " ~ op ~ " b.value");
        else
        {
            assert(unit == b.unit);

            This r;
            r.value = mixin("value " ~ op ~ " b.value");
            static if (Dynamic)
                r.unit = unit;
            return r;
        }
    }

    This opBinary(string op, U)(U value) const pure
        if ((op == "*" || op == "/") && is(U : T))
    {
        This r;
        r.value = mixin("this.value " ~ op ~ " value");
        static if (Dynamic)
            r.unit = unit;
        return r;
    }

    auto opBinary(string op, U, ScaledUnit _U)(Quantity!(U, _U) b) const pure
        if ((op == "*" || op == "/") && is(U : T))
    {
        static if (Dynamic || b.Dynamic)
        {
            Quantity!T r;
            r.unit = mixin("unit " ~ op ~ " b.unit");
        }
        else
            Quantity!(T, mixin("unit " ~ op ~ " b.unit")) r;
        r.value = mixin("value " ~ op ~ " b.value");
        return r;
    }

    void opOpAssign(string op, U)(U value) pure
    {
        this = opBinary!op(value);
    }

    void opOpAssign(string op, U, ScaledUnit _U)(Quantity!(U, _U) b) pure
    {
        this = opBinary!op(b);
    }

    bool opEquals(U)(U value) const pure
        if (is(U : T))
    {
        if (unit == Unit())
            return value == value;
        return false;
    }

    bool opEquals(double epsilon = 0, U, ScaledUnit _U)(Quantity!(U, _U) rh) const pure
        => opCmp!(epsilon, true)(rh);

    auto opCmp(double epsilon = 0, bool eq = false, U, ScaledUnit _U)(Quantity!(U, _U) rh) const pure
        if (is(U : T))
    {
        double lhs = value;
        double rhs = rh.value;

        // if they have the same unit and scale...
        if (unit == rh.unit)
            goto compare;

        // can't compare mismatch unit types... i think?
        assert(unit.canCompare(rh.unit));

        // I think it's more efficient if the scale values are both dynamic...
        enum meetInTheMiddle = Dynamic && rh.Dynamic;

        {
            static if (Dynamic)
            {
                auto lScale = unit.scale(false);
                auto lTrans = unit.offset(false);
            }
            else
            {
                enum lScale = unit.scale(false);
                enum lTrans = unit.offset(false);
            }
            static if (rh.Dynamic)
            {
                auto rScale = rh.unit.scale(!meetInTheMiddle);
                auto rTrans = rh.unit.offset(!meetInTheMiddle);
            }
            else
            {
                enum rScale = rh.unit.scale(!meetInTheMiddle);
                enum rTrans = rh.unit.offset(!meetInTheMiddle);
            }

            static if (meetInTheMiddle)
            {
                lhs = lhs*lScale + lTrans;
                rhs = rhs*rScale + rTrans;
            }
            else
            {
                static if (!Dynamic && !rh.Dynamic)
                {
                    enum scale = lScale*rScale;
                    enum trans = rScale*lTrans + rTrans;
                }
                else
                {
                    auto scale = lScale*rScale;
                    auto trans = rScale*lTrans + rTrans;
                }

                lhs = lhs*scale + trans;
            }
        }

    compare:
        static if (epsilon == 0)
        {
            static if (eq)
                return lhs == rhs;
            else
                return lhs < rhs ? -1 : lhs > rhs ? 1 : 0;
        }
        else
        {
            double cmp = lhs - rhs;
            static if (eq)
                return cmp >= -epsilon && cmp <= epsilon;
            else
                return cmp < -epsilon ? -1 : cmp > epsilon ? 1 : 0;
        }
    }
}


unittest
{
    alias Kilometres = Quantity!(double, Kilometre);
    alias Millimetres = Quantity!(double, Millimetre);
    alias Inches = Quantity!(double, Inch);
    alias Feet = Quantity!(double, Foot);
    alias SqCentimetres = Quantity!(double, Centimetre^^2);
    alias SqInches = Quantity!(double, Inch^^2);
    alias MetresPerSecond = Quantity!(double, ScaledUnit(Metre/Second));
    alias DegreesK = Quantity!(double, ScaledUnit(Kelvin));
    alias DegreesC = Quantity!(double, Celsius);
    alias DegreesF = Quantity!(double, Fahrenheit);

    Scalar a = 1;
    Scalar b = 2;
    assert(a + b == 3);
    assert(a * b == 2);
    a *= 3;
    assert(a == 3);

    a = 10;
    assert(a == 10);

    Metres m = 10;
    assert(m == Metres(10));
    assert(m * b == Metres(20));

    Seconds s = 2;
    auto mps = m/s;
    static assert(is(typeof(mps) == MetresPerSecond));
    assert(mps == MetresPerSecond(5));

    m = mps * 2 * s;
    assert(m == Metres(20));

    VarQuantity v = mps;
    assert(v.unit == Metre/Second);
    v = m;
    assert(v.unit == Metre);
    assert(v * b == Metres(40));

    enum epsilon = 1e-12;

    assert(Kilometres(2).opEquals!epsilon(Metres(2000)));
    assert(Metres(2).opEquals!epsilon(Kilometres(0.002)));
    assert(Kilometres(2).opEquals!epsilon(Millimetres(2000000)));

    assert(Inches(1).opEquals!epsilon(Metres(0.0254)));
    assert(Metres(1).opEquals!epsilon(Inches(1/0.0254)));
    assert(Millimetres(1).opEquals!epsilon(Inches(1/25.4)));
    assert(Inches(1).opEquals!epsilon(Millimetres(25.4)));
    assert(Feet(1).opEquals!epsilon(Inches(12)));
    assert(Inches(12).opEquals!epsilon(Feet(1)));
    assert(SqCentimetres(1).opEquals!epsilon(SqInches(0.15500031)));

    assert(DegreesC(100).opEquals!epsilon(DegreesK(373.15)));
    assert(DegreesK(200).opEquals!epsilon(DegreesC(-73.15)));
    assert(DegreesF(100).opEquals!epsilon(DegreesK(310.92777777777777)));
    assert(DegreesK(200).opEquals!epsilon(DegreesF(-99.67)));
    assert(DegreesC(100).opEquals!epsilon(DegreesF(212)));
    assert(DegreesF(100).opEquals!epsilon(DegreesC(37.77777777777777)));
}
