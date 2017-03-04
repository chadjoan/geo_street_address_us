module geo.street_address.us.tests;

import geo.street_address.us.parser;

unittest
{
	import std.algorithm.searching : canFind, startsWith;
	import std.algorithm.iteration : splitter;
	import std.format;

	// Ensure that the regular expression and the AddressParseResult class are
	// using the same terminology.
	
	// At some point in the future, D compilers might be capable of compiling
	// this regex at compile time (as of this writing, the regex is too large
	// and complicated to process at compile-time).  When that happens, it
	// would make sense to have these tests occur at compile-time as well,
	// rather than during unittesting.
	
	// Step 1: ensure that named captures have corresponding AddressParseResult
	// fields.  While we're at it, populate this set that represents all of
	// the named captures, so that we can look them up quickly in step 2.
	bool[string] fieldNameSegmentsOfNamedCapturesAA;
	foreach (name; addressRegex.namedCaptures)
	{
		if ( name.startsWith("_") )
			continue; // Exclude underscore'd captures from this check.  These are useful for troubleshooting.

		// By convention, the captures are named after the AddressParseResult
		// fields, but with an underscore and some other bits attached.
		// The underscore'd suffix is required because of a bug (I think) in
		// the regex engine that causes captures to fail capturing anything
		// when there are multiple captures with the same name (ex: on
		// both sides of an alternation).  Adding the suffix allows all capture
		// names to be unique, which makes the regex engine quite happy.
		auto fieldName = name.splitter('_').front;

		assert( AddressParseResult.propertyNames.canFind(fieldName),
			format("Address regex named capture '%s' does not have a "~
				"corresponding field in the AddressParseResult class.", name) );
		
		fieldNameSegmentsOfNamedCapturesAA[fieldName] = true;
	}
	
	// Step 2: ensure that AddressParseResult fields have corresponding
	// named captures in the regular expression (otherwise, there is no
	// way for them to be populated, and that'd probably be a bug).
	foreach(propertyName; AddressParseResult.propertyNames)
	{
		bool* match = propertyName in fieldNameSegmentsOfNamedCapturesAA;
		assert( match !is null,
			format("The property '%s' in the AddressParseResult class "~
				"does not have a corresponding named capture in the address regex.", propertyName) );
	}
	
	// We also want to ensure that all named captures in the regular
	// expression are uniquely named.  If they aren't, then it can
	// become tricky to extract captures precisely (and the regex
	// engine might not even capture them correctly).
	size_t[string] namedCapturesAA;
	size_t count = 0;
	foreach (name; addressRegex.namedCaptures())
	{
		count++;
		size_t* match = name in namedCapturesAA;
		assert ( match is null,
			format("Address regex named capture '%s' is not uniquely named. "~
				"Unique naming of named captures is required for bug-free operation. "~
				"First duplicate found at count %s; second duplicate found at count %s.",
				name, *match, count));
		namedCapturesAA[name] = count;
	}
}

unittest
{
	CanParseTypicalAddressWithoutPunctuationAfterStreetLine();
	CanParseTypicalAddressWithPunctuation();
	CanParseAddressWithRangelessSecondaryUnit();
	CanParsePostOfficeBoxAddress();
	CanParseMilitaryAddress();
	CanParseAddressWithoutPunctuation();
	CanParseGridStyleAddress();
	CanParseAddressWithAlphanumericRange();
	CanParseAddressWithSpacedAlphanumericRange();
	CanParseQueensStyleAddress();
	CanParseAddressWithCardinalStreetName();
	CanParseAddressWithRangedUnitAttachedToNumber();
	CanParseFractionalAddress();
}

public void CanParseTypicalAddressWithoutPunctuationAfterStreetLine()
{
	auto address = ParseAddress("1005 N Gravenstein Highway Sebastopol, CA 95472");

	assert(address.City == "SEBASTOPOL");
	assert(address.Number == "1005");
	assert(address.Postdirectional is null);
	assert(address.Predirectional == "N");
	assert(address.SecondaryNumber is null);
	assert(address.SecondaryUnit is null);
	assert(address.State == "CA");
	assert(address.Street == "GRAVENSTEIN");
	assert(address.StreetLine == "1005 N GRAVENSTEIN HWY");
	assert(address.Suffix == "HWY");
	assert(address.Zip == "95472");
}

public void CanParseTypicalAddressWithPunctuation()
{
	auto address = ParseAddress("1005 N Gravenstein Highway, Sebastopol, CA 95472");

	assert(address.City == "SEBASTOPOL");
	assert(address.Number == "1005");
	assert(address.Postdirectional is null);
	assert(address.Predirectional == "N");
	assert(address.SecondaryNumber is null);
	assert(address.SecondaryUnit is null);
	assert(address.State == "CA");
	assert(address.Street == "GRAVENSTEIN");
	assert(address.StreetLine == "1005 N GRAVENSTEIN HWY");
	assert(address.Suffix == "HWY");
	assert(address.Zip == "95472");
}

public void CanParseAddressWithRangelessSecondaryUnit()
{
	auto address = ParseAddress("1050 Broadway Penthouse, New York, NY 10001");

	assert(address.City == "NEW YORK");
	assert(address.Number == "1050");
	assert(address.Postdirectional is null);
	assert(address.Predirectional is null);
	assert(address.SecondaryNumber is null);
	assert(address.SecondaryUnit == "PH");
	assert(address.State == "NY");
	assert(address.Street == "BROADWAY");
	assert(address.StreetLine == "1050 BROADWAY PH");
	assert(address.Suffix is null);
	assert(address.Zip == "10001");
}

public void CanParsePostOfficeBoxAddress()
{
	auto address = ParseAddress("P.O. BOX 4857, New York, NY 10001");

	assert(address.City == "NEW YORK");
	assert(address.Number is null);
	assert(address.Postdirectional is null);
	assert(address.Predirectional is null);
	assert(address.SecondaryNumber is null);
	assert(address.SecondaryUnit is null);
	assert(address.State == "NY");
	assert(address.Street is null);
	assert(address.StreetLine == "PO BOX 4857");
	assert(address.Suffix is null);
	assert(address.Zip == "10001");
}

/// <summary>
/// Military addresses seem to follow no convention whatsoever in the
/// street line, but the APO/FPO/DPO AA/AE/AP 9NNNN part of the place line
/// is pretty well standardized. I've made a special exception for these
/// kinds of addresses so that the street line is just dumped as-is into
/// the StreetLine field.
/// </summary>
public void CanParseMilitaryAddress()
{
	auto address = ParseAddress("PSC BOX 453, APO AE 99969");

	assert(address.City == "APO");
	assert(address.Number is null);
	assert(address.Postdirectional is null);
	assert(address.Predirectional is null);
	assert(address.SecondaryNumber is null);
	assert(address.SecondaryUnit is null);
	assert(address.State == "AE");
	assert(address.Street is null);
	assert(address.StreetLine == "PSC BOX 453");
	assert(address.Suffix is null);
	assert(address.Zip == "99969");
}

public void CanParseAddressWithoutPunctuation()
{
	auto address = ParseAddress("999 West 89th Street Apt A New York NY 10024");

	assert(address.City == "NEW YORK");
	assert(address.Number == "999");
	assert(address.Postdirectional is null);
	assert(address.Predirectional == "W");
	assert(address.SecondaryNumber == "A");
	assert(address.SecondaryUnit == "APT");
	assert(address.State == "NY");
	assert(address.Street == "89TH");
	assert(address.StreetLine == "999 W 89TH ST APT A");
	assert(address.Suffix == "ST");
	assert(address.Zip == "10024");
}

/// <summary>
/// Grid-style addresses are common in parts of Utah. The official USPS address database
/// in this case treats "E" as a predirectional, "1700" as the street name, and "S" as a
/// postdirectional, and nothing as the suffix, so that's how we parse it, too.
/// </summary>
public void CanParseGridStyleAddress()
{
	auto address = ParseAddress("842 E 1700 S, Salt Lake City, UT 84105");

	assert(address.City == "SALT LAKE CITY");
	assert(address.Number == "842");
	assert(address.Postdirectional == "S");
	assert(address.Predirectional == "E");
	assert(address.SecondaryNumber is null);
	assert(address.SecondaryUnit is null);
	assert(address.State == "UT");
	assert(address.Street == "1700");
	assert(address.StreetLine == "842 E 1700 S");
	assert(address.Suffix is null);
	assert(address.Zip == "84105");
}

/// <summary>
/// People in Wisconsin and Illinois are eating too much cheese, apparently, because
/// you can encounter house numbers with letters in them. It's similar to the
/// Utah grid-system, except the gridness is all crammed into the house number.
/// </summary>
public void CanParseAddressWithAlphanumericRange()
{
	auto address = ParseAddress("N6W23001 BLUEMOUND ROAD, ROLLING MEADOWS, IL, 12345");

	assert(address.City == "ROLLING MEADOWS");
	assert(address.Number == "N6W23001");
	assert(address.Postdirectional is null);
	assert(address.Predirectional is null);
	assert(address.SecondaryNumber is null);
	assert(address.SecondaryUnit is null);
	assert(address.State == "IL");
	assert(address.Street == "BLUEMOUND");
	assert(address.StreetLine == "N6W23001 BLUEMOUND RD");
	assert(address.Suffix == "RD");
	assert(address.Zip == "12345");
}

/// <summary>
/// Speaking of weird addresses, sometimes people put a space in the number.
/// USPS says we should squash it together.
/// </summary>
public void CanParseAddressWithSpacedAlphanumericRange()
{
	auto address = ParseAddress("N645 W23001 BLUEMOUND ROAD, ROLLING MEADOWS, IL, 12345");

	assert(address.City == "ROLLING MEADOWS");
	assert(address.Number == "N645W23001");
	assert(address.Postdirectional is null);
	assert(address.Predirectional is null);
	assert(address.SecondaryNumber is null);
	assert(address.SecondaryUnit is null);
	assert(address.State == "IL");
	assert(address.Street == "BLUEMOUND");
	assert(address.StreetLine == "N645W23001 BLUEMOUND RD");
	assert(address.Suffix == "RD");
	assert(address.Zip == "12345");
}

/// <summary>
/// In parts of New York City, some people feel REALLY STRONGLY about
/// the hyphen in their house number. The numbering system makes sense,
/// but the USPS address database doesn't support hyphens in the number field.
/// To the USPS, the hyphen does not exist, but the DMM specifically does say
/// that "if present, the hyphen should not be removed."
/// </summary>
public void CanParseQueensStyleAddress()
{
	auto address = ParseAddress("123-465 34th St New York NY 12345");

	assert(address.City == "NEW YORK");
	assert(address.Number == "123-465");
	assert(address.Postdirectional is null);
	assert(address.Predirectional is null);
	assert(address.SecondaryNumber is null);
	assert(address.SecondaryUnit is null);
	assert(address.State == "NY");
	assert(address.Street == "34TH");
	assert(address.StreetLine == "123-465 34TH ST");
	assert(address.Suffix == "ST");
	assert(address.Zip == "12345");
}

/// <summary>
/// In Virginia Beach, for example, there's a South Blvd, which could really
/// throw a spanner into our predirectional/postdirectional parsing. We call
/// this case out specifically in our regex.
/// </summary>
public void CanParseAddressWithCardinalStreetName()
{
	auto address = ParseAddress("500 SOUTH STREET VIRGINIA BEACH VIRGINIA 23452");

	assert(address.City == "VIRGINIA BEACH");
	assert(address.Number == "500");
	assert(address.Postdirectional is null);
	assert(address.Predirectional is null);
	assert(address.SecondaryNumber is null);
	assert(address.SecondaryUnit is null);
	assert(address.State == "VA");
	assert(address.Street == "SOUTH");
	assert(address.StreetLine == "500 SOUTH ST");
	assert(address.Suffix == "ST");
	assert(address.Zip == "23452");
}

/// <summary>
/// When people live in apartments with letters, they sometimes attach the apartment
/// letter to the end of the house number. This is wrong, and these people need to be
/// lined up and individually slapped. We pull out the unit and designate it as "APT",
/// which in my experience is the designator that USPS uses in the vast, vast majority
/// of cases.
/// </summary>
public void CanParseAddressWithRangedUnitAttachedToNumber()
{
	auto address = ParseAddress("403D BERRYFIELD LANE CHESAPEAKE VA 23224");

	assert(address.City == "CHESAPEAKE");
	assert(address.Number == "403");
	assert(address.Postdirectional is null);
	assert(address.Predirectional is null);
	assert(address.SecondaryNumber == "D");
	assert(address.SecondaryUnit == "APT");
	assert(address.State == "VA");
	assert(address.Street == "BERRYFIELD");
	assert(address.StreetLine == "403 BERRYFIELD LN APT D");
	assert(address.Suffix == "LN");
	assert(address.Zip == "23224");
}

/// <summary>
/// At least it's not platform 9 3/4.
/// </summary>
public void CanParseFractionalAddress()
{
	auto address = ParseAddress("123 1/2 MAIN ST, RICHMOND, VA 23221");

	assert(address.City == "RICHMOND");
	assert(address.Number == "123 1/2");
	assert(address.Postdirectional is null);
	assert(address.Predirectional is null);
	assert(address.SecondaryNumber is null);
	assert(address.SecondaryUnit is null);
	assert(address.State == "VA");
	assert(address.Street == "MAIN");
	assert(address.StreetLine == "123 1/2 MAIN ST");
	assert(address.Suffix == "ST");
	assert(address.Zip == "23221");
}
