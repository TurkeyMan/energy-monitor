module protocol.ppp.client;

import urt.array;
import urt.lifetime;
import urt.string;
import urt.time;

import protocol.ppp;

import router.iface;
import router.stream;

nothrow @nogc:


class PPPClient : BaseInterface
{
nothrow @nogc:

    alias TypeName = StringLit!"ppp";

    union {
        Stream stream;
        BaseInterface iface;
    }
    TunnelProtocol proto;

    this(String name, Stream stream, BaseInterface iface, TunnelProtocol proto)
    {
        super(name.move, TypeName);

        this.proto = proto;

        if (proto < TunnelProtocol.PPPoE)
        {
            assert(stream, "PPP/SLIP requires a stream");
            assert(!iface, "PPP/SLIP must not specify an interface");
            this.stream = stream;

            mtu = 1500;
        }
        else
        {
            assert(iface, "PPPoE/PPPoA requires an interface");
            assert(!stream, "PPPoE/PPPoA must not specify a stream");
            this.iface = iface;

            mtu = 1492;
            // TODO: what about 'baby jumbo' (RFC 4638) which supports 1500 inside pppoe?
        }

        // TODO: assert proto is valid...
    }

    void setMTU(ushort mtu)
    {
        if (proto != TunnelProtocol.SLIP)
            assert(false, "TODO: terminate the session");
        this.mtu = mtu;
    }

    override void update()
    {
        ubyte[2048] buffer = void;
        SysTime now = getSysTime();

        final switch (proto)
        {
            case TunnelProtocol.PPP:
            case TunnelProtocol.SLIP:
                const ubyte FRAME_END = (proto == TunnelProtocol.PPP) ? 0x7E : 0xC0;

                // check the link status
                Status.Link streamStatus = stream.status.linkStatus;
                if (streamStatus != status.linkStatus)
                {
                    status.linkStatus = streamStatus;
                    status.linkStatusChangeTime = now;
                    if (streamStatus != Status.Link.Up)
                        ++status.linkDowns;
                    else
                    {
                        // begin PPP handshake...
                    }
                }
                if (streamStatus != Status.Link.Up)
                    return;

                // check for data
                ptrdiff_t frameStart = 0;
                ptrdiff_t offset = 0;
                ptrdiff_t length = 0;
                read_loop: while (true)
                {
                    ptrdiff_t r = stream.read(buffer[offset .. $]);
                    if (r < 0)
                    {
                        assert(false, "TODO: what causes read to fail?");
                        break read_loop;
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
                                if (proto == TunnelProtocol.PPP)
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
                // read packets from `iface`, and de-frame them...
                assert(false, "TODO: PPPoE de-framing");
                break;

            case TunnelProtocol.PPPoA:
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
    Array!ubyte tail;
}
