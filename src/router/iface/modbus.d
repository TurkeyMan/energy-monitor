module router.iface.modbus;

import urt.array;
import urt.conv;
import urt.crc;
import urt.endian;
import urt.map;
import urt.mem;
import urt.string;
import urt.string.format;
import urt.time;

import manager.console;
import manager.instance;
import manager.plugin;

import router.iface;
import router.iface.packet;
import router.modbus.message;
import router.stream;

alias modbusCRC = calculateCRC!(Algorithm.CRC16_MODBUS);
alias modbusCRC_2 = calculateCRC_2!(Algorithm.CRC16_MODBUS);

nothrow @nogc:


enum ModbusProtocol : byte
{
    Unknown = -1,
    RTU,
    TCP,
    ASCII
}

enum ModbusFrameType : ubyte
{
    Unknown,
    Request,
    Response
}

struct ServerMap
{
    String name;
    MACAddress mac;
    ubyte localAddress;
    ubyte universalAddress;
    ModbusInterface iface;
    String profile;
}

struct ModbusRequest
{
    ~this() nothrow @nogc
    {
        if (bufferedPacket)
            defaultAllocator().free((cast(void*)bufferedPacket)[0 .. Packet.sizeof + bufferedPacket.length]);
    }

    MonoTime requestTime;
    MACAddress requestFrom;
    ushort sequenceNumber;
    ubyte localServerAddress;
    bool inFlight;
    const(Packet)* bufferedPacket;
}

class ModbusInterface : BaseInterface
{
nothrow @nogc:

    Stream stream;

    ModbusProtocol protocol;
    bool isBusMaster;
    bool supportSimultaneousRequests = false;
    ushort requestTimeout = 500; // default 500ms? longer?
    ushort queueTimeout = 500;   // same as request timeout?
    ushort gapTime = 35;         // what's a reasonable RTU gap time?
    MonoTime lastReceiveEvent;

    // if we are the bus master
    Array!ModbusRequest pendingRequests;

    // if we are not the bus master
    MACAddress masterMac;
    ushort sequenceNumber;
    ModbusFrameType expectMessageType = ModbusFrameType.Unknown;

    this(InterfaceModule.Instance m, String name, Stream stream, ModbusProtocol protocol, bool isMaster) nothrow @nogc
    {
        super(m, name.move, StringLit!"modbus");
        this.stream = stream;
        this.protocol = protocol;
        this.isBusMaster = isMaster;
        this.supportSimultaneousRequests = protocol == ModbusProtocol.TCP;

        if (!isMaster)
        {
            masterMac = generateMacAddress();
            masterMac.b[5] = 0xFF;
            addAddress(masterMac, this);

            // if we're not the master, we can't write to the bus unless we are responding...
            // and if the stream is TCP, we'll never know if the remote has dropped the connection
            // we'll enable keep-alive in tcp streams to to detect this...
            import router.stream.tcp : TCPStream;
            auto tcpStream = cast(TCPStream)stream;
            if (tcpStream)
                tcpStream.enableKeepAlive(true, seconds(10), seconds(1), 10);
        }

        status.linkStatusChangeTime = getTime();
        status.linkStatus = stream.connected;

        // TODO: warn the user if they configure an interface to use modbus tcp over a serial line
        //       user needs to be warned that data corruption may occur!

        // TODO: assert that recvBufferLen and sendBufferLen are both larger than a single PDU (254 bytes)!
    }

    override void update()
    {
        MonoTime now = getTime();

        // check for timeouts
        for (size_t i = 0; i < pendingRequests.length; )
        {
            auto req = &pendingRequests[i];
            Duration elapsed = now - req.requestTime;
            if (elapsed > (req.inFlight ? requestTimeout.msecs : queueTimeout.msecs))
            {
                pendingRequests.remove(i);
                if (!req.inFlight)
                    ++status.sendDropped;
            }
            else
                ++i;
        }

        // check for latent transmit
        while (!pendingRequests.empty && !pendingRequests[0].inFlight && now - lastReceiveEvent >= gapTime.msecs)
        {
            if (forward(*pendingRequests[0].bufferedPacket))
            {
                // we'll reset the request time so it doesn't timeout straight away
                pendingRequests[0].requestTime = now;
                pendingRequests[0].inFlight = true;
            }
            else
            {
                // if send failed we won't try again
                pendingRequests.remove(0);
            }
        }

        // check the link status
        bool isConnected = stream.connected();
        if (isConnected != status.linkStatus)
        {
            status.linkStatus = isConnected;
            status.linkStatusChangeTime = now;
            if (!isConnected)
                ++status.linkDowns;
        }
        if (!isConnected)
            return;

        // check for data
        ubyte[1024] buffer = void;
        buffer[0 .. tailBytes] = tail[0 .. tailBytes];
        ptrdiff_t readOffset = tailBytes;
        ptrdiff_t length = tailBytes;
        tailBytes = 0;
        read_loop: do
        {
            assert(length < 260);

            ptrdiff_t r = stream.read(buffer[readOffset .. $]);
            if (r < 0)
            {
                assert(false, "TODO: what causes read to fail?");
                break read_loop;
            }
            if (r == 0)
            {
                // if there were no extra bytes available, stash the tail until later
                tail[0 .. length] = buffer[0 .. length];
                tailBytes = cast(ushort)length;
                break read_loop;
            }
            length += r;
            assert(length <= buffer.sizeof);

//            if (connParams.logDataStream)
//                logStream.rawWrite(buffer[0 .. length]);

            size_t offset = 0;
            while (offset < length)
            {
                // parse packets from the stream...
                const(void)[] message = void;
                ModbusFrameInfo frameInfo = void;
                size_t taken = 0;
                final switch (protocol)
                {
                    case ModbusProtocol.Unknown:
                        assert(false, "Modbus protocol not specified");
                        break;
                    case ModbusProtocol.RTU:
                        taken = parseRTU(buffer[offset .. length], message, frameInfo);
                        break;
                    case ModbusProtocol.TCP:
                        taken = parseTCP(buffer[offset .. length], message, frameInfo);
                        break;
                    case ModbusProtocol.ASCII:
                        taken = parseASCII(buffer[offset .. length], message, frameInfo);
                        break;
                }

                if (taken == 0)
                {
                    import urt.util : min;

                    // we didn't parse any packets
                    // we might have a split packet, so we'll shuffle unread data to the front of the buffer
                    // ...but we'll only keep at most one message worth!
                    size_t remain = length - offset;
                    size_t keepBytes = min(remain, 259);
                    size_t trunc = remain - keepBytes;
                    memmove(buffer.ptr, buffer.ptr + offset + trunc, keepBytes);
                    length = keepBytes;
                    readOffset = keepBytes;
                    offset = 0;
                    continue read_loop;
                }
                offset += taken;

                incomingPacket(message, now, frameInfo);
            }

            // we've eaten the whole buffer...
            length = 0;
        }
        while (true);
    }

    override bool forward(ref const Packet packet) nothrow @nogc
    {
        // can only handle modbus packets
        if (packet.etherType != EtherType.ENMS || packet.etherSubType != ENMS_SubType.Modbus || packet.data.length < 3)
        {
            ++status.sendDropped;
            return false;
        }

        auto modbus = mod_iface.app.moduleInstance!ModbusInterfaceModule();

        ushort length = 0;
        ubyte address = 0;

        if (isBusMaster)
        {
            if (!packet.dst.isBroadcast)
            {
                ServerMap* map = modbus.findServerByMac(packet.dst);
                if (!map)
                {
                    ++status.sendDropped;
                    return false; // we don't know who this server is!
                }
                if (map.iface !is this)
                {
                    // this server belongs to a different interface, but this interface received it...
                    // this probably happened because a bridge didn't know where to direct the packet.
                    // we have 2 options; just forward it, or drop it... since we know it should be directed somewhere else...?
                    ++status.sendDropped;
                    return false; // this server belongs to a different interface...
                }
                address = map.localAddress;

                // we can transmit immediately if simultaneous requests are accepted
                // or if there are no messages currently queued, and we satisfied the message gap time
                MonoTime now = getTime();
                bool transmitImmediately = supportSimultaneousRequests || (pendingRequests.empty ? (now - lastReceiveEvent >= gapTime.msecs) : (&packet == pendingRequests[0].bufferedPacket));

                // we need to queue the request so we can return the response to the sender...
                // but check that it's not a re-send attempt of the head queued packet
                if (pendingRequests.empty || &packet != pendingRequests[0].bufferedPacket)
                {
                    ushort sequenceNumber = (cast(ubyte[])packet.data)[0..2].bigEndianToNative!ushort;
                    pendingRequests ~= ModbusRequest(now, packet.src, sequenceNumber, map.localAddress, transmitImmediately, packet.clone());
                }

                if (!transmitImmediately)
                    return true;
            }
        }
        else
        {
            // if we're not a bus master, we can only send response packets destined for the master
            if (packet.dst != masterMac)
            {
                ++status.sendDropped;
                return false;
            }

            // the packet is a response to the master; just frame it and send it...
            ServerMap* map = modbus.findServerByMac(packet.src);
            if (!map)
            {
                ++status.sendDropped;
                return false; // how did we even get a response if we don't know who the server is?
            }

            if (map.iface is this)
            {
                assert(false, "This should be impossible; it should have served its own response...?");
                address = map.localAddress;
            }
            else
                address = map.universalAddress;
        }

        // frame it up and send...
        const(ubyte)[] data = cast(ubyte[])packet.data[2 .. $]; // skip sequence number
        ubyte[520] buffer = void;

        final switch (protocol)
        {
            case ModbusProtocol.Unknown:
                assert(false, "Modbus protocol not specified");
            case ModbusProtocol.RTU:
                // frame the packet
                length = cast(ushort)(1 + data.length);
                buffer[0] = address;
                buffer[1 .. length] = data[];
                buffer[length .. length + 2][0 .. 2] = buffer[0 .. length].modbusCRC().nativeToLittleEndian;
                length += 2;
                break;
            case ModbusProtocol.TCP:
                assert(false);
            case ModbusProtocol.ASCII:
                // calculate the LRC
                ubyte lrc = address;
                foreach (b; cast(ubyte[])data[])
                    lrc += cast(ubyte)b;
                lrc = cast(ubyte)-lrc;

                // format the packet
                buffer[0] = ':';
                formatInt(address, cast(char[])buffer[1..3], 16, 2, '0');
                length = cast(ushort)(3 + toHexString(data[], cast(char[])buffer[3..$]).length);
                formatInt(lrc, cast(char[])buffer[length .. length + 2], 16, 2, '0');
                (cast(char[])buffer)[length + 2 .. length + 4] = "\r\n";
                length += 4;
        }

        ptrdiff_t written = stream.write(buffer[0 .. length]);
        if (written <= 0)
        {
            // what could have gone wrong here?
            // TODO: proper error handling?

            // if the stream disconnected, maybe we should buffer the message incase it reconnects promptly?

            // just drop it for now...
            ++status.sendDropped;
            return false;
        }

        ++status.sendPackets;
        status.sendBytes += data.length;
        // TODO: or should we record `length`? payload bytes, or full protocol bytes?
        return true;
    }

private:
    ubyte[260] tail;
    ushort tailBytes;

    final void incomingPacket(const(void)[] message, MonoTime recvTime, ref ModbusFrameInfo frameInfo)
    {
        // TODO: some debug logging of the incoming packet stream?
        debug {
            import urt.log;
//            writeDebug("Modbus packet received from interface: '", name, "' (", message.length, ")[ ", message[], " ]");
        }

        // if we are the bus master, then we can only receive responses...
        ModbusFrameType type = isBusMaster ? ModbusFrameType.Response : frameInfo.frameType;
        if (type == ModbusFrameType.Unknown && expectMessageType != ModbusFrameType.Unknown)
        {
            // if we haven't seen a packet for longer than the timeout interval, then we can't trust our guess
            if (recvTime - lastReceiveEvent > requestTimeout.msecs)
                expectMessageType = ModbusFrameType.Unknown;
            else
                type = expectMessageType;
        }

        lastReceiveEvent = recvTime;

        MACAddress frameMac = void;
        if (frameInfo.address == 0)
            frameMac = MACAddress.broadcast;
        else
        {
            auto modbus = mod_iface.app.moduleInstance!ModbusInterfaceModule();

            // we probably need to find a way to cache these lookups.
            // doing this every packet feels kinda bad...

            // if we are the bus master, then incoming packets are responses from slaves
            //    ...so the address must be their local bus address
            // if we are not the bus master, then it could be a request from a master to a local or remote slave, or a response from a local slave
            //    ...the response is local, so it can only be a universal address if it's a request!
            ServerMap* map = modbus.findServerByLocalAddress(frameInfo.address, this);
            if (!map && type == ModbusFrameType.Request)
                map = modbus.findServerByUniversalAddress(frameInfo.address);
            if (!map)
            {
                // apparently this is the first time we've seen this guy...
                // this should be impossible if we're the bus master, because we must know anyone we sent a request to...
                // so, it must be a communication from a local master with a local slave we don't know...

                // let's confirm and then record their existence...
                if (isBusMaster)
                {
                    // if we are the bus-master, it should have been impossible to receive a packet from an unknown guy
                    // it's possibly a false packet from a corrupt bitstream, or there's another master on the bus!
                    // we'll drop this packet to be safe...
                    ++status.recvDropped;
                    return;
                }

                // we won't bother generating a universal address since 3rd party's can't send requests anyway, because we're not the bus master!
                map = modbus.addRemoteServer(null, this, frameInfo.address, null);
            }
            frameMac = map.mac;
        }

        ubyte[255] buffer = void;
        buffer[2 .. 2 + message.length] = cast(ubyte[])message[];
        Packet p = Packet(buffer[0 .. 2 + message.length]);
        p.creationTime = recvTime;
        p.etherType = EtherType.ENMS;
        p.etherSubType = ENMS_SubType.Modbus;

        if (isBusMaster)
        {
            // if we are the bus master, we expect to receive packets in response to queued requests
            if (!supportSimultaneousRequests)
            {
                // if there are no pending requests, then we probably received a late reply to something we timed out...
                if (pendingRequests.empty)
                {
                    ++status.recvDropped;
                    return;
                }

                // expect incoming messages are a response to the front message
                if (pendingRequests[0].localServerAddress == frameInfo.address)
                {
                    p.src = frameMac;
                    p.dst = pendingRequests[0].requestFrom;
                    buffer[0 .. 2] = nativeToBigEndian(pendingRequests[0].sequenceNumber);
                    dispatch(p);
                }
                else
                {
                    // what if we get a message we don't expect?
                    // one possible case is a delayed response from a server to a message we dismissed as a timeout...
                    // this is a wonky case; we have choices
                    //  1. don't dismiss the pending request, we may expect the response to come next
                    //  2. dismiss the pending request, we have no good reason to believe it's still in flight
                    //  3. dismiss ALL pending requests, because we may be out of cadence so drop everything to start over?

                    // we'll do 2 for now...
                    ++status.recvDropped;
                }

                pendingRequests.remove(0);
            }
            else
            {
                if (!frameInfo.hasSequenceNumber)
                {
                    // how can we supportSimultaneousRequests and not have a sequence number?
                    // we must be using modbus TCP to supportSimultaneousRequests, no?
                    assert(false);
                }
                ushort seq = frameInfo.sequenceNumber;
                bool dispatched = false;

                foreach (i, ref req; pendingRequests)
                {
                    if (req.localServerAddress != frameInfo.address || req.sequenceNumber != seq)
                        continue;

                    p.src = frameMac;
                    p.dst = req.requestFrom;

                    buffer[0 .. 2] = nativeToBigEndian(seq);

                    dispatch(p);
                    dispatched = true;

                    // remove the request from the queue
                    pendingRequests.remove(i);
                    break;
                }

                if (!dispatched)
                {
                    // we received a packet with no pending request...
                    // maybe it was a late response to a message that we already dismissed as timeout?
                    // ...or something else?
                    ++status.recvDropped;
                }
            }
        }
        else
        {
            // we can't dispatch this message if we don't know if its a request or a response...
            // we'll need to discard messages until we get one that we know, and then we can predict future messages from there
            if (type == ModbusFrameType.Unknown)
            {
                ++status.recvDropped;
                return;
            }

            p.src = type == ModbusFrameType.Request ? masterMac : frameMac;
            p.dst = type == ModbusFrameType.Request ? frameMac : masterMac;

            ushort seq = frameInfo.sequenceNumber;
            if (!frameInfo.hasSequenceNumber)
            {
                if (type == ModbusFrameType.Request)
                    ++sequenceNumber;
                seq = sequenceNumber;
            }
            buffer[0 .. 2] = nativeToBigEndian(seq);

            dispatch(p);

            expectMessageType = type == ModbusFrameType.Request ? ModbusFrameType.Response : ModbusFrameType.Request;
        }
    }
}


class ModbusInterfaceModule : Plugin
{
    mixin RegisterModule!"interface.modbus";

    class Instance : Plugin.Instance
    {
        mixin DeclareInstance;
    nothrow @nogc:

        Map!(ubyte, ServerMap) remoteServers;

        override void init()
        {
            app.console.registerCommand!add("/interface/modbus", this);
            app.console.registerCommand!remote_server_add("/interface/modbus/remote-server", this, "add");
        }

        ServerMap* findServerByName(const(char)[] name)
        {
            try foreach (ref map; remoteServers)
            {
                if (map.name[] == name)
                    return &map;
            }
            catch(Exception) {}
            return null;
        }

        ServerMap* findServerByMac(MACAddress mac)
        {
            foreach (ref map; remoteServers)
            {
                if (map.mac == mac)
                    return &map;
            }
            return null;
        }

        ServerMap* findServerByLocalAddress(ubyte localAddress, BaseInterface iface)
        {
            try foreach (ref map; remoteServers)
            {
                if (map.localAddress == localAddress && map.iface is iface)
                    return &map;
            }
            catch(Exception) {}
            return null;
        }

        ServerMap* findServerByUniversalAddress(ubyte universalAddress)
        {
            return universalAddress in remoteServers;
        }

        ServerMap* addRemoteServer(const(char)[] name, ModbusInterface iface, ubyte address, const(char)[] profile, ubyte universalAddress = 0)
        {
            if (!name)
                name = tconcat(iface.name[], '.', address);

            ServerMap map;
            map.name = name.makeString(defaultAllocator());
            map.mac = iface.generateMacAddress();
            map.mac.b[5] = address;

            if (!universalAddress)
            {
                universalAddress = map.mac.b[4] ^ address;
                while (universalAddress in remoteServers)
                    ++universalAddress;
            }
            else
                assert(universalAddress !in remoteServers, "Universal address already in use.");

            map.localAddress = address;
            map.universalAddress = universalAddress;
            map.iface = iface;
            map.profile = profile.makeString(defaultAllocator());

            remoteServers[universalAddress] = map;
            iface.addAddress(map.mac, iface);

            import urt.log;
            writeInfof("Create modbus server '{0}' - mac: {1}  uid: {2}  at-interface: {3}({4})", map.name, map.mac, map.universalAddress, iface.name, map.localAddress);

            return universalAddress in remoteServers;
        }

        import urt.meta.nullable;

        // /interface/modbus/add command
        // TODO: protocol enum!
        void add(Session session, const(char)[] name, const(char)[] stream, const(char)[] protocol, Nullable!bool master)
        {
            // is it an error to not specify a stream?
            assert(stream, "'stream' must be specified");

            Stream s = app.moduleInstance!StreamModule.getStream(stream);
            if (!s)
            {
                session.writeLine("Stream does not exist: ", stream);
                return;
            }

            ModbusProtocol p = ModbusProtocol.Unknown;
            switch (protocol)
            {
                case "rtu":
                    p = ModbusProtocol.RTU;
                    break;
                case "tcp":
                    p = ModbusProtocol.TCP;
                    break;
                case "ascii":
                    p = ModbusProtocol.ASCII;
                    break;
                default:
                    session.writeLine("Invalid modbus protocol '", protocol, "', expect 'rtu|tcp|ascii'.");
                    return;
            }
            if (p == ModbusProtocol.Unknown)
            {
                if (s && s.type == "tcp-client") // TODO: UDP here too... but what is the type called?
                    p = ModbusProtocol.TCP;
                else
                    p = ModbusProtocol.RTU;
            }

            auto mod_if = app.moduleInstance!InterfaceModule;

            if (name.empty)
                name = mod_if.generateInterfaceName("modbus");
            String n = name.makeString(defaultAllocator());

            ModbusInterface iface = defaultAllocator.allocT!ModbusInterface(mod_if, n.move, s, p, master ? master.value : false);
            mod_if.addInterface(iface);

            import urt.log;
            writeInfo("Create modbus interface '", name, "' - ", iface.mac);

//            // HACK: we'll print packets that we receive...
//            iface.subscribe((ref const Packet p, BaseInterface i) nothrow @nogc {
//                import urt.io;
//
//                auto modbus = app.moduleInstance!ModbusInterfaceModule;
//                ServerMap* src = modbus.findServerByMac(p.src);
//                ServerMap* dst = modbus.findServerByMac(p.dst);
//                const(char)[] srcName = src ? src.name[] : tconcat(p.src);
//                const(char)[] dstName = dst ? dst.name[] : tconcat(p.dst);
//                writef("{0}: Modbus packet received: ( {1} -> {2} )  [{3}]\n", i.name, srcName, dstName, p.data);
//            }, PacketFilter(etherType: EtherType.ENMS, enmsSubType: ENMS_SubType.Modbus));
        }


        void remote_server_add(Session session, const(char)[] name, const(char)[] _interface, ubyte address, const(char)[] profile, Nullable!ubyte universal_address)
        {
            if (!_interface)
            {
                session.writeLine("Interface must be specified.");
                return;
            }
            if (!address)
            {
                session.writeLine("Local address must be specified.");
                return;
            }

            BaseInterface iface = app.moduleInstance!InterfaceModule.findInterface(_interface);
            if (!iface)
            {
                session.writeLine("Interface '", _interface, "' not found.");
                return;
            }
            ModbusInterface modbusInterface = cast(ModbusInterface)iface;
            if (!modbusInterface)
            {
                session.writeLine("Interface '", _interface, "' is not a modbus interface.");
                return;
            }

            if (universal_address)
            {
                ServerMap* t = universal_address.value in remoteServers;
                if (t)
                {
                    session.writeLine("Universal address '", universal_address.value, "' already in use by '", t.name, "'.");
                    return;
                }
            }

            addRemoteServer(name, modbusInterface, address, profile, universal_address ? universal_address.value : 0);
        }
    }
}


private:

struct ModbusFrameInfo
{
    ubyte address;
    bool hasSequenceNumber;
    ushort sequenceNumber;
    FunctionCode functionCode;
    ExceptionCode exceptionCode = ExceptionCode.None;
    ModbusFrameType frameType = ModbusFrameType.Unknown;
}

__gshared immutable ushort[25] functionLens = [
    0x0000, 0x2306, 0x2306, 0x2306, 0x2306, 0x0606, 0x0606, 0x0302,
    0xFFFF, 0xFFFF, 0xFFFF, 0x0602, 0x2302, 0xFFFF, 0xFFFF, 0x0667,
    0x0667, 0x2302, 0xFFFF, 0xFFFF, 0x3232, 0x3232, 0x0808, 0x23AB,
    0x3404
];

int parseFrame(const(ubyte)[] data, out ModbusFrameInfo frameInfo)
{
    // RTU has no sync markers, so we need to get pretty creative to validate frames!
    // 1: packets are delimited by a 2-byte CRC, so any sequence of bytes where the running CRC is followed by 2 bytes with that value might be a frame...
    // 2: but 2-byte CRC's aren't good enough protection against false positives! (they appear semi-regularly), so...
    // 3:  a. we can exclude packets that start with an invalid function code
    //     b. we can exclude packets to the broadcast address (0), with a function code that can't broadcast
    //     c. we can then try and determine the expected packet length, and check for CRC only at the length offsets
    //     d. failing all that, we can crawl the buffer for a CRC...
    //     e. if we don't find a packet, repeat starting at the next BYTE...

    // ... losing stream sync might have a high computational cost!
    // we might determine that in practise it's superior to just drop the whole buffer and wait for new data which is probably aligned to the bitstream to arrive?

    // NOTE: it's also worth noting, that some of our stream validity checks exclude non-standard protocol...
    //       for instance, we exclude any function code that's not in the spec. What if an implementation invents their own function codes?
    //       maybe it should be an interface flag to control whether it accepts non-standard streams, and relax validation checking?

    if (data.length < 4) // @unlikely
        return 0;

    // check the address is in the valid range
    ubyte address = data[0];
    if (address >= 248 && address <= 255) // @unlikely
        return 0;
    frameInfo.address = address;

    // frames must start with a valid function code...
    ubyte f = data[1];
    FunctionCode fc = cast(FunctionCode)(f & 0x7F);
    ushort fnData = fc < functionLens.length ? functionLens[fc] : fc == 0x2B ? 0xFFFF : 0;
    if (fnData == 0) // @unlikely
        return 0;
    frameInfo.functionCode = fc;

    // exceptions are always 3 bytes
    ubyte reqLength = void;
    ubyte resLength = void;
    if (f & 0x80) // @unlikely
    {
        frameInfo.exceptionCode = cast(ExceptionCode)data[2];
        frameInfo.frameType = ModbusFrameType.Response;
        reqLength = 3;
        resLength = 3;
    }

    // zero bytes (broadcast address) are common in data streams, and if the function code can't broadcast, we can exclude this packet
    // NOTE: this can only catch 10 bad bytes in the second byte position... maybe not worth the if()?
//    else if (address == 0 && (fFlags & 2) == 0) // @unlikely
//    {
//        frameId.invalidFrame = true;
//        return false;
//    }

    // if the function code can determine the length...
    else if (fnData != 0xFFFF) // @likely
    {
        // TODO: we can instead load these bytes separately if the bit-shifting is worse than loads...
        reqLength = fnData & 0xF;
        ubyte reqExtra = (fnData >> 4) & 0xF;
        resLength = (fnData >> 8) & 0xF;
        ubyte resExtra = fnData >> 12;
        if (reqExtra && reqExtra < data.length)
            reqLength += data[reqExtra];
        if (resExtra)
            resLength += data[resExtra];
    }
    else
    {
        // function length can't be determined; scan for a CRC...

        // realistically, this is almost always a result of stream corruption...
        // and the implementation is quite a lot of code!
        const(ubyte)[] message = crawlForRTU(data, null);
        if (message != null)
            return cast(int)message.length;
        return 0;
    }

    int failResult = 0;
    if (reqLength != resLength) // @likely
    {
        ubyte length = void, smallerLength = void;
        ModbusFrameType type = void, smallerType = void;
        if (reqLength > resLength)
        {
            length = reqLength;
            smallerLength = resLength;
            type = ModbusFrameType.Request;
            smallerType = ModbusFrameType.Response;
        }
        else
        {
            length = resLength;
            smallerLength = reqLength;
            type = ModbusFrameType.Response;
            smallerType = ModbusFrameType.Request;
        }

        if (data.length >= length + 2) // @likely
        {
            uint crc2 = data[0 .. length].modbusCRC_2(smallerLength);

            if ((crc2 >> 16) == (data[smallerLength] | cast(ushort)data[smallerLength + 1] << 8))
            {
                frameInfo.frameType = smallerType;
                return smallerLength;
            }
            if ((crc2 & 0xFFFF) == (data[length] | cast(ushort)data[length + 1] << 8))
            {
                frameInfo.frameType = type;
                return length;
            }
            return 0;
        }
        else
        {
            failResult = -1;
            reqLength = smallerLength;
            frameInfo.frameType = smallerType;
        }
    }

    // check we have enough data...
    if (data.length < reqLength + 2) // @unlikely
        return -1;

    ushort crc = data[0 .. reqLength].modbusCRC();

    if (crc == (data[reqLength] | cast(ushort)data[reqLength + 1] << 8))
        return reqLength;

    return failResult;
}


size_t parseRTU(const(ubyte)[] data, out const(void)[] message, out ModbusFrameInfo frameInfo)
{
    if (data.length < 4)
        return 0;

    // the stream might have corruption or noise, RTU frames could be anywhere, so we'll scan forward searching for the next frame...
    size_t offset = 0;
    for (; offset < data.length - 4; ++offset)
    {
        int length = parseFrame(data[offset .. data.length], frameInfo);
        if (length < 0)
            return 0;
        if (length == 0)
            continue;

        message = data[offset + 1 .. offset + length];
        return offset + length + 2;
    }

    // no packet was found in the stream... how odd!
    return 0;
}

size_t parseTCP(const(ubyte)[] data, out const(void)[] message, out ModbusFrameInfo frameInfo)
{
    assert(false);
    return 0;
}

size_t parseASCII(const(ubyte)[] data, out const(void)[] message, out ModbusFrameInfo frameInfo)
{
    assert(false);
    return 0;
}

inout(ubyte)[] crawlForRTU(inout(ubyte)[] data, ushort* rcrc = null)
{
    alias modbus_crc_table = CRCTable!(Algorithm.CRC16_MODBUS);

//    if (data.length < 4)
//        return null;

    enum NumCRC = 8;
    ushort[NumCRC] foundCRC = void;
    size_t[NumCRC] foundCRCPos = void;
    int numfoundCRC = 0;

    // crawl through the buffer accumulating a CRC and looking for the following bytes to match
    ushort crc = 0xFFFF;
    ushort next = data[0] | cast(ushort)data[1] << 8;
    size_t len = data.length < 256 ? data.length : 256;
    for (size_t pos = 2; pos < len; )
    {
        ubyte index = (next & 0xFF) ^ cast(ubyte)crc;
        crc = (crc >> 8) ^ modbus_crc_table[index];

        // get the next word in sequence
        next = next >> 8 | cast(ushort)data[pos++] << 8;

        // if the running CRC matches the next word, we probably have an RTU packet delimiter
        if (crc == next)
        {
            foundCRC[numfoundCRC] = crc;
            foundCRCPos[numfoundCRC++] = pos;
            if (numfoundCRC == NumCRC)
                break;
        }
    }

    if (numfoundCRC > 0)
    {
        int bestMatch = 0;

        // TODO: this is a lot of code!
        // we should do some statistics to work out which conditions actually lead to better outcomes and compress the logic to only what is iecessary

        if (numfoundCRC > 1)
        {
            // if we matched multiple CRC's in the buffer, then we need to work out which CRC is not a false-positive...
            int[NumCRC] score;
            for (int i = 0; i < numfoundCRC; ++i)
            {
                // if the CRC is at the end of the buffer, we have a single complete message, and that's a really good indicator
                if (foundCRCPos[i] == data.length)
                    score[i] += 10;
                else if (foundCRCPos[i] <= data.length - 2)
                {
                    // we can check the bytes following the CRC appear to begin a new message...
                    // confirm the function code is valid
                    if (validFunctionCode(cast(FunctionCode)data[foundCRCPos[i] + 1]))
                        score[i] += 5;
                    // we can also give a nudge if the address looks plausible
                    ubyte addr = data[foundCRCPos[i]];
                    if (addr <= 247)
                    {
                        if (addr == 0)
                            score[i] += 1; // broadcast address is unlikely
                        else if (addr <= 4 || addr >= 245)
                            score[i] += 3; // very small or very big addresses are more likely
                        else
                            score[i] += 2;
                    }
                }
            }
            for (int i = 1; i < numfoundCRC; ++i)
            {
                if (score[i] > score[i - 1])
                    bestMatch = i;
            }
        }

        if (rcrc)
            *rcrc = foundCRC[bestMatch];
        return data[0 .. foundCRCPos[bestMatch]];
    }

    // didn't find anything...
    return null;
}

bool validFunctionCode(FunctionCode functionCode)
{
    if (functionCode & 0x80)
        functionCode ^= 0x80;

    version (X86_64) // TODO: use something more general!
    {
        enum ulong validCodes = 0b10000000000000000001111100111001100111111110;
        if (functionCode >= 64) // TODO: REMOVE THIS LINE (DMD BUG!)
            return false;       // TODO: REMOVE THIS LINE (DMD BUG!)
        return ((1uL << functionCode) & validCodes) != 0;
    }
    else
    {
        enum uint validCodes = 0b1111100111001100111111110;
        if (functionCode >= 32) // TODO: REMOVE THIS LINE (DMD BUG!)
            return false;       // TODO: REMOVE THIS LINE (DMD BUG!)
        if ((1 << functionCode) & validCodes)
            return true;
        return functionCode == FunctionCode.MEI;
    }
}
