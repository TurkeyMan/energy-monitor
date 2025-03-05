module apps.energy.circuit;

import urt.array;
import urt.lifetime;
import urt.math : sqrt, acos, fabs, PI;
import urt.string;

import apps.energy.appliance;
import apps.energy.manager;
import apps.energy.meter;

import manager.component;
import manager.element;

nothrow @nogc:


enum CircuitType : ubyte { Unknown, DC, SinglePhase, SplitPhase, ThreePhase, Delta }


struct Circuit
{
nothrow @nogc:

    this(String id)
    {
        this.id = id.move;
    }
    this(this) @disable;

    String id;
    String name;
    Circuit* parent;
    Component meter;
    uint maxCurrent;
    Array!(Circuit*) subCircuits;
    Array!Appliance appliances;

    CircuitType type;
    ubyte parentPhase;

    MeterData meterData;
    MeterData rogue;

    void update()
    {
        // update the circuit graph
        foreach (c; subCircuits)
            c.update();
        foreach (a; appliances)
        {
            if (a.meter)
                a.meterData = getMeterData(a.meter);
        }

        if (meter)
        {
            // if the circuit has a meter, just read the meter!
            meterData = getMeterData(meter);
        }
        else
        {
            // no meter; we'll infer usage from sub-circuits and appliances...
            // of course, this data is incomplete, and not all energy on this circuit will be accounted for

            meterData.voltage[] = 0;
            meterData.crossPhaseVoltage[] = 0;
            meterData.freq = 0;

            meterData.active[] = 0;
            meterData.reactive[] = 0;

            // sum the known loads...
            int numLoads = 0;
            foreach (c; subCircuits)
            {
                if (c.meterData.fields == 0)
                    continue;
                ++numLoads;

                meterData.active[] += c.meterData.active[];
                // TODO: I think summing reactive power this way is imprecise? (phase cancellation effects?)
                meterData.reactive[] += c.meterData.reactive[];

                meterData.freq += c.meterData.freq;
            }
            foreach (a; appliances)
            {
                if (a.meterData.fields == 0)
                    continue;
                ++numLoads;

                meterData.active[] += a.meterData.active[];
                // TODO: I think summing reactive power this way is imprecise? (phase cancellation effects?)
                meterData.reactive[] += a.meterData.reactive[];

                meterData.freq += a.meterData.freq;
            }
            // average the frequency (there really shouldn't be any meaningful deviation!)
            if (numLoads)
                meterData.freq /= numLoads;

            // calculate the apparent power, power factor, phase angle, voltage, and current...
            foreach (i; 0..4)
            {
                // apparent power can be calculated from active and reactive power
                meterData.apparent[i] = sqrt(meterData.active[i]^^2 + meterData.reactive[i]^^2);

                // with the apparent power, we can calculate the power factor and phase angle
                if (meterData.apparent[i] > 0)
                    meterData.pf[i] = fabs(meterData.active[i]) / meterData.apparent[i];
                else
                    meterData.pf[i] = meterData.active[i] ? 1 : 0;
                if (meterData.pf[i] != 0)
                {
                    // in degrees
                    meterData.phase[i] = acos(meterData.pf[i])*(1.0/(2*PI));
                    if (meterData.reactive[i] < 0)
                        meterData.phase[i] = -meterData.phase[i];
                }

                // this might be wrong to calculate the voltage... (weighted average of sub-circuits and appliances)
                // but I think it's better than averaging the violtages of the sub-circuits
                if (meterData.apparent[i] > 0)
                {
                    foreach (c; subCircuits)
                        meterData.voltage[i] += c.meterData.apparent[i] * c.meterData.voltage[i];
                    foreach (a; appliances)
                        meterData.voltage[i] += a.meterData.apparent[i] * a.meterData.voltage[i];
                    meterData.voltage[i] /= meterData.apparent[i];
                }

                // and given the voltage, we can calculate the current
                // TODO: confirm; I found this from some reference. I'm not sure why `/V` is inside the sqrt?
                //       I would have guessed A = VA/V, rather than A = sqrt(V²A²/V²)...
                if (meterData.voltage[i])
                    meterData.current[i] = sqrt((meterData.active[i]^^2 + meterData.reactive[i]^^2) / meterData.voltage[i]^^2);
                else
                    meterData.current[i] = 0;
            }
            // the same reference seemed to think this was also better to sum the currents
            // TODO: confirm; I would have guessed SUM = L1+L2+L3, rather than SUM = sqrt(L1²+L2²+L3²)...
            meterData.current[0] = sqrt(meterData.current[1]^^2 + meterData.current[2]^^2 + meterData.current[3]^^2);
        }

        // calculate rogue load...
        if (meter)
        {
            // if the circuit has a meter, then we want to know what portion of the load is not being sub-metered...
            rogue.voltage[] = meterData.voltage[];
            rogue.crossPhaseVoltage[] = meterData.crossPhaseVoltage[];
            rogue.freq = meterData.freq;

            rogue.active[] = meterData.active[];
            rogue.reactive[] = meterData.reactive[];

            // subtract the known loads from the meter total...
            foreach (c; subCircuits)
            {
                rogue.active[] -= c.meterData.active[];
                // TODO: I think subtracting reactive power this way is imprecise? (phase cancellation effects?)
                rogue.reactive[] -= c.meterData.reactive[];
            }
            foreach (a; appliances)
            {
                rogue.active[] -= a.meterData.active[];
                // TODO: I think subtracting reactive power this way is imprecise? (phase cancellation effects?)
                rogue.reactive[] -= a.meterData.reactive[];
            }
            foreach (i; 0..4)
            {
                // calculate the rogue apparent power
                rogue.apparent[i] = sqrt(rogue.active[i]^^2 + rogue.reactive[i]^^2);

                // calculate rogue power factor and phase angle
                if (rogue.apparent[i] > 0)
                    rogue.pf[i] = rogue.active[i] / rogue.apparent[i];
                else
                    rogue.pf[i] = rogue.active[i] ? 1 : 0;
                if (rogue.pf[i] != 0)
                {
                    // in degrees
                    rogue.phase[i] = acos(rogue.pf[i])*(1.0/(2*PI));
                    if (rogue.reactive[i] < 0)
                        rogue.phase[i] = -rogue.phase[i];
                }

                // calculate rogue currents assuming the voltages specified by the meter
                if (rogue.voltage[i])
                    rogue.current[i] = sqrt((rogue.active[i]^^2 + rogue.reactive[i]^^2) / rogue.voltage[i]^^2);
                else
                    rogue.current[i] = 0;
            }
            // calculate the sum of the rogue currents
            rogue.current[0] = sqrt(rogue.current[1]^^2 + rogue.current[2]^^2 + rogue.current[3]^^2);
        }
    }
}
