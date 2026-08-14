import javax.swing.JMenuBar;
import javax.swing.JMenuItem;
import javax.swing.JMenu;
import java.awt.event.ActionListener;

public class busGeneratorMenu extends JMenuBar {
  
  public static String fileExitAction = "exit";
  public static String fileSaveAction = "save";
  public static String fileSaveAsAction = "save as";
  public static String fileLoadAction = "load";
  public static String fileExportTikZ = "export TikZ";
  public static String fileExportSVG = "export SVG";
  public static String memMapRenumberAll = "renumber all";
  public static String memMapRenumberOverlap = "fix overlap";
  public static String memMapLatex = "export latex table";
  public static String generateShared = "shared bus";
  public static String generateCrossbar = "crossbar bus";
  public static String generateAll = "project bundle";
  private JMenu fileMenu = new JMenu("File");
  private JMenuItem fileExit = new JMenuItem(fileExitAction);
  private JMenuItem fileSave = new JMenuItem(fileSaveAction);
  private JMenuItem fileSaveAs = new JMenuItem(fileSaveAsAction);
  private JMenuItem fileLoad = new JMenuItem(fileLoadAction);
  private JMenuItem fileTikZExport = new JMenuItem(fileExportTikZ);
  private JMenuItem fileSVGExport = new JMenuItem(fileExportSVG);
  private JMenu memMap = new JMenu("Memory map");
  private JMenuItem memRenAll = new JMenuItem(memMapRenumberAll);
  private JMenuItem memRnOverlap = new JMenuItem(memMapRenumberOverlap);
  private JMenuItem memLatex = new JMenuItem(memMapLatex);
  private JMenu generate = new JMenu("Generate");
  private JMenuItem shared = new JMenuItem(generateShared); 
  private JMenuItem crossbar = new JMenuItem(generateCrossbar);
  private JMenuItem bundle = new JMenuItem(generateAll);

  busGeneratorMenu() {
    this.add(fileMenu);
    fileMenu.setMnemonic('F');
    fileMenu.add(fileSave);
    fileSave.setMnemonic('s');
    fileMenu.add(fileSaveAs);
    fileSaveAs.setMnemonic('a');
    fileMenu.add(fileLoad);
    fileMenu.addSeparator();
    fileLoad.setMnemonic('l');
    fileMenu.add(fileTikZExport);
    fileTikZExport.setMnemonic('T');
    fileMenu.add(fileSVGExport);
    fileSVGExport.setMnemonic('S');
    fileMenu.addSeparator();
    fileMenu.add(fileExit);
    fileExit.setMnemonic('x');
    this.add(memMap);
    memMap.setMnemonic('M');
    memMap.add(memRenAll);
    memMap.add(memRnOverlap);
    memMap.addSeparator();
    memMap.add(memLatex);
    memRenAll.setMnemonic('a');
    memRnOverlap.setMnemonic('o');
    memLatex.setMnemonic('l');
    this.add(generate);
    generate.setMnemonic('G');
    generate.add(shared);
    shared.setMnemonic('s');
    generate.add(crossbar);
    crossbar.setMnemonic('c');
    generate.addSeparator();
    generate.add(bundle);
    bundle.setMnemonic('b');
  }

  public void addActionListener(ActionListener listener) {
    fileExit.addActionListener(listener);
    fileSave.addActionListener(listener);
    fileSaveAs.addActionListener(listener);
    memRenAll.addActionListener(listener);
    memRnOverlap.addActionListener(listener);
    memLatex.addActionListener(listener);
    fileLoad.addActionListener(listener);
    shared.addActionListener(listener);
    crossbar.addActionListener(listener);
    fileTikZExport.addActionListener(listener);
    fileSVGExport.addActionListener(listener);
    bundle.addActionListener(listener);
  }
}
