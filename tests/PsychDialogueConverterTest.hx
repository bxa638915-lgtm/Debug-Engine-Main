import cne.compat.PsychDialogueConverter;
import haxe.xml.Access;

class PsychDialogueConverterTest
{
	static function main():Void
	{
		var xmlText = PsychDialogueConverter.toCneXml('{"dialogue":[{"portrait":"senpai","expression":"angry","text":"Hello <world> & friends","boxState":"angry","speed":0.03,"sound":"pixel/text"},{"portrait":"bf","text":"Beep"}]}');
		if (xmlText == null) throw "Valid Psych dialogue JSON should convert";
		var xml = new Access(Xml.parse(xmlText).firstElement());
		if (xml.name != "dialogue" || xml.att.box != "default") throw 'Unexpected dialogue root: $xmlText';
		if (xml.nodes.char.length != 2 || xml.nodes.char[0].att.name != "senpai" || xml.nodes.char[1].att.name != "boyfriend")
			throw 'Psych portraits should become CNE characters, including the bf alias: $xmlText';
		if (xml.nodes.char[0].att.position != "left" || xml.nodes.char[1].att.position != "right")
			throw 'Psych character positions must map to valid CNE dialogue-box positions: $xmlText';
		if (xml.nodes.line.length != 2) throw 'Every Psych dialogue entry should become a CNE line: $xmlText';
		var first = xml.nodes.line[0];
		if (first.att.char != "senpai" || first.att.bubble != "angry" || first.att.changeDefAnim != "angry" || first.att.textSound != "pixel/text")
			throw 'Psych dialogue metadata should map to CNE line attributes: $xmlText';
		if (first.innerData != "Hello <world> & friends" || first.att.speed != "0.03")
			throw 'Psych dialogue text and type speed should be preserved: $xmlText';
		if (xml.nodes.line[1].att.char != "boyfriend" || xml.nodes.line[1].innerData != "Beep")
			throw 'The bf portrait alias should be used by its line: $xmlText';
		if (PsychDialogueConverter.toCneXml('{"dialogue":[]}') == null)
			throw "An empty but valid dialogue list should convert";
		if (PsychDialogueConverter.toCneXml('{bad json}') != null || PsychDialogueConverter.toCneXml('{"dialogue":{}}') != null)
			throw "Malformed Psych dialogue payloads should fail without throwing";
		Sys.println("PsychDialogueConverterTest: PASS");
	}
}
