import java.awt.Color;
import java.awt.Dimension;
import java.awt.Graphics;
import java.awt.GridBagConstraints;
import java.awt.GridBagLayout;
import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.util.TreeMap;

import javax.swing.JButton;
import javax.swing.JCheckBox;
import javax.swing.JComboBox;
import javax.swing.JDialog;
import javax.swing.JLabel;
import javax.swing.JOptionPane;
import javax.swing.JTextField;

import org.w3c.dom.Document;
import org.w3c.dom.Element;

public class busGeneratorObject implements ActionListener {
  private boolean isMaster;
  private long slaveBaseAddress;
  private boolean baseAddressIsFixed;
  private int slaveNrOfUsedAddrBits;
  private int masterPriority = 0;
  private int W_ADDR = 32;
  private int W_DATA = 32;
  private String label = "";
  private Dimension myBounds;
  private int myXpos;
  private int myYpos;
  private boolean highlighted = false;
  private boolean acceptChanges = false;
  public static int BUS_CON_WIDTH = 20;

  busGeneratorObject() {
    this.isMaster = true;
    this.slaveBaseAddress = 0;
    this.slaveNrOfUsedAddrBits = 0;
    this.baseAddressIsFixed = false;
  }

  busGeneratorObject(long Base, int AddrSelBits, boolean fixed) {
    this.isMaster = false;
    this.slaveBaseAddress = Base;
    this.slaveNrOfUsedAddrBits = AddrSelBits;
    this.baseAddressIsFixed = fixed;
  }

  public int getMasterPriority() {
    return masterPriority;
  }

  public void setMasterPriority(int value) {
    masterPriority = value;
  }

  public boolean isSlaveComponent() {
    return !isMaster;
  }

  public boolean hasFixedBaseAddress() {
    return baseAddressIsFixed;
  }

  public void setNrOfAddressBits(int W_ADDR) {
    this.W_ADDR = W_ADDR;
  }

  public void setNrOfDataBits(int W_DATA) {
    this.W_DATA = W_DATA;
  }

  public int getNrOfAddressBits() {
    return W_ADDR;
  }

  public int getNrOfDataBits() {
    return W_DATA;
  }

  public int getNrOfAddrSelectBits() {
    return W_ADDR - slaveNrOfUsedAddrBits;
  }

  public int getNrOfUsedAddrBits() {
    return slaveNrOfUsedAddrBits;
  }

  public long getBaseAddress() {
    return slaveBaseAddress;
  }

  public void setBaseAddress(long addr) {
    if (baseAddressIsFixed) {
      return;
    }
    slaveBaseAddress = addr;
  }

  public void setName(String name) {
    this.label = name;
  }

  public void setHighlighted(boolean high) {
    this.highlighted = high;
  }

  public String getName() {
    if (!label.isEmpty()) {
      return label;
    }
    return (isMaster) ? "bus master" : "bus slave";
  }

  public static boolean isDataConsistent(busGeneratorObject comp) {
    final var nrOfMaskBits = comp.getNrOfUsedAddrBits();
    final var mask = (1L << nrOfMaskBits) - 1L;
    return (comp.getBaseAddress() & mask) == 0L;
  }

  public boolean isDataConsistent(long addr) {
    final var nrOfMaskBits = getNrOfUsedAddrBits();
    final var mask = (1L << nrOfMaskBits) - 1L;
    return (addr & mask) == 0L;
  }

  public static String getDigit(long value, int digitIndex) {
    final var digitValue = (int)((value >> (digitIndex * 4)) & 15L);
    return String.format("%X", digitValue);
  }

  private static String getAddrHex(int W_ADDR, long value) {
    final var result = new StringBuilder("0x");
    final var nrOfDigits = W_ADDR/4;
    for (var i = nrOfDigits - 1 ; i >= 0; i--) {
      result.append(getDigit(value, i));
    }
    return result.toString();
  }

  public static String getAddressRange(int W_ADDR, long start, long stop) {
    return getAddrHex(W_ADDR, start) + " - " + getAddrHex(W_ADDR, stop);
  }

  public String getAddressRange() {
    if (isMaster) return null;
    final var nrOfMaskBits = slaveNrOfUsedAddrBits;
    final var mask = (1L << nrOfMaskBits) - 1L;
    return getAddressRange(W_ADDR, slaveBaseAddress, slaveBaseAddress + mask);
  }

  public long getEndAddress() {
    final var nrOfMaskBits = slaveNrOfUsedAddrBits;
    final var mask = (1L << nrOfMaskBits) - 1L;
    return slaveBaseAddress + mask;
  }

  public String getSizeString() {
    var size = 1L << slaveNrOfUsedAddrBits;
    if (size < 1024L) {
      return String.format("%s bytes", Long.toUnsignedString(size));
    }
    size /= 1024L;
    if (size < 1024L) {
      return String.format("%s kbytes", Long.toUnsignedString(size));
    }
    size /= 1024L;
    if (size < 1024L) {
      return String.format("%s Mbytes", Long.toUnsignedString(size));
    }
    size /= 1024L;
    return String.format("%s Gbytes", Long.toUnsignedString(size));
  }

  private String getPriorityString() {
    return "Priority: " + Integer.toString(getMasterPriority());
  }

  public Dimension getBounds(Graphics g) {
    final var masterName = (getPriorityString().length() > getName().length()) ? getPriorityString() : getName();
    final var name = (isMaster) ? masterName :
                     (getAddressRange().length() > getName().length()) ? getAddressRange() : getName();
    var width = g.getFontMetrics().stringWidth(name);
    width += 2*g.getFontMetrics().stringWidth(" ");
    width += 10-(width % 10);
    var height = g.getFontMetrics().getHeight();
    height *= 2 + ((isMaster) ? 0 : 2);
    height += 10-(height % 10);
    myBounds = new Dimension(width, height);
    return myBounds;
  }

  public void paint(Graphics g, int xpos, int ypos) {
    myXpos = xpos;
    myYpos = ypos;
    getBounds(g);
    final var charHeight = g.getFontMetrics().getHeight();
    final var masterHighlightColor = new Color(0, 0, 128);
    if (isMaster) {
      g.setColor((highlighted) ? masterHighlightColor : Color.BLUE);
      g.fillRect(xpos, ypos, myBounds.width, myBounds.height);
      g.setColor(Color.BLACK);
      g.drawRect(xpos, ypos, myBounds.width, myBounds.height);
      g.setColor(Color.YELLOW);
      var curYpos = ypos + (myBounds.height / 2) - (charHeight / 2);
      var textWidth = g.getFontMetrics().stringWidth(getName());
      g.drawString(getName(), xpos + (myBounds.width / 2) - (textWidth / 2), curYpos);
      curYpos += charHeight;
      textWidth = g.getFontMetrics().stringWidth(getPriorityString());
      g.drawString(getPriorityString(), xpos + (myBounds.width / 2) - (textWidth / 2), curYpos);
      g.setColor(Color.BLACK);
      final var yMiddle = ypos + myBounds.height / 2;
      final var xStart = xpos + myBounds.width;
      g.fillRect(xStart, yMiddle - 2, BUS_CON_WIDTH, 4);
    } else {
      var curYpos = ypos + charHeight;
      g.setColor((highlighted) ? Color.DARK_GRAY : Color.GRAY);
      g.fillRect(xpos, ypos, myBounds.width, myBounds.height);
      g.setColor(Color.YELLOW);
      var textWidth = g.getFontMetrics().stringWidth(getName());
      g.drawString(getName(), xpos + (myBounds.width / 2) - (textWidth / 2), curYpos + (charHeight / 2));
      curYpos += charHeight;
      textWidth = g.getFontMetrics().stringWidth(getAddressRange());
      g.drawString(getAddressRange(), xpos + (myBounds.width / 2) - (textWidth / 2), curYpos + (charHeight / 2));
      curYpos += charHeight;
      textWidth = g.getFontMetrics().stringWidth(getSizeString());
      g.drawString(getSizeString(), xpos + (myBounds.width / 2) - (textWidth / 2), curYpos + (charHeight / 2));
      g.setColor(Color.BLACK);
      final var yMiddle = ypos + myBounds.height / 2;
      final var xStart = xpos - BUS_CON_WIDTH;
      g.fillRect(xStart, yMiddle - 2, BUS_CON_WIDTH, 4);
    }
  }

  public boolean inside(int xpos, int ypos) {
    if (myBounds == null) {
      return false;
    }
    final var isInXrange = (xpos >= myXpos) && (xpos <= myXpos + myBounds.width);
    final var isInYrange = (ypos >= myYpos) && (ypos <= myYpos + myBounds.height);
    return isInXrange && isInYrange;
  }

  public boolean arePropertiesChanged(busGeneratorFrame parent, boolean firstCreation) {
    final var result = new JDialog(parent, "Modify Items", true);
    final var addr = new JTextField(getAddrHex(W_ADDR, slaveBaseAddress));
    final var addrLock = new JCheckBox();
    final var addrBits = new JTextField(Integer.toString(slaveNrOfUsedAddrBits));
    final var masters = new TreeMap<Integer, busGeneratorObject> ();
    final var masterPriority = new JComboBox<Integer>();
    var priorityChanged = false;
    acceptChanges = false;
    result.setLayout(new GridBagLayout());
    final var c = new GridBagConstraints();
    c.gridx = 0;
    c.gridy = 0;
    c.gridwidth = 1;
    c.gridheight = 1;
    c.weightx = 1;
    c.weighty = 1;
    c.fill = GridBagConstraints.HORIZONTAL;
    var name = String.format("%s name:", isMaster ? "Master" : "Slave");
    result.add(new JLabel(name), c);
    final var newName = new JTextField(getName());
    newName.setSize(80, 1);
    c.gridx++;
    result.add(newName, c);
    c.gridx = 0;
    c.gridy++;
    if (!isMaster) {
      result.add(new JLabel("Base address:"), c);
      c.gridx++;
      result.add(addr, c);
      c.gridx = 0;
      c.gridy++;
      result.add(new JLabel("Base address Locked:"), c);
      c.gridx++;
      addrLock.setSelected(baseAddressIsFixed);
      result.add(addrLock, c);;
      c.gridx = 0;
      c.gridy++;
      result.add(new JLabel("Number of used LSB address bits:"), c);
      c.gridx++;
      result.add(addrBits, c);
      c.gridx = 0;
      c.gridy++;
    } else {
      for (var comp : parent.getBusComponents()) {
        if (!comp.isSlaveComponent()) {
          if (!masters.containsKey(comp.getMasterPriority())) {
            masters.put(comp.getMasterPriority(), comp);
          } else {
            var id = comp.getMasterPriority();
            while (masters.containsKey(id)) {
              id++;
            }
            comp.setMasterPriority(id);
            masters.put(id, comp);
          }
        }
      }
      if (firstCreation) {
        /* search for the first available priority */
        var id = 0;
        while (masters.containsKey(id)) {
          id++;
        }
        setMasterPriority(id);
      }
      result.add(new JLabel("Priority"), c);
      c.gridx++;
      result.add(masterPriority, c);
      for (var idx = 0; idx < 16; idx++) {
        masterPriority.addItem(idx);
      }
      masterPriority.setSelectedIndex(getMasterPriority());
      c.gridx = 0;
      c.gridy++;
    }
    final var ok = new JButton("Ok");
    ok.addActionListener(this);
    ok.addActionListener(
      new ActionListener() {
        public void actionPerformed(ActionEvent e) {
          result.setVisible(false);
          result.dispose();
        }
      }
    );
    result.add(ok,c);
    final var cancel = new JButton("Cancel");
    cancel.addActionListener(
      new ActionListener() {
        public void actionPerformed(ActionEvent e) {
          result.setVisible(false);
          result.dispose();
        }
      }
    );
    c.gridx++;
    result.add(cancel,c);
    result.pack();
    result.setLocationRelativeTo(parent);
    result.setVisible(true);
    final var newNameString = newName.getText();
    final var isNewName = !newNameString.equals(getName());
    if (isNewName) {
      setName(newNameString);
    }
    var isNewBase = false;
    var isNewLock = false;
    var isNewSize = false;
    if (!isMaster) {
      final var baseAddrStr = addr.getText();
      try {
        final var newBase = Long.decode(baseAddrStr);
        if (!newBase.equals(getBaseAddress())) {
          if (!isDataConsistent(newBase)) {
            JOptionPane.showMessageDialog(parent,"Address is not correctly alligned, not changing.",  "Slave Base Address", JOptionPane.ERROR_MESSAGE);
          } else {
            slaveBaseAddress = newBase;
            isNewBase = true;
          }
        }
      } catch (NumberFormatException e) {
        JOptionPane.showMessageDialog(parent,"Invalid address specified, not changing anything.",  "Slave Base Address", JOptionPane.ERROR_MESSAGE);
      }
      if (addrLock.isSelected() != baseAddressIsFixed) {
        baseAddressIsFixed = addrLock.isSelected();
        isNewLock = true;
      }
      try {
        final var addrSelBits = Integer.decode(addrBits.getText());
        if (!addrSelBits.equals(slaveNrOfUsedAddrBits) && addrSelBits < W_ADDR) {
          isNewSize = true;
          slaveNrOfUsedAddrBits = addrSelBits;
        }
      } catch (NumberFormatException e) {
        // for the moment do nothing
      }
    } else {
      final var priority = masterPriority.getSelectedIndex();
      if (priority != getMasterPriority()) {
        if (masters.containsKey(priority)) {
          for (var masterEntry : masters.keySet()) {
            final var master = masters.get(masterEntry);
            final var thisPrior = master.getMasterPriority();
            var moveMaybe = thisPrior >= priority;
            if (thisPrior > 0 && moveMaybe) {
              moveMaybe &= masters.containsKey(thisPrior - 1);
            }
            if (moveMaybe) {
              master.setMasterPriority(thisPrior + 1);
            }
          }
          /* renumber */
        }
        setMasterPriority(priority);
        priorityChanged = true;
      }
    }
    acceptChanges &= isNewName | isNewBase | isNewLock | isNewSize | priorityChanged | firstCreation;
    return acceptChanges;
  }

  public void getXmlProperties(Document doc, Element elt) {
    final var me = doc.createElement((isMaster) ? "BusMaster" : "BusSlave");
    if (!label.isEmpty()) {
      me.setAttribute("name", label);
    }
    if (W_ADDR != 32) {
      me.setAttribute("W_ADDR", Integer.toString(W_ADDR));
    }
    if (W_DATA != 32) {
      me.setAttribute("W_DATA", Integer.toString(W_DATA));
    }
    if (!isMaster) {
      me.setAttribute("baseAddress", "0x"+Long.toHexString(slaveBaseAddress));
      me.setAttribute("nrOfSelBits", Integer.toString(slaveNrOfUsedAddrBits));
      if (baseAddressIsFixed) {
        me.setAttribute("fixedBase", "true");
      }
    } else {
      me.setAttribute("priority", Integer.toString(masterPriority));
    }
    elt.appendChild(me);
  }

  static public busGeneratorObject getXmlObject(Element node) {
    busGeneratorObject result = null;
    String label = "";
    int W_ADDR = -1;
    int W_DATA = -1;
    if (node.hasAttribute("name")) {
      label = node.getAttribute("name");
    }
    if (node.hasAttribute("W_ADDR")) {
      try {
        W_ADDR = Integer.decode(node.getAttribute("W_ADDR"));
      } catch (NumberFormatException e) {
        return null;
      }
    }
    if (node.hasAttribute("W_DATA")) {
      try {
        W_DATA = Integer.decode(node.getAttribute("W_DATA"));
      } catch (NumberFormatException e) {
        return null;
      }
    }
    if (node.getNodeName().equals("BusMaster")) {
      result = new busGeneratorObject();
      if (node.hasAttribute("priority")) {
        try {
          final var newPrior = Integer.decode(node.getAttribute("priority"));
          result.setMasterPriority(newPrior);
        } catch (NumberFormatException e) {
          // do Nothing
        }
      }
    } else if (node.getNodeName().equals("BusSlave")){
      var fixed = false;
      long base;
      int selbits;
      if (node.hasAttribute("baseAddress")) {
        try {
          base = Long.decode(node.getAttribute("baseAddress"));
        } catch (NumberFormatException e) {
          return null;
        }
      } else {
        return null;
      }
      if (node.hasAttribute("nrOfSelBits")) {
        try {
          selbits = Integer.decode(node.getAttribute("nrOfSelBits"));
        } catch (NumberFormatException e) {
          return null;
        }
      } else {
        return null;
      }
      if (node.hasAttribute("fixedBase")) {
        fixed = node.getAttribute("fixedBase").equals("true");
      }
      result = new busGeneratorObject(base, selbits, fixed);
    } else {
      return null;
    }
    if (result != null){
      if (!label.isEmpty()) {
        result.setName(label);
      }
      if (W_ADDR > 0) {
        result.setNrOfAddressBits(W_ADDR);
      }
      if (W_DATA > 0) {
        result.setNrOfDataBits(W_DATA);
      }
    }
    return result;
  }

  @Override
  public void actionPerformed(ActionEvent e) {
    if (e.getActionCommand().endsWith("Ok")) {
      acceptChanges = true;
    }
  }
}