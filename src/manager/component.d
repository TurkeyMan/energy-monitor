module manager.component;

import urt.array;
import urt.lifetime;
import urt.log;
import urt.map;
import urt.string;

import manager.device;
import manager.element;
import manager.units;
import manager.value;

import router.modbus.profile;

nothrow @nogc:


struct FieldTemplate
{
    String name;
    String unit;
    ubyte flags; // mandatory, hidden
    // default value or default value expression (using related values)
}

struct ComponentTempalte
{
    String name;
    FieldTemplate[] fields;
}

extern(C++)
class Component
{
extern(D):
nothrow @nogc:

    this(String id)
    {
        this.id = id.move;
    }

    String id;
    String name;
    String template_;

    Array!(Component) components;
    Array!(Element*) elements;

    void addComponent(Component component) // TODO: include sampler here...
    {
        foreach (Component c; components)
        {
            if (c.name[] == component.name[])
            {
                debug assert(false, "Component '" ~ component.name ~ "' already exists in device '" ~ name ~ "'");
                assert(false, "Already exists");
                return;
            }
        }
        components.pushBack(component);
    }

    inout(Component) findComponent(const(char)[] name) inout pure nothrow @nogc
    {
        const(char)[] id = name.split!'.';
        foreach (inout Component c; components)
        {
            if (c.id[] == id[])
                return name.empty ? c : c.findComponent(name);
        }
        return null;
    }

    inout(Element)* findElement(const(char)[] name) inout pure nothrow @nogc
    {
        const(char)[] id = name.split!'.';
        if (!name.empty)
        {
            foreach (inout Component c; components)
            {
                if (c.id[] == id[])
                    return c.findElement(name);
            }
        }
        else
        {
            foreach (inout(Element)* e; elements)
            {
                if (e.id[] == id[])
                    return e;
            }
        }
        return null;
    }

    Component getFirstComponentByTemplate(const char[] templateName)
    {
        foreach (Component c; components)
            if (c.template_[] == templateName[])
                return c;
        return null;
    }

    Array!Component findComponentsByTemplate(const char[] templateName)
    {
        Array!Component result;
        foreach (Component c; components)
            if (c.template_[] == templateName[])
                result ~= c;
        return result;
    }

    import urt.string.format;
    ptrdiff_t toString(char[] buffer, const(char)[] fmt, const(FormatArg)[] formatArgs) const
    {
        return format(buffer, "Component({0}, \"{1}\", ...)", id, name).length;
    }
}


Map!(const(char)[], FieldTemplate*) componentTemplates;
//__gshared immutable FieldTemplate[] templates = [
//    FieldTemplate("switch");
//];

