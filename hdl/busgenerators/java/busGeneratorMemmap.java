import java.util.TreeMap;
import javax.swing.BorderFactory;
import javax.swing.JLabel;
import javax.swing.JPanel;
import javax.swing.JTextPane;
import javax.swing.SwingConstants;
import javax.swing.text.SimpleAttributeSet;
import javax.swing.text.StyleConstants;
import javax.swing.text.StyledDocument;
import java.awt.Color;
import java.awt.Font;
import java.awt.BorderLayout;
import java.awt.event.ActionEvent;

public class busGeneratorMemmap extends JPanel {
  private busGeneratorFrame parent;
  private JTextPane memMapPane = new JTextPane();
  public static String memAddressChanged = "memAddrChange";

  busGeneratorMemmap(busGeneratorFrame parent) {
    this.parent = parent;
    this.setEnabled(true);
    this.setLayout(new BorderLayout());
    final var titel = new JLabel("Memory map:", SwingConstants.CENTER);
    titel.setBorder(BorderFactory.createRaisedBevelBorder());
    this.add(titel, BorderLayout.NORTH);
    this.add(memMapPane,BorderLayout.CENTER);
    memMapPane.setEditable(false);
    memMapPane.setFocusable(false);
    buildItems();
  }

  private void addString(StyledDocument doc, String str, SimpleAttributeSet key) {
    try {
      doc.insertString(doc.getLength(), str, key);
    } catch (Exception e) {
      System.out.println(e);
    }
  }

  public void buildItems() {
    final var doc = memMapPane.getStyledDocument();
    final var key = new SimpleAttributeSet();
    var error = false;
    memMapPane.setText("");
     if (!W_ADDRisSame()) {
      StyleConstants.setForeground(key, Color.RED);
      StyleConstants.setBold(key, true);
      addString(doc, "Not all components have the same address bus width!\n", key);
      error = true;
    }
    if (!W_DATAisSame()) {
      StyleConstants.setForeground(key, Color.RED);
      StyleConstants.setBold(key, true);
      addString(doc, "Not all components have the same data bus width!\n", key);
      error = true;
    }
    if (error) {
      return;
    }
    StyleConstants.setFontFamily(key, Font.MONOSPACED);
    final var slaves = getSlaves();
    var currentAddr = 0L;
    var W_ADDR = 32;
    for (var slaveEntry : slaves.entrySet()) {
      final var slave = slaveEntry.getValue();
      W_ADDR = slave.getNrOfAddressBits();
      if (currentAddr < slave.getBaseAddress()) {
        StyleConstants.setForeground(key, Color.GRAY);
        final var info = busGeneratorObject.getAddressRange(W_ADDR, currentAddr, slave.getBaseAddress()-1L) +
                         " " + "empty \n";
        addString(doc, info, key);
      }
      StyleConstants.setForeground(key, memMapPane.getForeground());
      if (isOverlappedComponent(slave, slaves)) {
        StyleConstants.setForeground(key, Color.RED);
      }
      if (slave.hasFixedBaseAddress()) {
        StyleConstants.setForeground(key, Color.BLUE);
      }
      final var info = slave.getAddressRange() + " " + slave.getName() + "\n";
      addString(doc, info, key);
      currentAddr = Math.max(currentAddr, slave.getEndAddress() + 1L);
    }
    final var endAddr = 1L << W_ADDR;
    if (currentAddr < endAddr) {
      StyleConstants.setForeground(key, Color.GRAY);
      final var info = busGeneratorObject.getAddressRange(W_ADDR, currentAddr, endAddr-1L) + " " +
                       "empty\n";
      addString(doc, info, key);
    }
    this.repaint();
  }

  private boolean W_DATAisSame() {
    var W_DATA = 0;
    for (var busElement : parent.getBusComponents()) {
      final var thisW_DATA = busElement.getNrOfDataBits();
      if (W_DATA == 0) {
        W_DATA = thisW_DATA;
      } else {
        if (W_DATA != thisW_DATA) {
          return false;
        }
      }
    }
    return true;
  }

  private boolean W_ADDRisSame() {
    var W_ADDR = 0;
    for (var busElement : parent.getBusComponents()) {
      final var thisW_Addr = busElement.getNrOfAddressBits();
      if (W_ADDR == 0) {
        W_ADDR = thisW_Addr;
      } else {
        if (W_ADDR != thisW_Addr) {
          return false;
        }
      }
    }
    return true;
  }

  private TreeMap<Long, busGeneratorObject> getSlaves() {
    final var slaves = new TreeMap<Long, busGeneratorObject>();
    for (var busObject : parent.getBusComponents()) {
      if (busObject.isSlaveComponent()) {
        var base = busObject.getBaseAddress();
        while (slaves.containsKey(base)) {
          base++;
        }
        slaves.put(base, busObject);
      }
    }
    return slaves;
  }

  private TreeMap<Long, Long> getFreeRanges() {
    final var result = new TreeMap<Long, Long>();
    var current = 0L;
    var W_ADDR = 0;
    final var slaves = getSlaves();
    busGeneratorObject lastSlave = null;
    for (var slaveEntry : slaves.entrySet()) {
      final var thisSlave = slaveEntry.getValue();
      W_ADDR = thisSlave.getNrOfAddressBits();
      if (thisSlave.getBaseAddress() > current && lastSlave == null) {
        result.put(current, thisSlave.getBaseAddress() - 1L);
        current = thisSlave.getEndAddress() + 1L;
      }
      if (lastSlave != null) {
        if (thisSlave.getBaseAddress() > current && thisSlave.getBaseAddress() >= lastSlave.getEndAddress()) {
          result.put(current, thisSlave.getBaseAddress() - 1L);
          current = thisSlave.getEndAddress() + 1L;
        } else if (thisSlave.getBaseAddress() <= lastSlave.getEndAddress() || thisSlave.getBaseAddress() < current) {
          current = Math.max(current, lastSlave.getEndAddress() + 1L);
        } else {
          current = thisSlave.getEndAddress() + 1L;
        }
      }
      lastSlave = thisSlave;
    }
    final var endAddr = 1L << W_ADDR;
    if (current < endAddr) {
      result.put(current, endAddr - 1L);
    }
    return result;
  }

  private boolean isOverlappedComponent(busGeneratorObject slave, TreeMap<Long, busGeneratorObject> slaves) {
    var isOverlapped = false;
    final var checkStart = slave.getBaseAddress();
    final var checkEnd = slave.getEndAddress();
    final var checkSize = checkEnd - checkStart + 1L;
    for (var entries : slaves.entrySet()) {
      if (slave.equals(entries.getValue())) {
        continue;
      }
      var thisSlave = entries.getValue();
      final var thisStart = thisSlave.getBaseAddress();
      final var thisEnd = thisSlave.getEndAddress();
      final var thisSize = thisEnd - thisStart + 1L;
      /* we alwas chek the smallest against the biggest */
      final var smallestStart = (thisSize >= checkSize) ? checkStart : thisStart;
      final var smallestEnd = (thisSize >= checkSize) ? checkEnd : thisEnd;
      final var biggetsStart = (thisSize >= checkSize) ? thisStart : checkStart;
      final var biggestEnd = (thisSize >= checkSize) ? thisEnd : checkEnd;
      if (smallestStart >= biggetsStart && smallestStart < biggestEnd) {
        isOverlapped = true;
      } else if (smallestEnd > biggetsStart && smallestEnd <= biggestEnd ) {
        isOverlapped = true;
      }
    }
    return isOverlapped;
  }

  public void memMapFix(boolean renumberAll) {
    var slaves = getSlaves();
    busGeneratorObject lastSlave = null;
    if (renumberAll) {
      // reorder the slaves such that the biggest are on top
      TreeMap<Long, busGeneratorObject> newSlaves = new TreeMap<Long, busGeneratorObject>();
      for (var slaveEntry : slaves.entrySet()) {
        final var thisSlave = slaveEntry.getValue();
        final var nrAddrBits = (long)(thisSlave.getNrOfAddrSelectBits());
        newSlaves.put(nrAddrBits, thisSlave);
        thisSlave.setBaseAddress(0L);
      }
      var currentAddr = 0L;
      for (var slaveEntry : newSlaves.entrySet()) {
        final var thisSlave = slaveEntry.getValue();
        if (lastSlave == null) {
          currentAddr = thisSlave.getEndAddress() + 1L;
          lastSlave = thisSlave;
          continue;
        }
        thisSlave.setBaseAddress(currentAddr);
        currentAddr = thisSlave.getEndAddress() + 1L;
        lastSlave = thisSlave;
        parent.actionPerformed(new ActionEvent(thisSlave, 0, memAddressChanged));
      }
    } else {
      TreeMap<Long, busGeneratorObject> overLappedSlaves = new TreeMap<Long, busGeneratorObject>();
      for (var slaveEntry : slaves.entrySet()) {
        final var thisSlave = slaveEntry.getValue();
        if (isOverlappedComponent(thisSlave, slaves) && !thisSlave.hasFixedBaseAddress()) {
          overLappedSlaves.put(slaveEntry.getKey(), thisSlave);
        }
      }
      for (var slaveEntry : overLappedSlaves.entrySet()) {
        final var thisSlave = slaveEntry.getValue();
        if (isOverlappedComponent(thisSlave, slaves) && !thisSlave.hasFixedBaseAddress()) {
          final var emptyRanges = getFreeRanges();
          var placed = false;
          for (var emptyEntry : emptyRanges.entrySet()) {
            if (placed) {
              continue;
            }
            final var entrySize = thisSlave.getEndAddress() - thisSlave.getBaseAddress() + 1L;
            final var emptySize = emptyEntry.getValue() - emptyEntry.getKey() + 1L;
            if (emptySize >= entrySize) {
              var baseAddress = emptyEntry.getKey();
              final var entryMask = entrySize - 1L;
              if ((baseAddress & entryMask) != 0L) {
                baseAddress = (baseAddress + entrySize) & (entryMask ^ -1L);
              }
              final var endAddress = baseAddress + entrySize - 1L;
              if (endAddress <= emptyEntry.getValue()) {
                thisSlave.setBaseAddress(baseAddress);
                placed = true;
                parent.actionPerformed(new ActionEvent(thisSlave, 0, memAddressChanged));
              }
            }
          }
        }
        lastSlave = thisSlave;
      }
    }
  }
}
