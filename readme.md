# US Address Parser

This is a D port of the (partial) C# port of the Perl CPAN module
`Geo::StreetAddress::US`.  It's a regex-based street address
parser for the United States.

## Building and testing:

This project currently supports building through the
[dub](https://github.com/dlang/dub) package management and build system.

To run unittests and have the option of manually entering some addresses for the algorithm to parse, invoke DUB like so:
> dub --config=interactive --build=unittest

## Example usage:

```d
import geo.street_address.us;

void main(string[] args)
{
	import std.algorithm.sorting : sort;
	import std.array;
	import std.meta : aliasSeqOf;
	import std.stdio;
	import std.uni : toUpper;

	auto loop = false;

	writeln("Address Parser Driver");
	writeln(std.array.replicate("-", 40));
	writeln();
	writeln("Example Input:");
	writeln("125 Main St, Richmond VA 23221");
	writeln();

	do
	{
		writeln("Type an address and press <ENTER>:");
		auto input = readln();

		auto result = parseAddress(input);
		if (result is null)
		{
			writeln("ERROR. Input could not be parsed.");
		}
		else
		{
			writeln("RESULT: ", result.toString());

			enum properties = sort(result.propertyNames.dup);
			foreach (property; aliasSeqOf!properties)
			{
				writefln(
					"%30s : %s",
					property,
					__traits(getMember, result, property));
			}
		}

		writeln();
		writeln("Try again? [Y/N] ");

		loop = readln().toUpper == "Y";
	}
	while (loop);
}
```

Example output:
```
> dub --config=interactive
Performing "debug" build using dmd for x86_64.
geo_street_address_us ~master: building configuration "interactive"...
Linking...
Running .\bin\street_address_parser_us.exe
Address Parser Driver
----------------------------------------

Example Input:
125 Main St, Richmond VA 23221

Type an address and press <ENTER>:
125 Main St, Richmond VA 23221
RESULT: 125 MAIN ST; RICHMOND, VA  23221
                          city : RICHMOND
                        number : 125
               postdirectional :
                predirectional :
               secondaryNumber :
                 secondaryUnit :
                         state : VA
                        street : MAIN
                    streetLine : 125 MAIN ST
                        suffix : ST
                           zip : 23221

Try again? [Y/N]
```

## Licensing:

The licensing of this project is somewhat nuanced due to its history.

The original Perl version was written and is copyrighted by
Schuyler D. Erle <schuyler@geocoder.us>; and is accessible at
[CPAN](http://search.cpan.org/~timb/Geo-StreetAddress-US-1.03/US.pm)

It says that "this library is free software; you can redistribute it and/or modify 
it under the same terms as Perl itself, either Perl version 5.8.4 or, at 
your option, any later version of Perl 5 you may have available."

According to the [Perl licensing page](http://dev.perl.org/licenses/),
the perl license provides a choice between GPL V1 (or at your option, a later version)
or the Artistic License.

However, the C# port [specifies GPLv2 specifically](https://usaddress.codeplex.com/license).
As such, it may be safer to assume that this
code is effectively licensed under the GPL (v2).
