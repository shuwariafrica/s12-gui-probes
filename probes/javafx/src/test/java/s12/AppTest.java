package s12;

import static org.junit.jupiter.api.Assertions.assertEquals;

import javafx.scene.Scene;
import javafx.scene.control.Label;
import javafx.stage.Stage;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.testfx.api.FxRobot;
import org.testfx.framework.junit5.ApplicationExtension;
import org.testfx.framework.junit5.Start;

@ExtendWith(ApplicationExtension.class)
final class AppTest {
  @Start
  void start(Stage stage) {
    stage.setTitle("s12-javafx");
    stage.setScene(new Scene(App.root(), 400, 200));
    stage.show();
  }

  @Test
  void typedTextReachesTheLabel(FxRobot robot) {
    robot.clickOn("#name").write("hello");
    robot.clickOn("#go");
    assertEquals("got: hello", robot.lookup("#out").queryAs(Label.class).getText());
    System.out.println("glass platform: " + System.getProperty("glass.platform", "the OS default")
        + "; os " + System.getProperty("os.name") + "; screen " + javafx.stage.Screen.getPrimary().getBounds());
  }
}
