module router.iface.wpan;

import urt.lifetime;
import urt.meta.nullable;
import urt.string;

import manager;
import manager.plugin;
import manager.console.session;

import router.iface;
import router.iface.mac;
import router.iface.packet;
import router.stream;


class WPANInterface : BaseInterface
{
nothrow @nogc:

    alias TypeName = StringLit!"wpan";

    EUI64 eui;

    union {
        // raw radio device...?
        Stream serialBridge;
    }

    ubyte maxMacFrameRetries = 3;

    this(String name, Stream serialBridge) nothrow @nogc
    {
        super(name.move, TypeName);

        // if using radio device; we should set the mac address for this interface to the radio devices EUI...

        this.serialBridge = serialBridge;

        // generate the eui
        eui = mac.makeEui64();

        // add the missing bytes...
        import urt.crc;
        alias ccitt = calculateCRC!(Algorithm.CRC16_CCITT);
        uint crc = ccitt(name);
        eui.b[3] = cast(ubyte)(crc >> 8);
        eui.b[4] = crc & 0xFF;
    }

    override void update()
    {
    }

    protected override bool transmit(ref const Packet packet) nothrow @nogc
    {
        // can only handle zigbee packets
        if (packet.etherType != EtherType.ENMS || packet.etherSubType != ENMS_SubType.WPAN || packet.data.length < 3)
        {
            ++status.sendDropped;
            return false;
        }

        return false;
    }

private:
    void delegate(uint messageId, bool success) nothrow @nogc transmitCompletionCallback;
}


class WPANInterfaceModule : Module
{
    mixin DeclareModule!"interface.wpan";
    nothrow @nogc:

    override void init()
    {
        g_app.console.registerCommand!add("/interface/wpan", this);
    }

    // /interface/wpan/add command
    void add(Session session, const(char)[] name, Nullable!Stream serial, Nullable!(const(char)[]) pcap)
    {

        auto mod_if = getModule!InterfaceModule;
        String n = mod_if.addInterfaceName(session, name, WPANInterface.TypeName);
        if (!n)
            return;

        WPANInterface iface = g_app.allocator.allocT!WPANInterface(n.move, serial ? serial.value : null);

        mod_if.addInterface(session, iface, pcap ? pcap.value : null);
    }
}


private:
