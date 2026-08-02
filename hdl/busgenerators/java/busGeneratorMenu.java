import javax.swing.JMenuBar;
import javax.swing.JMenuItem;
import javax.swing.JMenu;
import java.awt.event.ActionListener;

public class busGeneratorMenu extends JMenuBar {
  
  public static String fileExitAction = "exit";
  public static String fileSaveAction = "save";
  public static String fileSaveAsAction = "save as";
  public static String fileLoadAction = "load";
  public static String memMapRenumberAll = "renumber all";
  public static String memMapRenumberOverlap = "fix overlap";
  public static String generateShared = "shared bus";
  private JMenu fileMenu = new JMenu("File");
  private JMenuItem fileExit = new JMenuItem(fileExitAction);
  private JMenuItem fileSave = new JMenuItem(fileSaveAction);
  private JMenuItem fileSaveAs = new JMenuItem(fileSaveAsAction);
  private JMenuItem fileLoad = new JMenuItem(fileLoadAction);
  private JMenu memMap = new JMenu("Memory map");
  private JMenuItem memRenAll = new JMenuItem(memMapRenumberAll);
  private JMenuItem memRnOverlap = new JMenuItem(memMapRenumberOverlap);
  private JMenu generate = new JMenu("Generate");
  private JMenuItem shared = new JMenuItem(generateShared); 

  busGeneratorMenu() {
    this.add(fileMenu);
    fileMenu.setMnemonic('F');
    fileMenu.add(fileSave);
    fileSave.setMnemonic('s');
    fileMenu.add(fileSaveAs);
    fileSaveAs.setMnemonic('a');
    fileMenu.add(fileLoad);
    fileLoad.setMnemonic('l');
    fileMenu.add(fileExit);
    fileExit.setMnemonic('x');
    this.add(memMap);
    memMap.setMnemonic('M');
    memMap.add(memRenAll);
    memMap.add(memRnOverlap);
    memRenAll.setMnemonic('a');
    memRnOverlap.setMnemonic('o');
    this.add(generate);
    generate.setMnemonic('G');
    generate.add(shared);
    shared.setMnemonic('s');
  }

  public void addActionListener(ActionListener listener) {
    fileExit.addActionListener(listener);
    fileSave.addActionListener(listener);
    fileSaveAs.addActionListener(listener);
    memRenAll.addActionListener(listener);
    memRnOverlap.addActionListener(listener);
    fileLoad.addActionListener(listener);
    shared.addActionListener(listener);
  }
}
