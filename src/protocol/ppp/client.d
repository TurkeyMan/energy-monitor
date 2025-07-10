module protocol.ppp.client;

import urt.array;
import urt.lifetime;
import urt.string;
import urt.time;

import manager.base;

import protocol.ppp;

import router.iface;
import router.stream;

nothrow @nogc:


class PPPClient : BaseInterface
{
    __gshared Property[3] Properties = [ Property.create!("stream", stream)(),
                                         Property.create!("interface", iface)(),
                                         Property.create!("protocol", protocol)() ];
nothrow @nogc:

    alias TypeName = StringLit!"ppp";

    this(String name, ObjectFlags flags = ObjectFlags.None)
    {
        super(collectionTypeInfo!PPPClient, name.move, flags);

        // Default protocol is PPP
        mtu = 1500;
    }

    // Properties...

    final inout(Stream) stream() inout pure
        => _protocol < TunnelProtocol.PPPoE ? _stream : null;
    final const(char)[] stream(Stream value)
    {
        if (!value)
            return "stream cannot be null";
        if (_stream is value)
            return null;
        _stream = value;

        if (_protocol >= TunnelProtocol.PPPoE)
            _protocol = TunnelProtocol.PPP;

        restart();
        return null;
    }

    final inout(BaseInterface) iface() inout pure
        => _protocol >= TunnelProtocol.PPPoE ? _interface : null;
    final const(char)[] iface(BaseInterface value)
    {
        if (!value)
            return "stream cannot be null";
        if (_interface is value)
            return null;
        _interface = value;

        if (_protocol < TunnelProtocol.PPPoE)
            _protocol = TunnelProtocol.PPPoE;

        restart();
        return null;
    }

    TunnelProtocol protocol() const pure
        => _protocol;
    void protocol(TunnelProtocol value)
    {
        if (value == _protocol)
            return;
        _protocol = value;

        if (value < TunnelProtocol.PPPoE && _protocol >= TunnelProtocol.PPPoE)
            _interface = null;
        if (value >= TunnelProtocol.PPPoE && _protocol < TunnelProtocol.PPPoE)
            _stream = null;

        if (value < TunnelProtocol.PPPoE)
            mtu = 1500;
        else
            mtu = 1492; // TODO: what about 'baby jumbo' (RFC 4638) which supports 1500 inside pppoe?

        restart();
    }

    // API...

    override bool validate() const pure
        => (_protocol < TunnelProtocol.PPPoE && _stream !is null) ||
           (_protocol >= TunnelProtocol.PPPoE && _interface !is null);

    final override CompletionStatus startup()
    {
        if (_protocol < TunnelProtocol.PPPoE && _stream.running)
        {
            // begin PPP handshake...

            return CompletionStatus.Complete;
        }
        if (_protocol >= TunnelProtocol.PPPoE && _interface.running)
            return CompletionStatus.Complete;
        return CompletionStatus.Continue;
    }

    final override CompletionStatus shutdown()
    {
        return CompletionStatus.Complete;
    }

    override void update()
    {
        ubyte[2048] buffer = void;
        SysTime now = getSysTime();

        final switch (_protocol)
        {
            case TunnelProtocol.PPP:
            case TunnelProtocol.SLIP:
                const ubyte FRAME_END = (_protocol == TunnelProtocol.PPP) ? 0x7E : 0xC0;

                if (!_stream)
                    restart();

                // check for data
                ptrdiff_t frameStart = 0;
                ptrdiff_t offset = 0;
                ptrdiff_t length = 0;
                read_loop: while (true)
                {
                    ptrdiff_t r = _stream.read(buffer[offset .. $]);
                    if (r < 0)
                    {
                        // TODO: do we care what causes read to fail?
                        restart();
                        return;
                    }
                    if (r == 0)
                    {
                        // if there were no extra bytes available, stash the tail until later
                        assert(false);
                        break read_loop;
                    }
                    length = offset + r;

                    for (size_t i = 0; i < length; ++i)
                    {
                        ubyte b = buffer[frameStart + i];
                        if (b == FRAME_END)
                        {
                            if (offset > frameStart)
                            {
                                if (_protocol == TunnelProtocol.PPP)
                                {
                                    // validate MTU...

                                    // validate the CRC...

                                    // check frame type...
                                }
                                else
                                {
                                    // validate MTU...

                                    // SLIP transmits IP frames...
                                    assert(false, "TODO: what do we do with an IP frame...");
                                }

                                frameStart = offset + 1;
                            }
                        }
                        else if (b == 0xDB)
                        {
                            // handle escape byte
                            if (i + 1 < length)
                            {
                                b = buffer[++i];
                                if (b == 0xDC)
                                    buffer[offset++] = FRAME_END;
                                else if (b == 0xDD)
                                    buffer[offset++] = 0xDB;
                                else
                                    assert(false, "TODO: invalid frame... drop this one");
                            }
                        }
                        else if (i > offset)
                            buffer[offset] = b;
                        ++offset;
                    }

                    // shuffle buffer[frameStart .. offset] to the front

                    // and start over...
                }
                break;

            case TunnelProtocol.PPPoE:
                if (!_interface)
                    restart();

                // read packets from `iface`, and de-frame them...
                assert(false, "TODO: PPPoE de-framing");
                break;

            case TunnelProtocol.PPPoA:
                if (!_interface)
                    restart();

                assert(false, "TODO? I don't think we have an ATM interface...");
                break;
        }
    }

protected:
    override bool transmit(ref const Packet packet)
    {
        assert(false, "TODO: frame and transmit");
    }

private:
    union {
        Stream _stream;
        BaseInterface _interface;
    }
    TunnelProtocol _protocol;

    Array!ubyte _tail;
}
