import java.awt.Color;
import java.awt.Dimension;
import java.awt.Font;
import java.awt.Graphics;
import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.awt.event.MouseEvent;
import java.awt.event.MouseListener;
import java.util.TreeMap;
import javax.swing.JMenuItem;
import javax.swing.JPanel;
import javax.swing.JPopupMenu;

public class busGeneratorDraw extends JPanel implements MouseListener, ActionListener {
  private busGeneratorFrame parent;
  private busGeneratorObject selectedItem = null;
  public static String DeleteAction = "Delete Item";
  public static String ModifyAction = "Modify Item";
  public static String AddAction = "Add new Item";
  public static String AddMasterAction = "Add a bus master";
  public static String AddSlaveAction = "Add a bus slave";

  busGeneratorDraw(busGeneratorFrame parent) {
    this.parent = parent;
    this.addMouseListener(this);
  }

  @Override
  public void paint(Graphics g) {
    g.setFont(new Font(Font.MONOSPACED, Font.PLAIN, 12));
    final var myBounds = super.getBounds();
    g.clearRect(0, 0, myBounds.width, myBounds.height);
    final var components = parent.getBusComponents();
    final var masters = new TreeMap<Integer, busGeneratorObject>();
    final var slaves = new TreeMap<Long, busGeneratorObject>();
    var height = 0;
    var width = 0;
    var maxMasterWidth = 0;
    var ypos = 10;
    for (var comp : components) {
      var compBounds = comp.getBounds(g);
      if (comp.isSlaveComponent()) {
        var key = comp.getBaseAddress();
        while (slaves.containsKey(key)) {
          key++;
        }
        slaves.put(key, comp);
      } else {
        maxMasterWidth = Math.max(maxMasterWidth, compBounds.width);
        masters.put(comp.getMasterPriority(), comp);
      }
    }
    var ymin = 0;
    var ymax = 0;
    final var xPosBus = maxMasterWidth + 10 + busGeneratorObject.BUS_CON_WIDTH;
    for (var masterEntry : masters.entrySet()) {
      final var master = masterEntry.getValue();
      final var bounds = master.getBounds(g);
      width = Math.max(width, xPosBus + 10 );
      master.paint(g, xPosBus - busGeneratorObject.BUS_CON_WIDTH - bounds.width, ypos);
      if (ymin == 0) {
        ymin = ypos + bounds.height / 2;
      }
      ymax = Math.max(ymax, ypos + bounds.height / 2);
      ypos += bounds.height + 10 ;
    }
    height = Math.max(height, ypos);
    ypos = 10;
    for (var slaveEntry : slaves.entrySet()) {
      final var slave = slaveEntry.getValue();
      final var bounds = slave.getBounds(g);
      slave.paint(g, xPosBus + busGeneratorObject.BUS_CON_WIDTH , ypos);
      if (ymin == 0) {
        ymin = ypos + bounds.height / 2;
      }
      width = Math.max(width, xPosBus + busGeneratorObject.BUS_CON_WIDTH + bounds.width + 10);
      ymax = Math.max(ymax, ypos + bounds.height / 2);
      ypos += bounds.height + 10;
    }
    height = Math.max(height, ypos);
    if (ymin < ymax) {
      g.setColor(Color.BLACK);
      g.fillRect(xPosBus-2, ymin - 2, 4, (ymax-ymin) + 4);
    }
    this.setPreferredSize(new Dimension(width, height));
    this.revalidate();
  }

  private busGeneratorObject selectedObject(MouseEvent mouse) {
    for (var comp : parent.getBusComponents()) {
      if (comp.inside(mouse.getX(), mouse.getY())) {
        return comp;
      }
    }
    return null;
  }

  @Override
  public void mouseClicked(MouseEvent e) {
    if (selectedItem != null) {
      final var popup = new JPopupMenu();
      final var Delete = new JMenuItem(DeleteAction);
      Delete.addActionListener(this);
      popup.add(Delete);
      final var Modify = new JMenuItem(ModifyAction);
      Modify.addActionListener(this);
      popup.add(Modify);
      popup.show(this, e.getX(), e.getY());
    } else {
      final var popup = new JPopupMenu();
      var item = new JMenuItem(AddMasterAction);
      item.addActionListener(this);
      popup.add(item);
      item = new JMenuItem(AddSlaveAction);
      item.addActionListener(this);
      popup.add(item);
      popup.show(this, e.getX(), e.getY());
    }
  }

  @Override
  public void mousePressed(MouseEvent e) {
    final var comp = selectedObject(e);
    if (comp != null) {
      if (selectedItem != null) {
        selectedItem.setHighlighted(false);
      }
      selectedItem = comp;
      selectedItem.setHighlighted(true);
      repaint();
    } else {
      if (selectedItem != null) {
        selectedItem.setHighlighted(false);
        repaint();
        selectedItem = null;
      }
    }
  }

  @Override
  public void mouseReleased(MouseEvent e) {
  }

  @Override
  public void mouseEntered(MouseEvent e) {
  }

  @Override
  public void mouseExited(MouseEvent e) {
  }

  @Override
  public void actionPerformed(ActionEvent e) {
    if (e.getActionCommand().equals(DeleteAction)) {
      if (selectedItem != null) {
        parent.actionPerformed(new ActionEvent(selectedItem, 0, DeleteAction));
        selectedItem = null;
      }
    }
    if (e.getActionCommand().equals(ModifyAction)) {
      if (selectedItem != null) {
        if (selectedItem.arePropertiesChanged(parent, false)) {
          parent.actionPerformed(new ActionEvent(selectedItem, 0, busGeneratorMemmap.memAddressChanged));
        }
      }
    }
    if (e.getActionCommand().equals(AddMasterAction)) {
      final var newMaster = new busGeneratorObject();
      if (newMaster != null) {
        if (newMaster.arePropertiesChanged(parent, true)) {
          parent.actionPerformed(new ActionEvent(newMaster, 0, AddAction));
        }
      }
    }
    if (e.getActionCommand().equals(AddSlaveAction)) {
      final var newSlave = new busGeneratorObject(0,2,false);
      if (newSlave != null) {
        if (newSlave.arePropertiesChanged(parent, true)) {
          parent.actionPerformed(new ActionEvent(newSlave, 0, AddAction));
        }
      }
    }
  }
}
