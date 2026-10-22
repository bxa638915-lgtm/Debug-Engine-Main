import json
from pathlib import Path
import pytest

def test_uihx_files_exist_and_valid():
    ui_dir = Path("assets/data/ui")
    assert ui_dir.is_dir(), "Diretório assets/data/ui não encontrado."

    uihx_files = list(ui_dir.glob("*.uihx"))
    assert len(uihx_files) >= 2, f"Esperado ao menos 2 arquivos .uihx, encontrados: {len(uihx_files)}"

    for file_path in uihx_files:
        with open(file_path, "r", encoding="utf-8") as f:
            data = json.load(f)

        assert "formatVersion" in data, f"formatVersion ausente em {file_path.name}"
        assert "screenName" in data, f"screenName ausente em {file_path.name}"
        assert "screenType" in data, f"screenType ausente em {file_path.name}"
        assert "canvasWidth" in data and data["canvasWidth"] > 0
        assert "canvasHeight" in data and data["canvasHeight"] > 0
        assert "nodes" in data and isinstance(data["nodes"], list)

        for node in data["nodes"]:
            assert "id" in node, f"Nó sem 'id' em {file_path.name}"
            assert "type" in node, f"Nó sem 'type' em {file_path.name}"
            assert "x" in node and "y" in node
            assert "width" in node and "height" in node

def test_mainmenu_uihx_contract():
    mainmenu_path = Path("assets/data/ui/mainmenu.uihx")
    assert mainmenu_path.exists()

    with open(mainmenu_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    assert data["screenType"] == "state"
    assert data["targetStateClass"] == "MainMenuState"
    node_ids = [n["id"] for n in data["nodes"]]
    assert "btnStoryMode" in node_ids
    assert "btnFreeplay" in node_ids
    assert "btnOptions" in node_ids

def test_pausesubstate_uihx_contract():
    pause_path = Path("assets/data/ui/pausesubstate.uihx")
    assert pause_path.exists()

    with open(pause_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    assert data["screenType"] == "substate"
    assert data["targetStateClass"] == "PauseSubState"
    node_ids = [n["id"] for n in data["nodes"]]
    assert "btnResume" in node_ids
    assert "btnRestart" in node_ids
    assert "btnQuit" in node_ids

def test_live_state_capture_contract():
    """Valida o contrato de serializacao e mapeamento do LiveStateHost e UIHXStateBridge."""
    dummy_scraped = [
        {
            "id": "Alphabet_Resume",
            "member": None,
            "sprite": None,
            "typeName": "Alphabet",
            "originalX": 100.0,
            "originalY": 200.0,
            "width": 300.0,
            "height": 70.0
        },
        {
            "id": "FunkinText_Test_Song",
            "member": None,
            "sprite": None,
            "typeName": "FunkinText",
            "originalX": 50.0,
            "originalY": 50.0,
            "width": 200.0,
            "height": 32.0
        }
    ]
    # Simula a estrutura que UIHXStateBridge gera a partir dos dados do LiveStateHost
    screen_def = {
        "formatVersion": 1,
        "screenName": "PauseSubState",
        "screenType": "substate",
        "targetStateClass": "funkin.menus.PauseSubState",
        "canvasWidth": 1280,
        "canvasHeight": 720,
        "defaultCamera": "camOther",
        "nodes": [
            {
                "id": m["id"],
                "type": "image",
                "x": m["originalX"],
                "y": m["originalY"],
                "width": int(m["width"]),
                "height": int(m["height"]),
                "visible": True,
                "active": True
            } for m in dummy_scraped
        ]
    }
    assert screen_def["targetStateClass"] == "funkin.menus.PauseSubState"
    assert len(screen_def["nodes"]) == 2
    assert screen_def["nodes"][0]["id"] == "Alphabet_Resume"
    assert screen_def["nodes"][1]["id"] == "FunkinText_Test_Song"

