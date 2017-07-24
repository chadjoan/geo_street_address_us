module geo.street_address.us.address_parse_result;

package struct AddressElement(S)
{
	string  propertyName;
	S       propertyValue;
}

alias SoftAddressElement = AddressElement!(char[]);
alias FirmAddressElement = AddressElement!(string);

/// Contains the fields that were extracted by the <see cref="AddressParser"/> object.
public struct AddressParseResult
{
	import std.algorithm;
	import std.array;
	import std.typecons;

	/// User-defined attribute used to track which class members are
	/// parsable address elements.
	private struct Lookup
	{
		string propertyName;
	}
	
	/+
	/// Table of property setters that are implemented in this class, indexed by name.
	private static (string*)[string] setterDispatchTable;
	
	static this
	{
		import std.stdio;
		import std.traits;
		foreach(memberName; __traits(derivedMembers, typeof(this)))
		{
			writefln("member: %s", memberName);
			foreach(methodOverload; MemberFunctionsTuple!(typeof(this), memberName) )
			{
				writefln("\toverload: %s %s(%s)", functionAttributes!methodOverload, ReturnType!methodOverload, Parameters!methodOverload);
				if ( hasFunctionAttributes!(methodOverload, "@property")
				&&   Parameters!(methodOverload).length == 1 )
				{
					setterDispatchTable[memberName] = methodOverload;
				}
			}
		}
	}
	+/
	
	private struct AddressProperty
	{
		string privateName;
		string propertyName;
	}
	
	pure private static AddressProperty[] scanAddressProperties()
	{
		import std.meta;
		import std.traits;

		AddressProperty[] result;

		foreach(privateName; std.traits.FieldNameTuple!(typeof(this)))
		{
			alias fieldSymbol = std.meta.Alias!(__traits(getMember, typeof(this), privateName));
			static if ( std.traits.hasUDA!(fieldSymbol, Lookup) )
			{
				enum propertyName = std.traits.getUDAs!(fieldSymbol, Lookup)[0].propertyName;
				result ~= AddressProperty(privateName, propertyName);
			}
		}

		return result;
	}

	pure private static size_t[string]
		getPropertyIndexMapping(const(AddressProperty)[] properties)
	{
		import std.exception : assumeUnique;
		size_t[string] mapping;
		size_t i = 0;
		foreach(prop; properties)
			mapping[prop.propertyName] = i++;
		return mapping;
	}
/+
	private alias AddressSetter = void delegate(string);
	pure private static AddressSetter[string]
		getAddressPropertySetters(
			AddressProperty[] properties,
			size_t[string]    propertiesBy)()
	{
		AddressSetter[string] mappings;
		/+static+/ foreach(prop; std.meta.aliasSeqOf!properties)
			mappings[prop.propertyName] = (string v){ mixin(prop.privateName~" = v;"; };
		return mappings;
	}
+/

	private static immutable(AddressProperty[])  properties = scanAddressProperties();

	public  static immutable(string[])        propertyNames = properties.map!"a.propertyName".array;
	public  static immutable(size_t[string])  propertyIndexesByGetterName;

	static this()
	{
		propertyIndexesByGetterName = getPropertyIndexMapping(properties);
	}

	//private static generateFieldSettingMixin(AddressProperty properties)()
	private static generateFieldSettingCode()
	{
		import std.format;
		string  genStr =
		`switch(propertyName)
		{
			`;
		foreach(prop; properties)
			genStr ~= format(
			`case "%s": %s = value; break;
			`, prop.propertyName, prop.privateName);
		genStr ~=
			`default: break;
		}
		`;
		return genStr;
	}

	private @nogc void setField(string propertyName, string value)
	{
		//mixin(generateFieldSettingMixin!properties);
		mixin(generateFieldSettingCode());
	}

/+
	this(string[string] fields)
	{
		foreach(prop; std.meta.aliasSeqOf!properties)
		{
			//pragma(msg, format("prop.getterName == %s", prop.getterName));
			string* elementRef = prop.getterName in fields;
			//writefln("Searching for getter name %s in fields.", prop.getterName);
			if ( elementRef !is null )
			{
				//writefln("  Found!  value == %s", *elementRef);
				__traits(getMember, this, prop.fieldName) = *elementRef;
			}
		}
	}
+/
	/// Initializes an new instance of the 'AddressParseResult' class.
	///
	/// Params:
	///      elements = The fields that were parsed.
	///
	@nogc package void initialize(FirmAddressElement[] elements)
	{
		import std.exception : assumeUnique;
		import std.meta;

		foreach(element; elements)
			setField(element.propertyName, element.propertyValue.assumeUnique);
	}

	/// Gets the city name.
	public  pure @nogc @property string city() const { return pCity; }
	private @Lookup("city") string pCity;

	/// Gets the house number.
	public  pure @nogc @property string number() const { return pNumber; }
	private @Lookup("number") string pNumber;

	/// Gets the predirectional, such as "N" in "500 N Main St".
	public  pure @nogc @property string predirectional() const { return pPredirectional; }
	private @Lookup("predirectional") string pPredirectional;

	/// Gets the postdirectional, such as "NW" in "500 Main St NW".
	public  pure @nogc @property string postdirectional() const { return pPostdirectional; }
	private @Lookup("postdirectional") string pPostdirectional;

	/// Gets the state or territory.
	public  pure @nogc @property string state() const { return pState; }
	private @Lookup("state") string pState;

	/// Gets the name of the street, such as "Main" in "500 N Main St".
	public  pure @nogc @property string street() const { return pStreet; }
	private @Lookup("street") string pStreet;

	// Things common to all of the streetLine formatters.
	private enum numStreetLineFields = 7;
	private enum streetLineFmtStr = "%-(%s %)";
	private pure @nogc auto streetLineRange(string[] buf) const
	{
		assert(buf.length >= numStreetLineFields);
		buf[0] = this.number;
		buf[1] = this.predirectional;
		buf[2] = this.street;
		buf[3] = this.suffix;
		buf[4] = this.postdirectional;
		buf[5] = this.secondaryUnit;
		buf[6] = this.secondaryNumber;
		return buf[0..numStreetLineFields];
	}

	/// Gets the full street line, such as "500 N Main St" in "500 N Main St".
	/// This is typically constructed by combining other elements in the parsed result.
	/// However, in some special circumstances, most notably APO/FPO/DPO addresses, the
	/// street line is set directly and the other elements will be null.
	public  @property string streetLine()
	{
		/+import std.array;
		import std.regex;
		import std.string;+/
		if (this.pStreetLine is null)
		{
			import std.algorithm.iteration : filter;
			import std.format;
			string[numStreetLineFields] buf;
			this.pStreetLine = format!streetLineFmtStr(
				streetLineRange(buf[]).filter!`a !is null`);
			/+auto tmpStreetLine = std.array.join([
					this.number,
					this.predirectional,
					this.street,
					this.suffix,
					this.postdirectional,
					this.secondaryUnit,
					this.secondaryNumber
				],  " ");
			this.pStreetLine =
				replaceAll(
					tmpStreetLine,
					std.regex.ctRegex!`\ +`,
					" ")
					.strip();+/
			return this.pStreetLine;
		}

		return this.pStreetLine;
	}

	private @Lookup("streetLine") string pStreetLine;

	public auto buildStreetLine(Writer)(ref Writer w) const
	{
		import std.algorithm.iteration : filter;
		import std.range.primitives;

		static assert(isOutputRange!(Writer, char));

		// The regex might assign the streetLine specifically, ex: for PO Boxes.
		if (this.pStreetLine !is null)
		{
			auto wSave = w.save;
			w.put(this.pStreetLine);
			return w.slice(wSave);
		}

		// But in most cases, we will need to compose the street line
		// out of other components.
		string[numStreetLineFields] streetLineFieldsBuf;
		return w.formattedPut!streetLineFmtStr(
				streetLineRange(streetLineFieldsBuf[]).filter!`a !is null`);
	}

	/// Gets the street suffix, such as "ST" in "500 N MAIN ST".
	public  pure @nogc @property string suffix() const { return pSuffix; }
	private @Lookup("suffix") string pSuffix;

	/// Gets the secondary unit, such as "APT" in "500 N MAIN ST APT 3".
	public  pure @nogc @property string secondaryUnit() const { return pSecondaryUnit; }
	private @Lookup("secondaryUnit") string pSecondaryUnit;

	/// Gets the secondary unit, such as "3" in "500 N MAIN ST APT 3".
	public  pure @nogc @property string secondaryNumber() const { return pSecondaryNumber; }
	private @Lookup("secondaryNumber") string pSecondaryNumber;

	/// Gets the ZIP code.
	public  pure @nogc @property string zip() const { return pZip; }
	private @Lookup("zip") string pZip;

	/// Returns a string that represents this instance.
	/// This method has its result memoized within the AddressParseResult
	/// instance, so there is no additional overhead to calling this
	/// after it has already been called once.  As a consequence, this
	/// method cannot be pure.
	///
	/// Returns: A string that represents this instance.
	public string toString()
	{
		import std.format;
		return format!"%s; %s, %s  %s"(
			this.streetLine,
			this.city,
			this.state,
			this.zip);
	}

	/// This is a pure version of the common toString function.
	/// This will always perform the string formatting necessary
	/// to stringize the address, but will do so without performing memory
	/// allocations, assuming the given 'textBuffer' is large enough.
	/// This both allows the method to be pure, and also allows it to be used
	/// in situations where memory heap allocations are highly undesirable.
	///
	/// Returns: A string that represents this instance.  This string will
	/// be a slice of the given 'textBuffer'.
	public auto toString(Writer)(ref Writer w) const
	{
		import std.range.primitives;

		static assert(isOutputRange!(Writer, char));

		auto wSave = w.save;
		buildStreetLine(w);
		w.formattedPut!"; %s, %s  %s"(
			this.city,
			this.state,
			this.zip);

		return w.slice(wSave);
	}
}

// Makes std.format.formattedWrite less of a bear to deal with.
import std.traits : isSomeString;
private auto formattedPut(alias fmt, Writer, A...)(ref Writer w, A args)
	if (isSomeString!(typeof(fmt)))
{
	import std.range.primitives;
	import std.format;

	// HACK: We have to assume that w has .length and is save-able,
	// because formattedWrite does not provide the formatted string
	// in any way, nor does it tell us how much of w was filled.
	// Even if it gave us the latter information, we'd still have to
	// make assumptions about w (ex: that it is random access and
	// slice-able).

	static assert(isOutputRange!(Writer, char));

	auto wSave = w.save;
	w.formattedWrite!fmt(args);
	return w.slice(wSave);
}