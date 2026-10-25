package s12;

import javafx.application.Application;
import javafx.scene.Scene;
import javafx.scene.control.Button;
import javafx.scene.control.Label;
import javafx.scene.control.TextField;
import javafx.scene.layout.VBox;
import javafx.stage.Stage;

/** A window whose label answers what is typed into its field when its button is pressed. */
public final class App extends Application {
  static VBox root() {
    TextField name = new TextField();
    name.setId("name");
    Button go = new Button("Send");
    go.setId("go");
    Label out = new Label("waiting");
    out.setId("out");
    go.setOnAction(e -> out.setText("got: " + name.getText()));
    return new VBox(name, go, out);
  }

  @Override
  public void start(Stage stage) {
    stage.setTitle("s12-javafx");
    stage.setScene(new Scene(root(), 400, 200));
    stage.show();
  }
}
