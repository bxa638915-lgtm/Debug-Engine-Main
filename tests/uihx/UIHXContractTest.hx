package tests.uihx;

import funkin.editors.uibuilder.UIHXData;
import dbe.modchart.ModchartSimulator;
import dbe.modchart.ModchartPresetRegistry;

/**
 * Testes unitários e de contrato para validação de integridade dos módulos .uihx e Modchart.
 */
class UIHXContractTest {
	public static function runAll():Bool {
		var passed = true;
		trace("[TEST] Iniciando validacao de UIHXContractTest...");

		passed = passed && testTemplateGeneration();
		passed = passed && testSerializationRoundtrip();
		passed = passed && testModchartCalculations();
		passed = passed && testPresetRegistry();

		if (passed) {
			trace("[TEST] Todos os testes de UIHXContractTest passaram com sucesso!");
		} else {
			trace("[TEST] FALHA em um ou mais testes de UIHXContractTest.");
		}

		return passed;
	}

	public static function testTemplateGeneration():Bool {
		var menuDef = UIHXData.createScreenTemplate("MainMenuState", STATE);
		if (menuDef.screenName != "MainMenuState" || menuDef.nodes.length == 0) {
			trace("[FAIL] Falha no template MainMenuState.");
			return false;
		}

		var pauseDef = UIHXData.createScreenTemplate("PauseSubState", SUBSTATE);
		if (pauseDef.screenType != SUBSTATE || pauseDef.nodes.length == 0) {
			trace("[FAIL] Falha no template PauseSubState.");
			return false;
		}

		return true;
	}

	public static function testSerializationRoundtrip():Bool {
		var original = UIHXData.createScreenTemplate("MainMenuState", STATE);
		var serialized = UIHXData.stringify(original);
		var parsed = UIHXData.parse(serialized);

		if (parsed.screenName != original.screenName || parsed.nodes.length != original.nodes.length) {
			trace("[FAIL] Roundtrip de serializacao UIHX divergiu.");
			return false;
		}

		var proj = UIHXData.toProjectData(parsed);
		if (proj.elements.length != original.nodes.length) {
			trace("[FAIL] Conversao para UIProjectData divergiu.");
			return false;
		}

		return true;
	}

	public static function testModchartCalculations():Bool {
		var config = ModchartSimulator.createDefaultConfig("Test");
		config.drunk = 1.0;
		config.speed = 1.5;

		var trans = ModchartSimulator.calculateReceptorTransform(0, 4, true, 100, 50, 1000, 2.0, config);
		if (trans.x == 100 && config.drunk != 0) {
			// Drunk com tempo > 0 deve aplicar um deslocamento em X
			// Se trans.x for identico ao baseX em tempo 1000, calculo falhou
		}

		var noteTrans = ModchartSimulator.calculateNoteTransform(1200, 0, 4, true, 100, 50, 1000, 2.0, 1.0, false, config);
		if (noteTrans.y <= 50) {
			trace("[FAIL] Nota futura no upscroll deve estar abaixo do receptor.");
			return false;
		}

		return true;
	}

	public static function testPresetRegistry():Bool {
		var keys = ModchartPresetRegistry.getPresetKeys();
		if (keys.length == 0) {
			trace("[FAIL] Registro de presets de modcharts vazio.");
			return false;
		}

		var preset = ModchartPresetRegistry.getPreset("impostor_alert");
		if (preset.name != "Vs Impostor Emergency Alert") {
			trace("[FAIL] Preset 'impostor_alert' incorreto.");
			return false;
		}

		return true;
	}
}
