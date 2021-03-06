package massive.munit.command;

import haxe.io.Path;
import massive.sys.io.File;
import massive.sys.io.FileSys;
import massive.munit.Config;
import massive.munit.Target;

class MUnitTargetCommandBase extends MUnitCommand
{
	var hxml:File;
	var targets:Array<Target>;
	var targetTypes:Array<TargetType>;
	var includeCoverage:Bool; 

	override public function initialise()
	{
		super.initialise();
		includeCoverage = console.getOption("-coverage") == "true";
	}

	function initialiseTargets(getHxmlFromConsole:Bool)
	{
		setTargetTypes();
		setHXMLFile(getHxmlFromConsole);
		setFilteredTargets();
		hxml = config.hxml;
		targetTypes = config.targetTypes;
		targets = config.targets;
	}

	function getTargetsFromConsole():Array<TargetType>
	{
		var result = new Array();
		if (console.getOption("swf") == "true" || console.getOption(as3) == "true")
			result.push(as3);
		if (console.getOption(js) == "true") result.push(js);
		if (console.getOption(neko) == "true") result.push(neko);
		if (console.getOption(cpp) == "true") result.push(cpp);
		if (console.getOption(java) == "true") result.push(java);
		if (console.getOption(cs) == "true") result.push(cs);
		if (console.getOption(python) == "true") result.push(python);
		if (console.getOption(php) == "true") result.push(php);
		if (console.getOption(hl) == "true") result.push(hl);
		return result;
	}

	/**
	 * Updates the config targetTypes if user has specified via the CLI.
	 */
	function setTargetTypes()
	{
		if (config.targetTypes != config.defaultTargetTypes) return;
		var targetTypes = getTargetsFromConsole();
		if (targetTypes.length == 0) targetTypes = config.targetTypes.copy();
		else config.targetTypes = targetTypes;//update config targets
	}

	/**
	 * Updates and validates the hxml file for the project.
	 */
	function setHXMLFile(checkConsole:Bool)
	{
		var hxml:File = null;
		var hxmlPath:String = null;
		if (checkConsole) hxmlPath = console.getNextArg();
		if (hxmlPath == Config.CLI_CONFIG || hxmlPath == null)
			return;

		if (hxmlPath != null)
		{
			hxml = File.create(hxmlPath, console.dir);
			if (!hxml.exists)
			{
				error("Cannot locate hxml file: " + hxmlPath);
			}
			config.hxml = hxml;//update config hxml file
		}
		else
		{
			hxml = config.hxml;
			if (hxml == null)
			{
				error("Default hxml file path is not set. Please run munit config.");
			}
			if (!hxml.exists)
			{
				error("Default hxml file path does not exist. Please run munit config.");
			}
		}
	}

	/**
	 * Updates the set of valid targets for the project.
	 * Note: also removes config.targetTypes that are not present in the hxml.
	 */
	function setFilteredTargets()
	{
		if (config.targets.length > 0 ) return;

		var tempTargets = getTargetsFromHXML(config.hxml);
		
		var targets:Array<Target> = [];

		var tempTargetTypes = [];

		for(target in tempTargets)
		{
			for(type in config.targetTypes)
			{
				if (target.type == type)
				{
					targets.push(target);
					tempTargetTypes.push(type);
					break;
				}
			}
		}

		config.targetTypes = tempTargetTypes;
		config.targets = targets;
	}

	/**
	 * Parses the contents of an hxml file and returns contents as an array of targets
	 * @param hxml: path to hxml file
	 * @return array of Targets
	 */
	function getTargetsFromHXML(hxml:File):Array<Target>
	{
		var contents:String = hxml.readString();
		var lines:Array<String> = contents.split("\n");
		var target:Target = new Target();
		
		var targets:Array<Target> = [];
		
		for (line in lines)
		{
			line = StringTools.trim(line);

			if (line == "" || line.indexOf("#") == 0) continue;
			
			if (line.indexOf("--next") == 0)
			{
				targets.push(target);
				target = new Target();
				continue;
			}
			
			var mainReg:EReg = ~/^-main (.*)/;
			if (mainReg.match(line))
			{
				target.main = config.src.resolveFile(mainReg.matched(1) + ".hx");
			}

			var flagReg:EReg = ~/^-D (.*)/;
			if (flagReg.match(line))
			{
				var flag = flagReg.matched(1).split(" ");
				target.flags.set(flag.shift(), flag.join(" "));
			}

			var ereg = ~/^-lib (.*)/;
			if (ereg.match(line)) {
				var m = ereg.matched(1).split(" ").shift();
				switch(m) {
					case "hxnodejs" | "nodejs": target.flags.set("nodejs", " ");
					case _:
				}
			}

			if (line == "-debug")
			{
				target.debug = true;
			}

			var fileStr:String = getOutputFileFromLine(line);

			if(target.file == null && fileStr != null)
			{
				//dont add to hxml just yet
				target.file = File.create(fileStr, File.current);
			}
			else target.hxml += line + "\n";
			if (target.type == null)
			{
				for(type in config.targetTypes)
				{
					var s:String = switch(type)
					{
						case as3: "swf-version [^8]";
						case _: type;
					}	
					var targetMatcher = new EReg("^-" + s, "");
					if (targetMatcher.match(line))
					{
						target.type = type;
						break;
					}
				}
			}

		}
		targets.push(target);
		for(target in targets)
		{
			if(target.type != null)
				updateHxmlOutput(target);
		}
		return targets;
	}

	function updateHxmlOutput(target:Target)
	{
		var output:String = switch(target.type)
		{
			case as3: "-swf";
			case _: '-${target.type}';
		}
		var file = config.dir.getRelativePath(target.file);
		switch (target.type) {
			case cpp:
				var executablePath = target.main.name;
				if(target.debug) executablePath += "-debug";
				if(FileSys.isWindows) executablePath += ".exe";
				target.executableFile = target.file.resolveFile(executablePath);
			case java:
				var executablePath = target.main.name;
				if(target.debug) executablePath += "-debug";
				executablePath += ".jar";
				target.executableFile = target.file.resolveFile(executablePath);
			case cs:
				var executablePath = target.main.name;
				if(target.debug) executablePath += "-debug";
				executablePath += ".exe";
				target.executableFile = target.file.resolveDirectory("bin").resolveFile(executablePath);
			case php:
				var executablePath = "index";
				if(target.debug) executablePath += "-debug";
				executablePath += ".php";
				target.executableFile = target.file.resolveFile(executablePath);
			case _: target.executableFile = target.file;
		}
		output += " " + file;
		target.hxml += output + "\n";
	}

	function getOutputFileFromLine(line:String):String
	{
		for (type in config.targetTypes)
		{
			var stype:String = switch(type) {
				case as3: "swf";
				case _: type;
			}
			var targetMatcher = new EReg("^-" + stype + "\\s+", "");
			if (targetMatcher.match(line))
			{
				var result = line.substr(stype.length + 2);
				result = switch(type) {
					case cpp | java | cs | php if(includeCoverage): '${result}-coverage';
					case _: result;
				}
				return Path.normalize(result);
			}
		}
		return null;
	}

}