package funkin.editors.uibuilder;

import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.math.FlxRect;
import funkin.backend.system.framerate.Framerate;
import funkin.backend.utils.NativeAPI;
import funkin.editors.EditorPicker;
import funkin.editors.SaveSubstate;
import funkin.editors.extra.CameraHoverDummy;
import funkin.editors.ui.*;
import funkin.editors.ui.UIContextMenu.UIContextMenuOption;
import funkin.editors.uibuilder.UIBuilderData;
import openfl.events.IOErrorEvent;
import openfl.net.FileFilter;
import openfl.net.FileReference;

using StringTools;

class UIBuilderEditor extends UIState {
	public static var instance(get, null):UIBuilderEditor;
	private static inline function get_instance()
		return FlxG.state is UIBuilderEditor ? cast FlxG.state : null;

	// ── Câmeras ────────────────────────────────────────────────
	public var canvasCamera:FlxCamera;
	public var uiCamera:FlxCamera;

	// ── Dados do Projeto ──────────────────────────────────────
	public var project:UIProjectData;
	public var selectedIndex:Int = -1;
	public var curSelected(get, never):UIElementData;
	inline function get_curSelected():UIElementData {
		return (selectedIndex >= 0 && selectedIndex < project.elements.length) ? project.elements[selectedIndex] : null;
	}

	// ── Grupos do Canvas ──────────────────────────────────────
	public var canvasBg:FlxSprite;
	public var canvasBorder:FlxSprite;
	public var gridSpr:FlxSprite;
	public var previewGroup:FlxTypedGroup<FlxSprite>;
	public var selectionBox:FlxSprite;
	public var selectionHandle:FlxSprite;

	// ── Grupo da UI do Editor ─────────────────────────────────
	public var uiGroup:FlxTypedGroup<FlxSprite>;
	public var cameraHoverDummy:CameraHoverDummy;

	// ── Janelas e Menus de UI ─────────────────────────────────
	public var topMenuSpr:UITopMenu;
	public var toolboxWindow:UIWindow;
	public var propertiesWindow:UIWindow;
	public var hierarchyWindow:UIWindow;
	public var infoText:UIText;

	// ── Controles do Inspetor de Propriedades ─────────────────
	public var propIdInput:UITextBox;
	public var propXInput:UINumericStepper;
	public var propYInput:UINumericStepper;
	public var propWInput:UINumericStepper;
	public var propHInput:UINumericStepper;
	public var propTextInput:UITextBox;
	public var propFontSizeInput:UINumericStepper;
	public var propAlphaInput:UINumericStepper;
	public var propColorInput:UITextBox;
	public var propBgColorInput:UITextBox;
	public var propCameraInput:UITextBox;
	public var propAlignDropDown:UIDropDown;
	public var propParentDropDown:UIDropDown;
	var _parentUidOptions:Array<String> = [null];
	public var propImagePathInput:UITextBox;
	public var propCharAnimInput:UITextBox;
	public var propCharPlayerCheck:UICheckbox;

	// ── Hierarquia de Camadas ─────────────────────────────────
	public var layerButtons:Array<UIButton> = [];
	public var layerGroup:FlxTypedGroup<FlxSprite>;

	// ── Estado de Interação ───────────────────────────────────
	public var isDragging:Bool = false;
	public var isResizing:Bool = false;
	public var isPanning:Bool = false;
	public var dragOffset:FlxPoint = FlxPoint.get();
	public var panStart:FlxPoint = FlxPoint.get();
	public var camStart:FlxPoint = FlxPoint.get();
	public var showGrid:Bool = true;
	public var gridSize:Int = 16;
	public var snapToGrid:Bool = false;

	// ── Histórico (Undo / Redo) ───────────────────────────────
	public var undoStack:Array<String> = [];
	public var redoStack:Array<String> = [];
	public var maxHistory:Int = 30;

	public function new(?initialProject:UIProjectData) {
		super();
		this.project = initialProject != null ? initialProject : UIBuilderData.createNVEMainMenuProject();
		if (this.project.elements.length > 0)
			this.selectedIndex = 0;
	}

	public override function create() {
		super.create();
		_recordHistory();

		// Câmera do Canvas (Mundo / Edição Visual)
		canvasCamera = FlxG.camera;
		canvasCamera.bgColor = 0xFF1E1E28;
		_fitCanvasToView();

		// Câmera da UI de Edição (Janelas / Inspetor)
		uiCamera = new FlxCamera();
		uiCamera.bgColor = 0;
		FlxG.cameras.add(uiCamera);
		uiCameras = [uiCamera];

		// A borda fica por baixo do canvas para evitar uma textura grande extra.
		canvasBorder = new FlxSprite(-2, -2);
		canvasBorder.cameras = [canvasCamera];
		add(canvasBorder);

		canvasBg = new FlxSprite(0, 0);
		canvasBg.cameras = [canvasCamera];
		add(canvasBg);

		// Grid
		gridSpr = new FlxSprite(0, 0);
		gridSpr.cameras = [canvasCamera];
		add(gridSpr);

		_refreshCanvasSurface();

		// Grupos de Preview
		previewGroup = new FlxTypedGroup<FlxSprite>();
		previewGroup.cameras = [canvasCamera];
		add(previewGroup);

		// Indicador de Seleção
		selectionBox = new FlxSprite();
		selectionBox.makeGraphic(1, 1, 0x00000000, true);
		selectionBox.cameras = [canvasCamera];
		selectionBox.visible = false;
		add(selectionBox);

		selectionHandle = new FlxSprite();
		selectionHandle.makeGraphic(10, 10, 0xFF00FFC8);
		selectionHandle.cameras = [canvasCamera];
		selectionHandle.visible = false;
		add(selectionHandle);

		// Grupo de UI nativa da Engine
		uiGroup = new FlxTypedGroup<FlxSprite>();
		uiGroup.cameras = [uiCamera];
		add(cameraHoverDummy = new CameraHoverDummy(uiGroup, FlxPoint.weak(0, 0)));

		// Constrói Menus e Janelas
		_buildTopMenu();
		_buildToolboxWindow();
		_buildPropertiesWindow();
		_buildHierarchyWindow();

		// Info Overlay
		infoText = new UIText(10, FlxG.height - 24, 700, "UI Builder | [Espaco+Arrastar] Pan | [Roda] Zoom | [G] Grid | [Del] Apagar | [Ctrl+D] Duplicar", 12);
		uiGroup.add(infoText);

		add(uiGroup);

		_refreshCanvas();
		_refreshHierarchy();
		_syncProperties();

		if (Framerate.isLoaded) {
			Framerate.fpsCounter.alpha = 0.4;
			Framerate.memoryCounter.alpha = 0.4;
		}
	}

	// ── Top Menu ───────────────────────────────────────────────
	function _buildTopMenu() {
		var menuOptions:Array<UIContextMenuOption> = [
			{
				label: "File",
				childs: [
					{
						label: "New Project (Blank)",
						keybind: [CONTROL, N],
						onSelect: function(_) {
							project = UIBuilderData.createDefaultProject("UntitledUI");
							selectedIndex = -1;
							_recordHistory();
							_refreshCanvasSurface();
							_fitCanvasToView();
							_refreshCanvas();
							_refreshHierarchy();
							_syncProperties();
						}
					},
					{
						label: "Open (JSON)...",
						keybind: [CONTROL, O],
						onSelect: function(_) { _openJsonDialog(); }
					},
					{
						label: "Save (JSON)",
						keybind: [CONTROL, S],
						onSelect: function(_) { _saveJsonDialog(); }
					},
					null,
					{
						label: "Export Codename HScript (.hx)",
						keybind: [CONTROL, E],
						onSelect: function(_) { _exportHScriptDialog(); }
					},
					{
						label: "Export Psych Lua (.lua)",
						keybind: [CONTROL, L],
						onSelect: function(_) { _exportLuaDialog(); }
					},
					{
						label: "Export XML Layout (.xml)",
						onSelect: function(_) { _exportXMLDialog(); }
					},
					null,
					{
						label: "Exit",
						onSelect: function(_) {
							FlxG.switchState(new EditorPicker());
						}
					}
				]
			},
			{
				label: "Edit",
				childs: [
					{
						label: "Undo",
						keybind: [CONTROL, Z],
						onSelect: function(_) { _undo(); }
					},
					{
						label: "Redo",
						keybind: [CONTROL, Y],
						onSelect: function(_) { _redo(); }
					},
					null,
					{
						label: "Duplicate Selected",
						keybind: [CONTROL, D],
						onSelect: function(_) { _duplicateSelected(); }
					},
					{
						label: "Delete Selected",
						keybind: [DELETE],
						onSelect: function(_) { _deleteSelected(); }
					}
				]
			},
			{
				label: "View",
				childs: [
					{
						label: "Zoom In",
						keybind: [CONTROL, NUMPADPLUS],
						onSelect: function(_) { canvasCamera.zoom = Math.min(3.0, canvasCamera.zoom + 0.15); }
					},
					{
						label: "Zoom Out",
						keybind: [CONTROL, NUMPADMINUS],
						onSelect: function(_) { canvasCamera.zoom = Math.max(0.25, canvasCamera.zoom - 0.15); }
					},
					{
						label: "Reset View",
						keybind: [CONTROL, NUMPADZERO],
						onSelect: function(_) { _fitCanvasToView(); }
					},
					null,
					{
						label: "Canvas Resolution",
						childs: [
							{label: "Default (1280 × 720)", onSelect: function(_) { _setCanvasSize(1280, 720); }},
							{label: "Full HD (1920 × 1080)", onSelect: function(_) { _setCanvasSize(1920, 1080); }},
							{label: "Quad HD (2560 × 1440)", onSelect: function(_) { _setCanvasSize(2560, 1440); }},
							{label: "4K UHD (3840 × 2160)", onSelect: function(_) { _setCanvasSize(3840, 2160); }},
							null,
							{label: "Portrait HD (720 × 1280)", onSelect: function(_) { _setCanvasSize(720, 1280); }},
							{label: "Portrait Full HD (1080 × 1920)", onSelect: function(_) { _setCanvasSize(1080, 1920); }}
						]
					},
					null,
					{
						label: "Toggle Grid",
						keybind: [G],
						onSelect: function(_) {
							showGrid = !showGrid;
							gridSpr.visible = showGrid;
						}
					},
					{
						label: "Snap to Grid",
						onSelect: function(_) { snapToGrid = !snapToGrid; }
					}
				]
			},
			{
				label: "Presets",
				childs: [
					{
						label: "VS Impostor (NVE) Main Menu",
						onSelect: function(_) { _loadNVETemplate(); }
					},
					null,
					{
						label: "Stats HUD Box",
						onSelect: function(_) { _addPresetStatsHUD(); }
					},
					{
						label: "Loading Screen Overlay",
						onSelect: function(_) { _addPresetLoadingScreen(); }
					},
					{
						label: "Dialogue Box Frame",
						onSelect: function(_) { _addPresetDialogueBox(); }
					}
				]
			}
		];

		topMenuSpr = new UITopMenu(menuOptions);
		uiGroup.add(topMenuSpr);
	}

	// ── Toolbox Window ─────────────────────────────────────────
	function _buildToolboxWindow() {
		toolboxWindow = new UIWindow(10, 35, 140, 345, "Components");

		var types:Array<{label:String, type:UIElementType}> = [
			{label: "Panel",        type: PANEL},
			{label: "Button",       type: BUTTON},
			{label: "Text Label",   type: TEXT},
			{label: "Progress Bar", type: PROGRESS_BAR},
			{label: "Checkbox",     type: CHECKBOX},
			{label: "Image",        type: IMAGE},
			{label: "Character",    type: CHARACTER},
			{label: "Input Box",    type: INPUT_BOX}
		];

		var btnY:Float = toolboxWindow.y + 35;
		for (t in types) {
			var type = t.type;
			var btn = new UIButton(toolboxWindow.x + 10, btnY, t.label, function() {
				_spawnElement(type);
			}, 120, 28);
			toolboxWindow.members.push(btn);
			btnY += 34;
		}

		uiGroup.add(toolboxWindow);
	}

	// ── Properties Inspector Window ────────────────────────────
	function _buildPropertiesWindow() {
		var winW = 230;
		var winH = 520;
		var winX = FlxG.width - winW - 10;
		var winY = 35;
		propertiesWindow = new UIWindow(winX, winY, winW, winH, "Properties");

		var startY:Float = winY + 32;
		var stepY:Float = 34;

		// ID
		var lblId = new UIText(winX + 10, startY + 6, 40, "ID:", 12);
		propIdInput = new UITextBox(winX + 55, startY, "elemId", 160, 24);
		propIdInput.onChange = function(val) {
			if (curSelected != null && val.trim() != "") {
				curSelected.id = val.trim();
				_refreshHierarchy();
			}
		};
		propertiesWindow.members.push(lblId);
		propertiesWindow.members.push(propIdInput);

		// X / Y
		startY += stepY;
		var lblX = new UIText(winX + 10, startY + 6, 20, "X:", 12);
		propXInput = new UINumericStepper(winX + 30, startY, 0, 10, 0, -2000, 4000, 80, 24);
		propXInput.onChange = function(v) {
			if (curSelected != null) {
				curSelected.x = Std.parseFloat(v);
				_refreshCanvas();
			}
		};
		var lblY = new UIText(winX + 115, startY + 6, 20, "Y:", 12);
		propYInput = new UINumericStepper(winX + 135, startY, 0, 10, 0, -2000, 4000, 80, 24);
		propYInput.onChange = function(v) {
			if (curSelected != null) {
				curSelected.y = Std.parseFloat(v);
				_refreshCanvas();
			}
		};
		propertiesWindow.members.push(lblX);
		propertiesWindow.members.push(propXInput);
		propertiesWindow.members.push(lblY);
		propertiesWindow.members.push(propYInput);

		// W / H
		startY += stepY;
		var lblW = new UIText(winX + 10, startY + 6, 20, "W:", 12);
		propWInput = new UINumericStepper(winX + 30, startY, 100, 10, 0, 1, 2000, 80, 24);
		propWInput.onChange = function(v) {
			if (curSelected != null) {
				curSelected.width = Std.int(Math.max(1, Std.parseFloat(v)));
				_refreshCanvas();
			}
		};
		var lblH = new UIText(winX + 115, startY + 6, 20, "H:", 12);
		propHInput = new UINumericStepper(winX + 135, startY, 40, 10, 0, 1, 2000, 80, 24);
		propHInput.onChange = function(v) {
			if (curSelected != null) {
				curSelected.height = Std.int(Math.max(1, Std.parseFloat(v)));
				_refreshCanvas();
			}
		};
		propertiesWindow.members.push(lblW);
		propertiesWindow.members.push(propWInput);
		propertiesWindow.members.push(lblH);
		propertiesWindow.members.push(propHInput);

		// Text / Char Name
		startY += stepY;
		var lblText = new UIText(winX + 10, startY + 6, 40, "Txt/Ch:", 12);
		propTextInput = new UITextBox(winX + 55, startY, "", 160, 24);
		propTextInput.onChange = function(val) {
			if (curSelected != null) {
				curSelected.text = val;
				_refreshCanvas();
			}
		};
		propertiesWindow.members.push(lblText);
		propertiesWindow.members.push(propTextInput);

		// Image Path (Para IMAGE)
		startY += stepY;
		var lblImg = new UIText(winX + 10, startY + 6, 40, "Image:", 12);
		propImagePathInput = new UITextBox(winX + 55, startY, "", 120, 24);
		propImagePathInput.onChange = function(val) {
			if (curSelected != null) {
				curSelected.imagePath = val.trim();
				_refreshCanvas();
			}
		};
		var btnImgBrowse = new UIButton(winX + 180, startY, "...", function() {
			openContextMenu([
				{label: "nve/main/vignette", onSelect: function(_) { propImagePathInput.label.text = "nve/main/vignette"; if (curSelected != null) { curSelected.imagePath = "nve/main/vignette"; _refreshCanvas(); } }},
				{label: "nve/main/tablet", onSelect: function(_) { propImagePathInput.label.text = "nve/main/tablet"; if (curSelected != null) { curSelected.imagePath = "nve/main/tablet"; _refreshCanvas(); } }},
				{label: "nve/main/glow", onSelect: function(_) { propImagePathInput.label.text = "nve/main/glow"; if (curSelected != null) { curSelected.imagePath = "nve/main/glow"; _refreshCanvas(); } }},
				{label: "nve/main/greenmenu", onSelect: function(_) { propImagePathInput.label.text = "nve/main/greenmenu"; if (curSelected != null) { curSelected.imagePath = "nve/main/greenmenu"; _refreshCanvas(); } }},
				{label: "nve/main/redmenu", onSelect: function(_) { propImagePathInput.label.text = "nve/main/redmenu"; if (curSelected != null) { curSelected.imagePath = "nve/main/redmenu"; _refreshCanvas(); } }},
				{label: "icons/icon-bf", onSelect: function(_) { propImagePathInput.label.text = "icons/icon-bf"; if (curSelected != null) { curSelected.imagePath = "icons/icon-bf"; _refreshCanvas(); } }},
				{label: "icons/icon-dad", onSelect: function(_) { propImagePathInput.label.text = "icons/icon-dad"; if (curSelected != null) { curSelected.imagePath = "icons/icon-dad"; _refreshCanvas(); } }},
				{label: "icons/icon-gf", onSelect: function(_) { propImagePathInput.label.text = "icons/icon-gf"; if (curSelected != null) { curSelected.imagePath = "icons/icon-gf"; _refreshCanvas(); } }}
			]);
		}, 35, 24);
		propertiesWindow.members.push(lblImg);
		propertiesWindow.members.push(propImagePathInput);
		propertiesWindow.members.push(btnImgBrowse);

		// Char Anim (Para CHARACTER)
		startY += stepY;
		var lblAnim = new UIText(winX + 10, startY + 6, 40, "Anim:", 12);
		propCharAnimInput = new UITextBox(winX + 55, startY, "idle", 100, 24);
		propCharAnimInput.onChange = function(val) {
			if (curSelected != null) {
				if (curSelected.extra == null) curSelected.extra = {};
				curSelected.extra.anim = val.trim();
				_refreshCanvas();
			}
		};
		propCharPlayerCheck = new UICheckbox(winX + 160, startY + 2, "Player", false);
		propCharPlayerCheck.onChecked = function(chk) {
			if (curSelected != null) {
				if (curSelected.extra == null) curSelected.extra = {};
				curSelected.extra.isPlayer = chk;
				_refreshCanvas();
			}
		};
		propertiesWindow.members.push(lblAnim);
		propertiesWindow.members.push(propCharAnimInput);
		propertiesWindow.members.push(propCharPlayerCheck);

		// Font Size / Alpha
		startY += stepY;
		var lblSize = new UIText(winX + 10, startY + 6, 30, "Font:", 12);
		propFontSizeInput = new UINumericStepper(winX + 45, startY, 18, 2, 0, 8, 120, 65, 24);
		propFontSizeInput.onChange = function(v) {
			if (curSelected != null) {
				curSelected.fontSize = Std.int(Math.max(8, Std.parseFloat(v)));
				_refreshCanvas();
			}
		};
		var lblAlpha = new UIText(winX + 115, startY + 6, 30, "Alp:", 12);
		propAlphaInput = new UINumericStepper(winX + 145, startY, 1.0, 0.1, 2, 0.0, 1.0, 70, 24);
		propAlphaInput.onChange = function(v) {
			if (curSelected != null) {
				curSelected.alpha = Math.max(0, Math.min(1, Std.parseFloat(v)));
				_refreshCanvas();
			}
		};
		propertiesWindow.members.push(lblSize);
		propertiesWindow.members.push(propFontSizeInput);
		propertiesWindow.members.push(lblAlpha);
		propertiesWindow.members.push(propAlphaInput);

		// Color Hex
		startY += stepY;
		var lblCol = new UIText(winX + 10, startY + 6, 40, "Color:", 12);
		propColorInput = new UITextBox(winX + 55, startY, "FFFFFF", 160, 24);
		propColorInput.onChange = function(val) {
			if (curSelected != null) {
				var parsed = Std.parseInt("0x" + val.trim());
				if (parsed != null) {
					curSelected.color = parsed;
					_refreshCanvas();
				}
			}
		};
		propertiesWindow.members.push(lblCol);
		propertiesWindow.members.push(propColorInput);

		// BgColor Hex
		startY += stepY;
		var lblBgCol = new UIText(winX + 10, startY + 6, 40, "BgCol:", 12);
		propBgColorInput = new UITextBox(winX + 55, startY, "1A1A2E", 160, 24);
		propBgColorInput.onChange = function(val) {
			if (curSelected != null) {
				var parsed = Std.parseInt("0x" + val.trim());
				if (parsed != null) {
					curSelected.bgColor = parsed;
					_refreshCanvas();
				}
			}
		};
		propertiesWindow.members.push(lblBgCol);
		propertiesWindow.members.push(propBgColorInput);

		// Camera
		startY += stepY;
		var lblCam = new UIText(winX + 10, startY + 6, 40, "Cam:", 12);
		propCameraInput = new UITextBox(winX + 55, startY, "camHUD", 160, 24);
		propCameraInput.onChange = function(val) {
			if (curSelected != null) {
				curSelected.camera = val.trim();
			}
		};
		propertiesWindow.members.push(lblCam);
		propertiesWindow.members.push(propCameraInput);

		// Align
		startY += stepY;
		var lblAlign = new UIText(winX + 10, startY + 6, 40, "Align:", 12);
		propAlignDropDown = new UIDropDown(winX + 55, startY, 160, 24, ["left", "center", "right"], 0);
		propAlignDropDown.onChange = function(idx) {
			if (curSelected != null) {
				curSelected.alignment = ["left", "center", "right"][idx];
				_refreshCanvas();
			}
		};
		propertiesWindow.members.push(lblAlign);
		propertiesWindow.members.push(propAlignDropDown);

		// Hierarchy parent. Element positions stay in absolute canvas coordinates.
		startY += stepY;
		var lblParent = new UIText(winX + 10, startY + 6, 45, "Parent:", 12);
		propParentDropDown = new UIDropDown(winX + 55, startY, 160, 24, ["(Root)"], 0);
		propParentDropDown.onChange = function(index:Int) {
			if (curSelected == null || index < 0 || index >= _parentUidOptions.length)
				return;
			var parentUid = _parentUidOptions[index];
			if (curSelected.parentUid == parentUid)
				return;
			curSelected.parentUid = parentUid;
			_recordHistory();
			_refreshHierarchy();
			_syncProperties();
		};
		propertiesWindow.members.push(lblParent);
		propertiesWindow.members.push(propParentDropDown);

		uiGroup.add(propertiesWindow);
	}

	// ── Hierarchy Window ───────────────────────────────────────
	function _buildHierarchyWindow() {
		var winW = 230;
		var winH = 200;
		var winX = FlxG.width - winW - 10;
		var winY = FlxG.height - winH - 10;
		hierarchyWindow = new UIWindow(winX, winY, winW, winH, "Layers / Elements");

		layerGroup = new FlxTypedGroup<FlxSprite>();
		hierarchyWindow.members.push(layerGroup);

		// Botões de Reordenação
		var btnUp = new UIButton(winX + 10, winY + winH - 35, "▲ Up", function() { _moveLayer(-1); }, 65, 25);
		var btnDown = new UIButton(winX + 80, winY + winH - 35, "▼ Down", function() { _moveLayer(1); }, 65, 25);
		var btnDel = new UIButton(winX + 150, winY + winH - 35, "✕ Del", function() { _deleteSelected(); }, 65, 25);
		btnDel.color = 0xFFFF4455;

		hierarchyWindow.members.push(btnUp);
		hierarchyWindow.members.push(btnDown);
		hierarchyWindow.members.push(btnDel);

		uiGroup.add(hierarchyWindow);
	}

	// ── Atualização e Interação ────────────────────────────────
	public override function update(elapsed:Float) {
		super.update(elapsed);

		_handleCanvasInput();
		_updateSelectionBox();
	}

	function _handleCanvasInput() {
		var mouseWorldPos = FlxG.mouse.getWorldPosition(canvasCamera);

		// Pan da Câmera (Espaço + Mouse ou Botão do Meio)
		if (FlxG.keys.pressed.SPACE || FlxG.mouse.pressedMiddle) {
			if (FlxG.mouse.justPressed || FlxG.mouse.justPressedMiddle) {
				isPanning = true;
				panStart.set(FlxG.mouse.screenX, FlxG.mouse.screenY);
				camStart.set(canvasCamera.scroll.x, canvasCamera.scroll.y);
			}
			if (isPanning) {
				var dx = (FlxG.mouse.screenX - panStart.x) / canvasCamera.zoom;
				var dy = (FlxG.mouse.screenY - panStart.y) / canvasCamera.zoom;
				canvasCamera.scroll.set(camStart.x - dx, camStart.y - dy);
			}
		} else {
			isPanning = false;
		}

		// Zoom com Roda do Mouse
		if (FlxG.mouse.wheel != 0 && (currentFocus == null || !(currentFocus is UITextBox))) {
			var zoomDelta = FlxG.mouse.wheel * 0.1;
			canvasCamera.zoom = Math.max(0.2, Math.min(3.0, canvasCamera.zoom + zoomDelta));
		}

		// Seleção e Arraste no Canvas
		var isHoveringUI = (hoveredSprite != null);
		if (!isHoveringUI && !isPanning) {
			// Redimensionamento pelo Handle
			if (selectionHandle.visible && FlxG.mouse.justPressed && _isMouseOverHandle(mouseWorldPos)) {
				isResizing = true;
			}

			if (isResizing) {
				if (curSelected != null) {
					var newW = Std.int(Math.max(10, mouseWorldPos.x - curSelected.x));
					var newH = Std.int(Math.max(10, mouseWorldPos.y - curSelected.y));
					if (snapToGrid) {
						newW = Std.int(Math.round(newW / gridSize) * gridSize);
						newH = Std.int(Math.round(newH / gridSize) * gridSize);
					}
					curSelected.width = newW;
					curSelected.height = newH;
					_refreshCanvas();
					_syncProperties();
				}
				if (FlxG.mouse.justReleased) {
					isResizing = false;
					_recordHistory();
				}
				return;
			}

			// Seleção / Arraste de Elemento
			if (FlxG.mouse.justPressed) {
				var clickedIdx = _findElementAt(mouseWorldPos.x, mouseWorldPos.y);
				if (clickedIdx >= 0) {
					selectedIndex = clickedIdx;
					isDragging = true;
					dragOffset.set(mouseWorldPos.x - curSelected.x, mouseWorldPos.y - curSelected.y);
					_syncProperties();
					_refreshHierarchy();
				} else if (mouseWorldPos.x >= 0 && mouseWorldPos.x <= project.canvasWidth && mouseWorldPos.y >= 0 && mouseWorldPos.y <= project.canvasHeight) {
					selectedIndex = -1;
					_syncProperties();
					_refreshHierarchy();
				}
			}

			if (isDragging && curSelected != null) {
				var targetX = mouseWorldPos.x - dragOffset.x;
				var targetY = mouseWorldPos.y - dragOffset.y;
				if (snapToGrid) {
					targetX = Math.round(targetX / gridSize) * gridSize;
					targetY = Math.round(targetY / gridSize) * gridSize;
				}
				curSelected.x = targetX;
				curSelected.y = targetY;
				_refreshCanvas();
				_syncProperties();

				if (FlxG.mouse.justReleased) {
					isDragging = false;
					_recordHistory();
				}
			}
		}

		if (FlxG.mouse.justReleased) {
			isDragging = false;
			isResizing = false;
		}
	}

	function _isMouseOverHandle(pos:FlxPoint):Bool {
		return pos.x >= selectionHandle.x && pos.x <= selectionHandle.x + selectionHandle.width &&
		       pos.y >= selectionHandle.y && pos.y <= selectionHandle.y + selectionHandle.height;
	}

	function _findElementAt(wx:Float, wy:Float):Int {
		var i = project.elements.length - 1;
		while (i >= 0) {
			var el = project.elements[i];
			if (el.visible && wx >= el.x && wx <= el.x + el.width && wy >= el.y && wy <= el.y + el.height)
				return i;
			i--;
		}
		return -1;
	}

	function _refreshCanvasSurface():Void {
		var canvasWidth = project.canvasWidth;
		var canvasHeight = project.canvasHeight;

		canvasBorder.makeGraphic(1, 1, 0xFF00FFC8);
		canvasBorder.scale.set(canvasWidth + 4, canvasHeight + 4);
		canvasBorder.updateHitbox();

		canvasBg.makeGraphic(1, 1, 0xFF0D0D14);
		canvasBg.scale.set(canvasWidth, canvasHeight);
		canvasBg.updateHitbox();

		gridSpr.makeGraphic(canvasWidth, canvasHeight, 0x00000000, true);
		_drawGrid();
		canvasBorder.x = -2;
		canvasBorder.y = -2;
	}

	function _refreshCanvasSurfaceIfDimensionsChanged(previousWidth:Int, previousHeight:Int):Void {
		if (project.canvasWidth != previousWidth || project.canvasHeight != previousHeight) {
			_refreshCanvasSurface();
			_fitCanvasToView();
		}
	}

	function _fitCanvasToView():Void {
		var viewportWidth = canvasCamera.width;
		var viewportHeight = canvasCamera.height;
		var zoom = Math.min(0.85, Math.min(viewportWidth / project.canvasWidth, viewportHeight / project.canvasHeight));
		canvasCamera.zoom = Math.max(0.1, zoom);
		var scroll = UIBuilderData.getCenteredCameraScroll(project.canvasWidth, project.canvasHeight, viewportWidth, viewportHeight, canvasCamera.zoom, canvasCamera.initialZoom);
		canvasCamera.scroll.set(scroll.x, scroll.y);
	}

	function _setCanvasSize(width:Int, height:Int):Void {
		if (project.canvasWidth == width && project.canvasHeight == height)
			return;

		UIBuilderData.setCanvasSize(project, width, height);
		_recordHistory();
		_refreshCanvasSurface();
		_fitCanvasToView();
	}

	// ── Renderização do Canvas e Previews ─────────────────────
	function _refreshCanvas() {
		for (sprite in previewGroup.members.copy())
			if (sprite != null) sprite.destroy();
		previewGroup.clear();

		for (sprite in UIBuilderRuntimeRenderer.renderProject(project, canvasCamera))
			previewGroup.add(sprite);
	}

	function _updateSelectionBox() {
		if (curSelected == null || !curSelected.visible) {
			selectionBox.visible = false;
			selectionHandle.visible = false;
			return;
		}

		selectionBox.visible = true;
		selectionBox.x = curSelected.x - 2;
		selectionBox.y = curSelected.y - 2;
		var sw = curSelected.width + 4;
		var sh = curSelected.height + 4;
		if (selectionBox.graphic == null || selectionBox.graphic.width != sw || selectionBox.graphic.height != sh) {
			selectionBox.makeGraphic(sw, sh, 0x00000000, true);
			_drawSelectionBorder(selectionBox, sw, sh);
		}

		selectionHandle.visible = true;
		selectionHandle.x = curSelected.x + curSelected.width - 5;
		selectionHandle.y = curSelected.y + curSelected.height - 5;
	}

	// ── Sincronização de UI ────────────────────────────────────
	function _syncProperties() {
		var el = curSelected;
		if (el == null) {
			propIdInput.label.text = "-";
			propXInput.value = 0;
			propYInput.value = 0;
			propWInput.value = 0;
			propHInput.value = 0;
			propTextInput.label.text = "";
			propFontSizeInput.value = 18;
			propAlphaInput.value = 1.0;
			propColorInput.label.text = "";
			propBgColorInput.label.text = "";
			propCameraInput.label.text = "";
			propImagePathInput.label.text = "";
			propCharAnimInput.label.text = "";
			propCharPlayerCheck.checked = false;
			_refreshParentDropdown(null);
			return;
		}

		propIdInput.label.text = el.id;
		propXInput.value = el.x;
		propYInput.value = el.y;
		propWInput.value = el.width;
		propHInput.value = el.height;
		propTextInput.label.text = el.text;
		propFontSizeInput.value = el.fontSize;
		propAlphaInput.value = el.alpha;
		propColorInput.label.text = StringTools.hex(el.color & 0x00FFFFFF, 6);
		propBgColorInput.label.text = StringTools.hex(el.bgColor & 0x00FFFFFF, 6);
		propCameraInput.label.text = el.camera;
		propImagePathInput.label.text = el.imagePath != null ? el.imagePath : "";
		propCharAnimInput.label.text = (el.extra != null && el.extra.anim != null) ? el.extra.anim : "idle";
		propCharPlayerCheck.checked = (el.extra != null && el.extra.isPlayer == true);

		var alignIdx = ["left", "center", "right"].indexOf(el.alignment);
		if (alignIdx >= 0) propAlignDropDown.setOption(alignIdx);
		_refreshParentDropdown(el.parentUid);
	}

	function _refreshParentDropdown(selectedParentUid:String):Void {
		var labels:Array<String> = ["(Root)"];
		_parentUidOptions = [null];
		var selectedOption = 0;
		if (curSelected != null) {
			for (candidate in UIBuilderData.getValidParentCandidates(project, curSelected.uid)) {
				labels.push(candidate.id);
				_parentUidOptions.push(candidate.uid);
				if (candidate.uid == selectedParentUid)
					selectedOption = labels.length - 1;
			}
			propParentDropDown.visible = true;
		} else {
			propParentDropDown.visible = false;
		}
		propParentDropDown.items = UIDropDown.getItems(labels);
		propParentDropDown.options = labels;
		propParentDropDown.index = selectedOption;
		propParentDropDown.label.text = labels[selectedOption];
	}

	function _refreshHierarchy() {
		layerGroup.clear();
		layerButtons = [];

		var winX = hierarchyWindow.x;
		var startY:Float = hierarchyWindow.y + 35;
		var maxDisplay = Std.int((hierarchyWindow.bHeight - 75) / 26);
		var treeOrder = UIBuilderData.getHierarchyOrder(project);
		var count = Std.int(Math.min(treeOrder.length, maxDisplay));
		for (i in 0...count) {
			var node = treeOrder[i];
			var el = node.element;
			var elementUid = el.uid;
			var elementIndex = project.elements.indexOf(el);
			var isSel = (elementIndex == selectedIndex);
			var indent = "";
			for (_ in 0...node.depth) indent += "  ";
			var btn = new UIButton(winX + 10, startY, (isSel ? "▶ " : "  ") + indent + el.id + " (" + el.type + ")", function() {
				selectedIndex = -1;
				for (index in 0...project.elements.length)
					if (project.elements[index].uid == elementUid) selectedIndex = index;
				_syncProperties();
				_refreshHierarchy();
			}, 210, 24);
			if (isSel) btn.color = 0xFF00FFC8;
			layerGroup.add(btn);
			layerButtons.push(btn);
			startY += 26;
		}
	}

	// ── Ações e Edição ─────────────────────────────────────────
	function _spawnElement(type:UIElementType) {
		var count = project.elements.length + 1;
		var id = type + "_" + count;
		var el = UIBuilderData.createElement(type, id, 0, 0);
		var position = UIBuilderData.getCenteredElementPosition(project, el.width, el.height);
		el.x = position.x;
		el.y = position.y;
		project.elements.push(el);
		selectedIndex = project.elements.length - 1;

		_recordHistory();
		_refreshCanvas();
		_refreshHierarchy();
		_syncProperties();
	}

	function _deleteSelected() {
		if (selectedIndex >= 0 && selectedIndex < project.elements.length) {
			var deletedUid = curSelected.uid;
			var newParentUid = curSelected.parentUid;
			for (element in project.elements)
				if (element.parentUid == deletedUid) element.parentUid = newParentUid;
			project.elements.splice(selectedIndex, 1);
			selectedIndex = Std.int(Math.min(selectedIndex, project.elements.length - 1));
			_recordHistory();
			_refreshCanvas();
			_refreshHierarchy();
			_syncProperties();
		}
	}

	function _duplicateSelected() {
		if (curSelected != null) {
			var clone = UIBuilderData.createElement(curSelected.type, curSelected.id + "_copy", curSelected.x + 20, curSelected.y + 20, curSelected.width, curSelected.height);
			clone.text = curSelected.text;
			clone.color = curSelected.color;
			clone.bgColor = curSelected.bgColor;
			clone.borderColor = curSelected.borderColor;
			clone.fontSize = curSelected.fontSize;
			clone.alpha = curSelected.alpha;
			clone.camera = curSelected.camera;
			clone.alignment = curSelected.alignment;
			clone.imagePath = curSelected.imagePath;
			clone.parentUid = curSelected.parentUid;
			clone.extra = Reflect.copy(curSelected.extra);

			project.elements.push(clone);
			selectedIndex = project.elements.length - 1;
			_recordHistory();
			_refreshCanvas();
			_refreshHierarchy();
			_syncProperties();
		}
	}

	function _moveLayer(dir:Int) {
		if (selectedIndex < 0) return;
		var target = selectedIndex + dir;
		if (target >= 0 && target < project.elements.length) {
			var temp = project.elements[selectedIndex];
			project.elements[selectedIndex] = project.elements[target];
			project.elements[target] = temp;
			selectedIndex = target;
			_recordHistory();
			_refreshCanvas();
			_refreshHierarchy();
		}
	}

	// ── Presets ────────────────────────────────────────────────
	function _loadNVETemplate() {
		project = UIBuilderData.createNVEMainMenuProject();
		selectedIndex = project.elements.length > 0 ? 0 : -1;
		_recordHistory();
		_refreshCanvasSurface();
		_fitCanvasToView();
		_refreshCanvas();
		_refreshHierarchy();
		_syncProperties();
	}

	function _addPresetStatsHUD() {
		var p = UIBuilderData.createElement(PANEL, "statsPanel", 20, 20, 280, 160);
		p.text = "STATS";
		var l1 = UIBuilderData.createElement(TEXT, "txtScore", 35, 60, 240, 24);
		l1.text = "Score: 0";
		var l2 = UIBuilderData.createElement(TEXT, "txtAccuracy", 35, 90, 240, 24);
		l2.text = "Accuracy: 100%";
		var bar = UIBuilderData.createElement(PROGRESS_BAR, "healthBar", 35, 130, 250, 16);
		bar.text = "HEALTH";

		project.elements.push(p);
		project.elements.push(l1);
		project.elements.push(l2);
		project.elements.push(bar);
		selectedIndex = project.elements.length - 1;

		_recordHistory();
		_refreshCanvas();
		_refreshHierarchy();
		_syncProperties();
	}

	function _addPresetLoadingScreen() {
		var bg = UIBuilderData.createElement(PANEL, "loadBg", 0, 0, 1280, 720);
		bg.bgColor = 0xFF000000;
		bg.text = "";
		var title = UIBuilderData.createElement(TEXT, "txtLoading", 0, 300, 1280, 48);
		title.text = "LOADING...";
		title.alignment = "center";
		title.color = 0xFF00FFC8;
		var bar = UIBuilderData.createElement(PROGRESS_BAR, "loadBar", 340, 440, 600, 20);
		bar.text = "0%";
		bar.color = 0xFF90FF90;

		project.elements.push(bg);
		project.elements.push(title);
		project.elements.push(bar);
		selectedIndex = project.elements.length - 1;

		_recordHistory();
		_refreshCanvas();
		_refreshHierarchy();
		_syncProperties();
	}

	function _addPresetDialogueBox() {
		var box = UIBuilderData.createElement(PANEL, "dialogueBox", 100, 480, 1080, 200);
		box.text = "SPEAKER NAME";
		box.bgColor = 0xFF0D0D1A;
		box.borderColor = 0xFF00FFC8;
		var text = UIBuilderData.createElement(TEXT, "dialogueText", 130, 530, 1020, 120);
		text.text = "Dialogue text goes here...";
		text.fontSize = 24;

		project.elements.push(box);
		project.elements.push(text);
		selectedIndex = project.elements.length - 1;

		_recordHistory();
		_refreshCanvas();
		_refreshHierarchy();
		_syncProperties();
	}

	// ── Histórico ──────────────────────────────────────────────
	function _recordHistory() {
		var snap = UIBuilderData.serialize(project);
		if (undoStack.length == 0 || undoStack[undoStack.length - 1] != snap) {
			undoStack.push(snap);
			if (undoStack.length > maxHistory) undoStack.shift();
			redoStack = [];
		}
	}

	function _undo() {
		if (undoStack.length > 1) {
			var previousCanvasWidth = project.canvasWidth;
			var previousCanvasHeight = project.canvasHeight;
			redoStack.push(undoStack.pop());
			project = UIBuilderData.deserialize(undoStack[undoStack.length - 1]);
			selectedIndex = Std.int(Math.min(selectedIndex, project.elements.length - 1));
			_refreshCanvasSurfaceIfDimensionsChanged(previousCanvasWidth, previousCanvasHeight);
			_refreshCanvas();
			_refreshHierarchy();
			_syncProperties();
		}
	}

	function _redo() {
		if (redoStack.length > 0) {
			var previousCanvasWidth = project.canvasWidth;
			var previousCanvasHeight = project.canvasHeight;
			var snap = redoStack.pop();
			undoStack.push(snap);
			project = UIBuilderData.deserialize(snap);
			selectedIndex = Std.int(Math.min(selectedIndex, project.elements.length - 1));
			_refreshCanvasSurfaceIfDimensionsChanged(previousCanvasWidth, previousCanvasHeight);
			_refreshCanvas();
			_refreshHierarchy();
			_syncProperties();
		}
	}

	// ── Arquivos e Exportação ──────────────────────────────────
	function _saveJsonDialog() {
		var json = UIBuilderData.serialize(project);
		openSubState(new SaveSubstate(json, {
			defaultSaveFile: '${project.name}.json'
		}));
	}

	function _exportHScriptDialog() {
		var code = UIBuilderData.generateHScript(project);
		openSubState(new SaveSubstate(code, {
			defaultSaveFile: '${project.name}UI.hx'
		}));
	}

	function _exportLuaDialog() {
		var code = UIBuilderData.generatePsychLua(project);
		openSubState(new SaveSubstate(code, {
			defaultSaveFile: '${project.name}.lua'
		}));
	}

	function _exportXMLDialog() {
		var xml = UIBuilderData.generateXML(project);
		openSubState(new SaveSubstate(xml, {
			defaultSaveFile: '${project.name}.xml'
		}));
	}

	function _openJsonDialog() {
		#if sys
		var fileRef = new FileReference();
		fileRef.addEventListener(openfl.events.Event.SELECT, function(_) {
			fileRef.load();
		});
		fileRef.addEventListener(openfl.events.Event.COMPLETE, function(_) {
			var content:String = fileRef.data.toString();
			var loadedProject:UIProjectData;
			try {
				loadedProject = UIBuilderData.deserialize(content);
			} catch (e:Dynamic) {
				openSubState(new UIWarningSubstate("Could not open UI project", 'The selected file could not be loaded as a UI project. Your current project was kept.\n\n${Std.string(e)}', [
					{label: "OK", onClick: function(_) {}}
				]));
				return;
			}

			project = loadedProject;
			selectedIndex = -1;
			_recordHistory();
			_refreshCanvasSurface();
			_fitCanvasToView();
			_refreshCanvas();
			_refreshHierarchy();
			_syncProperties();
		});
		fileRef.browse([new FileFilter("UI Project JSON", "*.json")]);
		#end
	}

	// ── Utilitários Gráficos ───────────────────────────────────
	function _drawGrid() {
		var g = gridSpr.graphic.bitmap;
		var step = Std.int(Math.max(1, gridSize));
		var columns = Std.int((project.canvasWidth - 1) / step) + 1;
		var rows = Std.int((project.canvasHeight - 1) / step) + 1;
		for (x in 0...columns) {
			for (y in 0...rows) {
				g.setPixel32(x * step, y * step, 0x33444466);
			}
		}
	}

	function _drawSelectionBorder(spr:FlxSprite, w:Int, h:Int) {
		var g = spr.graphic.bitmap;
		var color = 0xFF00FFC8;
		for (x in 0...w) {
			if ((x % 6) < 4) {
				g.setPixel32(x, 0, color);
				g.setPixel32(x, h - 1, color);
			}
		}
		for (y in 0...h) {
			if ((y % 6) < 4) {
				g.setPixel32(0, y, color);
				g.setPixel32(w - 1, y, color);
			}
		}
	}
}
