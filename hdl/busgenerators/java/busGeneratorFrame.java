import java.awt.BorderLayout;
import java.awt.Dimension;
import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.ArrayList;
import java.util.LinkedList;
import java.util.TreeMap;

import javax.swing.JFileChooser;
import javax.swing.JFrame;
import javax.swing.JOptionPane;
import javax.swing.JScrollPane;
import javax.swing.filechooser.FileNameExtensionFilter;
import javax.xml.XMLConstants;
import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;
import javax.xml.parsers.ParserConfigurationException;
import javax.xml.transform.OutputKeys;
import javax.xml.transform.Transformer;
import javax.xml.transform.TransformerConfigurationException;
import javax.xml.transform.TransformerException;
import javax.xml.transform.TransformerFactory;
import javax.xml.transform.dom.DOMSource;
import javax.xml.transform.stream.StreamResult;

import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.Node;
import org.xml.sax.SAXException;

public class busGeneratorFrame extends JFrame implements ActionListener {

  private LinkedList<busGeneratorObject> busComponents;
  private busGeneratorMemmap memMap;
  private busGeneratorDraw drawPane;
  private boolean changed = false;
  private static String myTitle = "Wishbone bus generator";
  private String fileName = "";
  private static final FileNameExtensionFilter filter = new FileNameExtensionFilter("Xml files", "xml");

  busGeneratorFrame() {
    final var con = this.getContentPane();
    final var layout = new BorderLayout();
    con.setLayout(layout);
    final var myMenu = new busGeneratorMenu();
    setJMenuBar(myMenu);
    myMenu.addActionListener(this);
    busComponents = new LinkedList<>();
    memMap = new busGeneratorMemmap(this);
    var scrollPane = new JScrollPane(memMap);
    scrollPane.setPreferredSize(new Dimension(200, 480));
    this.add(scrollPane, BorderLayout.LINE_END);
    drawPane = new busGeneratorDraw(this);
    scrollPane = new JScrollPane(drawPane);
    this.add(scrollPane, BorderLayout.CENTER);
    this.pack();
    this.setTitle(myTitle);
  }

  public LinkedList<busGeneratorObject> getBusComponents() {
    return busComponents;
  }

  private void thereIsAChange() {
    if (changed) {
      return;
    }
    changed = true;
    this.setTitle(myTitle+"*");
  }

  private static DocumentBuilderFactory getHardenedBuilderFactory() {
    var dbf = DocumentBuilderFactory.newInstance();
    var feature = "";
    try {
      feature = "http://apache.org/xml/features/disallow-doctype-decl";
      dbf.setFeature(feature, true);
      feature = "http://xml.org/sax/features/external-general-entities";
      dbf.setFeature(feature, false);
      feature = "http://xml.org/sax/features/external-parameter-entities";
      dbf.setFeature(feature, false);
      feature = "http://apache.org/xml/features/nonvalidating/load-external-dtd";
      dbf.setFeature(feature, false);
      dbf.setXIncludeAware(false);
      dbf.setExpandEntityReferences(false);
    } catch (ParserConfigurationException e) {
      System.err.println("Error: could not put feature " + feature);
      dbf = null;
    }

    return dbf;
  }

  private boolean writeXml() {
    if (busComponents.isEmpty()) {
      return true;
    }
    final var docFactory = getHardenedBuilderFactory();
    if (docFactory == null) {
      return false;
    }
    DocumentBuilder docBuilder = null;
    try {
      docBuilder = docFactory.newDocumentBuilder();
    } catch (ParserConfigurationException e) {
      return false;
    }
    final var doc = docBuilder.newDocument();
    if (fileName.isEmpty()) {
      final var fc = new JFileChooser();
      fc.setDialogTitle("Save a bus generator file");
      fc.setFileFilter(filter);
      final var res = fc.showOpenDialog(this);
      if (res == JFileChooser.APPROVE_OPTION) {
        fileName = fc.getSelectedFile().getAbsolutePath();
        if (!fileName.toLowerCase().endsWith(".xml")) {
          fileName += ".xml";
        }
      } else {
        return true;
      }
    }
    final var ret = doc.createElement("WishBoneBusDescription");
    doc.appendChild(ret);
    ret.appendChild(doc.createTextNode("\nThis file is intended to be loaded by busGenerator\n"));
    ret.setAttribute("version", "1.0");
    /* fill Document */
    for (var element : busComponents) {
      element.getXmlProperties(doc, ret);
    }
    FileOutputStream fileOut;
    try {
      fileOut = new FileOutputStream(fileName);
    } catch (FileNotFoundException e) {
      return false;
    }
    final var out = new BufferedOutputStream(fileOut);
    final var tfFactory = TransformerFactory.newInstance();
    try {
      tfFactory.setAttribute("indent-number", 2);
    } catch (IllegalArgumentException e) {
      return false;
    }
    Transformer tf;
    try {
      tf = tfFactory.newTransformer();
    } catch (TransformerConfigurationException e) {
      return false;
    }
    tf.setOutputProperty(OutputKeys.ENCODING, "UTF-8");
    tf.setOutputProperty(OutputKeys.INDENT, "yes");
    try {
      tf.setOutputProperty("{http://xml.apache.org/xslt}indent-amount", "2");
    } catch (IllegalArgumentException e) {
      return false;
    }
    doc.normalize();
    final var src = new DOMSource(doc);
    final var dest = new StreamResult(out);
    try {
      tf.transform(src, dest);
    } catch (TransformerException e) {
      return false;
    }
    try {
      out.close();
    } catch (IOException e) {
      return false;
    }
    changed = false;
    this.setTitle(myTitle);
    return true;
  }

  private boolean readXml() {
    final var fc = new JFileChooser();
    fc.setDialogTitle("Load a bus generator file");
    fc.setFileFilter(filter);
    final var res = fc.showOpenDialog(this);
    if (res == JFileChooser.APPROVE_OPTION) {
      fileName = fc.getSelectedFile().getAbsolutePath();
    } else {
      return false;
    }
    FileInputStream file;
    try {
      file = new FileInputStream(fileName);
    } catch (FileNotFoundException e) {
      return false;
    }
    final var in = new BufferedInputStream(file);
    final var factory = getHardenedBuilderFactory();
    if (factory == null) {
      return false;
    }
    factory.setNamespaceAware(true);
    try {
      factory.setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true);
    } catch (ParserConfigurationException e) {
      return false;
    }
    DocumentBuilder builder;
    try {
      builder = factory.newDocumentBuilder();
    } catch (ParserConfigurationException e) {
      return false;
    }
    Document doc;
    try {
      doc = builder.parse(in);
    } catch (SAXException e) {
      return false;
    } catch (IOException e) {
      return false;
    }
    final var content = doc.getDocumentElement();
    if (!content.getNodeName().equals("WishBoneBusDescription")) {
      return false;
    }
    final var nodes = new ArrayList<Element>();
    final var cNodes = content.getChildNodes();
    for (var idx = 0; idx < cNodes.getLength(); idx++) {
      final var sub = cNodes.item(idx);
      if (sub.getNodeType() == Node.ELEMENT_NODE) {
        nodes.add((Element) sub);
      }
    }
    if (!busComponents.isEmpty()) {
      busComponents.clear();
    }
    final var masters = new TreeMap<Integer, busGeneratorObject>();
    for (var node : nodes) {
      final var element = busGeneratorObject.getXmlObject(node);
      if (element != null) {
        if (!element.isSlaveComponent()) {
          if (masters.containsKey(element.getMasterPriority())) {
            var prior = 0;
            while (masters.containsKey(prior)) {
              prior++;
            }
            element.setMasterPriority(prior);
          }
          masters.put(element.getMasterPriority(), element);
        }
        busComponents.add(element);
      }
    }
    try {
      in.close();
    } catch (IOException e) {
      return false;
    }
    return true;
  }

  private boolean compNameExists(String name) {
    for (var obj : busComponents) {
      if (obj.getName().toLowerCase().equals(name.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  @Override
  public void actionPerformed(ActionEvent e) {
    final var arg = e.getActionCommand();
    if (arg.equals(busGeneratorMenu.generateShared)) {
      if (!busGeneratorSharedBusGenerator.createHdlFiles(this)) {
        System.out.println("Something went wrong");
      }
    }
    if (arg.equals(busGeneratorMenu.fileLoadAction)) {
      if (changed) {
        final var res = JOptionPane.showConfirmDialog(this, "The current architecture has changes\nShould I save?", "Changes", JOptionPane.YES_NO_OPTION);
        if (res == JOptionPane.YES_OPTION) {
          writeXml();
          changed = false;
        }
      }
      if (readXml()) {
        changed = false;
        memMap.buildItems();
        drawPane.repaint();
      }
    }
    if (arg.equals(busGeneratorMenu.fileExitAction)) {
      System.exit(0);
    }
    if (arg.equals(busGeneratorMenu.fileSaveAction)) {
      if (changed) {
        writeXml();
      }
    }
    if (arg.equals(busGeneratorMenu.fileSaveAsAction)) {
      fileName = "";
      writeXml();
    }
    if (arg.equals(busGeneratorMemmap.memAddressChanged)) {
      thereIsAChange();
      memMap.buildItems();
      drawPane.repaint();
    }
    if (arg.equals(busGeneratorMenu.memMapRenumberAll)) {
      thereIsAChange();
      memMap.memMapFix(true);
    }
    if (arg.equals(busGeneratorMenu.memMapRenumberOverlap)) {
      thereIsAChange();
      memMap.memMapFix(false);
    }
    if (arg.equals(busGeneratorDraw.DeleteAction)) {
      thereIsAChange();
      final var object = (busGeneratorObject) e.getSource();
      busComponents.remove(object);
      if (object.isSlaveComponent()) {
        memMap.buildItems();
      }
      drawPane.repaint();
    }
    if (arg.equals(busGeneratorDraw.AddAction)) {
      thereIsAChange();
      final var object = (busGeneratorObject) e.getSource();
      int idx = 0;
      var name = object.getName();
      if (compNameExists(name)) {
        String newName;
        do {
          newName = name+"_"+Integer.toString(idx++);
        } while (compNameExists(newName));
        object.setName(newName);
      }
      busComponents.add(object);
      if (object.isSlaveComponent()) {
        memMap.buildItems();
      }
      drawPane.repaint();
    }
  }
}
