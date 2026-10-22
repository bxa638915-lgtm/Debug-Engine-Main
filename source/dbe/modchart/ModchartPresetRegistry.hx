package dbe.modchart;

import dbe.modchart.ModchartSimulator.ModchartConfig;

/**
 * Registro e biblioteca de presets de modcharts pré-programados para o Charter e Mods.
 */
class ModchartPresetRegistry {
	public static var presets:Map<String, ModchartConfig> = [
		"impostor_alert" => {
			name: "Vs Impostor Emergency Alert",
			drunk: 0.65,
			tipsy: 0.8,
			bumpy: 0.4,
			wave: 0.3,
			speed: 1.8,
			beatZoom: 0.7,
			invert: 0.2,
			flip: 0.0,
			steer: 0.3,
			tornado: 0.0,
			spiral: 0.0,
			pitch: 0.0,
			roll: 12.0,
			scaleX: 1.0,
			scaleY: 1.0,
			alpha: 1.0
		},
		"zero_gravity" => {
			name: "Zero Gravity Drift",
			drunk: 0.45,
			tipsy: 0.5,
			bumpy: 0.0,
			wave: 0.9,
			speed: 0.8,
			beatZoom: 0.2,
			invert: 0.0,
			flip: 0.0,
			steer: 0.15,
			tornado: 0.0,
			spiral: 0.35,
			pitch: 0.0,
			roll: 5.0,
			scaleX: 1.05,
			scaleY: 1.05,
			alpha: 1.0
		},
		"black_hole_spiral" => {
			name: "Black Hole Spiral",
			drunk: 0.3,
			tipsy: 0.3,
			bumpy: 0.6,
			wave: 0.0,
			speed: 2.2,
			beatZoom: 0.5,
			invert: 0.0,
			flip: 0.0,
			steer: 0.0,
			tornado: 1.1,
			spiral: 1.3,
			pitch: 0.0,
			roll: 25.0,
			scaleX: 0.9,
			scaleY: 0.9,
			alpha: 0.95
		},
		"double_helix" => {
			name: "Double Helix Vortex",
			drunk: 0.9,
			tipsy: 0.7,
			bumpy: 0.2,
			wave: 0.8,
			speed: 1.4,
			beatZoom: 0.3,
			invert: 0.5,
			flip: 0.0,
			steer: 0.2,
			tornado: 0.4,
			spiral: 0.0,
			pitch: 0.0,
			roll: 0.0,
			scaleX: 1.0,
			scaleY: 1.0,
			alpha: 1.0
		},
		"quantum_split" => {
			name: "Quantum Split",
			drunk: 0.2,
			tipsy: 0.3,
			bumpy: 0.0,
			wave: 0.4,
			speed: 1.2,
			beatZoom: 0.4,
			invert: 1.0,
			flip: 0.8,
			steer: 0.0,
			tornado: 0.0,
			spiral: 0.0,
			pitch: 0.0,
			roll: 0.0,
			scaleX: 1.0,
			scaleY: 1.0,
			alpha: 1.0
		},
		"pendulum_swing" => {
			name: "Pendulum Swing",
			drunk: 0.8,
			tipsy: 0.2,
			bumpy: 0.0,
			wave: 0.5,
			speed: 1.0,
			beatZoom: 0.25,
			invert: 0.0,
			flip: 0.0,
			steer: 0.75,
			tornado: 0.0,
			spiral: 0.0,
			pitch: 0.0,
			roll: 15.0,
			scaleX: 1.0,
			scaleY: 1.0,
			alpha: 1.0
		},
		"perspective_warp" => {
			name: "Perspective Warp 3D",
			drunk: 0.2,
			tipsy: 0.2,
			bumpy: 0.8,
			wave: 0.3,
			speed: 1.5,
			beatZoom: 0.6,
			invert: 0.0,
			flip: 0.0,
			steer: 0.4,
			tornado: 0.0,
			spiral: 0.0,
			pitch: 35.0,
			roll: 18.0,
			scaleX: 1.15,
			scaleY: 0.85,
			alpha: 1.0
		},
		"classic_drunk_tipsy" => {
			name: "Classic Drunk & Tipsy",
			drunk: 1.0,
			tipsy: 1.0,
			bumpy: 0.0,
			wave: 0.0,
			speed: 1.0,
			beatZoom: 0.0,
			invert: 0.0,
			flip: 0.0,
			steer: 0.0,
			tornado: 0.0,
			spiral: 0.0,
			pitch: 0.0,
			roll: 0.0,
			scaleX: 1.0,
			scaleY: 1.0,
			alpha: 1.0
		}
	];

	public static function getPreset(id:String):ModchartConfig {
		if (presets.exists(id)) {
			return Reflect.copy(presets.get(id));
		}
		return ModchartSimulator.createDefaultConfig("Custom");
	}

	public static function getPresetKeys():Array<String> {
		var keys = [];
		for (k in presets.keys()) keys.push(k);
		return keys;
	}
}
