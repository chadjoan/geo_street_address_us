module geo.street_address.us.address_parse_result;

/*
	import std.array, std.range : isInputRange, dropOne;
	template TupleOf(alias R) if (isInputRange!(typeof(R))) {
		import std.typecons;
		static if (R.empty)
			enum TupleOf = tuple();
		else
			enum TupleOf = tuple(R.front(), TupleOf!(R.dropOne()));
	}
*/
/// <summary>
/// Contains the fields that were extracted by the <see cref="AddressParser"/> object.
/// </summary>
public class AddressParseResult
{
	import std.algorithm;
	import std.array;
	import std.typecons;

	/// User-defined attribute used to track which class members are
	/// parsable address elements.
	private struct Lookup
	{
		string getterName;
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
		string fieldName;
		string getterName;
	}
	
	pure private static AddressProperty[] scanAddressProperties()
	{
		import std.meta;
		import std.traits;
		
		AddressProperty[] result;
		
		foreach(fieldName; std.traits.FieldNameTuple!(typeof(this)))
		{
			alias fieldSymbol = std.meta.Alias!(__traits(getMember, typeof(this), fieldName));
			static if ( std.traits.hasUDA!(fieldSymbol, Lookup) )
			{
				enum getterName = std.traits.getUDAs!(fieldSymbol, Lookup)[0].getterName;
				result ~= AddressProperty(fieldName, getterName);
			}
		}
		
		return result;
	}

	//private enum AddressProperty[] properties = scanAddressProperties();
	private static immutable(AddressProperty[]) properties = scanAddressProperties();
	//private static immutable(string[]) fieldNames    = properties.map!"a.fieldName".array;
	public  static immutable(string[]) propertyNames = properties.map!"a.getterName".array;

	/// <summary>
	/// Initializes a new instance of the <see cref="AddressParseResult"/> class.
	/// </summary>
	/// <param name="fields">The fields that were parsed.</param>
	this(string[string] fields)
	{
		import std.meta;
		//import std.format;
		//import std.stdio;
		//writefln("fields == %s", fields);
		
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

		/+
		import std.traits;
		foreach(fieldName; std.traits.FieldNameTuple!(typeof(this)))
		{
			writefln("field: %s", fieldName);
			static if ( ! std.traits.hasUDA!(__traits(getMember, this, fieldName), "@Lookup") )
			{
				enum getterName = std.traits.getUDAs!(
					__traits(getMember, this, fieldName), Lookup)[0].getterName;
				string* elementRef = getterName in fields;
				if ( elementRef !is null )
					__traits(getMember, this, fieldName) = *elementRef;
			}
		}
		+/
		
		/+
		foreach ( key, val; fields )
		{
			setterDispatchTable[key](val);
		}
		+/

		/+
		var type = this.GetType();
		foreach (var pair in fields)
		{
			var bindingFlags = 
				BindingFlags.Instance | 
				BindingFlags.Public | 
				BindingFlags.IgnoreCase;
			var propertyInfo = type.GetProperty(pair.Key, bindingFlags);
			if (propertyInfo != null)
			{
				var methodInfo = propertyInfo.GetSetMethod(true);
				if (methodInfo != null)
				{
					methodInfo.Invoke(this, new[] { pair.Value });
				}
			}
		}
		+/
	}

	/// <summary>
	/// Gets the city name.
	/// </summary>
	public  @property string City() const { return pCity; }
	private @Lookup("City") string pCity;

	/// <summary>
	/// Gets the house number.
	/// </summary>
	public  @property string Number() const { return pNumber; }
	private @Lookup("Number") string pNumber;

	/// <summary>
	/// Gets the predirectional, such as "N" in "500 N Main St".
	/// </summary>
	public  @property string Predirectional() const { return pPredirectional; }
	private @Lookup("Predirectional") string pPredirectional;

	/// <summary>
	/// Gets the postdirectional, such as "NW" in "500 Main St NW".
	/// </summary>
	public  @property string Postdirectional() const { return pPostdirectional; }
	private @Lookup("Postdirectional") string pPostdirectional;

	/// <summary>
	/// Gets the state or territory.
	/// </summary>
	public  @property string State() const { return pState; }
	private @Lookup("State") string pState;

	/// <summary>
	/// Gets the name of the street, such as "Main" in "500 N Main St".
	/// </summary>
	public  @property string Street() const { return pStreet; }
	private @Lookup("Street") string pStreet;

	/// <summary>
	/// Gets the full street line, such as "500 N Main St" in "500 N Main St".
	/// This is typically constructed by combining other elements in the parsed result.
	/// However, in some special circumstances, most notably APO/FPO/DPO addresses, the
	/// street line is set directly and the other elements will be null.
	/// </summary>
	public  @property string StreetLine()
	{
		import std.array;
		import std.regex;
		import std.string;
		if (this.pStreetLine is null)
		{
			auto tmpStreetLine = std.array.join([
					this.Number,
					this.Predirectional,
					this.Street,
					this.Suffix,
					this.Postdirectional,
					this.SecondaryUnit,
					this.SecondaryNumber
				],  " ");
			this.pStreetLine =
				replaceAll(
					tmpStreetLine,
					std.regex.ctRegex!`\ +`,
					" ")
					.strip();
			return this.pStreetLine;
		}

		return this.pStreetLine;
	}
	
	private @Lookup("StreetLine") string pStreetLine;

	/// <summary>
	/// Gets the street suffix, such as "ST" in "500 N MAIN ST".
	/// </summary>
	public  @property string Suffix() const { return pSuffix; }
	private @Lookup("Suffix") string pSuffix;

	/// <summary>
	/// Gets the secondary unit, such as "APT" in "500 N MAIN ST APT 3".
	/// </summary>
	public  @property string SecondaryUnit() const { return pSecondaryUnit; }
	private @Lookup("SecondaryUnit") string pSecondaryUnit;

	/// <summary>
	/// Gets the secondary unit, such as "3" in "500 N MAIN ST APT 3".
	/// </summary>
	public  @property string SecondaryNumber() const { return pSecondaryNumber; }
	private @Lookup("SecondaryNumber") string pSecondaryNumber;

	/// <summary>
	/// Gets the ZIP code.
	/// </summary>
	public  @property string Zip() const { return pZip; }
	private @Lookup("Zip") string pZip;

	/// <summary>
	/// Returns a string that represents this instance.
	/// </summary>
	/// <returns>
	/// A string that represents this instance.
	/// </returns>
	public override string toString()
	{
		import std.format;
		return format(
			"%s; %s, %s  %s",
			this.StreetLine,
			this.City,
			this.State,
			this.Zip);
	}
}
