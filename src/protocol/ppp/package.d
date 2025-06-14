module protocol.ppp;

import urt.lifetime;
import urt.map;
import urt.mem.allocator;
import urt.meta.nullable;
import urt.string;

import manager;
import manager.console.session;
import manager.plugin;

import protocol.ppp.server;
import protocol.ppp.client;

import router.iface;
import router.stream;

nothrow @nogc:


enum TunnelProtocol
{
    PPP,
    SLIP,
    PPPoE,
    PPPoA,
}

enum PPPProtocol
{
    LCP = 0xC021, // Link Control Protocol
    BCP = 0xC029, // Bridge Control Protocol
    IPCP = 0x8021, // Internet Protocol Control Protocol
    IPv6CP = 0x8057, // Internet Protocol version 6 Control Protocol
    IPv4 = 0x0021, // Internet Protocol version 4
    IPv6 = 0x0057, // Internet Protocol version 6
    CCP = 0x80FD, // Compression Control Protocol
    PAP = 0xC023, // Password Authentication Protocol
    CHAP = 0xC223, // Challenge Handshake Authentication Protocol
    EAP = 0xC227, // Extensible Authentication Protocol
}


class PPPModule : Module
{
    mixin DeclareModule!"protocol.ppp";
nothrow @nogc:

    Map!(const(char)[], PPPServer) servers;
    Map!(const(char)[], PPPClient) clients;

    override void init()
    {
        g_app.console.registerCommand!add_client("/protocol/ppp/client", this, "add");
        g_app.console.registerCommand!add_server("/protocol/ppp/server", this, "add");
    }

    override void update()
    {
        foreach (s; servers.values)
            s.update();
        foreach (c; clients.values)
            c.update();
    }

    void add_server(Session session, const(char)[] name, Nullable!Stream stream, Nullable!BaseInterface _interface, TunnelProtocol protocol)
    {

        String n = name.makeString(defaultAllocator());

        PPPServer server = defaultAllocator().allocT!PPPServer(n.move, stream ? stream.value : null, _interface ? _interface.value : null, protocol);
        servers[server.name[]] = server;
    }

    void add_client(Session session, const(char)[] name, Nullable!Stream stream, Nullable!BaseInterface _interface, TunnelProtocol protocol)
    {

        String n = name.makeString(defaultAllocator());

        PPPClient client = defaultAllocator().allocT!PPPClient(n.move, stream ? stream.value : null, _interface ? _interface.value : null, protocol);
        clients[client.name[]] = client;
    }
}
