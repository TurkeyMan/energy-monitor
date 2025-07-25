module router.iface.tesla;

import urt.log;
import urt.map;
import urt.mem;
import urt.meta.nullable;
import urt.string;
import urt.string.format;
import urt.time;

import manager.console;
import manager.plugin;

import protocol.tesla.twc;

import router.iface;
import router.iface.packet;
import router.stream;

//version = DebugTeslaInterface;

nothrow @nogc:


struct DeviceMap
{
    String name;
    MACAddress mac;
    ushort address;
    TeslaInterface iface;
}

class TeslaInterface : BaseInterface
{
nothrow @nogc:

    alias TypeName = StringLit!"tesla-twc";

    Stream stream;

    this(String name, Stream stream) nothrow @nogc
    {
        super(name, TypeName);
        this.stream = stream;
    }

    override bool running() const pure
        => status.linkStatus == Status.Link.Up;

    override void update()
    {
        SysTime now = getSysTime();

        // check the link status
        Status.Link streamStatus = stream.status.linkStatus;
        if (streamStatus != status.linkStatus)
        {
            _status.linkStatus = streamStatus;
            _status.linkStatusChangeTime = now;
            if (streamStatus != Status.Link.Up)
                ++_status.linkDowns;
        }
        if (streamStatus != Status.Link.Up)
            return;

        // check for data
        ubyte[1024] buffer = void;
        ptrdiff_t bytes = stream.read(buffer);
        if (bytes < 0)
        {
            assert(false, "what causes read to fail?");
            // TODO...
        }
        if (bytes == 0)
            return;

        size_t offset = 0;
        while (offset < bytes)
        {
            // scan for start of message
            while (offset < bytes && buffer[offset] != 0xC0)
                ++offset;
            size_t end = offset + 1;
            for (; end < bytes; ++end)
            {
                if (buffer[end] == 0xC0)
                    break;
            }

            if (offset == bytes || end == bytes)
            {
                if (bytes != buffer.length || offset == 0)
                    break;
                for (size_t i = offset; i < bytes; ++i)
                    buffer[i - offset] = buffer[i];
                bytes = bytes - offset;
                offset = 0;
                bytes += stream.read(buffer[bytes .. $]);
                continue;
            }

            ubyte[] msg = buffer[offset + 1 .. end];
            offset = end;

            // let's check if the message looks valid...
            if (msg.length < 13)
                continue;
            msg = unescapeMsg(msg);
            if (!msg)
                continue;
            ubyte checksum = 0;
            for (size_t i = 1; i < msg.length - 1; i++)
                checksum += msg[i];
            if (checksum != msg[$ - 1])
                continue;
            msg = msg[0 .. $-1];

            // we seem to have a valid packet...
            incomingPacket(msg, now);
        }
    }

    protected override bool transmit(ref const Packet packet) nothrow @nogc
    {
        if (packet.etherType != EtherType.ENMS || packet.etherSubType != ENMS_SubType.TeslaTWC)
        {
            ++_status.sendDropped;
            return false;
        }

        const(ubyte)[] msg = cast(ubyte[])packet.data;

        ubyte[64] t = void;
        size_t offset = 1;
        ubyte checksum = 0;

        t[0] = 0xC0;
        for (size_t i = 0; i < msg.length; i++)
        {
            if (i > 0)
                checksum += msg.ptr[i];
            if (msg.ptr[i] == 0xC0)
            {
                t[offset++] = 0xDB;
                t[offset++] = 0xDC;
            }
            else if (msg.ptr[i] == 0xDB)
            {
                t[offset++] = 0xDB;
                t[offset++] = 0xDD;
            }
            else
                t[offset++] = msg.ptr[i];
        }
        t[offset++] = checksum;
        t[offset++] = 0xC0;

        // It works without this byte, but I always receive it from a real device!
        t[offset++] = 0xFD;

        size_t written = stream.write(t[0..offset]);
        if (written != offset)
        {
            debug writeDebug("Failed to write to stream '", stream.name, "'");
            ++_status.sendDropped;
            return false;
        }

        version (DebugTeslaInterface) {
            import urt.io;
            writef("{4} - {0}: TWC packet sent {1}-->{2} [{3}]\n", name, packet.src, packet.dst, packet.data, packet.creationTime);
        }

        ++_status.sendPackets;
        _status.sendBytes += packet.data.length;
        // TODO: but should we record the ACTUAL protocol packet?
        return true;
    }

private:

    final void incomingPacket(const(ubyte)[] msg, SysTime recvTime)
    {
        // we need to extract the sender/receiver addresses...
        TWCMessage message;
        bool r = msg.parseTWCMessage(message);
        if (!r)
            return;

        Packet p = Packet(msg);
        p.creationTime = recvTime;
        p.etherType = EtherType.ENMS;
        p.etherSubType = ENMS_SubType.TeslaTWC;

        auto mod_tesla = getModule!TeslaInterfaceModule();

        DeviceMap* map = mod_tesla.findServerByAddress(message.sender);
        if (!map)
            map = mod_tesla.addDevice(null, this, message.sender);
        p.src = map.mac;

        if (!message.receiver)
            p.dst = MACAddress.broadcast;
        else
        {
            // find receiver... do we have a global device registry?
            map = mod_tesla.findServerByAddress(message.receiver);
            if (!map)
            {
                // we haven't seen the other guy, so we can't assign a dst address
                return;
            }
            p.dst = map.mac;
        }

        if (p.dst)
            dispatch(p);
    }
}


class TeslaInterfaceModule : Module
{
    mixin DeclareModule!"interface.tesla-twc";
nothrow @nogc:

    Map!(ushort, DeviceMap) devices;

    override void init()
    {
        g_app.console.registerCommand!add("/interface/tesla-twc", this);
    }

    void add(Session session, const(char)[] name, Stream stream, Nullable!(const(char)[]) pcap)
    {
        auto mod_if = getModule!InterfaceModule;
        String n = mod_if.addInterfaceName(session, name, TeslaInterface.TypeName);
        if (!n)
            return;

        TeslaInterface iface = defaultAllocator.allocT!TeslaInterface(n.move, stream);

        mod_if.interfaces.add(iface);

        version (DebugTeslaInterface)
        {
            // HACK: we'll print packets that we receive...
            iface.subscribe((ref const Packet p, BaseInterface i, void* u) {
                import urt.io;
                writef("{4} - {0}: TWC packet recv {2}<--{1} [{3}]\n", i.name, p.src, p.dst, p.data, p.creationTime);
            }, PacketFilter(etherType: EtherType.ENMS, enmsSubType: ENMS_SubType.TeslaTWC));
        }
    }


    DeviceMap* findServerByName(const(char)[] name)
    {
        foreach (ref map; devices.values)
        {
            if (map.name[] == name[])
                return &map;
        }
        return null;
    }

    DeviceMap* findServerByMac(MACAddress mac)
    {
        foreach (ref map; devices.values)
        {
            if (map.mac == mac)
                return &map;
        }
        return null;
    }

    DeviceMap* findServerByAddress(ushort address)
    {
        return address in devices;
    }

    DeviceMap* addDevice(const(char)[] name, TeslaInterface iface, ushort address)
    {
        if (!name)
            name = tformat("{0}.{1,04X}", iface.name[], address);

        DeviceMap map;
        map.name = name.makeString(defaultAllocator());
        map.address = address;
        map.mac = iface.generateMacAddress();
        map.mac.b[4] = address >> 8;
        map.mac.b[5] = address & 0xFF;
//        while (findMacAddress(map.mac) !is null)
//            ++map.mac.b[5];
        map.iface = iface;

        iface.addAddress(map.mac, iface);
        return devices.insert(address, map);
    }

    DeviceMap* addServer(const(char)[] name, BaseInterface iface, ushort address)
    {
        DeviceMap map;
        map.name = name.makeString(defaultAllocator());
        map.address = address;
        map.mac = iface.mac;
//        map.iface = iface;
        return devices.insert(address, map);
    }
}


private:

ubyte[] unescapeMsg(ubyte[] msg) nothrow @nogc
{
    size_t offset = 0;
    for (size_t i = 0; i < msg.length; i++)
    {
        if (msg[i] == 0xDB)
        {
            if (++i >= msg.length)
                return null;
            else if (msg[i] == 0xDC)
                msg[offset++] = 0xC0;
            else if (msg[i] == 0xDD)
                msg[offset++] = 0xDB;
            else
                return null;
        }
        else
        {
            if (offset < i)
                msg[offset] = msg[i];
            offset++;
        }
    }
    return msg[0 .. offset];
}
