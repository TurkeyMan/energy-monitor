module protocol.ppp.server;

import urt.lifetime;
import urt.string;

import protocol.ppp;

import router.iface;
import router.stream;

nothrow @nogc:


class PPPServer
{
nothrow @nogc:

    const String name;

    union {
        Stream stream;
        BaseInterface iface;
    }
    TunnelProtocol proto;

    this(String name, Stream stream, BaseInterface iface, TunnelProtocol proto)
    {
        this.name = name.move;
        this.proto = proto;

        if (proto < TunnelProtocol.PPPoE)
        {
            assert(stream, "PPP/SLIP requires a stream");
            assert(!iface, "PPP/SLIP must not specify an interface");
            this.stream = stream;
        }
        else
        {
            assert(iface, "PPPoE/PPPoA requires an interface");
            assert(!stream, "PPPoE/PPPoA must not specify a stream");
            this.iface = iface;
        }
    }

    void update()
    {
    }
}
