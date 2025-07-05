module manager.base;

import urt.array;
import urt.lifetime;
import urt.map;
import urt.meta;
import urt.mem.string;
import urt.mem.temp;
import urt.variant;
import urt.string;

public import manager.collection : collectionTypeInfo, CollectionTypeInfo;

nothrow @nogc:


enum WorkingState : ubyte
{
    Disabled,
    InitFailed,
    Validate,
    Stopping,
    Starting,
    Restarting,
    Running,
}

enum ClientStateSignal
{
    Online,
    Offline,
    Destroyed
}

struct Property
{
    alias GetFun = Variant function(BaseObject i) nothrow @nogc;
    alias SetFun = const(char)[] function(ref const Variant value, BaseObject i) nothrow @nogc;
    alias ResetFun = void function(BaseObject i) nothrow @nogc;
    alias SuggestFun = Array!String function(const(char)[] arg) nothrow @nogc;

    String name;
    GetFun get;
    SetFun set;
    ResetFun reset;
    SuggestFun suggest;

    static Property create(string name, alias member)()
    {
        import manager.console.argument;

        enum Member = __traits(identifier, member);

        alias Type = __traits(parent, member);
        static assert(is(Type : BaseObject), "Type must be a subclass of BaseObject");

        Property prop;
        prop.name = StringLit!name;

        static foreach (i; 0 .. __traits(getOverloads, Type, Member).length)
        {{
            alias Fun = typeof(&__traits(getOverloads, Type, Member)[i]);
            static if (is(Fun == R function(Args) nothrow @nogc, R, Args...))
            {
                static if (Args.length == 0)
                {
                    prop.get = (BaseObject item) {
                        Type instance = cast(Type)item;
                        auto r = __traits(getOverloads, instance, Member)[i]();
                        assert(false, "TODO: convert to Variant...");
                        return Variant(/+...+/);
                    };
                }
                else static if (Args.length == 1)
                {
                    prop.set = (ref const Variant value, BaseObject item) {
                        Type instance = cast(Type)item;
                        Args[0] arg;
                        if (const(char)[] error = convertVariant(value, arg))
                            return error;
                        static if (is(R == void))
                        {
                            __traits(getOverloads, instance, Member)[i](arg);
                            return null;
                        }
                        else
                            return __traits(getOverloads, instance, Member)[i](arg);
                    };

                    static if (is(typeof(suggestCompletion!(Args[0]))))
                        prop.suggest = &suggestCompletion!(Args[0]);
                }
                else
                {
                    static assert(false, "it's something else! - ", Fun.stringof);
                }
            }
        }}

        return prop;
    }
}


class BaseObject
{
    __gshared Property[6] Properties = [ Property.create!("type", type)(),
                                         Property.create!("name", name)(),
                                         Property.create!("disabled", disabled)(),
                                         Property.create!("comment", comment)(),
                                         Property.create!("running", running)(),
                                         Property.create!("status", statusMessage)() ];
nothrow @nogc:

    // TODO: delete this constructor!!!
    this(String name, const(char)[] type)
    {
        _typeInfo = null;
        _type = type.addString();
        _name = name.move;
    }

    this(const CollectionTypeInfo* typeInfo, String name)
    {
        _typeInfo = typeInfo;
        _type = typeInfo.type[].addString();
        _name = name.move;
    }


    // Properties...

    final const(char)[] type() const pure
        => _type;

    final ref const(String) name() const pure
        => _name;
    final const(char)[] name(ref String value)
    {
        // TODO: check if name is already in use...
        _name = value.move;
        return null;
    }

    final ref const(String) comment() const pure
        => _comment;
    final void comment(ref String value)
    {
        _comment = value.move;
    }

    final bool disabled() const pure
        => _state == WorkingState.Disabled || _state == WorkingState.Stopping;
    final void disabled(bool value)
    {
        if (_state >= WorkingState.Starting)
            setState(WorkingState.Stopping);
        else if (_state == WorkingState.Restarting)
            _state = WorkingState.Stopping;
        else
            _state = WorkingState.Disabled;
    }

    // TODO: PUT FINAL BACK WHEN EVERYTHING PORTED!
    /+final+/ bool running() const pure
        => _state == WorkingState.Running;

    // give a helpful status string, e.g. "Ready", "Disabled", "Error: <message>"
    const(char)[] statusMessage() const pure
    {
        final switch (_state)
        {
            case WorkingState.Disabled:
            case WorkingState.Stopping:
                return "Disabled";
            case WorkingState.InitFailed:
                return "Failed";
            case WorkingState.Validate:
                return "Invalid";
            case WorkingState.Starting:
                return "Starting";
            case WorkingState.Restarting:
                return "Restarting";
            case WorkingState.Running:
                return "Running";
        }
    }


    // Object API...

    final void restart()
    {
        if (_state >= WorkingState.Starting)
            setState(WorkingState.Restarting);
    }

    // return a list of properties that can be set on this object
    final const(Property*)[] properties() const
        => _typeInfo.properties;

    // get and set and reset (to default) properties
    final Variant get(scope const(char)[] property)
    {
        foreach (p; properties())
        {
            if (p.name[] == property)
            {
                // some properties aren't get-able...
                if (p.get)
                    return p.get(this);
                return Variant();
            }
        }
        // TODO: should we return empty if the property doesn't exist; or should we complain somehow?
        return Variant();
    }

    final const(char)[] set(scope const(char)[] property, ref const Variant value)
    {
        foreach (i, p; properties())
        {
            if (p.name[] == property)
            {
                if (!p.set)
                    return tconcat("Property '", property, "' is read-only");
                return p.set(value, this);
            }
        }
        return tconcat("No property '", property, "' for ", name[]);
    }

    final void reset(scope const(char)[] property)
    {
        foreach (i, p; properties())
        {
            if (p.name[] == property)
            {
                propsSet &= ~(1 << i);
                if (p.reset)
                    p.reset(this);
                return;
            }
        }
    }

    // get the whole config
    final Variant getConfig() const
        => Variant();

    final MutableString!0 exportConfig() const pure
    {
        // TODO: this should return a string that contains the command which would recreate this object...
        return MutableString!0();
    }

    final void registerClient(BaseObject client)
    {
        assert(!clients[].exists(client), "Client already registered");
        clients ~= client;
    }

protected:
    const CollectionTypeInfo* _typeInfo;
    size_t propsSet;
    WorkingState _state = WorkingState.Validate;

    final void setState(WorkingState newState)
    {
        if (newState == _state)
            return;

        final switch (newState)
        {
            case WorkingState.Disabled:
                _state = WorkingState.Disabled;
                break;

            case WorkingState.InitFailed:
                _state = WorkingState.InitFailed;
                break;

            case WorkingState.Validate:
                _state = WorkingState.Validate;
                if (validate())
                    goto case WorkingState.Starting;
                break;

            case WorkingState.Starting:
                _state = WorkingState.Starting;
                if (startup())
                    goto case WorkingState.Running;
                break;

            case WorkingState.Restarting:
                if (_state == WorkingState.Running)
                    setOffline();
                _state = WorkingState.Restarting;
                goto shutdown;
            case WorkingState.Stopping:
                if (_state == WorkingState.Running)
                    setOffline();
                _state = WorkingState.Stopping;
            shutdown:
                setOffline();
                if (shutdown())
                {
                    if (newState == WorkingState.Stopping)
                        goto case WorkingState.Disabled;
                    goto case WorkingState.Validate;
                }
                break;

            case WorkingState.Running:
                _state = WorkingState.Running;
                setOnline();

                // TODO: should we run the first update cycle immediately?
                update();
                break;
        }
    }

    // validate configuration is in an operable state
    bool validate() const
        => true;

    bool startup()
        => true;

    bool shutdown()
        => true;

    void update()
    {
    }

    void setOnline()
    {
        signalStateChange(ClientStateSignal.Online);
    }

    void setOffline()
    {
        signalStateChange(ClientStateSignal.Offline);
    }

    // sends a signal to all clients
    final void signalStateChange(ClientStateSignal signal)
    {
        foreach (c; clients)
            c.clientSignal(this, signal);
    }

    // receive signal from a subscriber
    void clientSignal(BaseObject client, ClientStateSignal signal)
    {
        debug assert(clients[].exists(client), "Client not registered!");

        if (signal == ClientStateSignal.Destroyed)
            clients.removeFirstSwapLast(client);
    }

private:
    const CacheString _type; // TODO: DELETE THIS MEMBER!!!
    String _name;
    String _comment;
    Array!BaseObject clients;

    package void do_update()
    {
        final switch (_state)
        {
            case WorkingState.Disabled:
                // do nothing...
                return;

            case WorkingState.InitFailed:
                // implement backoff timer?
               setState(WorkingState.Validate);
                return;

            case WorkingState.Validate:
                if (validate())
                    setState(WorkingState.Starting);
                return;

            case WorkingState.Starting:
                if (startup())
                    setState(WorkingState.Running);
                break;

            case WorkingState.Restarting:
            case WorkingState.Stopping:
                if (shutdown())
                {
                    if (_state == WorkingState.Restarting)
                        setState(WorkingState.Validate);
                    setState(WorkingState.Disabled);
                }
                break;

            case WorkingState.Running:
                update();
                break;
        }
    }
}


const(Property*)[] allProperties(Type)()
{
    alias AllProps = allPropertiesImpl!(Type, 0);
    enum Count = typeof(AllProps()).length;
    __gshared const(Property*)[Count] props = AllProps();
    return props[];
}


private:

auto allPropertiesImpl(Type, size_t allocCount)()
{
    import urt.traits : Unqual;

    static if (is(Type S == super) && !is(Unqual!S == Object))
    {
        alias Super = Unqual!S;
        static if (!is(typeof(Type.Properties) == typeof(Super.Properties)) || &Type.Properties !is &Super.Properties)
            enum PropCount = Type.Properties.length;
        else
            enum PropCount = 0;
        auto result = allPropertiesImpl!(Super, PropCount + allocCount)();
    }
    else
    {
        enum PropCount = Type.Properties.length;
        const(Property)*[PropCount + allocCount] result;
    }

    static foreach (i; 0 .. PropCount)
        result[result.length - allocCount - PropCount + i] = &Type.Properties[i];
    return result;
}
