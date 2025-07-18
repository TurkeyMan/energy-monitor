module apps.energy.appliance;

import urt.array;
import urt.lifetime;
import urt.string;
import urt.util;

import apps.energy.circuit;
import apps.energy.manager;
import apps.energy.meter;

import manager.component;
import manager.device;
import manager.element;

nothrow @nogc:


enum ControlCapability
{
    None = 0,           // no control capability
    Implicit = 1 << 0,  // will adapt to other appliances
    OnOff = 1 << 1,     // can enable/disable operation
    Linear = 1 << 2,    // can specify target power consumption
    Reverse = 1 << 3,   // can reverse flow to supply energy
}


extern(C++)
class Appliance
{
extern(D):
nothrow @nogc:

    String id;
    string type;
    String name;

    EnergyManager* manager;

    Component info;
    Component config;

    Circuit* circuit;
    Component meter;

    MeterData meterData;

    bool enabled;
    float targetPower = 0;

    // HACK: distribute power according to priority...
    int priority;

    this(String id, string type, EnergyManager* manager)
    {
        this.id = id.move;
        this.type = type;
        this.manager = manager;
    }

    void init(Device device) // TODO: rest of cmdline args...
    {
        if (device)
            config = device.getFirstComponentByTemplate("Configuration");
    }

    T as(T)() pure
        if (is(T : Appliance))
    {
        if (type[] == T.Type[])
            return cast(T)this;
        return null;
    }

    // get the power currently being consumed by the appliance
    float currentConsumption() const
        => meterData.active[0] > 0 ? meterData.active[0] : 0;

    // returns true if the appliance can be controlled
    bool canControl() const
        => hasControl() != ControlCapability.None;

    // returns the control capabilities of the appliance
    ControlCapability hasControl() const
        => ControlCapability.None;

    // enable/disable the appliance
    void enable(bool on)
    {
        enabled = on;
    }

    // specifies power that the appliance wants to consume
    float wantsPower() const
        => 0;

    // offset power to the appliance, returns the amount accepted
    float offerPower(float watts)
    {
        float min, max;
        if (minPowerLimit(min) && watts < min)
            targetPower = min;
        else if (maxPowerLimit(max) && watts > max)
            targetPower = max;
        else
            targetPower = watts;
        return targetPower;
    }

    // specifies the minimum power that the appliance can accept
    bool minPowerLimit(out float watts) const
        => false;

    // specifies the maximum power that the appliance can accept
    bool maxPowerLimit(out float watts) const
        => false;

    void update()
    {
    }
}

class Inverter : Appliance
{
nothrow @nogc:
    enum Type = "inverter";

    Component control;
    Component backup; // meter for the backup circuit, if available...
    Array!(Component) mppt; // solar arrays
    Array!(Component) battery; // batteries

    Component dummyMeter; // this can be used to control the charge/discharge functionality

    float ratedPower = 0;

    this(String id, EnergyManager* manager)
    {
        super(id.move, Type, manager);
    }

    final override ControlCapability hasControl() const
    {
        // we need to drill into these components, and see what controls they actually offer...
        if (control || dummyMeter)
            return ControlCapability.OnOff | ControlCapability.Linear | ControlCapability.Reverse;

        // if there are no controls but it's a battery inverter, then it should have implicit control
        if (mppt.length && mppt[0].template_ == "Battery")
            return ControlCapability.Implicit | ControlCapability.Reverse;

        return ControlCapability.Reverse;
    }

    final override float wantsPower() const
    {
        // if SOC < 100%, then we want to charge the battery

        // TODO: it would be REALLY great to attenuate the power request based on
        //       the amount of sunlight hours remaining in the day...
        //       we should aim to fill the battery by sun-down, while also not charging faster than necessary

//        return 0;
        // HACK:
        return ratedPower ? ratedPower : 5000; // we should work out how much the battery actually wants!
    }

    final override void update()
    {
        if (info)
        {
            if (Element* rp = info.findElement("ratedPower"))
            {
                if (rp)
                    ratedPower = rp.value.getFloat();
            }
        }

        if (control)
        {
            // specify control parameters...
        }
        else if (dummyMeter)
        {
            // specify the meter values to influence the inverter...
        }
        else
        {
            // nothing?
        }
    }
}

class EVSE : Appliance
{
nothrow @nogc:
    enum Type = "evse";

    Component control;

    Car connectedCar;

    this(String id, EnergyManager* manager)
    {
        super(id.move, Type, manager);
    }

    final override void init(Device device) // TODO: rest of cmdline args...
    {
        super.init(device);

    }

    final override ControlCapability hasControl() const
    {
        if (control && control.findElement("targetCurrent"))
            return ControlCapability.Linear;
        // on/off control?

        // TODO: maybe we can control the car directly?
        //       which should we prefer?

        return ControlCapability.None;
    }

    final override float wantsPower() const
    {
        float wants = 0;
        if (connectedCar)
            maxPowerLimit(wants);
        return wants;
    }

    final override bool minPowerLimit(out float watts) const
    {
        watts = meterData.voltage[0] ? meterData.voltage[0] * 6 : 230 * 6;
        return true;
    }
    final override bool maxPowerLimit(out float watts) const
    {
        watts = meterData.voltage[0] ? meterData.voltage[0] * 32 : 240 * 32;
        return true;
    }

    final override void update()
    {
        if (!info)
            return;

        // check the charger for a connected VIN
        if (Element* e = info.findElement("vin"))
        {
            if (connectedCar)
                connectedCar.evse = null;
            connectedCar = null;

            const(char)[] vin = e.value.getString();
            if (vin.length > 0)
            {
                // find a car with this VIN among our appliances...
                foreach (a; manager.appliances.values)
                {
                    if (a.type != "car")
                        continue;
                    Car car = cast(Car)a;

                    if (car.vin[] != vin[])
                        continue;

                    connectedCar = car;
                    car.evse = this;
                    break;
                }
            }
        }

        float targetCurrent = targetPower;
        if (connectedCar)
        {
            if (connectedCar.targetPower > 0)
                targetPower = max(targetPower, connectedCar.targetPower);
        }
        targetCurrent /= meterData.voltage[0] ? meterData.voltage[0] : 230;
        if (targetCurrent > 0)
        {
            // set the

            if (control)
            {
                Element* e = control.findElement("targetCurrent");
                if (e)
                    e.value = cast(int)(targetCurrent * 100); // HACK: respect UNITS!
            }

        }
    }
}

class Car : Appliance
{
nothrow @nogc:
    enum Type = "car";

    String vin;
    Component battery;
    Component control;

    EVSE evse;

    this(String id, EnergyManager* manager)
    {
        super(id.move, Type, manager);
    }

    final override ControlCapability hasControl() const
    {
        if (evse)
            return evse.hasControl();

        // some cars can be controlled directly...
        // tesla API?

        return ControlCapability.None;
    }

    final override float currentConsumption() const
    {
        if (evse)
            return evse.currentConsumption();
        return 0;
    }

    final override float wantsPower() const
    {
        // if it actually wants to charge...

        float wants = 0;
        if (evse)
            maxPowerLimit(wants);
        return wants;
    }

    final override bool minPowerLimit(out float watts) const
    {
        watts = meterData.voltage[0] ? meterData.voltage[0] * 6 : 230 * 6;
        return true;
    }
    final override bool maxPowerLimit(out float watts) const
    {
        watts = meterData.voltage[0] ? meterData.voltage[0] * 32 : 240 * 32;
        return true;
    }

    final override void update()
    {

        if (control)
        {
            // specify control parameters...
        }
    }
}

class AirCon : Appliance
{
nothrow @nogc:
    enum Type = "ac";

    Component control;

    this(String id, EnergyManager* manager)
    {
        super(id.move, Type, manager);
    }

    final override void update()
    {

        if (control)
        {
            // specify control parameters...
        }
    }
}

class WaterHeater : Appliance
{
nothrow @nogc:
    enum Type = "water_heater";

    Component control;

    this(String id, EnergyManager* manager)
    {
        super(id.move, Type, manager);
    }

    final override float wantsPower() const
    {
        // we need to check the thermostat to see if temp < target
        //...

        // in the meantime, we probably just offer power any time we have unused excess...

        return 0;
    }

    final override void update()
    {

        // this thing really needs to respond to the thermostat...
        if (control)
        {
            // specify control parameters...
        }
    }
}
