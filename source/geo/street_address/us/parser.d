/// This is an attempt at a D port of the C# port of the Perl CPAN module
/// Geo::StreetAddress::US.  It's a regex-based street address and
/// street intersection parser for the United States. 
///
/// The original Perl version was written and is copyrighted by
/// Schuyler D. Erle &lt;schuyler@geocoder.us&gt; and is accessible at
/// <a href="http://search.cpan.org/~timb/Geo-StreetAddress-US-1.03/US.pm">CPAN</a>.
///
/// It says that "this library is free software; you can redistribute it and/or modify 
/// it under the same terms as Perl itself, either Perl version 5.8.4 or, at 
/// your option, any later version of Perl 5 you may have available."
///
/// According to the <a href="http://dev.perl.org/licenses/">Perl licensing page</a>,
/// that seems to mean you have a choice between GPL V1 (or at your option, a later version)
/// or the Artistic License.

module geo.street_address.us.parser;

public import geo.street_address.us.address_parse_result;
import geo.street_address.us.tests;

import std.regex;
import std.traits : isInstanceOf;

private
{
	/// Maps directional names (north, northeast, etc.) to abbreviations (N, NE, etc.).
	enum string[][2] directionalsArray = twoColumnCsvFileToArray!"directionals.csv";
	immutable string[string] directionalsAA; /// ditto

	/// Maps lowercased US state and territory names to their canonical two-letter
	/// postal abbreviations.
	enum string[][2] statesArray = twoColumnCsvFileToArray!"states.csv";
	immutable string[string] statesAA; /// ditto

	/// Maps lowerecased USPS standard street suffixes to their canonical postal
	/// abbreviations as found in TIGER/Line.
	enum string[][2] suffixesArray = twoColumnCsvFileToArray!"suffixes.csv";
	immutable string[string] suffixesAA; /// ditto

	/// Secondary units that require a number after them.
	enum string[][2] rangedSecondaryUnitsArray = twoColumnCsvFileToArray!"ranged_secondary_units.csv";
	immutable string[string] rangedSecondaryUnitsAA; /// ditto

	/// Secondary units that do not require a number after them.
	enum string[][2] rangelessSecondaryUnitsArray = twoColumnCsvFileToArray!"rangeless_secondary_units.csv";
	immutable string[string] rangelessSecondaryUnitsAA; /// ditto

	/// A combined dictionary of the ranged and rangeless secondary units.
	enum string[][2] allSecondaryUnitsArray = concatTwoColumnArray(rangedSecondaryUnitsArray, rangelessSecondaryUnitsArray);
	immutable string[string] allSecondaryUnitsAA; /// ditto
}

/// The gigantic regular expression that actually extracts the bits and pieces
/// from a given address.
package Regex!char threadLocalAddressRegex;

static this()
{
	import std.range;
	import std.stdio;

	directionalsAA             = twoColumnArrayToAA(directionalsArray);
	statesAA                   = twoColumnArrayToAA(statesArray);
	suffixesAA                 = twoColumnArrayToAA(suffixesArray);
	rangedSecondaryUnitsAA     = twoColumnArrayToAA(rangedSecondaryUnitsArray);
	rangelessSecondaryUnitsAA  = twoColumnArrayToAA(rangelessSecondaryUnitsArray);
	allSecondaryUnitsAA        = twoColumnArrayToAA(allSecondaryUnitsArray);

	// Build the giant regex
	threadLocalAddressRegex = buildAddressRegex();
}

/// Attempts to parse the given input as a US address.
///
/// Params:
///      input = The input string.
///
/// Returns: The parsed address, or null if the address could not be parsed.
public AddressParseResult* parseAddress(string input)
{
	AddressParseResult* output = new AddressParseResult;
	return parseAddress(input, output);
}

/// Attempts to parse the given input as a US address.
///
/// Params:
///      input = The input string.
///      output = A pre-allocated but uninitialized parse result object.
///
/// Returns: The parsed address, or null if the address could not be parsed.
public AddressParseResult* parseAddress(string input, AddressParseResult* output)
{
	char[] dummy = null;
	return parseAddress(input, output, dummy);
}

/// Attempts to parse the given input as a US address.
///
/// Params:
///      input = The input string.
///      output = A pre-allocated but uninitialized parse result object.
///      textBuf = Buffer used to store any normalizations to the address.
///                This allows the caller to preallocate memory and possibly
///                avoid unnecessary memory allocations.  This should be
///                large enough to store the address twice.  The resulting
///                contents are not necessarily a valid address: as a result
///                of avoiding out-of-scope computations, this may end up
///                being a concatenation of normalized address elements in an
///                arbitrary order.  After this call, textBuf will be a slice
///                of the remaining buffer space.
///
/// Returns: The parsed address, or null if the address could not be parsed.
///
public /+@nogc+/ AddressParseResult* parseAddress(string input, AddressParseResult* output, ref char[] textBuf)
{
	import std.exception : enforce;
	import std.format;
	import std.regex;
	import std.string;
	import std.uni;

	// Even if you prefer assertions of enforcement for this, the time
	// required to parse the address is going to be many orders of magnitude
	// greater than the cost of the enforce statements.
	// And it helps A LOT with troubleshooting when nulls propagate in the wild.
	enforce(input  !is null);
	enforce(output !is null);
	//enforce(textBuf is null || textBuf.ptr !is input.ptr,
	//	"Input address string starts at same address as output buffer.")
	enforce(textBuf is null
		|| textBuf.ptr >= input.ptr   + input.length
		|| input.ptr   >= textBuf.ptr + textBuf.length,
		format("Input address string and output buffer overlap.\n"~
			"Input string:  %X .. %X, '%s'\n"~
			"Output buffer: %X .. %X\n",
			input.ptr,   input.ptr   + input.length, input,
			textBuf.ptr, textBuf.ptr + textBuf.length));

	//
	auto address = std.string.strip(input);
	auto len = address.length;
	if ( len == 0 )
		return null;

	// If the caller didn't provide a preallocated text buffer, or it isn't
	// big enough, then we need to allocate one ourselves.
	if ( textBuf is null || textBuf.length < len )
		textBuf = new char[len*2];

	// We're about to potentially mutate the string.
	// Attempt to avoid allocations by using the preallocated buffer.
	textBuf[0..len] = address;
	auto addressEmplaced = textBuf[0..len];
	textBuf = textBuf[len..$];

	// Uppercase so that any normalization steps that follow will be simpler.
	// This is also, itself, a normalization step.
	std.uni.toUpperInPlace(addressEmplaced);

	// Use the giant address regex.
	// This is the most useful part, and probably the slowest part too.
	auto captures = std.regex.matchFirst(addressEmplaced, threadLocalAddressRegex);
	if (captures.empty)
		return null;

	//printNamedCapturesByIndex(threadLocalAddressRegex, captures);

	// Stack allocate an AddressElement array.
	// This won't be passed back to the caller.  Instead, it is needed
	// internally for mapping regex matches to fields in the result.
	SoftAddressElement[AddressParseResult.propertyNames.length] addressElemsBuf;

	// Populate the address elements buffer.
	auto addressElems = getApplicableFields(input, addressEmplaced, captures, addressElemsBuf[]);

	// Normalize and finish.
	output.initialize(normalize(addressElems, addressElemsBuf[], textBuf));
	return output;
}

/// Given a successful match, this method creates a dictionary 
/// consisting of the fields that we actually care to extract from the address.
///
/// Returns: A list of SoftAddressElement's, each of which contains a mapping
///   between a field name and a field value.
private /+@nogc+/ SoftAddressElement[] getApplicableFields(RegexCaptures) (
	string                addressOriginal,
	const(char)[]         addressEmplaced,
	RegexCaptures         captures,
	SoftAddressElement[]  addressElems
	)
		if ( isInstanceOf!(std.regex.Captures, RegexCaptures) )
{
	import std.algorithm.iteration : splitter;
	import std.range;
	import std.regex;
	import std.uni : icmp;

	assert(0 == icmp(addressOriginal, addressEmplaced));

	size_t i = 0;
	foreach (captureName; threadLocalAddressRegex.namedCaptures)
	{
		auto fieldName = captureName.splitter('_').front;
		if ( fieldName !in AddressParseResult.propertyIndexesByGetterName )
			continue;

		auto matchSlice = captures[captureName];
		if ( matchSlice !is null && !matchSlice.empty )
		{
			auto addressEndPtr = addressEmplaced.ptr + addressEmplaced.length;
			auto matchSliceEndPtr = matchSlice.ptr + matchSlice.length;

			assert(addressEmplaced.ptr <= matchSlice.ptr);
			assert(matchSlice.ptr <= addressEndPtr);

			assert(addressEmplaced.ptr <= matchSliceEndPtr);
			assert(matchSliceEndPtr <= addressEndPtr);

			auto lo = matchSlice.ptr - addressEmplaced.ptr;
			auto hi = matchSliceEndPtr - addressEmplaced.ptr;

			// These are calculated from slices into addressEmplaced and not
			// addressOriginal.  HOWEVER, as long as the transformation from
			// the one to the other does not actually move any of the
			// characters in the text, then these indices will do the same
			// thing on both strings.  As of this writing, the only
			// difference between addressOriginal and addressEmplaced is that
			// addressEmplaced is all uppercase, while addressOriginal is mixed
			// case.  They should otherwise be the same string.
			assert(addressEmplaced.length == addressOriginal.length);
			assert(hi <= addressOriginal.length);

			addressElems[i].propertyName  = fieldName;
			addressElems[i].propertyValue = matchSlice;
			addressElems[i].loIndex = lo;
			addressElems[i].hiIndex = hi;
			i++;
		}
	}

	return addressElems[0..i];
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
private string getNormalizedValueByRegexLookup(string[][2] table)(string  input)
{
	import std.array : array;
	import std.meta : aliasSeqOf, staticMap;
	import std.regex;

	// Convert the table's left column into an array of regular expression
	// parsers that are compiled at (program) compile-time.
	enum patterns = table.leftColumn;
	static string[] replacements = table.rightColumn;
	//alias largeTupleOfRegexes = staticMap!(ctRegex, aliasSeqOf!patterns);
	//static Regex!(char)[] arrayOfRegexes = [largeTupleOfRegexes];
	
	static auto makeRegexArray()
	{
		import std.range.primitives;
		auto result = new Regex!(char)[patterns.length];
		for(size_t i = 0; i < patterns.length; i++)
			result[i] = regex(patterns[i],"s");
		return result;
	}

	static Regex!(char)[] arrayOfRegexes = makeRegexArray;

	// Iterate over the compiled regexes in lockstep with the
	// table's right column.  The right column is used to provide
	// replacement values if the regex (derived from the left column)
	// matches the input.
	assert(patterns.length == replacements.length);
	assert(arrayOfRegexes.length == replacements.length);
	for ( size_t i = 0; i < arrayOfRegexes.length; i++ )
	{
		auto regex = arrayOfRegexes[i];
		auto replacement = replacements[i];
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
private /+@nogc+/ string getNormalizedValueByStaticLookup(
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
private /+@nogc+/ string getNormalizedValueForField( string field, string input, ref char[] textBuf )
{
	import std.algorithm;
	import std.array : replaceInto;
	import std.exception : assumeUnique;
	import std.range.primitives;

	auto output = input;

	switch (field)
	{
		case "predirectional":
		case "postdirectional":
			output = getNormalizedValueByStaticLookup(directionalsAA, input);
			break;
		case "suffix":
			output = getNormalizedValueByStaticLookup(suffixesAA, input);
			break;
		case "secondaryUnit":
			output = getNormalizedValueByRegexLookup!allSecondaryUnitsArray(input);
			break;
		case "state":
			output = getNormalizedValueByStaticLookup(statesAA, input);
			break;
		case "number":
			if (!input.canFind('/'))
			{
				char[] buffer = textBuf;
				auto appender = NogcAppender(buffer);
				char[] before = appender.data;
				appender.replaceInto(input," ", "");
				char[] after = appender.data;

				// We assume that replaceInto modifies textBuf and
				// not a copy of textBuf.
				assert(before.ptr !is after.ptr);
				assert(textBuf.ptr < buffer.ptr);

				// Retrieve the result and advance the textBuf.
				output = textBuf[0 .. (after.ptr - before.ptr)].assumeUnique;
				textBuf = buffer;
			}

			break;
		default:
			break;
	}

	return output;
}

/// Builds a gigantic regular expression that can be used to parse addresses.
/// The result is intended to be fed into parseAddress(...).
public auto buildAddressRegex()
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
			((?P<number_00>\d+)(?P<secondaryNumber_00>(-[0-9])|(\-?[A-Z]))(?=\b))   (?# Unit-attached      )
			|(?P<number_01>\d+[\-\x20]?\d+\/\d+)                                    (?# Fractional         )
			|(?P<number_02>\d+\-?\d*)                                               (?# Normal Number      )
			|(?P<number_03>[NSWE]\x20?\d+\x20?[NSWE]\x20?\d+)                       (?# Wisconsin/Illinois )
		)`;

	// This can't be executed at compile-time due to using directionalPattern.
	auto streetPattern =
		format(
			`
				(?P<_streetPattern>
					(?P<_streetPattern_0>
						(?# special case for addresses like 100 South Street)
						(?P<street_00>%1$s)\W+
						(?P<suffix_00>%2$s)\b
					)
					|
					(?P<_streetPattern_1>
						(?:(?P<predirectional_00>%1$s)\W+)?
						(?P<_streetPattern_1_0>
							(?P<_streetPattern_1_0_0>
								(?P<street_01>[^,]*\d)
								(?:[^\w,]*(?P<postdirectional_01>%1$s)\b)
							)
							|
							(?P<_streetPattern_1_0_1>
								(?P<street_02>[^,]+)
								(?:[^\w,]+(?P<suffix_02>%2$s)\b)
								(?:[^\w,]+(?P<postdirectional_02>%1$s)\b)?
							)
							|
							(?P<_streetPattern_1_0_2>
								(?P<street_03>[^,]+?)
								(?:[^\w,]+(?P<suffix_03>%2$s)\b)?
								(?:[^\w,]+(?P<postdirectional_03>%1$s)\b)?
							)
						)
					)
				)
			`,
			directionalPattern,
			suffixPattern);

	enum rangedSecondaryUnitPattern =
		`(?P<secondaryUnit_00>` ~
		rangedSecondaryUnitsArray.leftColumn.join("|") ~
		`)(?![a-z])`;

	enum rangelessSecondaryUnitPattern =
		`(?P<secondaryUnit_01>` ~
		rangelessSecondaryUnitsArray.leftColumn.join("|") ~
		`)\b`;

	enum allSecondaryUnitPattern = format(
		`
			(?P<_allSecondaryUnitPattern>
				(?:[:]?
					(?: (?:%1$s \W*)
						| (?P<secondaryUnit_02>\#)\W*
					)
					(?P<secondaryNumber_02>[\w-]+)
				)
				|%2$s
			),?
		`,
		rangedSecondaryUnitPattern,
		rangelessSecondaryUnitPattern);

	enum cityAndStatePattern = format(
		`
			(?P<_cityAndStatePattern_%%1$s>
				(?P<city_%%1$s>[^\d,]+?)\W+
				(?P<state_%%1$s>%1$s)
			)
		`,
		statePattern);

	enum placePattern = format(
		`
			(?:%1$s\W*)?
			(?:(?P<zip_%%1$s>%2$s))?
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
					(?P<streetLine_00>.+?)
					(?P<city_00>[AFD]PO)\W+
					(?P<state_00>A[AEP])\W+
					(?P<zip_00>%6$s)
					\W*
				)
				|
				(?P<_addressPattern_1>
					(?# Special case for PO boxes)
					\W*
					(?P<streetLine_01>(P[\.\x20]?O[\.\x20]?\x20)?BOX\x20[0-9]+)\W+
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

	return regex( addressPattern, "sx" );
}

/// Removes punctuation from 'src', outputting the result to 'dst' as it
/// processes.
///
/// This function is designed to give correct results when 'src' and 'dst'
/// point to the same slice.  In other words: it is an in-place algorithm
/// with the optional capability of doing a copy operation in the same step.
///
/// The returned value's .ptr field will always equal 'dst''s .ptr field.
/// (This can simplify some buffer management calculations for the caller.)
///
/// Returns: a slice of 'dst' populated with the result of processing 'src'.
public /+@nogc+/ char[] normalizeRemovePunctuation(char[] src, char[] dst,
	string exceptionsToRemove, string exceptionsToKeep)
{
	import std.algorithm.mutation : copy;
	import std.algorithm.searching : canFind;
	import std.string;
	import std.uni : isAlphaNum, isWhite;
	import std.utf : decode;

	src = strip(src);

	// Loop to remove punctuation.
	// This implementation is a bit tedious, but it allows the operation
	// to occur without any allocations and a minimum of copying.
	//
	// If char[] were an output range for dchar, then we would be able to
	// use a regular expression here.  The original code had a regex like
	// this one: `^\s+|\s+$|[^\/\w\s\-\#\&]`
	// Even so, this code will probably execute faster than the regex,
	// at least as of dmd v2.074.1 (even with ctRegex).
	//
	size_t count = 0;
	size_t srcIndex = 0;
	size_t dstIndex = 0;
	while( srcIndex < src.length )
	{
		size_t prev = srcIndex;
		auto ch = decode(src, srcIndex);
		if ( !isAlphaNum(ch)
		&&   !isWhite(ch)
		&&   exceptionsToRemove.canFind(ch)
		&&   !exceptionsToKeep.canFind(ch))
			continue;

		// Keep this character.
		size_t sz = srcIndex - prev;
		copy(
			src[prev .. srcIndex],
			dst[dstIndex .. dstIndex + sz]);
		dstIndex += sz;
	}

	// Clear out any characters left after the removal.
	dst[dstIndex .. $] = ' ';

	// Shrink dst so it doesn't include the extra spaces.
	dst = dst[0..dstIndex];

	//
	return dst;
}

/// Given a set of fields pulled from a successful match, this normalizes each value
/// by stripping off some punctuation and, if applicable, converting it to a standard
/// USPS abbreviation.
///
/// Params:
///      elements     = The fields extracted from the address.
///      elementsBuf  = The buffer that 'elements' resides within.
///      textBuf      = Preallocated space for any new elements or enlargements.
///
/// Returns: A list of fields with normalized values represented by immutable
///          strings.
private /+@nogc+/ FirmAddressElement[] normalize(
	SoftAddressElement[]  elements,
	SoftAddressElement[]  elementsBuf,
	ref char[]            textBuf )
{
	import std.algorithm.sorting : sort;
	import std.algorithm.mutation : SwapStrategy;
	import std.range.primitives;
	import std.string;
	//import std.regex;

	assert(elements.ptr == elementsBuf.ptr);

	// Sort the elements according to where the match occurred in the address.
	// This is the first step in detecting any overlapping matches
	// (ex: 'streetLine' containing 'predirectional' or 'street').
	elements.sort!("a.propertyValue.ptr < b.propertyValue.ptr", SwapStrategy.stable);

	// Perform operations that require modifying the strings in the individual
	// address elements.  This requires that the element list still be "soft".
	auto elementsIter = elements;
	SoftAddressElement* elem = null;
	SoftAddressElement* next = null;

	// Provide a way to iterate over the elementsIter range with a window
	// that is two elements wide.  This is necessary for overlap detection.
	void advance()
	{
		elem = next;
		if ( elementsIter.empty )
			next = null;
		else
		{
			next = &elementsIter.front;
			elementsIter.popFront();
		}
	}

	// Remove punctuation from all elements.  If the match slices overlap,
	// then one of the slices will not be computed in-place, but will instead
	// have its result placed in the textBuf.
	advance();
	while(true)
	{
		advance();
		if ( elem is null )
			break;

		// Start off assuming an in-place removal will be performed.
		char[] src = elem.propertyValue;
		char[] dst = elem.propertyValue;

		// Check for overlap.
		if ( next !is null && next.propertyValue.ptr < src.ptr + src.length )
		{
			// Ensure there is enough space present in 'textBuf'.
			// If not, do a reallocation.
			if ( textBuf.length < src.length )
				textBuf.length = src.length;

			// Adjust 'dst' as necessary.
			dst = textBuf;
		}

		// Remove punctuation.
		// If (dst != src), then this operation will not modify the 'src'
		// slice.  This allows us to avoid corrupting other matches if there
		// is an overlap.
		dst = normalizeRemovePunctuation(src,dst,"","/-#&");

		// Update textBuf if we used it.
		if ( dst.ptr == textBuf.ptr )
			textBuf = textBuf[dst.length .. $];

		// Commit the results.
		elem.propertyValue = dst;
	}

	// Mark the element list as containing "firm" elements.  This means that
	// the strings held by the elements will not be modified any more
	// (but they can be replaced).
	auto firmedElems    = cast(FirmAddressElement[])elements;
	auto firmedElemsBuf = cast(FirmAddressElement[])elementsBuf;

	// Now perform normalization that requires immutable strings
	// (firmed elements).
	size_t     i = 0;
	ptrdiff_t  secondaryNumberIndex = -1;
	ptrdiff_t  secondaryUnitIndex   = -1;

	foreach(ref element; firmedElems)
	with(element)
	{
		// Normalize to official abbreviations where appropriate
		propertyValue = getNormalizedValueForField(propertyName, propertyValue, textBuf);

		// Special case for an attached unit
		switch(propertyName)
		{
			case "secondaryNumber" : secondaryNumberIndex = i; break;
			case "secondaryUnit"   : secondaryUnitIndex   = i; break;
			default: break;
		}

		i++;
	}

	// Special case for an attached unit
	if (secondaryNumberIndex >= 0
	&&   (secondaryUnitIndex < 0
	||   std.string.strip(firmedElems[secondaryUnitIndex].propertyValue).empty ))
	{
		if ( secondaryUnitIndex < 0 )
		{
			// Grow the firmedElems array by one element.
			// The function the original buffer so that we can do this without
			// causing an allocation.
			firmedElems = firmedElemsBuf[0 .. firmedElems.length+1];

			// Allocate the new element as the secondaryUnit field.
			secondaryUnitIndex = firmedElems.length - 1;
			firmedElems[secondaryUnitIndex].propertyName  = "secondaryUnit";
		}

		firmedElems[secondaryUnitIndex].propertyValue = "APT";
	}

	return firmedElems;
}

// Other implementation details:
pure private string[][2] parseTwoColumnCsv(string inputCsv)
{
	import std.custom_csv;
	import std.typecons;
	
	string[][2] result;
	
	foreach ( record; csvReader!(Tuple!(string,string))(inputCsv) )
	{
		result[0] ~= record[0];
		result[1] ~= record[1];
	}

	return result;
}

pure private string[][2] twoColumnCsvFileToArray(string csvFile)()
{
	return import(csvFile).parseTwoColumnCsv();
}

pure private string[string] twoColumnArrayToAA(const string[][2] arr)
{
	import std.range : zip;
	string[string] result;
	foreach ( left, right; zip(arr[0], arr[1]) )
		result[left] = right;
	return result;
}

pure private const(string)[][2] concatTwoColumnArray(const(string)[][2] a, const(string)[][2] b)
{
	const(string)[][2] result;
	result[0] = a[0] ~ b[0];
	result[1] = a[1] ~ b[1];
	return result;
}

/+
pure private string[string] importTwoColumnCsv(string csvFile)()
{
	// Force the parse to happen at compile time.
	immutable string[][2] tempArray = import(csvFile).parseTwoColumnCsv();
	
	// Convert the parsed array into a runtime Associative Array and return it.
	return tempArray.twoColumnArrayToAA();
}
+/

pure private auto leftColumn(string[][] table)
{
	import std.algorithm.iteration : map;
	return table[0];
}

pure private auto rightColumn(string[][] table)
{
	import std.algorithm.iteration : map;
	return table[$-1];
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


private struct NogcAppender
{
	@nogc:
	char[]* bufferRef;

	@property ref char[] data() { return *bufferRef; }
	alias data this;

	this(ref char[] buffer)
	{
		bufferRef = &buffer;
	}

	void put(const(char)[] val)
	{
		char[] buffer = *bufferRef;
		buffer[0..val.length] = val[];
		*bufferRef = buffer[val.length .. $];
	}

	void put(char val)
	{
		char[] buffer = *bufferRef;
		buffer[0] = val;
		*bufferRef = buffer[1 .. $];
	}
}

/+
// Nope.  Nice try though.
// (Does not compile on DMD v2.074.1)
@nogc string nogc_format(string fmtstr, T...)(T args)
{
	import std.format;
	import std.exception : assumeUnique;

	static char[1024] _buffer;
	char[] buffer = _buffer;

	struct NogcAppender
	{
		@nogc:
		char[]* bufferRef;

		@property ref char[] data() { return *bufferRef; }
		alias data this;

		void put(const(char)[] val)
		{
			char[] buffer = *bufferRef;
			buffer[0..val.length] = val[];
			*bufferRef = buffer[val.length .. $];
		}

		void put(char val)
		{
			char[] buffer = *bufferRef;
			buffer[0] = val;
			*bufferRef = buffer[1 .. $];
		}
	}

	char[] before = buffer;

	NogcAppender appender;
	appender.data = buffer;
	appender.formattedWrite!fmtstr(args);

	char[] after = appender.data;

	return buffer[0 .. (after.ptr - before.ptr)].assumeUnique;
}
+/