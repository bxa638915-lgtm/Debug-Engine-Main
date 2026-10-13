import kade.hex.chart.Scene;

class ModchartChannelTest {
    static function main() {
        var s = new Scene("test_scene", 1);
        var idGlitch = s.channel("screen.glitch", 0.5);
        var idAngle = s.channel("eyes.angle", 1.57);

        s.watch([idGlitch, idAngle]);
        var values = s.readWatched();

        if (values.length != 2 || values[0] != 0.5 || values[1] != 1.57) {
            Sys.println("ModchartChannelTest: FAIL initial values");
            Sys.exit(1);
        }

        s.setChannel("screen.glitch", 1.0);
        values = s.readWatched();

        if (values[0] != 1.0) {
            Sys.println("ModchartChannelTest: FAIL updated values");
            Sys.exit(1);
        }

        Sys.println("ModchartChannelTest: PASS");
    }
}
