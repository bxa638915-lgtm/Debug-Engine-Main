import funkin.editors.uibuilder.UIBuilderData;

class UIBuilderDataTest
{
	static function main():Void
	{
		var rejectedMalformedJson = false;
		var errorMessage = "";
		try
		{
			UIBuilderData.deserialize("{");
		}
		catch (e:Dynamic)
		{
			rejectedMalformedJson = true;
			errorMessage = Std.string(e);
		}

		if (!rejectedMalformedJson)
			throw "Malformed UI project JSON must be rejected instead of replaced with the NVE template";
		if (errorMessage.indexOf("Failed to parse UI project JSON") == -1)
			throw "Malformed UI project JSON must include a useful parse error";

		var legacyProject = UIBuilderData.deserialize(haxe.Json.stringify({
			name: "Legacy",
			version: "1.0",
			canvasWidth: 1280,
			canvasHeight: 720,
			defaultCamera: "camHUD",
			elements: [{
				id: "legacyPanel",
				type: "panel",
				x: 0,
				y: 0,
				width: 10,
				height: 10,
				text: "Legacy",
				fontSize: 18,
				color: 0,
				bgColor: 0,
				borderColor: 0,
				alpha: 1,
				camera: "camHUD",
				scrollFactorX: 0,
				scrollFactorY: 0,
				imagePath: "",
				alignment: "left",
				visible: true,
				active: true
			}]
		}));
		if (Reflect.field(legacyProject, "schemaVersion") != 2)
			throw "Legacy UI projects must be migrated to the current schema version";
		var legacyElementUid = Reflect.field(legacyProject.elements[0], "uid");
		if (legacyElementUid == null || Std.string(legacyElementUid) == "")
			throw "Legacy UI elements must receive stable identifiers during migration";
		if (Reflect.field(legacyProject.elements[0], "parentUid") != null)
			throw "Legacy UI elements must migrate as root-level elements without changing their structure";

		var versionOneProject = UIBuilderData.deserialize(haxe.Json.stringify({
			schemaVersion: 1,
			name: "VersionOne",
			version: "1.0",
			canvasWidth: 1280,
			canvasHeight: 720,
			defaultCamera: "camHUD",
			elements: [{
				uid: "stable-parent-uid",
				id: "legacyRoot",
				type: "panel",
				x: 0,
				y: 0,
				width: 100,
				height: 100,
				text: "",
				fontSize: 18,
				color: 0xFFFFFFFF,
				bgColor: 0xFF000000,
				borderColor: 0xFFFFFFFF,
				alpha: 1,
				camera: "camHUD",
				scrollFactorX: 0,
				scrollFactorY: 0,
				imagePath: "",
				alignment: "left",
				visible: true,
				active: true
			}]
		}));
		if (versionOneProject.schemaVersion != 2 || versionOneProject.elements[0].uid != "stable-parent-uid")
			throw "Version 1 UI projects must migrate to the hierarchy schema without changing stable UIDs";

		var futureSchemaRejected = false;
		try
		{
			UIBuilderData.deserialize('{"schemaVersion":999,"name":"Future","elements":[]}');
		}
		catch (_:Dynamic)
		{
			futureSchemaRejected = true;
		}
		if (!futureSchemaRejected)
			throw "UI projects from a newer schema must be rejected instead of loaded with unknown data";

		var invalidSchemaTypeRejected = false;
		try
		{
			UIBuilderData.deserialize('{"schemaVersion":"1","elements":[]}');
		}
		catch (_:Dynamic)
		{
			invalidSchemaTypeRejected = true;
		}
		if (!invalidSchemaTypeRejected)
			throw "UI project schemaVersion must be an integer";

		var invalidRootRejected = false;
		try
		{
			UIBuilderData.deserialize("[]");
		}
		catch (_:Dynamic)
		{
			invalidRootRejected = true;
		}
		if (!invalidRootRejected)
			throw "UI project JSON must have an object at its root";

		var original = UIBuilderData.createDefaultProject("RoundTrip");
		var newElement = UIBuilderData.createElement("panel", "panel_1", 0, 0);
		var newElementUid = Reflect.field(newElement, "uid");
		if (newElementUid == null || Std.string(newElementUid) == "")
			throw "New UI elements must have stable identifiers immediately";
		original.elements.push(newElement);
		var serialized = UIBuilderData.serialize(original);
		var serializedData:Dynamic = haxe.Json.parse(serialized);
		if (Reflect.field(serializedData, "schemaVersion") != 2)
			throw "Serialized UI projects must include the current schema version";
		var restored = UIBuilderData.deserialize(serialized);
		if (restored.name != original.name || restored.elements.length != original.elements.length)
			throw "Valid UI project JSON must retain its project data";
		if (Reflect.field(restored.elements[0], "uid") != newElementUid)
			throw "Stable element identifiers must survive serialization round-trips";
		var childElement = UIBuilderData.createElement("text", "child_text", 10, 20);
		childElement.parentUid = newElementUid;
		original.elements.push(childElement);
		var hierarchyRoundTrip = UIBuilderData.deserialize(UIBuilderData.serialize(original));
		if (hierarchyRoundTrip.elements[1].parentUid != newElementUid)
			throw "UI hierarchy parent references must survive serialization round-trips";

		var missingParentRejected = false;
		var missingParentProject = UIBuilderData.createDefaultProject("MissingParent");
		var orphan = UIBuilderData.createElement("text", "orphan", 0, 0);
		orphan.parentUid = "missing-parent";
		missingParentProject.elements.push(orphan);
		try
		{
			UIBuilderData.serialize(missingParentProject);
		}
		catch (_:Dynamic)
		{
			missingParentRejected = true;
		}
		if (!missingParentRejected)
			throw "UI hierarchy must reject parent UIDs that do not exist in the document";

		var cyclicHierarchyRejected = false;
		var cyclicProject = UIBuilderData.createDefaultProject("Cycle");
		var cycleA = UIBuilderData.createElement("panel", "cycle_a", 0, 0);
		var cycleB = UIBuilderData.createElement("text", "cycle_b", 0, 0);
		cycleA.parentUid = cycleB.uid;
		cycleB.parentUid = cycleA.uid;
		cyclicProject.elements.push(cycleA);
		cyclicProject.elements.push(cycleB);
		try
		{
			UIBuilderData.serialize(cyclicProject);
		}
		catch (_:Dynamic)
		{
			cyclicHierarchyRejected = true;
		}
		if (!cyclicHierarchyRejected)
			throw "UI hierarchy must reject parent cycles before saving or exporting";

		var treeProject = UIBuilderData.createDefaultProject("TreeOrder");
		var childFirst = UIBuilderData.createElement("text", "childFirst", 0, 0);
		var secondRoot = UIBuilderData.createElement("panel", "secondRoot", 0, 0);
		var treeParent = UIBuilderData.createElement("panel", "treeParent", 0, 0);
		var treeGrandchild = UIBuilderData.createElement("text", "treeGrandchild", 0, 0);
		childFirst.parentUid = treeParent.uid;
		treeGrandchild.parentUid = childFirst.uid;
		treeProject.elements = [childFirst, secondRoot, treeParent, treeGrandchild];
		var hierarchyOrderFunction = Reflect.field(UIBuilderData, "getHierarchyOrder");
		if (hierarchyOrderFunction == null)
			throw "UI document model must expose a validated depth-first hierarchy for the editor tree";
		var hierarchyOrder:Array<Dynamic> = Reflect.callMethod(UIBuilderData, hierarchyOrderFunction, [treeProject]);
		if (hierarchyOrder.length != 4 || hierarchyOrder[0].element.id != "secondRoot" || hierarchyOrder[1].element.id != "treeParent"
			|| hierarchyOrder[1].depth != 0 || hierarchyOrder[2].element.id != "childFirst" || hierarchyOrder[2].depth != 1
			|| hierarchyOrder[3].element.id != "treeGrandchild" || hierarchyOrder[3].depth != 2)
			throw "UI tree order must keep siblings stable and render parents before nested children";
		var parentCandidatesFunction = Reflect.field(UIBuilderData, "getValidParentCandidates");
		if (parentCandidatesFunction == null)
			throw "UI document model must expose safe parent candidates for reparenting controls";
		var parentCandidates:Array<Dynamic> = Reflect.callMethod(UIBuilderData, parentCandidatesFunction, [treeProject, treeParent.uid]);
		if (parentCandidates.length != 1 || parentCandidates[0].uid != secondRoot.uid)
			throw "Reparenting controls must exclude the selected element and every descendant from parent choices";

		var widescreenProject = UIBuilderData.createDefaultProject("Widescreen");
		UIBuilderData.setCanvasSize(widescreenProject, 1920, 1080);
		var centeredPosition = UIBuilderData.getCenteredElementPosition(widescreenProject, 200, 40);
		if (centeredPosition.x != 860 || centeredPosition.y != 520)
			throw "New UI elements must be centered using the project's canvas dimensions";
		UIBuilderData.setCanvasSize(widescreenProject, 3840, 2160);
		if (widescreenProject.canvasWidth != 3840 || widescreenProject.canvasHeight != 2160)
			throw "4K canvas presets must be accepted by the project model";

		var centeredScrollFunction = Reflect.field(UIBuilderData, "getCenteredCameraScroll");
		if (centeredScrollFunction == null)
			throw "Canvas viewport fitting must expose centered camera scroll calculations";
		var portraitScroll:Dynamic = Reflect.callMethod(UIBuilderData, centeredScrollFunction, [720, 1280, 1280, 720, 0.5625, 1.0]);
		var portraitCenterScreenX = (720 * 0.5 - portraitScroll.x) * 0.5625 - (1280 * 0.5) * (0.5625 - 1.0);
		var portraitCenterScreenY = (1280 * 0.5 - portraitScroll.y) * 0.5625 - (720 * 0.5) * (0.5625 - 1.0);
		if (Math.abs(portraitCenterScreenX - 640) > 0.001 || Math.abs(portraitCenterScreenY - 360) > 0.001)
			throw "Portrait canvas fitting must center the canvas after the camera's zoom-anchor offset";
		var landscapeScroll:Dynamic = Reflect.callMethod(UIBuilderData, centeredScrollFunction, [1280, 720, 1280, 720, 0.85, 1.0]);
		var landscapeCenterScreenX = (1280 * 0.5 - landscapeScroll.x) * 0.85 - (1280 * 0.5) * (0.85 - 1.0);
		var landscapeCenterScreenY = (720 * 0.5 - landscapeScroll.y) * 0.85 - (720 * 0.5) * (0.85 - 1.0);
		if (Math.abs(landscapeCenterScreenX - 640) > 0.001 || Math.abs(landscapeCenterScreenY - 360) > 0.001)
			throw "Landscape canvas fitting must center the canvas after the camera's zoom-anchor offset";

		var invalidResizeRejected = false;
		try
		{
			UIBuilderData.setCanvasSize(widescreenProject, 4096, 4096);
		}
		catch (_:Dynamic)
		{
			invalidResizeRejected = true;
		}
		if (!invalidResizeRejected || widescreenProject.canvasWidth != 3840 || widescreenProject.canvasHeight != 2160)
			throw "An invalid canvas preset must be rejected without changing the current project size";
		var defaultPanel = UIBuilderData.createElement("panel", "defaultPanel", 0, 0);
		if (defaultPanel.width != 300 || defaultPanel.height != 200)
			throw "New panels must use their component-specific default size";
		var defaultButton = UIBuilderData.createElement("button", "defaultButton", 0, 0);
		if (defaultButton.width != 180 || defaultButton.height != 42)
			throw "New buttons must use their component-specific default size";

		var invalidCanvasRejected = false;
		try
		{
			UIBuilderData.deserialize('{"schemaVersion":1,"name":"InvalidCanvas","version":"1.0","canvasWidth":0,"canvasHeight":720,"defaultCamera":"camHUD","elements":[]}');
		}
		catch (_:Dynamic)
		{
			invalidCanvasRejected = true;
		}
		if (!invalidCanvasRejected)
			throw "UI projects must reject zero-sized canvases before they reach the viewport";

		var oversizedCanvasRejected = false;
		try
		{
			UIBuilderData.deserialize('{"schemaVersion":1,"name":"OversizedCanvas","version":"1.0","canvasWidth":4096,"canvasHeight":4096,"defaultCamera":"camHUD","elements":[]}');
		}
		catch (_:Dynamic)
		{
			oversizedCanvasRejected = true;
		}
		if (!oversizedCanvasRejected)
			throw "UI projects must reject canvases above the viewport pixel budget";

		var oversizedDimensionRejected = false;
		try
		{
			UIBuilderData.deserialize('{"schemaVersion":1,"name":"OversizedDimension","version":"1.0","canvasWidth":5000,"canvasHeight":1,"defaultCamera":"camHUD","elements":[]}');
		}
		catch (_:Dynamic)
		{
			oversizedDimensionRejected = true;
		}
		if (!oversizedDimensionRejected)
			throw "UI projects must reject dimensions above the viewport side limit";

		var duplicateIdsProject = UIBuilderData.createDefaultProject("DuplicateIds");
		var firstElement = UIBuilderData.createElement("panel", "panel_1", 0, 0);
		var secondElement = UIBuilderData.createElement("panel", "panel_2", 0, 0);
		if (firstElement.uid == secondElement.uid)
			throw "New UI elements must receive distinct stable identifiers";
		secondElement.uid = firstElement.uid;
		duplicateIdsProject.elements.push(firstElement);
		duplicateIdsProject.elements.push(secondElement);
		var restoredDuplicateIds = UIBuilderData.deserialize(UIBuilderData.serialize(duplicateIdsProject));
		if (restoredDuplicateIds.elements[0].uid == restoredDuplicateIds.elements[1].uid)
			throw "Duplicate stable identifiers must be repaired before serialization";

		var template = UIBuilderData.createNVEMainMenuProject();
		var seenTemplateUids = new Map<String, Bool>();
		for (element in template.elements)
		{
			var uid = Reflect.field(element, "uid");
			var uidString = Std.string(uid);
			if (uid == null || uidString == "" || seenTemplateUids.exists(uidString))
				throw "NVE template elements must have distinct stable identifiers";
			seenTemplateUids.set(uidString, true);
		}

		var renderContractProject = UIBuilderData.createDefaultProject("RenderContract");
		var renderFirst = UIBuilderData.createElement("panel", "renderFirst", 0, 0);
		var renderHidden = UIBuilderData.createElement("text", "renderHidden", 0, 0);
		var renderLast = UIBuilderData.createElement("button", "renderLast", 0, 0);
		renderHidden.visible = false;
		renderContractProject.elements = [renderFirst, renderHidden, renderLast];
		var renderOrderMethod = Reflect.field(UIBuilderData, "visibleElementsInRenderOrder");
		if (renderOrderMethod == null)
			throw "UI runtime rendering must expose the document's visible draw order as a shared contract";
		var visibleRenderOrder:Array<Dynamic> = cast Reflect.callMethod(UIBuilderData, renderOrderMethod, [renderContractProject]);
		if (visibleRenderOrder.length != 2 || visibleRenderOrder[0].uid != renderFirst.uid || visibleRenderOrder[1].uid != renderLast.uid)
			throw "UI runtime preview must preserve document z-order and omit hidden elements";
		if (UIBuilderData.generateHScript(renderContractProject).indexOf("UIBuilderRuntimeRenderer.createRuntimeElements") == -1)
			throw "Generated runtime UI must use the same renderer as the editor preview";

		var escapingProject = UIBuilderData.createDefaultProject("Escaping");
		var escapingText = UIBuilderData.createElement("text", "safeLabel", 0, 0);
		escapingText.text = "first\n\"quoted\" & <tag>";
		escapingProject.elements.push(escapingText);
		var hscriptOutput = UIBuilderData.generateHScript(escapingProject);
		var exportedTextStart = hscriptOutput.indexOf("first");
		var exportedTextEnd = hscriptOutput.indexOf("quoted", exportedTextStart);
		var exportedTextSegment = exportedTextStart >= 0 && exportedTextEnd > exportedTextStart ? hscriptOutput.substr(exportedTextStart, exportedTextEnd - exportedTextStart) : "";
		if (hscriptOutput.indexOf("UIBuilderRuntimeRenderer.createRuntimeElements") == -1 || exportedTextSegment == "" || exportedTextSegment.indexOf("\n") != -1 || exportedTextSegment.indexOf("\r") != -1)
			throw "HScript export must preserve escaped text while using the shared runtime renderer";
		var luaOutput = UIBuilderData.generatePsychLua(escapingProject);
		if (luaOutput.indexOf('"first\\n\\"quoted\\" & <tag>"') == -1)
			throw "Psych Lua export must escape line breaks and quotes inside string literals";
		var xmlOutput = UIBuilderData.generateXML(escapingProject);
		if (xmlOutput.indexOf('text="first&#10;&quot;quoted&quot; &amp; &lt;tag&gt;"') == -1)
			throw "XML export must escape attribute values as XML and preserve line breaks";

		var invalidExportIdProject = UIBuilderData.createDefaultProject("InvalidExportId");
		invalidExportIdProject.elements.push(UIBuilderData.createElement("text", "bad-id", 0, 0));
		var invalidExportIdRejected = false;
		try
		{
			UIBuilderData.generateHScript(invalidExportIdProject);
		}
		catch (_:Dynamic)
		{
			invalidExportIdRejected = true;
		}
		if (!invalidExportIdRejected)
			throw "HScript export must reject element IDs that are not valid identifiers";

		var invalidCameraProject = UIBuilderData.createDefaultProject("InvalidCamera");
		var invalidCameraElement = UIBuilderData.createElement("text", "safeLabel", 0, 0);
		invalidCameraElement.camera = "camHUD; trace('injected')";
		invalidCameraProject.elements.push(invalidCameraElement);
		var invalidCameraRejected = false;
		try
		{
			UIBuilderData.generateHScript(invalidCameraProject);
		}
		catch (_:Dynamic)
		{
			invalidCameraRejected = true;
		}
		if (!invalidCameraRejected)
			throw "HScript export must reject camera property expressions that are not identifiers";

		trace("UIBuilderDataTest: PASS");
	}
}
