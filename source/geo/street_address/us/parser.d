/// <summary>
///     <para>
///         This is an attempt at a D port of the C# port of the Perl CPAN module
///         Geo::StreetAddress::US.  It's a regex-based street address and
///         street intersection parser for the United States. 
///     </para>
///     <para>
///         The original Perl version was written and is copyrighted by
///         Schuyler D. Erle &lt;schuyler@geocoder.us&gt; and is accessible at
///         <a href="http://search.cpan.org/~timb/Geo-StreetAddress-US-1.03/US.pm">CPAN</a>.
///     </para>
///     <para>
///         It says that "this library is free software; you can redistribute it and/or modify 
///         it under the same terms as Perl itself, either Perl version 5.8.4 or, at 
///         your option, any later version of Perl 5 you may have available."
///     </para>
///     <para>
///         According to the <a href="http://dev.perl.org/licenses/">Perl licensing page</a>,
///         that seems to mean you have a choice between GPL V1 (or at your option, a later version)
///         or the Artistic License.
///     </para>
/// </summary>
module geo.street_address.us.parser;

public import geo.street_address.us.address_parse_result;
import geo.street_address.us.tests;

import std.regex;
import std.traits : isInstanceOf;


/// <summary>
/// Maps directional names (north, northeast, etc.) to abbreviations (N, NE, etc.).
/// </summary>
enum string[2][] directionalsArray = twoColumnCsvFileToArray!"directionals.csv";
immutable string[string] directionalsAA; /// ditto

/// <summary>
/// Maps lowercased US state and territory names to their canonical two-letter
/// postal abbreviations.
/// </summary>
enum string[2][] statesArray = twoColumnCsvFileToArray!"states.csv";
immutable string[string] statesAA; /// ditto

/// <summary>
/// Maps lowerecased USPS standard street suffixes to their canonical postal
/// abbreviations as found in TIGER/Line.
/// </summary>
enum string[2][] suffixesArray = twoColumnCsvFileToArray!"suffixes.csv";
immutable string[string] suffixesAA; /// ditto

/// <summary>
/// Secondary units that require a number after them.
/// </summary>
enum string[2][] rangedSecondaryUnitsArray = twoColumnCsvFileToArray!"ranged_secondary_units.csv";
immutable string[string] rangedSecondaryUnitsAA; /// ditto

/// <summary>
/// Secondary units that do not require a number after them.
/// </summary>
enum string[2][] rangelessSecondaryUnitsArray = twoColumnCsvFileToArray!"rangeless_secondary_units.csv";
immutable string[string] rangelessSecondaryUnitsAA; /// ditto

/// <summary>
/// A combined dictionary of the ranged and rangeless secondary units.
/// </summary>
enum string[2][] allSecondaryUnitsArray = rangedSecondaryUnitsArray ~ rangelessSecondaryUnitsArray;
immutable string[string] allSecondaryUnitsAA; /// ditto

/// <summary>
/// The gigantic regular expression that actually extracts the bits and pieces
/// from a given address.
/// </summary>
package static Regex!char addressRegex;

static this()
{
	import std.range;

	directionalsAA             = twoColumnArrayToAA(directionalsArray);
	statesAA                   = twoColumnArrayToAA(statesArray);
	suffixesAA                 = twoColumnArrayToAA(suffixesArray);
	rangedSecondaryUnitsAA     = twoColumnArrayToAA(rangedSecondaryUnitsArray);
	rangelessSecondaryUnitsAA  = twoColumnArrayToAA(rangelessSecondaryUnitsArray);
	allSecondaryUnitsAA        = twoColumnArrayToAA(allSecondaryUnitsArray);

	// Build the giant regex
	initializeRegex();
}

/// <summary>
/// Attempts to parse the given input as a US address.
/// </summary>
/// <param name="input">The input string.</param>
/// <returns>The parsed address, or null if the address could not be parsed.</returns>
public AddressParseResult parseAddress(string input)
{
	import std.exception : enforce;
	import std.regex;
	import std.string;
	import std.uni;
	
	enforce(input !is null);

	auto address = std.string.strip(input);
	if ( address.length == 0 )
		return null;
	
	address = std.uni.toUpper(address);

	auto captures = std.regex.matchFirst(address, addressRegex);
	if (captures.empty)
		return null;
		
	//printNamedCapturesByIndex(addressRegex, captures);

	auto extracted = getApplicableFields(captures);
	return new AddressParseResult(normalize(extracted));
}

/// <summary>
/// Given a successful match, this method creates a dictionary 
/// consisting of the fields that we actually care to extract from the address.
/// </summary>
/// <param name="match">The successful <see cref="Match"/> instance.</param>
/// <returns>A dictionary in which the keys are the name of the fields and the values
/// are pulled from the input address.</returns>
private static string[string] getApplicableFields(RegexCaptures)(RegexCaptures captures)
	if ( isInstanceOf!(std.regex.Captures, RegexCaptures) )
{
	import std.algorithm.searching : canFind;
	import std.algorithm.iteration : splitter;
	import std.range;
	import std.regex;
	string[string] applicable;

	foreach (captureName; addressRegex.namedCaptures)
	{
		auto fieldName = captureName.splitter('_').front;
		if ( !AddressParseResult.propertyNames.canFind(fieldName) )
			continue;

		auto matchSlice = captures[captureName];
		if ( matchSlice !is null && !matchSlice.empty )
			applicable[fieldName] = matchSlice;
	}

	return applicable;
}

/// <summary>
/// Given a dictionary that maps regular expressions to USPS abbreviations,
/// this function finds the first entry whose regular expression matches the given
/// input value and supplies the corresponding USPS abbreviation as its output. If
/// no match is found, the original value is returned.
/// </summary>
/// <param name="map">The dictionary that maps regular expressions to USPS abbreviations.</param>
/// <param name="input">The value to test against the regular expressions.</param>
/// <returns>The correct USPS abbreviation, or the original value if no regular expression
/// matched successfully.</returns>
private static string getNormalizedValueByRegexLookup
	(string[2][] table) (string  input)
{
	import std.array : array;
	import std.meta : aliasSeqOf, staticMap;
	import std.range : zip;
	import std.regex;

	// Convert the table's left column into an array of regular expression
	// parsers that are compiled at (program) compile-time.
	enum patterns = table.leftColumn.array;
	alias largeTupleOfRegexes = staticMap!(ctRegex, aliasSeqOf!patterns);
	enum arrayOfRegexes = [largeTupleOfRegexes];

	// Iterate over the compiled regexes in lockstep with the
	// table's right column.  The right column is used to provide
	// replacement values if the regex (derived from the left column)
	// matches the input.
	foreach (regex, replacement; zip(arrayOfRegexes, table.rightColumn))
	{
		if ( std.regex.matchFirst(input, regex) )
			return replacement;
	}
	
	return input;
}

/// <summary>
/// Given a dictionary that maps strings to USPS abbreviations,
/// this function finds the first entry whose key matches the given
/// input value and supplies the corresponding USPS abbreviation as its output. If
/// no match is found, the original value is returned.
/// </summary>
/// <param name="map">The dictionary that maps strings to USPS abbreviations.</param>
/// <param name="input">The value to search for in the list of strings.</param>
/// <returns>The correct USPS abbreviation, or the original value if no string
/// matched successfully.</returns>
pure private static string getNormalizedValueByStaticLookup(
	const string[string]  map,
	string                value)
{
	const(string)* output = value in map;
	if ( output !is null )
		return *output; // Found.
	else
		return value; // Not found: return original value.
}

/// <summary>
/// Given a field type and an input value, this method returns the proper USPS
/// abbreviation for it (or the original value if no substitution can be found or is
/// necessary).
/// </summary>
/// <param name="field">The type of the field.</param>
/// <param name="input">The value of the field.</param>
/// <returns>The normalized value.</returns>
private static string getNormalizedValueForField( string field, string input )
{
	import std.algorithm;
	import std.array;

	auto output = input;

	switch (field)
	{
		case "Predirectional":
		case "Postdirectional":
			output = getNormalizedValueByStaticLookup(directionalsAA, input);
			break;
		case "Suffix":
			output = getNormalizedValueByStaticLookup(suffixesAA, input);
			break;
		case "SecondaryUnit":
			output = getNormalizedValueByRegexLookup!allSecondaryUnitsArray(input);
			break;
		case "State":
			output = getNormalizedValueByStaticLookup(statesAA, input);
			break;
		case "Number":
			if (!input.canFind('/'))
			{
				output = input.replace(" ", "");
			}

			break;
		default:
			break;
	}

	return output;
}

/// <summary>
/// Builds the gigantic regular expression stored in the addressRegex static
/// member that actually does the parsing.
/// </summary>
private static void initializeRegex()
{
	import std.algorithm.iteration : map, uniq;
	import std.array : join;
	import std.format;
	import std.range : chain;
	import std.regex;
	// import std.utf : toUTF8; <- deprecation message due to a toUTF8 overload.
	import std.utf;

	enum string suffixPattern =
		chain(suffixesArray.leftColumn, suffixesArray.rightColumn.uniq).join("|");

	enum string statePattern = 
		`\b(?:` ~
		chain(
			statesArray.leftColumn.map!(x => std.regex.escaper(x).toUTF8),
			statesArray.rightColumn
			).join("|") ~
		`)\b`;

	// This one can't be executed at compile-time due to calling the replaceAll
	// method, which seems to call malloc and thus prevent itself from being
	// CTFE-able.
	string directionalPattern =
		chain(
			directionalsArray.leftColumn,
			directionalsArray.rightColumn,
			directionalsArray.rightColumn.map!(x => std.regex.replaceAll(x, ctRegex!`(\w)`, `$1\.`))
			).join("|");

	enum zipPattern = `\d{5}(?:-?\d{4})?`;

	enum numberPattern =
		`(?P<_numberPattern>
			((?P<Number_00>\d+)(?P<SecondaryNumber_00>(-[0-9])|(\-?[A-Z]))(?=\b))   (?# Unit-attached      )
			|(?P<Number_01>\d+[\-\x20]?\d+\/\d+)                                    (?# Fractional         )
			|(?P<Number_02>\d+\-?\d*)                                               (?# Normal Number      )
			|(?P<Number_03>[NSWE]\x20?\d+\x20?[NSWE]\x20?\d+)                       (?# Wisconsin/Illinois )
		)`;

	// This can't be executed at compile-time due to using directionalPattern.
	auto streetPattern =
		format(
			`
				(?P<_streetPattern>
					(?P<_streetPattern_0>
						(?# special case for addresses like 100 South Street)
						(?P<Street_00>%1$s)\W+
						(?P<Suffix_00>%2$s)\b
					)
					|
					(?P<_streetPattern_1>
						(?:(?P<Predirectional_00>%1$s)\W+)?
						(?P<_streetPattern_1_0>
							(?P<_streetPattern_1_0_0>
								(?P<Street_01>[^,]*\d)
								(?:[^\w,]*(?P<Postdirectional_01>%1$s)\b)
							)
							|
							(?P<_streetPattern_1_0_1>
								(?P<Street_02>[^,]+)
								(?:[^\w,]+(?P<Suffix_02>%2$s)\b)
								(?:[^\w,]+(?P<Postdirectional_02>%1$s)\b)?
							)
							|
							(?P<_streetPattern_1_0_2>
								(?P<Street_03>[^,]+?)
								(?:[^\w,]+(?P<Suffix_03>%2$s)\b)?
								(?:[^\w,]+(?P<Postdirectional_03>%1$s)\b)?
							)
						)
					)
				)
			`,
			directionalPattern,
			suffixPattern);

	enum rangedSecondaryUnitPattern =
		`(?P<SecondaryUnit_00>` ~
		rangedSecondaryUnitsArray.leftColumn.join("|") ~
		`)(?![a-z])`;

	enum rangelessSecondaryUnitPattern =
		`(?P<SecondaryUnit_01>` ~
		rangelessSecondaryUnitsArray.leftColumn.join("|") ~
		`)\b`;

	enum allSecondaryUnitPattern = format(
		`
			(?P<_allSecondaryUnitPattern>
				(?:[:]?
					(?: (?:%1$s \W*)
						| (?P<SecondaryUnit_02>\#)\W*
					)
					(?P<SecondaryNumber_02>[\w-]+)
				)
				|%2$s
			),?
		`,
		rangedSecondaryUnitPattern,
		rangelessSecondaryUnitPattern);

	enum cityAndStatePattern = format(
		`
			(?P<_cityAndStatePattern_%%1$s>
				(?P<City_%%1$s>[^\d,]+?)\W+
				(?P<State_%%1$s>%1$s)
			)
		`,
		statePattern);

	enum placePattern = format(
		`
			(?:%1$s\W*)?
			(?:(?P<Zip_%%1$s>%2$s))?
		`,
		format(cityAndStatePattern,"%1$s"),
		zipPattern);

	// This can't be executed at compile-time due to using streetPattern.
	auto addressPattern = format(
		`
			^
			(?P<_addressPattern>
				(?P<_addressPattern_0>
					(?# Special case for APO/FPO/DPO addresses)
					[^\w\#]*
					(?P<StreetLine_00>.+?)
					(?P<City_00>[AFD]PO)\W+
					(?P<State_00>A[AEP])\W+
					(?P<Zip_00>%6$s)
					\W*
				)
				|
				(?P<_addressPattern_1>
					(?# Special case for PO boxes)
					\W*
					(?P<StreetLine_01>(P[\.\x20]?O[\.\x20]?\x20)?BOX\x20[0-9]+)\W+
					%5$s
					\W*
				)
				|
				(?P<_addressPattern_2>
					[^\w\#]*    (?# skip non-word chars except # {eg unit})
					(?:%1$s)\W*
					   %2$s\W+
					(?:%3$s\W+)?
					   %4$s
					\W*         (?# require on non-word chars at end)
				)
			)
			$           (?# right up to end of string)
		`,
		numberPattern,
		streetPattern,
		allSecondaryUnitPattern,
		format(placePattern,"02"),
		format(placePattern,"01"),
		zipPattern);

	addressRegex = regex( addressPattern, "sx" );
}

/// <summary>
/// Given a set of fields pulled from a successful match, this normalizes each value
/// by stripping off some punctuation and, if applicable, converting it to a standard
/// USPS abbreviation.
/// </summary>
/// <param name="extracted">The dictionary of extracted fields.</param>
/// <returns>A dictionary of the extracted fields with normalized values.</returns>
private static string[string] normalize(const string[string] extracted)
{
	import std.range;
	import std.regex;
	import std.string;

	string[string] normalized;

	foreach (pair; extracted.byKeyValue())
	{
		string key = pair.key;
		string value = pair.value;

		// Strip off some punctuation
		value = std.regex.replaceAll(
			value,
			ctRegex!`^\s+|\s+$|[^\/\w\s\-\#\&]`,
			"");

		// Normalize to official abbreviations where appropriate
		value = getNormalizedValueForField(key, value);

		normalized[key] = value;
	}

	// Special case for an attached unit
	if ("SecondaryNumber" in extracted
	&&   ("SecondaryUnit" !in extracted
	||   std.string.strip(extracted["SecondaryUnit"]).empty ))
	{
		normalized["SecondaryUnit"] = "APT";
	}

	return normalized;
}

// Other implementation details:
pure private string[2][] parseTwoColumnCsv(string inputCsv)
{
	import std.custom_csv;
	import std.typecons;
	
	string[2][] result;
	
	foreach ( record; csvReader!(Tuple!(string,string))(inputCsv) )
		result ~= [record[0],record[1]];
	
	return result;
}

pure private string[2][] twoColumnCsvFileToArray(string csvFile)()
{
	return import(csvFile).parseTwoColumnCsv();
}

pure private string[string] twoColumnArrayToAA(const string[2][] arr)
{
	string[string] result;
	foreach ( pair; arr )
		result[pair[0]] = pair[1];
	return result;
}

/+
pure private string[string] importTwoColumnCsv(string csvFile)()
{
	// Force the parse to happen at compile time.
	immutable string[2][] tempArray = import(csvFile).parseTwoColumnCsv();
	
	// Convert the parsed array into a runtime Associative Array and return it.
	return tempArray.twoColumnArrayToAA();
}
+/

pure private auto leftColumn(string[][] table)
{
	import std.algorithm.iteration : map;
	return table.map!(row => row[0]);
}

pure private auto rightColumn(string[][] table)
{
	import std.algorithm.iteration : map;
	return table.map!(row => row[$-1]);
}


import std.regex;
string[] getNamedCapturesByIndex(R, C)(R regex, C captures)
	if ( /+isInstanceOf!(Regex, R)
	&&   +/isInstanceOf!(std.regex.Captures, C) )
{
	import std.algorithm : filter, map, sort, startsWith;
	import std.array : array;
	import std.range : empty, lockstep, StoppingPolicy;

	class IndexSet
	{
		size_t[] indices;
		string   captureContent;
		
		this(size_t initialIndex, string captureContent)
		{
			this.indices = [initialIndex];
			this.captureContent = captureContent;
		}
	}

	IndexSet[string] captureIndicesByContentId;
	
	size_t i = 0;
	for ( i = 0; i < captures.length; i++ )
	{
		string captureContent = captures[i];
		if ( captureContent is null || captureContent.empty )
			continue;

		string contentId = (cast(char*)(&captureContent))[0..captureContent.sizeof].idup;
		IndexSet* indicesRef = contentId in captureIndicesByContentId;
		if ( indicesRef is null )
			captureIndicesByContentId[contentId] = new IndexSet(i,captureContent);
		else
			(*indicesRef).indices ~= i;
	}

	string[] results = new string[i];
	foreach( ref result; results )
		result = "";

	foreach( IndexSet set; captureIndicesByContentId.byValue() )
	{
		struct CaptureMeta
		{
			string name;
			string content;
		}
		
		// Associate capture names to the captured content.
		
		scope bool contentMatches(CaptureMeta capture)
		{
			bool result = (capture.content is set.captureContent)
				&& (capture.content.length == set.captureContent.length);
			//writef(" [Considering %s: %s] ", capture.name, result?"***!TRUE!***":"false");
			return result;
		}
		
		/*
		// Doesn't work:
		auto matchingNamedCaptures =
			regex.namedCaptures()
				.map!(name => CaptureMeta(name, captures[name]))
				.filter!(contentMatches).array;
		// source\geo\street_address\us\parser.d(...): Error: variable
		//   geo.street_address.us.parser.getNamedCapturesByIndex!(Regex!char,
		//   Captures!(string, uint)).getNamedCapturesByIndex.captures
		//   has scoped destruction, cannot build closure
		*/
		
		// Works:
		auto matchingNamedCaptures = new CaptureMeta[regex.namedCaptures().length];
		size_t j = 0;
		foreach( name; regex.namedCaptures() )
		{
			auto meta = CaptureMeta(name, captures[name]);
			if ( !contentMatches(meta) )
				continue;
			matchingNamedCaptures[j] = meta;
			j++;
		}
		matchingNamedCaptures = matchingNamedCaptures[0..j];

		// We will sort the capture {name,content} tuples according to how
		// specific their names are.  The definition of "specific" for strings
		// is arbitrary, so this function defines a convention for using
		// your capture names to tell this algorithm which groups nest into
		// which groups (based on naming alone).
		//
		// It goes like this:
		//
		// # If one string has the other string as its prefix,
		// #   then it is more specific.
		// "_abc123" is more specific than "_abc12" is more specific than "_abc".
		// "abc123" is more specific than "abc12" is more specific than "abc".
		// "_abc" is more specific than ""
		// "_abc" is just as specific as "_abc" (of course)
		//
		// # The underscore is used to segregate debugging captures from
		// #   the regular expression's intended targets.
		// "abc123" is more specific than "_abc123"
		// "abc" is more specific than "_abc"
		// "abc" is more specific than "_abc123"
		// "xyz" is more specific than "_abc"
		// "abc" is more specific than "_xyz"
		//
		// # If the strings don't contain one-another, then the longer is
		// #   more specific.
		// "xyz123" is more specific than "abc"
		// "abc123" is more specific than "xyz"
		// "ab1" is more specific than "ac"
		//
		// # If the strings don't contain one-another and have the same
		// #   length, then they are equally specific.
		// "xyz" is just as specific as "abc"
		// "ab" is just as specific as "ac"
		//
		// So write your regular expression like this to make it work:
		// `(?P<_debug0>
		//      (?:
		//          stuff
		//          (?P<_debug00>morestuff(?P<TargetA>a)lessstuff)
		//          closingstuff
		//      )
		//      |
		//      (?:
		//          asdfqwer
		//          (?P<_debug01>yada(?P<TargetB>b)yada)
		//          qwerasdf
		//      )
		//  )
		//  |
		//  (?P<_debug1>
		//      (?:
		//          stuff1
		//          (?P<_debug10>maybe?(?P<TargetC>c)yes[!])
		//          strap
		//      )
		//      |
		//      (?:
		//          strap a
		//          (?P<_debug11>rocket(?P<TargetD>d)to a)
		//          chicken
		//      )
		//  )
		bool moreSpecific(CaptureMeta a, CaptureMeta b)
		{
			// Having a capture name is more specific than not having a capture name.
			if ( a.name is null || a.name.empty ) return false;
			else
			if ( b.name is null || b.name.empty ) return true;
			else
			// Debugging symbols start with _.  Non-debugging symbols are (usually) more specific.
			if ( a.name.startsWith("_") && !b.name.startsWith("_") )
				return false;
			else
			if ( !a.name.startsWith("_") && b.name.startsWith("_") )
				return true;
			else
			{
				// Look for one symbol to contain the other:
				// this allows capture names to nest without having distinct capture content.
				if ( a.name == b.name )
					return true;
				else if ( a.name.startsWith(b.name) )
					return true;
				else if ( b.name.startsWith(a.name) )
					return false;
				// Return the longest.
				else if ( a.name.length > b.name.length )
					return true;
				else if ( b.name.length < a.name.length )
					return false;
				// Equal length, very different strings.  It's arbitrary.
				else
					return true;
			}
		}
		
		/+
		import std.stdio;
		writefln("matchingNamedCaptures == %s", matchingNamedCaptures);
		writefln("set.indices == %s", set.indices);
		+/

		// Sort both arrays in descending order rather than ascending.
		// This is done because we don't know if the lengths match
		// (they /probably/ do...), and we want the most specific
		// named capture to associate with the highest index (because
		// capture groups nest left-to-right).  The less specific matches
		// are probably not as important, so we will leave them out if
		// the array lengths don't match, and that is done by using a
		// "shortest" stopping policy in the later step.  (There might
		// be a smarter way to handle the corner case pf different-sized
		// arrays, but it's not worth it for this author at the time
		// of this writing).
		matchingNamedCaptures.sort!moreSpecific;
		set.indices.sort!"a > b";
		
		foreach(index, capture; lockstep(set.indices, matchingNamedCaptures, StoppingPolicy.shortest))
			results[index] = capture.name;
	}
	
	return results;
}

void printNamedCapturesByIndex(R, C)(R regex, C captures)
	if ( /+isInstanceOf!(Regex, R)
	&&   +/isInstanceOf!(Captures, C) )
{
	import std.range : empty;
	import std.stdio;

	string[] namedCapturesByIndex = getNamedCapturesByIndex(regex,captures);
	
	size_t index = 0;
	foreach( namedCapture; namedCapturesByIndex )
	{
		writef("captures[%s] == %s", index, captures[index]);
		scope(success)
		{
			index++;
			writeln();
		}

		if ( namedCapture is null || namedCapture.empty )
			continue;

		writef("  (Correlates: %s)", namedCapture);
	}
	writeln("================================================================");
	writeln("");
}