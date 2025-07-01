module router.iface.ethernet;

import urt.array;
import urt.log;
import urt.mem;
import urt.meta.nullable;
import urt.string;
import urt.time;

import manager.console;
import manager.plugin;

import router.iface;


class EthernetInterface : BaseInterface
{
nothrow @nogc:

    alias TypeName = StringLit!"ether";

    this(String name)
    {
        this(name.move, TypeName);
    }

    override void update()
    {
    }

    protected override bool transmit(ref const Packet packet)
    {
        send(packet);

        ++status.sendPackets;
        status.sendBytes += packet.data.length;

        return true;
    }

protected:
    Array!BaseInterface members;

    this(String name, String type)
    {
        super(name.move, type.move);

        status.linkStatus = Status.Link.Up;
        status.linkStatusChangeTime = getSysTime();
    }

    void incomingPacket(ref const Packet packet, BaseInterface srcInterface, PacketDirection dir, void* userData)
    {
//        // TODO: should we check and strip a vlan tag?
//        ushort srcVlan = 0;
//
//        if (!packet.src.isMulticast)
//            macTable.insert(packet.src, srcPort, srcVlan);
//
//        // we're the destination!
//        // we don't need to forward it, just deliver it to the upper layer...
//        dispatch(packet);
    }

    void send(ref const Packet packet) nothrow @nogc
    {
        assert(false, "TODO");
    }
}

class WiFiInterface : EthernetInterface
{
nothrow @nogc:

    alias TypeName = StringLit!"wifi";

    this(String name)
    {
        super(name.move, TypeName);
    }

protected:
    // TODO: wifi details...
    // ssid, signal details, security.
}

class SFPInterface : EthernetInterface
{
nothrow @nogc:

    alias TypeName = StringLit!"sfp";

    this(String name)
    {
        super(name.move, TypeName);
    }

protected:
    // TODO: module info...
    // ventor, type, etc.
}


class EthernetInterfaceModule : Module
{
    mixin DeclareModule!"interface.ethernet";
nothrow @nogc:

    override void init()
    {
        g_app.console.registerCommand!add("/interface/ethernet", this);
    }

    // /interface/ethernet/add command
    // TODO: protocol enum!
    void add(Session session, const(char)[] name, Nullable!(const(char)[]) pcap)
    {
        auto mod_if = getModule!InterfaceModule;
        String n = mod_if.addInterfaceName(session, name, EthernetInterface.TypeName);
        if (!n)
            return;

        EthernetInterface iface = defaultAllocator.allocT!EthernetInterface(n.move);

        mod_if.addInterface(session, iface, pcap ? pcap.value : null);
    }
}
