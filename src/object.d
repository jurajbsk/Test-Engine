module object;

alias size_t = typeof(int.sizeof);
alias ptrdiff_t = typeof(cast(void*)0 - cast(void*)0);

alias noreturn = typeof(*null);

alias string  = immutable(char)[];
alias wstring = immutable(wchar)[];
alias dstring = immutable(dchar)[];

version (LDC) // note: there's a copy for importC in __builtins.di
{
    version (ARM)     version = ARM_Any;
    version (AArch64) version = ARM_Any;

    // Define a __va_list[_tag] alias if the platform uses an elaborate type, as it
    // is referenced from implicitly generated code for D-style variadics, etc.
    // LDC does not require people to manually import core.vararg like DMD does.
    version (X86_64)
    {
        version (Win64) {} else
        alias __va_list_tag = imported!"core.internal.vararg.sysv_x64".__va_list_tag;
    }
    else version (ARM_Any)
    {
        // Darwin does not use __va_list
        version (OSX) {}
        else version (iOS) {}
        else version (TVOS) {}
        else version (WatchOS) {}
        else:

        version (ARM)
            public import core.stdc.stdarg : __va_list;
        else version (AArch64)
            public import core.internal.vararg.aarch64 : __va_list;
    }
}

version (GNU) {
    // No TypeInfo-based core.vararg.va_arg().
}
else version (X86_64)
{
    version (DigitalMars) version = WithArgTypes;
    else version (Windows) { /* no need for Win64 ABI */ }
    else version = WithArgTypes;
}
else version (AArch64)
{
    // Apple uses a trivial varargs implementation
    version (OSX) {}
    else version (iOS) {}
    else version (TVOS) {}
    else version (WatchOS) {}
    else version = WithArgTypes;
}

class Object
{
    /**
     * Convert Object to a human readable string.
     */
    string toString()
    {
        return typeid(this).name;
    }

    /**
     * Compute hash function for Object.
     */
    size_t toHash() @trusted nothrow
    {
        // BUG: this prevents a compacting GC from working, needs to be fixed
        size_t addr = cast(size_t) cast(void*) this;
        // The bottom log2((void*).alignof) bits of the address will always
        // be 0. Moreover it is likely that each Object is allocated with a
        // separate call to malloc. The alignment of malloc differs from
        // platform to platform, but rather than having special cases for
        // each platform it is safe to use a shift of 4. To minimize
        // collisions in the low bits it is more important for the shift to
        // not be too small than for the shift to not be too big.
        return addr ^ (addr >>> 4);
    }
    int opCmp(Object o)
    {
        // BUG: this prevents a compacting GC from working, needs to be fixed
        //return cast(int)cast(void*)this - cast(int)cast(void*)o;

        throw new Exception("need opCmp for class " ~ typeid(this).name);
        //return this !is o;
    }
    bool opEquals(Object o)
    {
        return this is o;
    }

    interface Monitor
    {
        void lock();
        void unlock();
    }
    static Object factory(string classname)
    {
        auto ci = TypeInfo_Class.find(classname);
        if (ci)
        {
            return ci.create();
        }
        return null;
    }
}
bool opEquals(LHS, RHS)(LHS lhs, RHS rhs)
if ((is(LHS : const Object) || is(LHS : const shared Object)) &&
    (is(RHS : const Object) || is(RHS : const shared Object)))
{
    static if (__traits(compiles, lhs.opEquals(rhs)) && __traits(compiles, rhs.opEquals(lhs)))
    {
        // If aliased to the same object or both null => equal
        if (lhs is rhs) return true;

        // If either is null => non-equal
        if (lhs is null || rhs is null) return false;

        if (!lhs.opEquals(rhs)) return false;

        // If same exact type => one call to method opEquals
        if (typeid(lhs) is typeid(rhs) ||
            !__ctfe && typeid(lhs).opEquals(typeid(rhs)))
                /* CTFE doesn't like typeid much. 'is' works, but opEquals doesn't:
                https://issues.dlang.org/show_bug.cgi?id=7147
                But CTFE also guarantees that equal TypeInfos are
                always identical. So, no opEquals needed during CTFE. */
        {
            return true;
        }

        // General case => symmetric calls to method opEquals
        return rhs.opEquals(lhs);
    }
    else
    {
        // this is a compatibility hack for the old const cast behavior
        // if none of the new overloads compile, we'll go back plain Object,
        // including casting away const. It does this through the pointer
        // to bypass any opCast that may be present on the original class.
        return .opEquals!(Object, Object)(*cast(Object*) &lhs, *cast(Object*) &rhs);

    }
}

private extern(C) void _d_setSameMutex(shared Object ownee, shared Object owner) nothrow;

void setSameMutex(shared Object ownee, shared Object owner)
{
    import core.atomic : atomicLoad;
    _d_setSameMutex(atomicLoad(ownee), atomicLoad(owner));
}

/**
 * Information about an interface.
 * When an object is accessed via an interface, an Interface* appears as the
 * first entry in its vtbl.
 */
struct Interface
{
    /// Class info returned by `typeid` for this interface (not for containing class)
    TypeInfo_Class   classinfo;
    void*[]     vtbl;
    size_t      offset;     /// offset to Interface 'this' from Object 'this'
}

/**
 * Array of pairs giving the offset and type information for each
 * member in an aggregate.
 */
struct OffsetTypeInfo
{
    size_t   offset;    /// Offset of member from start of object
    TypeInfo ti;        /// TypeInfo for this member
}

/**
 * Runtime type information about a type.
 * Can be retrieved for any type using a
 * $(GLINK2 expression,TypeidExpression, TypeidExpression).
 */
class TypeInfo
{
    override string toString() const @safe nothrow
    {
        return typeid(this).name;
    }

    override size_t toHash() @trusted const nothrow
    {
        return hashOf(this.toString());
    }

    override int opCmp(Object rhs)
    {
        if (this is rhs)
            return 0;
        auto ti = cast(TypeInfo) rhs;
        if (ti is null)
            return 1;
        return __cmp(this.toString(), ti.toString());
    }

    override bool opEquals(Object o)
    {
        return opEquals(cast(TypeInfo) o);
    }

    bool opEquals(const TypeInfo ti) @safe nothrow const
    {
        /* TypeInfo instances are singletons, but duplicates can exist
         * across DLL's. Therefore, comparing for a name match is
         * sufficient.
         */
        if (this is ti)
            return true;
        return ti && this.toString() == ti.toString();
    }

    /**
     * Computes a hash of the instance of a type.
     * Params:
     *    p = pointer to start of instance of the type
     * Returns:
     *    the hash
     * Bugs:
     *    fix https://issues.dlang.org/show_bug.cgi?id=12516 e.g. by changing this to a truly safe interface.
     */
    size_t getHash(scope const void* p) @trusted nothrow const
    {
        return 0;
    }

    /// Compares two instances for equality.
    bool equals(in void* p1, in void* p2) const { return p1 == p2; }

    /// Compares two instances for &lt;, ==, or &gt;.
    int compare(in void* p1, in void* p2) const { return _xopCmp(p1, p2); }

    /// Returns size of the type.
    @property size_t tsize() nothrow pure const @safe @nogc { return 0; }

    /// Swaps two instances of the type.
    void swap(void* p1, void* p2) const
    {
        size_t remaining = tsize;
        // If the type might contain pointers perform the swap in pointer-sized
        // chunks in case a garbage collection pass interrupts this function.
        if ((cast(size_t) p1 | cast(size_t) p2) % (void*).alignof == 0)
        {
            while (remaining >= (void*).sizeof)
            {
                void* tmp = *cast(void**) p1;
                *cast(void**) p1 = *cast(void**) p2;
                *cast(void**) p2 = tmp;
                p1 += (void*).sizeof;
                p2 += (void*).sizeof;
                remaining -= (void*).sizeof;
            }
        }
        for (size_t i = 0; i < remaining; i++)
        {
            byte t = (cast(byte *)p1)[i];
            (cast(byte*)p1)[i] = (cast(byte*)p2)[i];
            (cast(byte*)p2)[i] = t;
        }
    }

    /** Get TypeInfo for 'next' type, as defined by what kind of type this is,
    null if none. */
    @property inout(TypeInfo) next() nothrow pure inout @nogc { return null; }

    /**
     * Return default initializer.  If the type should be initialized to all
     * zeros, an array with a null ptr and a length equal to the type size will
     * be returned. For static arrays, this returns the default initializer for
     * a single element of the array, use `tsize` to get the correct size.
     */
version (LDC)
{
    // LDC uses TypeInfo's vtable for the typeof(null) type:
    //   %"typeid(typeof(null))" = type { %object.TypeInfo.__vtbl*, i8* }
    // Therefore this class cannot be abstract, and all methods need implementations.
    const(void)[] initializer() nothrow pure const @trusted @nogc
    {
        return (cast(const(void)*) null)[0 .. typeof(null).sizeof];
    }
}
else
{
    abstract const(void)[] initializer() nothrow pure const @safe @nogc;
}

    /** Get flags for type: 1 means GC should scan for pointers,
    2 means arg of this type is passed in SIMD register(s) if available */
    @property uint flags() nothrow pure const @safe @nogc { return 0; }

    /// Get type information on the contents of the type; null if not available
    const(OffsetTypeInfo)[] offTi() const { return null; }
    /// Run the destructor on the object and all its sub-objects
    void destroy(void* p) const {}
    /// Run the postblit on the object and all its sub-objects
    void postblit(void* p) const {}


    /// Return alignment of type
    @property size_t talign() nothrow pure const @safe @nogc { return tsize; }

    /** Return internal info on arguments fitting into 8byte.
     * See X86-64 ABI 3.2.3
     */
    version (WithArgTypes) int argTypes(out TypeInfo arg1, out TypeInfo arg2) @safe nothrow
    {
        arg1 = this;
        return 0;
    }

    /** Return info used by the garbage collector to do precise collection.
     */
    @property immutable(void)* rtInfo() nothrow pure const @safe @nogc { return rtinfoHasPointers; } // better safe than sorry
}

class TypeInfo_Enum : TypeInfo
{
    override string toString() const pure { return name; }

    override bool opEquals(Object o)
    {
        if (this is o)
            return true;
        auto c = cast(const TypeInfo_Enum)o;
        return c && this.name == c.name &&
                    this.base == c.base;
    }

    override size_t getHash(scope const void* p) const { return base.getHash(p); }

    override bool equals(in void* p1, in void* p2) const { return base.equals(p1, p2); }

    override int compare(in void* p1, in void* p2) const { return base.compare(p1, p2); }

    override @property size_t tsize() nothrow pure const { return base.tsize; }

    override void swap(void* p1, void* p2) const { return base.swap(p1, p2); }

    override @property inout(TypeInfo) next() nothrow pure inout { return base.next; }

    override @property uint flags() nothrow pure const { return base.flags; }

    override void destroy(void* p) const { return base.destroy(p); }
    override void postblit(void* p) const { return base.postblit(p); }

    override const(void)[] initializer() const
    {
        return m_init.length ? m_init : base.initializer();
    }

    override @property size_t talign() nothrow pure const { return base.talign; }

    version (WithArgTypes) override int argTypes(out TypeInfo arg1, out TypeInfo arg2)
    {
        return base.argTypes(arg1, arg2);
    }

    override @property immutable(void)* rtInfo() const { return base.rtInfo; }

    TypeInfo base;
    string   name;
    void[]   m_init;
}


// Please make sure to keep this in sync with TypeInfo_P (src/rt/typeinfo/ti_ptr.d)
class TypeInfo_Pointer : TypeInfo
{
    override string toString() const { return m_next.toString() ~ "*"; }

    override bool opEquals(Object o)
    {
        if (this is o)
            return true;
        auto c = cast(const TypeInfo_Pointer)o;
        return c && this.m_next == c.m_next;
    }

    override size_t getHash(scope const void* p) @trusted const
    {
        size_t addr = cast(size_t) *cast(const void**)p;
        return addr ^ (addr >> 4);
    }

    override bool equals(in void* p1, in void* p2) const
    {
        return *cast(void**)p1 == *cast(void**)p2;
    }

    override int compare(in void* p1, in void* p2) const
    {
        const v1 = *cast(void**) p1, v2 = *cast(void**) p2;
        return (v1 > v2) - (v1 < v2);
    }

    override @property size_t tsize() nothrow pure const
    {
        return (void*).sizeof;
    }

    override const(void)[] initializer() const @trusted
    {
        return (cast(void *)null)[0 .. (void*).sizeof];
    }

    override void swap(void* p1, void* p2) const
    {
        void* tmp = *cast(void**)p1;
        *cast(void**)p1 = *cast(void**)p2;
        *cast(void**)p2 = tmp;
    }

    override @property inout(TypeInfo) next() nothrow pure inout { return m_next; }
    override @property uint flags() nothrow pure const { return 1; }

    TypeInfo m_next;
}

class TypeInfo_Array : TypeInfo
{
    override string toString() const { return value.toString() ~ "[]"; }

    override bool opEquals(Object o)
    {
        if (this is o)
            return true;
        auto c = cast(const TypeInfo_Array)o;
        return c && this.value == c.value;
    }

    override size_t getHash(scope const void* p) @trusted const
    {
        void[] a = *cast(void[]*)p;
        return getArrayHash(value, a.ptr, a.length);
    }

    override bool equals(in void* p1, in void* p2) const
    {
        void[] a1 = *cast(void[]*)p1;
        void[] a2 = *cast(void[]*)p2;
        if (a1.length != a2.length)
            return false;
        size_t sz = value.tsize;
        for (size_t i = 0; i < a1.length; i++)
        {
            if (!value.equals(a1.ptr + i * sz, a2.ptr + i * sz))
                return false;
        }
        return true;
    }

    override int compare(in void* p1, in void* p2) const
    {
        void[] a1 = *cast(void[]*)p1;
        void[] a2 = *cast(void[]*)p2;
        size_t sz = value.tsize;
        size_t len = a1.length;

        if (a2.length < len)
            len = a2.length;
        for (size_t u = 0; u < len; u++)
        {
            immutable int result = value.compare(a1.ptr + u * sz, a2.ptr + u * sz);
            if (result)
                return result;
        }
        return (a1.length > a2.length) - (a1.length < a2.length);
    }

    override @property size_t tsize() nothrow pure const
    {
        return (void[]).sizeof;
    }

    override const(void)[] initializer() const @trusted
    {
        return (cast(void *)null)[0 .. (void[]).sizeof];
    }

    override void swap(void* p1, void* p2) const
    {
        void[] tmp = *cast(void[]*)p1;
        *cast(void[]*)p1 = *cast(void[]*)p2;
        *cast(void[]*)p2 = tmp;
    }

    TypeInfo value;

    override @property inout(TypeInfo) next() nothrow pure inout
    {
        return value;
    }

    override @property uint flags() nothrow pure const { return 1; }

    override @property size_t talign() nothrow pure const
    {
        return (void[]).alignof;
    }

    version (WithArgTypes) override int argTypes(out TypeInfo arg1, out TypeInfo arg2)
    {
        arg1 = typeid(size_t);
        arg2 = typeid(void*);
        return 0;
    }

    override @property immutable(void)* rtInfo() nothrow pure const @safe { return RTInfo!(void[]); }
}

class TypeInfo_StaticArray : TypeInfo
{
    override string toString() const
    {
        import core.internal.string : unsignedToTempString;

        char[20] tmpBuff = void;
        const lenString = unsignedToTempString(len, tmpBuff);

        return (() @trusted => cast(string) (value.toString() ~ "[" ~ lenString ~ "]"))();
    }

    override bool opEquals(Object o)
    {
        if (this is o)
            return true;
        auto c = cast(const TypeInfo_StaticArray)o;
        return c && this.len == c.len &&
                    this.value == c.value;
    }

    override size_t getHash(scope const void* p) @trusted const
    {
        return getArrayHash(value, p, len);
    }

    override bool equals(in void* p1, in void* p2) const
    {
        size_t sz = value.tsize;

        for (size_t u = 0; u < len; u++)
        {
            if (!value.equals(p1 + u * sz, p2 + u * sz))
                return false;
        }
        return true;
    }

    override int compare(in void* p1, in void* p2) const
    {
        size_t sz = value.tsize;

        for (size_t u = 0; u < len; u++)
        {
            immutable int result = value.compare(p1 + u * sz, p2 + u * sz);
            if (result)
                return result;
        }
        return 0;
    }

    override @property size_t tsize() nothrow pure const
    {
        return len * value.tsize;
    }

    override void swap(void* p1, void* p2) const
    {
        import core.stdc.string : memcpy;

        size_t remaining = value.tsize * len;
        void[size_t.sizeof * 4] buffer = void;
        while (remaining > buffer.length)
        {
            memcpy(buffer.ptr, p1, buffer.length);
            memcpy(p1, p2, buffer.length);
            memcpy(p2, buffer.ptr, buffer.length);
            p1 += buffer.length;
            p2 += buffer.length;
            remaining -= buffer.length;
        }
        memcpy(buffer.ptr, p1, remaining);
        memcpy(p1, p2, remaining);
        memcpy(p2, buffer.ptr, remaining);
    }

    override const(void)[] initializer() nothrow pure const
    {
        return value.initializer();
    }

    override @property inout(TypeInfo) next() nothrow pure inout { return value; }
    override @property uint flags() nothrow pure const { return value.flags; }

    override void destroy(void* p) const
    {
        immutable sz = value.tsize;
        p += sz * len;
        foreach (i; 0 .. len)
        {
            p -= sz;
            value.destroy(p);
        }
    }

    override void postblit(void* p) const
    {
        immutable sz = value.tsize;
        foreach (i; 0 .. len)
        {
            value.postblit(p);
            p += sz;
        }
    }

    TypeInfo value;
    size_t   len;

    override @property size_t talign() nothrow pure const
    {
        return value.talign;
    }

    version (WithArgTypes) override int argTypes(out TypeInfo arg1, out TypeInfo arg2)
    {
        arg1 = typeid(void*);
        return 0;
    }

    // just return the rtInfo of the element, we have no generic type T to run RTInfo!T on
    override @property immutable(void)* rtInfo() nothrow pure const @safe { return value.rtInfo(); }
}

class TypeInfo_AssociativeArray : TypeInfo
{
    override string toString() const
    {
        return value.toString() ~ "[" ~ key.toString() ~ "]";
    }

    override bool opEquals(Object o)
    {
        if (this is o)
            return true;
        auto c = cast(const TypeInfo_AssociativeArray)o;
        return c && this.key == c.key &&
                    this.value == c.value;
    }

    override bool equals(in void* p1, in void* p2) @trusted const
    {
        return !!_aaEqual(this, *cast(const AA*) p1, *cast(const AA*) p2);
    }

    override size_t getHash(scope const void* p) nothrow @trusted const
    {
        return _aaGetHash(cast(AA*)p, this);
    }

    // BUG: need to add the rest of the functions

    override @property size_t tsize() nothrow pure const
    {
        return (char[int]).sizeof;
    }

    override const(void)[] initializer() const @trusted
    {
        return (cast(void *)null)[0 .. (char[int]).sizeof];
    }

    override @property inout(TypeInfo) next() nothrow pure inout { return value; }
    override @property uint flags() nothrow pure const { return 1; }

    TypeInfo value;
    TypeInfo key;

    override @property size_t talign() nothrow pure const
    {
        return (char[int]).alignof;
    }

    version (WithArgTypes) override int argTypes(out TypeInfo arg1, out TypeInfo arg2)
    {
        arg1 = typeid(void*);
        return 0;
    }
}

class TypeInfo_Vector : TypeInfo
{
    override string toString() const { return "__vector(" ~ base.toString() ~ ")"; }

    override bool opEquals(Object o)
    {
        if (this is o)
            return true;
        auto c = cast(const TypeInfo_Vector)o;
        return c && this.base == c.base;
    }

    override size_t getHash(scope const void* p) const { return base.getHash(p); }
    override bool equals(in void* p1, in void* p2) const { return base.equals(p1, p2); }
    override int compare(in void* p1, in void* p2) const { return base.compare(p1, p2); }
    override @property size_t tsize() nothrow pure const { return base.tsize; }
    override void swap(void* p1, void* p2) const { return base.swap(p1, p2); }

    override @property inout(TypeInfo) next() nothrow pure inout { return base.next; }
    override @property uint flags() nothrow pure const { return 2; /* passed in SIMD register */ }

    override const(void)[] initializer() nothrow pure const
    {
        return base.initializer();
    }

    override @property size_t talign() nothrow pure const { return 16; }

    version (WithArgTypes) override int argTypes(out TypeInfo arg1, out TypeInfo arg2)
    {
        return base.argTypes(arg1, arg2);
    }

    TypeInfo base;
}

class TypeInfo_Function : TypeInfo
{
    override string toString() const pure @trusted
    {
        import core.demangle : demangleType;

        alias SafeDemangleFunctionType = char[] function (const(char)[] buf, char[] dst = null) @safe nothrow pure;
        SafeDemangleFunctionType demangle = cast(SafeDemangleFunctionType) &demangleType;

        return cast(string) demangle(deco);
    }

    override bool opEquals(Object o)
    {
        if (this is o)
            return true;
        auto c = cast(const TypeInfo_Function)o;
        return c && this.deco == c.deco;
    }

    // BUG: need to add the rest of the functions

    override @property size_t tsize() nothrow pure const
    {
        return 0;       // no size for functions
    }

    override const(void)[] initializer() const @safe
    {
        return null;
    }

    override @property immutable(void)* rtInfo() nothrow pure const @safe { return rtinfoNoPointers; }

    TypeInfo next;

    /**
    * Mangled function type string
    */
    string deco;
}

class TypeInfo_Delegate : TypeInfo
{
    override string toString() const pure @trusted
    {
        import core.demangle : demangleType;

        alias SafeDemangleFunctionType = char[] function (const(char)[] buf, char[] dst = null) @safe nothrow pure;
        SafeDemangleFunctionType demangle = cast(SafeDemangleFunctionType) &demangleType;

        return cast(string) demangle(deco);
    }

    override size_t getHash(scope const void* p) @trusted const
    {
        return hashOf(*cast(const void delegate() *)p);
    }

    override bool equals(in void* p1, in void* p2) const
    {
        auto dg1 = *cast(void delegate()*)p1;
        auto dg2 = *cast(void delegate()*)p2;
        return dg1 == dg2;
    }

    override int compare(in void* p1, in void* p2) const
    {
        auto dg1 = *cast(void delegate()*)p1;
        auto dg2 = *cast(void delegate()*)p2;

        if (dg1 < dg2)
            return -1;
        else if (dg1 > dg2)
            return 1;
        else
            return 0;
    }

    override @property size_t tsize() nothrow pure const
    {
        alias dg = int delegate();
        return dg.sizeof;
    }

    override const(void)[] initializer() const @trusted
    {
        return (cast(void *)null)[0 .. (int delegate()).sizeof];
    }

    override @property uint flags() nothrow pure const { return 1; }

    TypeInfo next;
    string deco;

    override @property size_t talign() nothrow pure const
    {
        alias dg = int delegate();
        return dg.alignof;
    }

    version (WithArgTypes) override int argTypes(out TypeInfo arg1, out TypeInfo arg2)
    {
        arg1 = typeid(void*);
        arg2 = typeid(void*);
        return 0;
    }

    override @property immutable(void)* rtInfo() nothrow pure const @safe { return RTInfo!(int delegate()); }
}

private extern (C) Object _d_newclass(const TypeInfo_Class ci);
private extern (C) int _d_isbaseof(scope TypeInfo_Class child,
    scope const TypeInfo_Class parent) @nogc nothrow pure @safe; // rt.cast_

/**
 * Runtime type information about a class.
 * Can be retrieved from an object instance by using the
 * $(DDSUBLINK spec/expression,typeid_expressions,typeid expression).
 */
class TypeInfo_Class : TypeInfo
{
    override string toString() const pure { return name; }

    override bool opEquals(const TypeInfo o) const
    {
        if (this is o)
            return true;
        auto c = cast(const TypeInfo_Class)o;
        return c && this.name == c.name;
    }

    override size_t getHash(scope const void* p) @trusted const
    {
        auto o = *cast(Object*)p;
        return o ? o.toHash() : 0;
    }

    override bool equals(in void* p1, in void* p2) const
    {
        Object o1 = *cast(Object*)p1;
        Object o2 = *cast(Object*)p2;

        return (o1 is o2) || (o1 && o1.opEquals(o2));
    }

    override int compare(in void* p1, in void* p2) const
    {
        Object o1 = *cast(Object*)p1;
        Object o2 = *cast(Object*)p2;
        int c = 0;

        // Regard null references as always being "less than"
        if (o1 !is o2)
        {
            if (o1)
            {
                if (!o2)
                    c = 1;
                else
                    c = o1.opCmp(o2);
            }
            else
                c = -1;
        }
        return c;
    }

    override @property size_t tsize() nothrow pure const
    {
        return Object.sizeof;
    }

    override const(void)[] initializer() nothrow pure const @safe
    {
        return m_init;
    }

    override @property uint flags() nothrow pure const { return 1; }

    override @property const(OffsetTypeInfo)[] offTi() nothrow pure const
    {
        return m_offTi;
    }

    final @property auto info() @safe @nogc nothrow pure const return { return this; }
    final @property auto typeinfo() @safe @nogc nothrow pure const return { return this; }

    byte[]      m_init;         /** class static initializer
                                 * (init.length gives size in bytes of class)
                                 */
    string      name;           /// class name
    void*[]     vtbl;           /// virtual function pointer table
    Interface[] interfaces;     /// interfaces this class implements
    TypeInfo_Class   base;           /// base class
    void*       destructor;
    void function(Object) classInvariant;
    enum ClassFlags : uint
    {
        isCOMclass = 0x1,
        noPointers = 0x2,
        hasOffTi = 0x4,
        hasCtor = 0x8,
        hasGetMembers = 0x10,
        hasTypeInfo = 0x20,
        isAbstract = 0x40,
        isCPPclass = 0x80,
        hasDtor = 0x100,
    }
    ClassFlags m_flags;
    void*       deallocator;
    OffsetTypeInfo[] m_offTi;
    void function(Object) defaultConstructor;   // default Constructor

    immutable(void)* m_RTInfo;        // data for precise GC
    override @property immutable(void)* rtInfo() const { return m_RTInfo; }

    /**
     * Search all modules for TypeInfo_Class corresponding to classname.
     * Returns: null if not found
     */
    static const(TypeInfo_Class) find(const scope char[] classname)
    {
        foreach (m; ModuleInfo)
        {
            if (m)
            {
                //writefln("module %s, %d", m.name, m.localClasses.length);
                foreach (c; m.localClasses)
                {
                    if (c is null)
                        continue;
                    //writefln("\tclass %s", c.name);
                    if (c.name == classname)
                        return c;
                }
            }
        }
        return null;
    }

    /**
     * Create instance of Object represented by 'this'.
     */
    Object create() const
    {
        if (m_flags & 8 && !defaultConstructor)
            return null;
        if (m_flags & 64) // abstract
            return null;
        Object o = _d_newclass(this);
        if (m_flags & 8 && defaultConstructor)
        {
            defaultConstructor(o);
        }
        return o;
    }

   /**
    * Returns true if the class described by `child` derives from or is
    * the class described by this `TypeInfo_Class`. Always returns false
    * if the argument is null.
    *
    * Params:
    *  child = TypeInfo for some class
    * Returns:
    *  true if the class described by `child` derives from or is the
    *  class described by this `TypeInfo_Class`.
    */
    final bool isBaseOf(scope const TypeInfo_Class child) const @nogc nothrow pure @trusted
    {
        if (m_init.length)
        {
            // If this TypeInfo_Class represents an actual class we only need
            // to check the child and its direct ancestors.
            for (auto ti = cast() child; ti !is null; ti = ti.base)
                if (ti is this)
                    return true;
            return false;
        }
        else
        {
            // If this TypeInfo_Class is the .info field of a TypeInfo_Interface
            // we also need to recursively check the child's interfaces.
            return child !is null && _d_isbaseof(cast() child, this);
        }
    }
}

alias ClassInfo = TypeInfo_Class;

class TypeInfo_Interface : TypeInfo
{
    override string toString() const pure { return info.name; }

    override bool opEquals(Object o)
    {
        if (this is o)
            return true;
        auto c = cast(const TypeInfo_Interface)o;
        return c && this.info.name == typeid(c).name;
    }

    override size_t getHash(scope const void* p) @trusted const
    {
        if (!*cast(void**)p)
        {
            return 0;
        }
        Interface* pi = **cast(Interface ***)*cast(void**)p;
        Object o = cast(Object)(*cast(void**)p - pi.offset);
        assert(o);
        return o.toHash();
    }

    override bool equals(in void* p1, in void* p2) const
    {
        Interface* pi = **cast(Interface ***)*cast(void**)p1;
        Object o1 = cast(Object)(*cast(void**)p1 - pi.offset);
        pi = **cast(Interface ***)*cast(void**)p2;
        Object o2 = cast(Object)(*cast(void**)p2 - pi.offset);

        return o1 == o2 || (o1 && o1.opCmp(o2) == 0);
    }

    override int compare(in void* p1, in void* p2) const
    {
        Interface* pi = **cast(Interface ***)*cast(void**)p1;
        Object o1 = cast(Object)(*cast(void**)p1 - pi.offset);
        pi = **cast(Interface ***)*cast(void**)p2;
        Object o2 = cast(Object)(*cast(void**)p2 - pi.offset);
        int c = 0;

        // Regard null references as always being "less than"
        if (o1 != o2)
        {
            if (o1)
            {
                if (!o2)
                    c = 1;
                else
                    c = o1.opCmp(o2);
            }
            else
                c = -1;
        }
        return c;
    }

    override @property size_t tsize() nothrow pure const
    {
        return Object.sizeof;
    }

    override const(void)[] initializer() const @trusted
    {
        return (cast(void *)null)[0 .. Object.sizeof];
    }

    override @property uint flags() nothrow pure const { return 1; }

    TypeInfo_Class info;

   /**
    * Returns true if the class described by `child` derives from the
    * interface described by this `TypeInfo_Interface`. Always returns
    * false if the argument is null.
    *
    * Params:
    *  child = TypeInfo for some class
    * Returns:
    *  true if the class described by `child` derives from the
    *  interface described by this `TypeInfo_Interface`.
    */
    final bool isBaseOf(scope const TypeInfo_Class child) const @nogc nothrow pure @trusted
    {
        return child !is null && _d_isbaseof(cast() child, this.info);
    }

   /**
    * Returns true if the interface described by `child` derives from
    * or is the interface described by this `TypeInfo_Interface`.
    * Always returns false if the argument is null.
    *
    * Params:
    *  child = TypeInfo for some interface
    * Returns:
    *  true if the interface described by `child` derives from or is
    *  the interface described by this `TypeInfo_Interface`.
    */
    final bool isBaseOf(scope const TypeInfo_Interface child) const @nogc nothrow pure @trusted
    {
        return child !is null && _d_isbaseof(cast() child.info, this.info);
    }
}

class TypeInfo_Struct : TypeInfo
{
    override string toString() const { return name; }

    override size_t toHash() const
    {
        return hashOf(this.mangledName);
    }

    override bool opEquals(Object o)
    {
        if (this is o)
            return true;
        auto s = cast(const TypeInfo_Struct)o;
        return s && this.mangledName == s.mangledName;
    }

    override size_t getHash(scope const void* p) @trusted pure nothrow const
    {
        assert(p);
        if (xtoHash)
        {
            return (*xtoHash)(p);
        }
        else
        {
            return hashOf(p[0 .. initializer().length]);
        }
    }

    override bool equals(in void* p1, in void* p2) @trusted pure nothrow const
    {
        import core.stdc.string : memcmp;

        if (!p1 || !p2)
            return false;
        else if (xopEquals)
        {
            const dg = _memberFunc(p1, xopEquals);
            return dg.xopEquals(p2);
        }
        else if (p1 == p2)
            return true;
        else
            // BUG: relies on the GC not moving objects
            return memcmp(p1, p2, initializer().length) == 0;
    }

    override int compare(in void* p1, in void* p2) @trusted pure nothrow const
    {
        import core.stdc.string : memcmp;

        // Regard null references as always being "less than"
        if (p1 != p2)
        {
            if (p1)
            {
                if (!p2)
                    return true;
                else if (xopCmp)
                {
                    const dg = _memberFunc(p1, xopCmp);
                    return dg.xopCmp(p2);
                }
                else
                    // BUG: relies on the GC not moving objects
                    return memcmp(p1, p2, initializer().length);
            }
            else
                return -1;
        }
        return 0;
    }

    override @property size_t tsize() nothrow pure const
    {
        return initializer().length;
    }

    override const(void)[] initializer() nothrow pure const @safe
    {
        return m_init;
    }

    override @property uint flags() nothrow pure const { return m_flags; }

    override @property size_t talign() nothrow pure const { return m_align; }

    final override void destroy(void* p) const
    {
        if (xdtor)
        {
            if (m_flags & StructFlags.isDynamicType)
                (*xdtorti)(p, this);
            else
                (*xdtor)(p);
        }
    }

    override void postblit(void* p) const
    {
        if (xpostblit)
            (*xpostblit)(p);
    }

    string mangledName;

    final @property string name() nothrow const @trusted
    {
        import core.demangle : demangleType;

        if (mangledName is null) // e.g., opaque structs
            return null;

        const key = cast(const void*) this; // faster lookup than TypeInfo_Struct, at the cost of potential duplicates per binary
        static string[typeof(key)] demangledNamesCache; // per thread

        // not nothrow:
        //return demangledNamesCache.require(key, cast(string) demangleType(mangledName));

        if (auto pDemangled = key in demangledNamesCache)
            return *pDemangled;

        const demangled = cast(string) demangleType(mangledName);
        demangledNamesCache[key] = demangled;
        return demangled;
    }

    void[] m_init;      // initializer; m_init.ptr == null if 0 initialize

    @safe pure nothrow
    {
        size_t   function(in void*)           xtoHash;
        bool     function(in void*, in void*) xopEquals;
        int      function(in void*, in void*) xopCmp;
        string   function(in void*)           xtoString;

        enum StructFlags : uint
        {
            hasPointers = 0x1,
            isDynamicType = 0x2, // built at runtime, needs type info in xdtor
        }
        StructFlags m_flags;
    }
    union
    {
        void function(void*)                xdtor;
        void function(void*, const TypeInfo_Struct ti) xdtorti;
    }
    void function(void*)                    xpostblit;

    uint m_align;

    override @property immutable(void)* rtInfo() nothrow pure const @safe { return m_RTInfo; }

    version (WithArgTypes)
    {
        override int argTypes(out TypeInfo arg1, out TypeInfo arg2)
        {
            arg1 = m_arg1;
            arg2 = m_arg2;
            return 0;
        }
        TypeInfo m_arg1;
        TypeInfo m_arg2;
    }
    immutable(void)* m_RTInfo;                // data for precise GC

    // The xopEquals and xopCmp members are function pointers to member
    // functions, which is not guaranteed to share the same ABI, as it is not
    // known whether the `this` parameter is the first or second argument.
    // This wrapper is to convert it to a delegate which will always pass the
    // `this` parameter in the correct way.
    private struct _memberFunc
    {
        union
        {
            struct // delegate
            {
                const void* ptr;
                const void* funcptr;
            }
            @safe pure nothrow
            {
                bool delegate(in void*) xopEquals;
                int delegate(in void*) xopCmp;
            }
        }
    }
}

class TypeInfo_Tuple : TypeInfo
{
    TypeInfo[] elements;

    override string toString() const
    {
        string s = "(";
        foreach (i, element; elements)
        {
            if (i)
                s ~= ',';
            s ~= element.toString();
        }
        s ~= ")";
        return s;
    }

    override bool opEquals(Object o)
    {
        if (this is o)
            return true;

        auto t = cast(const TypeInfo_Tuple)o;
        if (t && elements.length == t.elements.length)
        {
            for (size_t i = 0; i < elements.length; i++)
            {
                if (elements[i] != t.elements[i])
                    return false;
            }
            return true;
        }
        return false;
    }

    override size_t getHash(scope const void* p) const
    {
        assert(0);
    }

    override bool equals(in void* p1, in void* p2) const
    {
        assert(0);
    }

    override int compare(in void* p1, in void* p2) const
    {
        assert(0);
    }

    override @property size_t tsize() nothrow pure const
    {
        assert(0);
    }

    override const(void)[] initializer() const @trusted
    {
        assert(0);
    }

    override void swap(void* p1, void* p2) const
    {
        assert(0);
    }

    override void destroy(void* p) const
    {
        assert(0);
    }

    override void postblit(void* p) const
    {
        assert(0);
    }

    override @property size_t talign() nothrow pure const
    {
        assert(0);
    }

    version (WithArgTypes) override int argTypes(out TypeInfo arg1, out TypeInfo arg2)
    {
        assert(0);
    }
}

class TypeInfo_Const : TypeInfo
{
    override string toString() const
    {
        return cast(string) ("const(" ~ base.toString() ~ ")");
    }

    //override bool opEquals(Object o) { return base.opEquals(o); }
    override bool opEquals(Object o)
    {
        if (this is o)
            return true;

        if (typeid(this) != typeid(o))
            return false;

        auto t = cast(TypeInfo_Const)o;
        return base.opEquals(t.base);
    }

    override size_t getHash(scope const void *p) const { return base.getHash(p); }
    override bool equals(in void *p1, in void *p2) const { return base.equals(p1, p2); }
    override int compare(in void *p1, in void *p2) const { return base.compare(p1, p2); }
    override @property size_t tsize() nothrow pure const { return base.tsize; }
    override void swap(void *p1, void *p2) const { return base.swap(p1, p2); }

    override @property inout(TypeInfo) next() nothrow pure inout { return base.next; }
    override @property uint flags() nothrow pure const { return base.flags; }

    override const(void)[] initializer() nothrow pure const
    {
        return base.initializer();
    }

    override @property size_t talign() nothrow pure const { return base.talign; }

    version (WithArgTypes) override int argTypes(out TypeInfo arg1, out TypeInfo arg2)
    {
        return base.argTypes(arg1, arg2);
    }

    TypeInfo base;
}

class TypeInfo_Invariant : TypeInfo_Const
{
    override string toString() const
    {
        return cast(string) ("immutable(" ~ base.toString() ~ ")");
    }
}

class TypeInfo_Shared : TypeInfo_Const
{
    override string toString() const
    {
        return cast(string) ("shared(" ~ base.toString() ~ ")");
    }
}

class TypeInfo_Inout : TypeInfo_Const
{
    override string toString() const
    {
        return cast(string) ("inout(" ~ base.toString() ~ ")");
    }
}

// Contents of Moduleinfo._flags
enum
{
    MIctorstart  = 0x1,   // we've started constructing it
    MIctordone   = 0x2,   // finished construction
    MIstandalone = 0x4,   // module ctor does not depend on other module
                        // ctors being done first
    MItlsctor    = 8,
    MItlsdtor    = 0x10,
    MIctor       = 0x20,
    MIdtor       = 0x40,
    MIxgetMembers = 0x80,
    MIictor      = 0x100,
    MIunitTest   = 0x200,
    MIimportedModules = 0x400,
    MIlocalClasses = 0x800,
    MIname       = 0x1000,
}

/*****************************************
 * An instance of ModuleInfo is generated into the object file for each compiled module.
 *
 * It provides access to various aspects of the module.
 * It is not generated for betterC.
 */
struct ModuleInfo
{
    uint _flags; // MIxxxx
    uint _index; // index into _moduleinfo_array[]

    version (all)
    {
        deprecated("ModuleInfo cannot be copy-assigned because it is a variable-sized struct.")
        void opAssign(const scope ModuleInfo m) { _flags = m._flags; _index = m._index; }
    }
    else
    {
        @disable this();
    }

const:
    private void* addrOf(int flag) return nothrow pure @nogc
    in
    {
        assert(flag >= MItlsctor && flag <= MIname);
        assert(!(flag & (flag - 1)) && !(flag & ~(flag - 1) << 1));
    }
    do
    {
        import core.stdc.string : strlen;

        void* p = cast(void*)&this + ModuleInfo.sizeof;

        if (flags & MItlsctor)
        {
            if (flag == MItlsctor) return p;
            p += typeof(tlsctor).sizeof;
        }
        if (flags & MItlsdtor)
        {
            if (flag == MItlsdtor) return p;
            p += typeof(tlsdtor).sizeof;
        }
        if (flags & MIctor)
        {
            if (flag == MIctor) return p;
            p += typeof(ctor).sizeof;
        }
        if (flags & MIdtor)
        {
            if (flag == MIdtor) return p;
            p += typeof(dtor).sizeof;
        }
        if (flags & MIxgetMembers)
        {
            if (flag == MIxgetMembers) return p;
            p += typeof(xgetMembers).sizeof;
        }
        if (flags & MIictor)
        {
            if (flag == MIictor) return p;
            p += typeof(ictor).sizeof;
        }
        if (flags & MIunitTest)
        {
            if (flag == MIunitTest) return p;
            p += typeof(unitTest).sizeof;
        }
        if (flags & MIimportedModules)
        {
            if (flag == MIimportedModules) return p;
            p += size_t.sizeof + *cast(size_t*)p * typeof(importedModules[0]).sizeof;
        }
        if (flags & MIlocalClasses)
        {
            if (flag == MIlocalClasses) return p;
            p += size_t.sizeof + *cast(size_t*)p * typeof(localClasses[0]).sizeof;
        }
        if (true || flags & MIname) // always available for now
        {
            if (flag == MIname) return p;
            p += strlen(cast(immutable char*)p);
        }
        assert(0);
    }

    @property uint index() nothrow pure @nogc { return _index; }

    @property uint flags() nothrow pure @nogc { return _flags; }

    /************************
     * Returns:
     *  module constructor for thread locals, `null` if there isn't one
     */
    @property void function() tlsctor() nothrow pure @nogc
    {
        return flags & MItlsctor ? *cast(typeof(return)*)addrOf(MItlsctor) : null;
    }

    /************************
     * Returns:
     *  module destructor for thread locals, `null` if there isn't one
     */
    @property void function() tlsdtor() nothrow pure @nogc
    {
        return flags & MItlsdtor ? *cast(typeof(return)*)addrOf(MItlsdtor) : null;
    }

    /*****************************
     * Returns:
     *  address of a module's `const(MemberInfo)[] getMembers(string)` function, `null` if there isn't one
     */
    @property void* xgetMembers() nothrow pure @nogc
    {
        return flags & MIxgetMembers ? *cast(typeof(return)*)addrOf(MIxgetMembers) : null;
    }

    /************************
     * Returns:
     *  module constructor, `null` if there isn't one
     */
    @property void function() ctor() nothrow pure @nogc
    {
        return flags & MIctor ? *cast(typeof(return)*)addrOf(MIctor) : null;
    }

    /************************
     * Returns:
     *  module destructor, `null` if there isn't one
     */
    @property void function() dtor() nothrow pure @nogc
    {
        return flags & MIdtor ? *cast(typeof(return)*)addrOf(MIdtor) : null;
    }

    /************************
     * Returns:
     *  module order independent constructor, `null` if there isn't one
     */
    @property void function() ictor() nothrow pure @nogc
    {
        return flags & MIictor ? *cast(typeof(return)*)addrOf(MIictor) : null;
    }

    /*************
     * Returns:
     *  address of function that runs the module's unittests, `null` if there isn't one
     */
    @property void function() unitTest() nothrow pure @nogc
    {
        return flags & MIunitTest ? *cast(typeof(return)*)addrOf(MIunitTest) : null;
    }

    /****************
     * Returns:
     *  array of pointers to the ModuleInfo's of modules imported by this one
     */
    @property immutable(ModuleInfo*)[] importedModules() return nothrow pure @nogc
    {
        if (flags & MIimportedModules)
        {
            auto p = cast(size_t*)addrOf(MIimportedModules);
            return (cast(immutable(ModuleInfo*)*)(p + 1))[0 .. *p];
        }
        return null;
    }

    /****************
     * Returns:
     *  array of TypeInfo_Class references for classes defined in this module
     */
    @property TypeInfo_Class[] localClasses() return nothrow pure @nogc
    {
        if (flags & MIlocalClasses)
        {
            auto p = cast(size_t*)addrOf(MIlocalClasses);
            return (cast(TypeInfo_Class*)(p + 1))[0 .. *p];
        }
        return null;
    }

    /********************
     * Returns:
     *  name of module, `null` if no name
     */
    @property string name() return nothrow pure @nogc
    {
        import core.stdc.string : strlen;

        auto p = cast(immutable char*) addrOf(MIname);
        return p[0 .. strlen(p)];
    }

    static int opApply(scope int delegate(ModuleInfo*) dg)
    {
        import core.internal.traits : externDFunc;
        alias moduleinfos_apply = externDFunc!("rt.minfo.moduleinfos_apply",
                                              int function(scope int delegate(immutable(ModuleInfo*))));
        // Bugzilla 13084 - enforcing immutable ModuleInfo would break client code
        return moduleinfos_apply(
            (immutable(ModuleInfo*)m) => dg(cast(ModuleInfo*)m));
    }
}

///////////////////////////////////////////////////////////////////////////////
// Throwable
///////////////////////////////////////////////////////////////////////////////


/**
 * The base class of all thrown objects.
 *
 * All thrown objects must inherit from Throwable. Class $(D Exception), which
 * derives from this class, represents the category of thrown objects that are
 * safe to catch and handle. In principle, one should not catch Throwable
 * objects that are not derived from $(D Exception), as they represent
 * unrecoverable runtime errors. Certain runtime guarantees may fail to hold
 * when these errors are thrown, making it unsafe to continue execution after
 * catching them.
 */
class Throwable : Object
{
    interface TraceInfo
    {
        int opApply(scope int delegate(ref const(char[]))) const;
        int opApply(scope int delegate(ref size_t, ref const(char[]))) const;
        string toString() const;
    }

    alias TraceDeallocator = void function(TraceInfo) nothrow;

    string      msg;    /// A message describing the error.

    /**
     * The _file name of the D source code corresponding with
     * where the error was thrown from.
     */
    string      file;
    /**
     * The _line number of the D source code corresponding with
     * where the error was thrown from.
     */
    size_t      line;

    /**
     * The stack trace of where the error happened. This is an opaque object
     * that can either be converted to $(D string), or iterated over with $(D
     * foreach) to extract the items in the stack trace (as strings).
     */
    TraceInfo   info;

    /**
     * If set, this is used to deallocate the TraceInfo on destruction.
     */
    TraceDeallocator infoDeallocator;


    /**
     * A reference to the _next error in the list. This is used when a new
     * $(D Throwable) is thrown from inside a $(D catch) block. The originally
     * caught $(D Exception) will be chained to the new $(D Throwable) via this
     * field.
     */
    private Throwable   nextInChain;

    private uint _refcount;     // 0 : allocated by GC
                                // 1 : allocated by _d_newThrowable()
                                // 2.. : reference count + 1

    /**
     * Returns:
     * A reference to the _next error in the list. This is used when a new
     * $(D Throwable) is thrown from inside a $(D catch) block. The originally
     * caught $(D Exception) will be chained to the new $(D Throwable) via this
     * field.
     */
    @property inout(Throwable) next() @safe inout return scope pure nothrow @nogc { return nextInChain; }

    /**
     * Replace next in chain with `tail`.
     * Use `chainTogether` instead if at all possible.
     */
    @property void next(Throwable tail) @safe scope pure nothrow @nogc
    {
        if (tail && tail._refcount)
            ++tail._refcount;           // increment the replacement *first*

        auto n = nextInChain;
        nextInChain = null;             // sever the tail before deleting it

        if (n && n._refcount)
            _d_delThrowable(n);         // now delete the old tail

        nextInChain = tail;             // and set the new tail
    }

    /**
     * Returns:
     *  mutable reference to the reference count, which is
     *  0 - allocated by the GC, 1 - allocated by _d_newThrowable(),
     *  and >=2 which is the reference count + 1
     * Note:
     *  Marked as `@system` to discourage casual use of it.
     */
    @system @nogc final pure nothrow ref uint refcount() return { return _refcount; }

    /**
     * Loop over the chain of Throwables.
     */
    int opApply(scope int delegate(Throwable) dg)
    {
        int result = 0;
        for (Throwable t = this; t; t = t.nextInChain)
        {
            result = dg(t);
            if (result)
                break;
        }
        return result;
    }

    /**
     * Append `e2` to chain of exceptions that starts with `e1`.
     * Params:
     *  e1 = start of chain (can be null)
     *  e2 = second part of chain (can be null)
     * Returns:
     *  Throwable that is at the start of the chain; null if both `e1` and `e2` are null
     */
    static @__future @system @nogc pure nothrow Throwable chainTogether(return scope Throwable e1, return scope Throwable e2)
    {
        if (!e1)
            return e2;
        if (!e2)
            return e1;
        if (e2.refcount())
            ++e2.refcount();

        for (auto e = e1; 1; e = e.nextInChain)
        {
            if (!e.nextInChain)
            {
                e.nextInChain = e2;
                break;
            }
        }
        return e1;
    }

    @nogc @safe pure nothrow this(string msg, Throwable nextInChain = null)
    {
        this.msg = msg;
        this.nextInChain = nextInChain;
        if (nextInChain && nextInChain._refcount)
            ++nextInChain._refcount;
        //this.info = _d_traceContext();
    }

    @nogc @safe pure nothrow this(string msg, string file, size_t line, Throwable nextInChain = null)
    {
        this(msg, nextInChain);
        this.file = file;
        this.line = line;
        //this.info = _d_traceContext();
    }

    @trusted nothrow ~this()
    {
        if (nextInChain && nextInChain._refcount)
            _d_delThrowable(nextInChain);
        // handle owned traceinfo
        if (infoDeallocator !is null)
        {
            infoDeallocator(info);
            info = null; // avoid any kind of dangling pointers if we can help
                         // it.
        }
    }

    /**
     * Overrides $(D Object.toString) and returns the error message.
     * Internally this forwards to the $(D toString) overload that
     * takes a $(D_PARAM sink) delegate.
     */
    override string toString()
    {
        string s;
        toString((in buf) { s ~= buf; });
        return s;
    }

    /**
     * The Throwable hierarchy uses a toString overload that takes a
     * $(D_PARAM _sink) delegate to avoid GC allocations, which cannot be
     * performed in certain error situations.  Override this $(D
     * toString) method to customize the error message.
     */
    void toString(scope void delegate(in char[]) sink) const
    {
        import core.internal.string : unsignedToTempString;

        char[20] tmpBuff = void;

        sink(typeid(this).name);
        sink("@"); sink(file);
        sink("("); sink(unsignedToTempString(line, tmpBuff)); sink(")");

        if (msg.length)
        {
            sink(": "); sink(msg);
        }
        if (info)
        {
            try
            {
                sink("\n----------------");
                foreach (t; info)
                {
                    sink("\n"); sink(t);
                }
            }
            catch (Throwable)
            {
                // ignore more errors
            }
        }
    }

    /**
     * Get the message describing the error.
     *
     * This getter is an alternative way to access the Exception's message,
     * with the added advantage of being override-able in subclasses.
     * Subclasses are hence free to do their own memory managements without
     * being tied to the requirement of providing a `string` in a field.
     *
     * The default behavior is to return the `Throwable.msg` field.
     *
     * Returns:
     *  A message representing the cause of the `Throwable`
     */
    @__future const(char)[] message() const @safe nothrow
    {
        return this.msg;
    }
}


/**
 * The base class of all errors that are safe to catch and handle.
 *
 * In principle, only thrown objects derived from this class are safe to catch
 * inside a $(D catch) block. Thrown objects not derived from Exception
 * represent runtime errors that should not be caught, as certain runtime
 * guarantees may not hold, making it unsafe to continue program execution.
 */
class Exception : Throwable
{

    /**
     * Creates a new instance of Exception. The nextInChain parameter is used
     * internally and should always be $(D null) when passed by user code.
     * This constructor does not automatically throw the newly-created
     * Exception; the $(D throw) expression should be used for that purpose.
     */
    @nogc @safe pure nothrow this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable nextInChain = null)
    {
        super(msg, file, line, nextInChain);
    }

    @nogc @safe pure nothrow this(string msg, Throwable nextInChain, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line, nextInChain);
    }
}

/**
 * The base class of all unrecoverable runtime errors.
 *
 * This represents the category of $(D Throwable) objects that are $(B not)
 * safe to catch and handle. In principle, one should not catch Error
 * objects, as they represent unrecoverable runtime errors.
 * Certain runtime guarantees may fail to hold when these errors are
 * thrown, making it unsafe to continue execution after catching them.
 */
class Error : Throwable
{
    /**
     * Creates a new instance of Error. The nextInChain parameter is used
     * internally and should always be $(D null) when passed by user code.
     * This constructor does not automatically throw the newly-created
     * Error; the $(D throw) statement should be used for that purpose.
     */
    @nogc @safe pure nothrow this(string msg, Throwable nextInChain = null)
    {
        super(msg, nextInChain);
        bypassedException = null;
    }

    @nogc @safe pure nothrow this(string msg, string file, size_t line, Throwable nextInChain = null)
    {
        super(msg, file, line, nextInChain);
        bypassedException = null;
    }

    /** The first $(D Exception) which was bypassed when this Error was thrown,
    or $(D null) if no $(D Exception)s were pending. */
    Throwable   bypassedException;
}

extern (C)
{
    // from druntime/src/rt/aaA.d

    version (LDC)
    {
        /* The real type is (non-importable) `rt.aaA.Impl*`;
         * the compiler uses `void*` for its prototypes.
         */
        private alias AA = void*;
    }
    else
    {
        private struct AA { void* impl; }
    }

    // size_t _aaLen(in AA aa) pure nothrow @nogc;
    private void* _aaGetY(scope AA* paa, const TypeInfo_AssociativeArray ti, const size_t valsz, const scope void* pkey) pure nothrow;
    private void* _aaGetX(scope AA* paa, const TypeInfo_AssociativeArray ti, const size_t valsz, const scope void* pkey, out bool found) pure nothrow;
    // inout(void)* _aaGetRvalueX(inout AA aa, in TypeInfo keyti, in size_t valsz, in void* pkey);
    inout(void[]) _aaValues(inout AA aa, const size_t keysz, const size_t valsz, const TypeInfo tiValueArray) pure nothrow;
    inout(void[]) _aaKeys(inout AA aa, const size_t keysz, const TypeInfo tiKeyArray) pure nothrow;
    void* _aaRehash(AA* paa, const scope TypeInfo keyti) pure nothrow;
    void _aaClear(AA aa) pure nothrow;

    // alias _dg_t = extern(D) int delegate(void*);
    // int _aaApply(AA aa, size_t keysize, _dg_t dg);

    // alias _dg2_t = extern(D) int delegate(void*, void*);
    // int _aaApply2(AA aa, size_t keysize, _dg2_t dg);

    private struct AARange { AA impl; size_t idx; }
    AARange _aaRange(AA aa) pure nothrow @nogc @safe;
    bool _aaRangeEmpty(AARange r) pure nothrow @nogc @safe;
    void* _aaRangeFrontKey(AARange r) pure nothrow @nogc @safe;
    void* _aaRangeFrontValue(AARange r) pure nothrow @nogc @safe;
    void _aaRangePopFront(ref AARange r) pure nothrow @nogc @safe;

    int _aaEqual(scope const TypeInfo tiRaw, scope const AA aa1, scope const AA aa2);
    size_t _aaGetHash(scope const AA* aa, scope const TypeInfo tiRaw) nothrow;

    /*
        _d_assocarrayliteralTX marked as pure, because aaLiteral can be called from pure code.
        This is a typesystem hole, however this is existing hole.
        Early compiler didn't check purity of toHash or postblit functions, if key is a UDT thus
        copiler allowed to create AA literal with keys, which have impure unsafe toHash methods.
    */
    void* _d_assocarrayliteralTX(const TypeInfo_AssociativeArray ti, void[] keys, void[] values) pure;
}

void* aaLiteral(Key, Value)(Key[] keys, Value[] values) @trusted pure
{
    return _d_assocarrayliteralTX(typeid(Value[Key]), *cast(void[]*)&keys, *cast(void[]*)&values);
}

alias AssociativeArray(Key, Value) = Value[Key];

/***********************************
 * Removes all remaining keys and values from an associative array.
 * Params:
 *      aa =     The associative array.
 */
void clear(Value, Key)(Value[Key] aa)
{
    _aaClear(*cast(AA *) &aa);
}

/** ditto */
void clear(Value, Key)(Value[Key]* aa)
{
    _aaClear(*cast(AA *) aa);
}

/***********************************
 * Reorganizes the associative array in place so that lookups are more
 * efficient.
 * Params:
 *      aa =     The associative array.
 * Returns:
 *      The rehashed associative array.
 */
T rehash(T : Value[Key], Value, Key)(T aa)
{
    _aaRehash(cast(AA*)&aa, typeid(Value[Key]));
    return aa;
}

/** ditto */
T rehash(T : Value[Key], Value, Key)(T* aa)
{
    _aaRehash(cast(AA*)aa, typeid(Value[Key]));
    return *aa;
}

/** ditto */
T rehash(T : shared Value[Key], Value, Key)(T aa)
{
    _aaRehash(cast(AA*)&aa, typeid(Value[Key]));
    return aa;
}

/** ditto */
T rehash(T : shared Value[Key], Value, Key)(T* aa)
{
    _aaRehash(cast(AA*)aa, typeid(Value[Key]));
    return *aa;
}

/***********************************
 * Creates a new associative array of the same size and copies the contents of
 * the associative array into it.
 * Params:
 *      aa =     The associative array.
 */
V[K] dup(T : V[K], K, V)(T aa)
{
    //pragma(msg, "K = ", K, ", V = ", V);

    // Bug10720 - check whether V is copyable
    static assert(is(typeof({ V v = aa[K.init]; })),
        "cannot call " ~ T.stringof ~ ".dup because " ~ V.stringof ~ " is not copyable");

    V[K] result;

    //foreach (k, ref v; aa)
    //    result[k] = v;  // Bug13701 - won't work if V is not mutable

    ref V duplicateElem(ref K k, ref const V v) @trusted pure nothrow
    {
        import core.stdc.string : memcpy;

        void* pv = _aaGetY(cast(AA*)&result, typeid(V[K]), V.sizeof, &k);
        memcpy(pv, &v, V.sizeof);
        return *cast(V*)pv;
    }

    foreach (k, ref v; aa)
    {
        static if (!__traits(hasPostblit, V))
            duplicateElem(k, v);
        else static if (__traits(isStaticArray, V))
            _doPostblit(duplicateElem(k, v)[]);
        else static if (!is(typeof(v.__xpostblit())) && is(immutable V == immutable UV, UV))
            (() @trusted => *cast(UV*) &duplicateElem(k, v))().__xpostblit();
        else
            duplicateElem(k, v).__xpostblit();
    }

    return result;
}

/** ditto */
V[K] dup(T : V[K], K, V)(T* aa)
{
    return (*aa).dup;
}

// this should never be made public.
private AARange _aaToRange(T: V[K], K, V)(ref T aa) pure nothrow @nogc @safe
{
    // ensure we are dealing with a genuine AA.
    static if (is(const(V[K]) == const(T)))
        alias realAA = aa;
    else
        const(V[K]) realAA = aa;
    return _aaRange(() @trusted { return *cast(AA*)&realAA; } ());
}

/***********************************
 * Returns a $(REF_ALTTEXT forward range, isForwardRange, std,range,primitives)
 * which will iterate over the keys of the associative array. The keys are
 * returned by reference.
 *
 * If structural changes are made to the array (removing or adding keys), all
 * ranges previously obtained through this function are invalidated. The
 * following example program will dereference a null pointer:
 *
 *---
 * import std.stdio : writeln;
 *
 * auto dict = ["k1": 1, "k2": 2];
 * auto keyRange = dict.byKey;
 * dict.clear;
 * writeln(keyRange.front);    // Segmentation fault
 *---
 *
 * Params:
 *      aa =     The associative array.
 * Returns:
 *      A forward range referencing the keys of the associative array.
 */
auto byKey(T : V[K], K, V)(T aa) pure nothrow @nogc @safe
{
    import core.internal.traits : substInout;

    static struct Result
    {
        AARange r;

    pure nothrow @nogc:
        @property bool empty()  @safe { return _aaRangeEmpty(r); }
        @property ref front() @trusted
        {
            return *cast(substInout!K*) _aaRangeFrontKey(r);
        }
        void popFront() @safe { _aaRangePopFront(r); }
        @property Result save() { return this; }
    }

    return Result(_aaToRange(aa));
}

/** ditto */
auto byKey(T : V[K], K, V)(T* aa) pure nothrow @nogc
{
    return (*aa).byKey();
}

/***********************************
 * Returns a $(REF_ALTTEXT forward range, isForwardRange, std,range,primitives)
 * which will iterate over the values of the associative array. The values are
 * returned by reference.
 *
 * If structural changes are made to the array (removing or adding keys), all
 * ranges previously obtained through this function are invalidated. The
 * following example program will dereference a null pointer:
 *
 *---
 * import std.stdio : writeln;
 *
 * auto dict = ["k1": 1, "k2": 2];
 * auto valueRange = dict.byValue;
 * dict.clear;
 * writeln(valueRange.front);    // Segmentation fault
 *---
 *
 * Params:
 *      aa =     The associative array.
 * Returns:
 *      A forward range referencing the values of the associative array.
 */
auto byValue(T : V[K], K, V)(T aa) pure nothrow @nogc @safe
{
    import core.internal.traits : substInout;

    static struct Result
    {
        AARange r;

    pure nothrow @nogc:
        @property bool empty() @safe { return _aaRangeEmpty(r); }
        @property ref front() @trusted
        {
            return *cast(substInout!V*) _aaRangeFrontValue(r);
        }
        void popFront() @safe { _aaRangePopFront(r); }
        @property Result save() { return this; }
    }

    return Result(_aaToRange(aa));
}

/** ditto */
auto byValue(T : V[K], K, V)(T* aa) pure nothrow @nogc
{
    return (*aa).byValue();
}

/***********************************
 * Returns a $(REF_ALTTEXT forward range, isForwardRange, std,range,primitives)
 * which will iterate over the key-value pairs of the associative array. The
 * returned pairs are represented by an opaque type with `.key` and `.value`
 * properties for accessing references to the key and value of the pair,
 * respectively.
 *
 * If structural changes are made to the array (removing or adding keys), all
 * ranges previously obtained through this function are invalidated. The
 * following example program will dereference a null pointer:
 *
 *---
 * import std.stdio : writeln;
 *
 * auto dict = ["k1": 1, "k2": 2];
 * auto kvRange = dict.byKeyValue;
 * dict.clear;
 * writeln(kvRange.front.key, ": ", kvRange.front.value);    // Segmentation fault
 *---
 *
 * Note that this is a low-level interface to iterating over the associative
 * array and is not compatible withth the
 * $(LINK2 $(ROOT_DIR)phobos/std_typecons.html#.Tuple,`Tuple`) type in Phobos.
 * For compatibility with `Tuple`, use
 * $(LINK2 $(ROOT_DIR)phobos/std_array.html#.byPair,std.array.byPair) instead.
 *
 * Params:
 *      aa =     The associative array.
 * Returns:
 *      A forward range referencing the pairs of the associative array.
 */
auto byKeyValue(T : V[K], K, V)(T aa) pure nothrow @nogc @safe
{
    import core.internal.traits : substInout;

    static struct Result
    {
        AARange r;

    pure nothrow @nogc:
        @property bool empty() @safe { return _aaRangeEmpty(r); }
        @property auto front()
        {
            static struct Pair
            {
                // We save the pointers here so that the Pair we return
                // won't mutate when Result.popFront is called afterwards.
                private void* keyp;
                private void* valp;

                @property ref key() inout @trusted
                {
                    return *cast(substInout!K*) keyp;
                }
                @property ref value() inout @trusted
                {
                    return *cast(substInout!V*) valp;
                }
            }
            return Pair(_aaRangeFrontKey(r),
                        _aaRangeFrontValue(r));
        }
        void popFront() @safe { return _aaRangePopFront(r); }
        @property Result save() { return this; }
    }

    return Result(_aaToRange(aa));
}

/** ditto */
auto byKeyValue(T : V[K], K, V)(T* aa) pure nothrow @nogc
{
    return (*aa).byKeyValue();
}

/***********************************
 * Returns a newly allocated dynamic array containing a copy of the keys from
 * the associative array.
 * Params:
 *      aa =     The associative array.
 * Returns:
 *      A dynamic array containing a copy of the keys.
 */
Key[] keys(T : Value[Key], Value, Key)(T aa) @property
{
    // ensure we are dealing with a genuine AA.
    static if (is(const(Value[Key]) == const(T)))
        alias realAA = aa;
    else
        const(Value[Key]) realAA = aa;
    auto res = () @trusted {
        auto a = cast(void[])_aaKeys(*cast(inout(AA)*)&realAA, Key.sizeof, typeid(Key[]));
        return *cast(Key[]*)&a;
    }();
    static if (__traits(hasPostblit, Key))
        _doPostblit(res);
    return res;
}

/** ditto */
Key[] keys(T : Value[Key], Value, Key)(T *aa) @property
{
    return (*aa).keys;
}

/***********************************
 * Returns a newly allocated dynamic array containing a copy of the values from
 * the associative array.
 * Params:
 *      aa =     The associative array.
 * Returns:
 *      A dynamic array containing a copy of the values.
 */
Value[] values(T : Value[Key], Value, Key)(T aa) @property
{
    // ensure we are dealing with a genuine AA.
    static if (is(const(Value[Key]) == const(T)))
        alias realAA = aa;
    else
        const(Value[Key]) realAA = aa;
    auto res = () @trusted {
        auto a = cast(void[])_aaValues(*cast(inout(AA)*)&realAA, Key.sizeof, Value.sizeof, typeid(Value[]));
        return *cast(Value[]*)&a;
    }();
    static if (__traits(hasPostblit, Value))
        _doPostblit(res);
    return res;
}

/** ditto */
Value[] values(T : Value[Key], Value, Key)(T *aa) @property
{
    return (*aa).values;
}

/***********************************
 * Looks up key; if it exists returns corresponding value else evaluates and
 * returns defaultValue.
 * Params:
 *      aa =     The associative array.
 *      key =    The key.
 *      defaultValue = The default value.
 * Returns:
 *      The value.
 */
inout(V) get(K, V)(inout(V[K]) aa, K key, lazy inout(V) defaultValue)
{
    auto p = key in aa;
    return p ? *p : defaultValue;
}

/** ditto */
inout(V) get(K, V)(inout(V[K])* aa, K key, lazy inout(V) defaultValue)
{
    return (*aa).get(key, defaultValue);
}

/***********************************
 * Looks up key; if it exists returns corresponding value else evaluates
 * value, adds it to the associative array and returns it.
 * Params:
 *      aa =     The associative array.
 *      key =    The key.
 *      value =  The required value.
 * Returns:
 *      The value.
 */
ref V require(K, V)(ref V[K] aa, K key, lazy V value = V.init)
{
    bool found;
    // if key is @safe-ly copyable, `require` can infer @safe
    static if (isSafeCopyable!K)
    {
        auto p = () @trusted
        {
            return cast(V*) _aaGetX(cast(AA*) &aa, typeid(V[K]), V.sizeof, &key, found);
        } ();
    }
    else
    {
        auto p = cast(V*) _aaGetX(cast(AA*) &aa, typeid(V[K]), V.sizeof, &key, found);
    }
    if (found)
        return *p;
    else
    {
        *p = value; // Not `return (*p = value)` since if `=` is overloaded
        return *p;  // this might not return a ref to the left-hand side.
    }
}

// Tests whether T can be @safe-ly copied. Use a union to exclude destructor from the test.
private enum bool isSafeCopyable(T) = is(typeof(() @safe { union U { T x; } T *x; auto u = U(*x); }));

/***********************************
 * Calls `create` if `key` doesn't exist in the associative array,
 * otherwise calls `update`.
 * `create` returns a corresponding value for `key`.
 * `update` accepts a key parameter. If it returns a value, the value is
 * set for `key`.
 * Params:
 *      aa =     The associative array.
 *      key =    The key.
 *      create = The callable to create a value for `key`.
 *               Must return V.
 *      update = The callable to call if `key` exists.
 *               Takes a K argument, returns a V or void.
 */
void update(K, V, C, U)(ref V[K] aa, K key, scope C create, scope U update)
if (is(typeof(create()) : V) && (is(typeof(update(aa[K.init])) : V) || is(typeof(update(aa[K.init])) == void)))
{
    bool found;
    // if key is @safe-ly copyable, `update` may infer @safe
    static if (isSafeCopyable!K)
    {
        auto p = () @trusted
        {
            return cast(V*) _aaGetX(cast(AA*) &aa, typeid(V[K]), V.sizeof, &key, found);
        } ();
    }
    else
    {
        auto p = cast(V*) _aaGetX(cast(AA*) &aa, typeid(V[K]), V.sizeof, &key, found);
    }
    if (!found)
        *p = create();
    else
    {
        static if (is(typeof(update(*p)) == void))
            update(*p);
        else
            *p = update(*p);
    }
}

version (CoreDdoc)
{
    // This lets DDoc produce better documentation.

    /**
    Calculates the hash value of `arg` with an optional `seed` initial value.
    The result might not be equal to `typeid(T).getHash(&arg)`.

    Params:
        arg = argument to calculate the hash value of
        seed = optional `seed` value (may be used for hash chaining)

    Return: calculated hash value of `arg`
    */
    size_t hashOf(T)(auto ref T arg, size_t seed)
    {
        static import core.internal.hash;
        return core.internal.hash.hashOf(arg, seed);
    }
    /// ditto
    size_t hashOf(T)(auto ref T arg)
    {
        static import core.internal.hash;
        return core.internal.hash.hashOf(arg);
    }
}
else
{
    public import core.internal.hash : hashOf;
}

bool _xopEquals(in void*, in void*)
{
    throw new Error("TypeInfo.equals is not implemented");
}

bool _xopCmp(in void*, in void*)
{
    throw new Error("TypeInfo.compare is not implemented");
}

/******************************************
 * Create RTInfo for type T
 */

template RTInfoImpl(size_t[] pointerBitmap)
{
    immutable size_t[pointerBitmap.length] RTInfoImpl = pointerBitmap[];
}

template NoPointersBitmapPayload(size_t N)
{
    enum size_t[N] NoPointersBitmapPayload = 0;
}

template RTInfo(T)
{
    enum pointerBitmap = __traits(getPointerBitmap, T);
    static if (pointerBitmap[1 .. $] == NoPointersBitmapPayload!(pointerBitmap.length - 1))
        enum RTInfo = rtinfoNoPointers;
    else
        enum RTInfo = RTInfoImpl!(pointerBitmap).ptr;
}

/**
* shortcuts for the precise GC, also generated by the compiler
* used instead of the actual pointer bitmap
*/
enum immutable(void)* rtinfoNoPointers  = null;
enum immutable(void)* rtinfoHasPointers = cast(void*)1;

// Helper functions

private inout(TypeInfo) getElement(return scope inout TypeInfo value) @trusted pure nothrow
{
    TypeInfo element = cast() value;
    for (;;)
    {
        if (auto qualified = cast(TypeInfo_Const) element)
            element = qualified.base;
        else if (auto redefined = cast(TypeInfo_Enum) element)
            element = redefined.base;
        else if (auto staticArray = cast(TypeInfo_StaticArray) element)
            element = staticArray.value;
        else if (auto vector = cast(TypeInfo_Vector) element)
            element = vector.base;
        else
            break;
    }
    return cast(inout) element;
}

private size_t getArrayHash(const scope TypeInfo element, const scope void* ptr, const size_t count) @trusted nothrow
{
    if (!count)
        return 0;

    const size_t elementSize = element.tsize;
    if (!elementSize)
        return 0;

    static bool hasCustomToHash(const scope TypeInfo value) @trusted pure nothrow
    {
        const element = getElement(value);

        if (const struct_ = cast(const TypeInfo_Struct) element)
            return !!struct_.xtoHash;

        return cast(const TypeInfo_Array) element
            || cast(const TypeInfo_AssociativeArray) element
            || cast(const ClassInfo) element
            || cast(const TypeInfo_Interface) element;
    }

    if (!hasCustomToHash(element))
        return hashOf(ptr[0 .. elementSize * count]);

    size_t hash = 0;
    foreach (size_t i; 0 .. count)
        hash = hashOf(element.getHash(ptr + i * elementSize), hash);
    return hash;
}

/// Provide the .dup array property.
@property auto dup(T)(T[] a)
    if (!is(const(T) : T))
{
    import core.internal.traits : Unconst;
    import core.internal.array.duplication : _dup;
    static assert(is(T : Unconst!T), "Cannot implicitly convert type "~T.stringof~
                  " to "~Unconst!T.stringof~" in dup.");

    return _dup!(T, Unconst!T)(a);
}

/// ditto
// const overload to support implicit conversion to immutable (unique result, see DIP29)
@property T[] dup(T)(const(T)[] a)
    if (is(const(T) : T))
{
    import core.internal.array.duplication : _dup;
    return _dup!(const(T), T)(a);
}


/// Provide the .idup array property.
@property immutable(T)[] idup(T)(T[] a)
{
    import core.internal.array.duplication : _dup;
    static assert(is(T : immutable(T)), "Cannot implicitly convert type "~T.stringof~
                  " to immutable in idup.");
    return _dup!(T, immutable(T))(a);
}

/// ditto
@property immutable(T)[] idup(T:void)(const(T)[] a)
{
    return a.dup;
}

// HACK:  This is a lie.  `_d_arraysetcapacity` is neither `nothrow` nor `pure`, but this lie is
// necessary for now to prevent breaking code.
private extern (C) size_t _d_arraysetcapacity(const TypeInfo ti, size_t newcapacity, void[]* arrptr) pure nothrow;

/**
(Property) Gets the current _capacity of a slice. The _capacity is the size
that the slice can grow to before the underlying array must be
reallocated or extended.

If an append must reallocate a slice with no possibility of extension, then
`0` is returned. This happens when the slice references a static array, or
if another slice references elements past the end of the current slice.

Note: The _capacity of a slice may be impacted by operations on other slices.
*/
@property size_t capacity(T)(T[] arr) pure nothrow @trusted
{
    return _d_arraysetcapacity(typeid(T[]), 0, cast(void[]*)&arr);
}

/**
Reserves capacity for a slice. The capacity is the size
that the slice can grow to before the underlying array must be
reallocated or extended.

Returns: The new capacity of the array (which may be larger than
the requested capacity).
*/
size_t reserve(T)(ref T[] arr, size_t newcapacity) pure nothrow @trusted
{
    if (__ctfe)
        return newcapacity;
    else
        return _d_arraysetcapacity(typeid(T[]), newcapacity, cast(void[]*)&arr);
}

// HACK:  This is a lie.  `_d_arrayshrinkfit` is not `nothrow`, but this lie is necessary
// for now to prevent breaking code.
private extern (C) void _d_arrayshrinkfit(const TypeInfo ti, void[] arr) nothrow;

/**
Assume that it is safe to append to this array. Appends made to this array
after calling this function may append in place, even if the array was a
slice of a larger array to begin with.

Use this only when it is certain there are no elements in use beyond the
array in the memory block.  If there are, those elements will be
overwritten by appending to this array.

Warning: Calling this function, and then using references to data located after the
given array results in undefined behavior.

Returns:
  The input is returned.
*/
auto ref inout(T[]) assumeSafeAppend(T)(auto ref inout(T[]) arr) nothrow @system
{
    _d_arrayshrinkfit(typeid(T[]), *(cast(void[]*)&arr));
    return arr;
}

private void _doPostblit(T)(T[] arr)
{
    // infer static postblit type, run postblit if any
    static if (__traits(hasPostblit, T))
    {
        static if (__traits(isStaticArray, T) && is(T : E[], E))
            _doPostblit(cast(E[]) arr);
        else static if (!is(typeof(arr[0].__xpostblit())) && is(immutable T == immutable U, U))
            foreach (ref elem; (() @trusted => cast(U[]) arr)())
                elem.__xpostblit();
        else
            foreach (ref elem; arr)
                elem.__xpostblit();
    }
}

/**
Destroys the given object and optionally resets to initial state. It's used to
_destroy an object, calling its destructor or finalizer so it no longer
references any other objects. It does $(I not) initiate a GC cycle or free
any GC memory.
If `initialize` is supplied `false`, the object is considered invalid after
destruction, and should not be referenced.
*/
void destroy(bool initialize = true, T)(ref T obj) if (is(T == struct))
{
    import core.internal.destruction : destructRecurse;

    destructRecurse(obj);

    static if (initialize)
    {
        import core.internal.lifetime : emplaceInitializer;
        emplaceInitializer(obj); // emplace T.init
    }
}

private extern (C) void rt_finalize2(void* p, bool det = true, bool resetMemory = true) nothrow;

/// ditto
void destroy(bool initialize = true, T)(T obj) if (is(T == class))
{
    static if (__traits(getLinkage, T) == "C++")
    {
        static if (__traits(hasMember, T, "__xdtor"))
            obj.__xdtor();

        static if (initialize)
        {
            const initializer = __traits(initSymbol, T);
            (cast(void*)obj)[0 .. initializer.length] = initializer[];
        }
    }
    else
    {
        // Bypass overloaded opCast
        auto ptr = (() @trusted => *cast(void**) &obj)();
        rt_finalize2(ptr, true, initialize);
    }
}

/// ditto
void destroy(bool initialize = true, T)(T obj) if (is(T == interface))
{
    static assert(__traits(getLinkage, T) == "D", "Invalid call to destroy() on extern(" ~ __traits(getLinkage, T) ~ ") interface");

    destroy!initialize(cast(Object)obj);
}

/// ditto
void destroy(bool initialize = true, T)(ref T obj)
if (__traits(isStaticArray, T))
{
    foreach_reverse (ref e; obj[])
        destroy!initialize(e);
}

/// ditto
void destroy(bool initialize = true, T)(ref T obj)
    if (!is(T == struct) && !is(T == interface) && !is(T == class) && !__traits(isStaticArray, T))
{
    static if (initialize)
        obj = T.init;
}

/* ************************************************************************
                           COMPILER SUPPORT
The compiler lowers certain expressions to instantiations of the following
templates.  They must be implicitly imported, which is why they are here
in this file. They must also be `public` as they must be visible from the
scope in which they are instantiated.  They are explicitly undocumented as
they are only intended to be instantiated by the compiler, not the user.
**************************************************************************/

public import core.internal.entrypoint : _d_cmain;

public import core.internal.array.appending : _d_arrayappendT;
public import core.internal.array.appending : _d_arrayappendcTXImpl;
public import core.internal.array.comparison : __cmp;
public import core.internal.array.equality : __equals;
public import core.internal.array.casting: __ArrayCast;
public import core.internal.array.concatenation : _d_arraycatnTX;
public import core.internal.array.construction : _d_arrayctor;
public import core.internal.array.construction : _d_arraysetctor;
public import core.internal.array.arrayassign : _d_arrayassign_l;
public import core.internal.array.arrayassign : _d_arrayassign_r;
public import core.internal.array.arrayassign : _d_arraysetassign;
public import core.internal.array.capacity: _d_arraysetlengthTImpl;

public import core.internal.dassert: _d_assert_fail;

public import core.internal.destruction: __ArrayDtor;

public import core.internal.moving: __move_post_blt;

public import core.internal.postblit: __ArrayPostblit;

public import core.internal.switch_: __switch;
public import core.internal.switch_: __switch_error;

public import core.lifetime : _d_delstructImpl;
public import core.lifetime : _d_newThrowable;
public import core.lifetime : _d_newclassT;
public import core.lifetime : _d_newclassTTrace;
public import core.lifetime : _d_newitemT;

public @trusted @nogc nothrow pure extern (C) void _d_delThrowable(scope Throwable);

// Compiler hook into the runtime implementation of array (vector) operations.
template _arrayOp(Args...)
{
    import core.internal.array.operations;
    alias _arrayOp = arrayOp!Args;
}

public import core.builtins : __ctfeWrite;

/**

Provides an "inline import", i.e. an `import` that is only available for a
limited lookup. For example:

---
void fun(imported!"std.stdio".File input)
{
    ... use File from std.stdio normally ...
}
---

There is no need to import `std.stdio` at top level, so `fun` carries its own
dependencies. The same approach can be used for template constraints:

---
void fun(T)(imported!"std.stdio".File input, T value)
if (imported!"std.traits".isIntegral!T)
{
    ...
}
---

An inline import may be used in conjunction with the `with` statement as well.
Inside the scope controlled by `with`, all symbols in the imported module are
made available:

---
void fun()
{
    with (imported!"std.datetime")
    with (imported!"std.stdio")
    {
        Clock.currTime.writeln;
    }
}
---

The advantages of inline imports over top-level uses of the `import` declaration
are the following:

$(UL
$(LI The `imported` template specifies dependencies at declaration level, not at
module level. This allows reasoning about the dependency cost of declarations in
separation instead of aggregated at module level.)
$(LI Declarations using `imported` are easier to move around because they don't
require top-level context, making for simpler and quicker refactorings.)
$(LI Declarations using `imported` scale better with templates. This is because
templates that are not instantiated do not have their parameters and constraints
instantiated, so additional modules are not imported without necessity. This
makes the cost of unused templates negligible. Dependencies are pulled on a need
basis depending on the declarations used by client code.)
)

The use of `imported` also has drawbacks:

$(UL
$(LI If most declarations in a module need the same imports, then factoring them
at top level, outside the declarations, is simpler than repeating them.)
$(LI Traditional dependency-tracking tools such as make and other build systems
assume file-level dependencies and need special tooling (such as rdmd) in order
to work efficiently.)
$(LI Dependencies at the top of a module are easier to inspect quickly than
dependencies spread throughout the module.)
)

See_Also: The $(HTTP forum.dlang.org/post/tzqzmqhankrkbrfsrmbo@forum.dlang.org,
forum discussion) that led to the creation of the `imported` facility. Credit is
due to Daniel Nielsen and Dominikus Dittes Scherkl.

*/
template imported(string moduleName)
{
    mixin("import imported = " ~ moduleName ~ ";");
}
