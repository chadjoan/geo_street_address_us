module geo.street_address.us.main;

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
			writefln("RESULT: %s", result);

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