import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.util.ArrayList;
import java.util.TreeMap;

import javax.swing.JFileChooser;

public class busGeneratorSharedBusGenerator {

  public class busHdlComponent {
    private busGeneratorObject object;
    private ArrayList<busGeneratorPortType> signals;

    public busHdlComponent(busGeneratorObject object) {
      this.object = object;
      this.signals = (object.isSlaveComponent() ? 
          busGeneratorWishboneSignals.getSlaveSignals(object.getName()): 
          busGeneratorWishboneSignals.getMasterSignals(object.getName()));
    }

    public busGeneratorObject getComponent() {
      return object;
    }

    public ArrayList<busGeneratorPortType> getSignals() {
      return signals;
    }
  }
  
  TreeMap<Integer, busHdlComponent> masters = new TreeMap<Integer, busHdlComponent>();
  TreeMap<Long, busHdlComponent> slaves = new TreeMap<Long, busHdlComponent>();
  int W_ADDR = 0;
  int W_DATA = 0;
  String baseDirectory = null;
  static String vhdlDir = "vhdl"+File.separator;
  static String verilogDir = "verilog"+File.separator;
  static String vhdlExtention = ".vhdl";
  static String verilogExtention = ".v";
  String busTopLevelName = "wishBoneSharedBusTop";
  String busTopTemplateName = "wishBoneSharedBusTemplate";
  static String arbiterBusCycs = "s_arbiterMasterCycs";
  static String arbiterBusLocks = "s_arbiterMasterLocks";
  static String arbiterBusEnables = "s_arbiterBusEnables";
  static String arbiterGeneric = "priorityScheme";
  static String arbiterError = "s_arbiterErrorOut";
  static String masterDataBusIn; 
  static String slaveDataBusIn;
  static int nrOfMasters;
  static String[] arbiterInternalSignals = {
      "s_arbiterMaskReg",
      "s_arbiterEnablesReg",
      "s_arbiterTimeOutReg",
      "s_arbiterBusIsUsedReg",
      "s_arbiterBeforeMeCarries",
      "s_arbiterAferMeCarries",
      "s_arbiterBeforeMeMask",
      "s_arbiterAfterMeMask",
      "s_arbiterNewMask",
      "s_arbiterServeRequest",
      "s_arbiterIsTimeOut",
      "s_arbiterIsBusRelease"
  };
  private static Boolean[] arbiterIsVerilogReg = {
      true,
      true,
      true,
      true,
      false,
      false,
      false,
      false,
      false,
      false,
      false,
      false
  };
  private static Integer[] arbiterNrOfBits = {
      -1,
      -1,
      16,
      1,
      -1,
      -1,
      -1,
      -1,
      -1,
      1,
      1,
      1
  };

  private void generateMySelf(busGeneratorFrame parent) {
    for (var item : parent.getBusComponents()) {
      if (W_ADDR == 0) {
        W_ADDR = item.getNrOfAddressBits();
      }
      if (W_DATA == 0) {
        W_DATA = item.getNrOfDataBits();
      }
      if (item.isSlaveComponent()) {
        slaves.put(item.getBaseAddress(), new busHdlComponent(item));
      } else {
        masters.put(item.getMasterPriority(), new busHdlComponent(item));
      }
    }
    if (baseDirectory == null) {
      final var fc = new JFileChooser();
      fc.setFileSelectionMode(JFileChooser.DIRECTORIES_ONLY);
      fc.setDialogTitle("Select the directory where to put the HDL files");
      final var res = fc.showOpenDialog(parent);
      if (res == JFileChooser.APPROVE_OPTION) {
        baseDirectory = fc.getSelectedFile().getAbsolutePath()+File.separator;
      }
    }
    masterDataBusIn = busGeneratorWishboneSignals.getMasterInputMap().get(busGeneratorWishboneSignals.datInEntry);
    slaveDataBusIn = busGeneratorWishboneSignals.getSlaveInputMap().get(busGeneratorWishboneSignals.datInEntry);
    var maxIndex = 0;
    for (var masterEntry : masters.keySet()) {
      maxIndex = Math.max(maxIndex, masterEntry);
    }
    nrOfMasters = maxIndex + 1;
  }

  busGeneratorSharedBusGenerator(busGeneratorFrame parent) {
    generateMySelf(parent);
  }

  busGeneratorSharedBusGenerator(busGeneratorFrame parent, String directory) {
    this.baseDirectory = directory;
    generateMySelf(parent);
  }

  public boolean canGenerate() {
    if (baseDirectory == null || baseDirectory.isBlank()){
      return false;
    }
    var newDir = new File(baseDirectory+vhdlDir);
    if (!newDir.exists()) {
      if (!newDir.mkdir()) {
        return false;
      }
    }
    newDir = new File(baseDirectory+verilogDir);
    if (!newDir.exists()) {
      if (!newDir.mkdir()) {
        return false;
      }
    }
    return true;
  }

  public String getRemark(String remark, int indent, boolean isVHDL) {
    final var lines = remark.split("\n");
    final var result = new StringBuilder();
    if (lines.length == 1) {
      for (var spaces = 0 ; spaces < indent; spaces++) {
        result.append(" ");
      }
      if (isVHDL) {
        result.append("--" + lines[0] + "\n");
      } else {
        result.append("//" + lines[0] + "\n");
      }
    } else {
      for (var line = 0; line < lines.length; line++) {
        for (var spaces = 0 ; spaces < indent; spaces++) {
          result.append(" ");
        }
        if (isVHDL) {
          result.append("-- " + lines[line] + "\n");
        } else {
          result.append("// " + lines[line] + "\n");
        }
      }
    }
    return result.toString();
  }

  public String getPreamble(boolean isVHDL, String name, boolean slaveGeneric) {
    final var result = new StringBuilder();
    if (isVHDL) {
      result.append("""
      library ieee;
      use ieee.std_logic_1164.all;
      use ieee.numeric_std.all;

      """);
      result.append(String.format("entity %s is\n", name));
      result.append(String.format("  generic( %s : integer := %d;\n", 
          busGeneratorWishboneSignals.DataBitsGeneric, W_DATA));
      result.append(String.format("           %s : integer := %d;\n",
          busGeneratorWishboneSignals.AddressBitsGeneric, W_ADDR));
      if (slaveGeneric) {
        result.append(String.format("           %s : std_logic_vector;\n", 
          busGeneratorWishboneSignals.BaseAddressGeneric));
        result.append(String.format("           %s : std_logic_vector;\n", 
          busGeneratorWishboneSignals.EndAddressGeneric));
      }
      result.append(String.format("           %s : integer := 1);", arbiterGeneric));
      result.append("  port (\n");
    } else {
      result.append(String.format("module %s\n", name));
      result.append(String.format("  #( parameter %s = %d,\n",
          busGeneratorWishboneSignals.DataBitsGeneric, W_DATA));
      result.append(String.format("     parameter %s = %d,\n",
          busGeneratorWishboneSignals.AddressBitsGeneric, W_ADDR));
      if (slaveGeneric) {
        result.append(String.format("     parameter %s,\n", 
          busGeneratorWishboneSignals.BaseAddressGeneric));
        result.append(String.format("     parameter %s,\n", 
          busGeneratorWishboneSignals.EndAddressGeneric));
      }
      result.append(String.format("     parameter %s = 1)\n", arbiterGeneric));
      result.append("   (\n");
    }
    return result.toString();
  }

  public String getMasterPorts(boolean isVHDL, boolean supressSyscon) {
    final var result = new StringBuilder();
    for (var masterEnty : masters.keySet()) {
      final var master = masters.get(masterEnty);
      final var masterPorts = master.getSignals();
      final var masterRemark = new StringBuilder();
      masterRemark.append(String.format("Here the signals for the master \"%s\" are defined\n", master.getComponent().getName()));
      masterRemark.append("""
      Note that although the signals are noted with _O/_I their direction is oposite defined
      as they connect directly with the same signals on the master.
      """);
      result.append(getRemark(masterRemark.toString(), 4, isVHDL));
      for (var signal : masterPorts) {
        if (supressSyscon && signal.isSysCon()) {
          continue;
        }
        if (isVHDL) {
          result.append("    "+signal.getVHDLPort(true)+";\n");
        } else {
          result.append("    "+signal.getVerilogPort(true)+",\n");
        }
      }
      result.append("\n");
    }
    return result.toString();
  }

  public String getSlavePorts(boolean isVHDL, TreeMap<Long, busHdlComponent> slaves) {
    final var result = new StringBuilder();
    for (var slaveEnty : slaves.keySet()) {
      final var slave = slaves.get(slaveEnty);
      final var slavePorts = slave.getSignals();
      final var slaveRemark = new StringBuilder();
      slaveRemark.append(String.format("Here the signals for the slave \"%s\" are defined\n", slave.getComponent().getName()));
      slaveRemark.append("""
      Note that although the signals are noted with _O/_I their direction is oposite defined
      as they connect directly with the same signals on the master.
      """);
      result.append(getRemark(slaveRemark.toString(), 4, isVHDL));
      for (var signal : slavePorts) {
        if (isVHDL) {
          result.append("    "+signal.getVHDLPort(true)+";\n");
        } else {
          result.append("    "+signal.getVerilogPort(true)+",\n");
        }
      }
      result.append("\n");
    }
    return result.toString();
  }

  public String getSysconPort(boolean isVHDL, String name) {
    final var result = new StringBuilder();
    final var sysconRemark = new StringBuilder();
    sysconRemark.append("""
    Here the Syscon connections are defined
    Connect the signals with the same name together
    Note that although we have the _O suffix these are inputs as
    they are outputs on the syscon component
    """);
    result.append(getRemark(sysconRemark.toString(), 4, isVHDL));
    if (isVHDL) {
      result.append("""
          CLK_O : in  std_logic;
          RST_O : in  std_logic);
      """);
      result.append(String.format("end entity %s;\n\n", name));
      result.append(String.format("architecture autogenerated of %s is\n\n", name));
    } else {
      result.append("""
          input wire CLK_O,
          input wire RST_O);

      """);
    }
    return result.toString();
  }

  private String getPorts(boolean isVHDL) {
    final var result = new StringBuilder();
    result.append(getMasterPorts(isVHDL, false));
    result.append(getSlavePorts(isVHDL, slaves));
    result.append(getSysconPort(isVHDL, busTopLevelName));
    return result.toString();
  }

  public String getSignals(boolean isVHDL, TreeMap<Long, busHdlComponent> slaves, boolean withTimeout) {
    final var result = new StringBuilder();
    for (var masterEntry : masters.keySet()) {
      final var master = masters.get(masterEntry);
      final var masterSignals = master.getSignals();
      for (var signal : masterSignals) {
        final var sig = (isVHDL) ? signal.getVhdlMaskedSignalDefinition() : signal.getVerilogMaskedSignalDefinition();
        if (sig != null) {
          result.append("  "+sig+"\n");
        }
      }
    }
    if (slaves != null) {
      for (var slaveEntry : slaves.keySet()) {
        final var slave = slaves.get(slaveEntry);
        final var slaveSignals = slave.getSignals();
        for (var signal : slaveSignals) {
          final var sig = (isVHDL) ? signal.getVhdlMaskedSignalDefinition() : signal.getVerilogMaskedSignalDefinition();
          if (sig != null) {
            result.append("  "+sig+"\n");
          }
        }
      }
    }
    if (slaves != null) {
      final var masterSignals = busGeneratorWishboneSignals.getMasterSignals("");
      final var masterInpSignals = busGeneratorWishboneSignals.getMasterInputMap();
      for (var entry : masterInpSignals.keySet()) {
        final var sigName = masterInpSignals.get(entry);
        final var masterEntry = masterSignals.get(entry);
        final var isGeneric = masterEntry.isGeneric();
        final var genericName = masterEntry.getGeneric();
        final var bits = masterEntry.getNrOfBits();
        if (isGeneric) {
          result.append("  "+busGeneratorPortType.getSignalDefinition(sigName, genericName, isVHDL)+"\n");
        } else {
          result.append("  "+busGeneratorPortType.getSignalDefinition(sigName, bits, isVHDL)+"\n");
        }
      }
      final var slaveSignals = busGeneratorWishboneSignals.getMasterSignals("");
      final var slaveInpSignals = busGeneratorWishboneSignals.getSlaveInputMap();
      for (var entry : slaveInpSignals.keySet()) {
        final var sigName = slaveInpSignals.get(entry);
        final var slaveEntry = slaveSignals.get(entry);
        final var isGeneric = slaveEntry.isGeneric();
        final var genericName = slaveEntry.getGeneric();
        final var bits = slaveEntry.getNrOfBits();
        if (isGeneric) {
          result.append("  "+busGeneratorPortType.getSignalDefinition(sigName, genericName, isVHDL)+"\n");
        } else {
          result.append("  "+busGeneratorPortType.getSignalDefinition(sigName, bits, isVHDL)+"\n");
        }
      }
    }
    result.append("  "+busGeneratorPortType.getSignalDefinition(arbiterBusCycs, nrOfMasters, isVHDL)+"\n");
    result.append("  "+busGeneratorPortType.getSignalDefinition(arbiterBusLocks, nrOfMasters, isVHDL)+"\n");
    result.append("  "+busGeneratorPortType.getSignalDefinition(arbiterBusEnables, nrOfMasters, isVHDL)+"\n");
    if (withTimeout) {
      result.append("  "+busGeneratorPortType.getSignalDefinition(arbiterError, 1, isVHDL)+"\n");
    }
    for (var idx = 0; idx < arbiterInternalSignals.length; idx++) {
      if (!withTimeout && (idx == 2 || idx == 10)) {
        continue;
      }
      final var nrOfBits = (arbiterNrOfBits[idx] < 0) ? nrOfMasters : arbiterNrOfBits[idx];
      final var isReg = arbiterIsVerilogReg[idx];
      final var name = arbiterInternalSignals[idx];
      result.append("  "+busGeneratorPortType.getSignalDefinition(name, nrOfBits, isVHDL, isReg)+"\n");
    }
    result.append("\n");
    return result.toString();
  }

  public String getAssignment(String destination, String source, boolean isVHDL) {
    if (isVHDL) {
      return destination+" <= "+source+";";
    }
    return "assign "+destination+" = "+source+";";
  }

  public String getSyscon(boolean isVHDL) {
    final var result = new StringBuilder();
    result.append(getRemark(" Here we connect all clocks and resets to the syscon", 2, isVHDL));
    for (var masterEntry : masters.keySet()) {
      final var master = masters.get(masterEntry);
      result.append("  "+getAssignment(master.getSignals().get(busGeneratorWishboneSignals.clockEntry).getName(), "CLK_O", isVHDL)+"\n");
      result.append("  "+getAssignment(master.getSignals().get(busGeneratorWishboneSignals.resetEntry).getName(), "RST_O", isVHDL)+"\n");
    }
    for (var slaveEntry : slaves.keySet()) {
      final var slave = slaves.get(slaveEntry);
      result.append("  "+getAssignment(slave.getSignals().get(busGeneratorWishboneSignals.clockEntry).getName(), "CLK_O", isVHDL)+"\n");
      result.append("  "+getAssignment(slave.getSignals().get(busGeneratorWishboneSignals.resetEntry).getName(), "RST_O", isVHDL)+"\n");
    }
    result.append("\n");
    return result.toString();
  }

  public String getArbiterCons(boolean isVHDL) {
    final var result = new StringBuilder();
    result.append(getRemark(" Here the arbiter signals are mapped", 2, isVHDL));
    final var index = (isVHDL) ? "(%d)" : "[%d]";
    final var zero = (isVHDL) ? "'0'" : "1'b0";
    for (var idx = 0 ; idx < nrOfMasters; idx++) {
      final var master = masters.get(idx);
      result.append((isVHDL) ? "  " : "  assign ");
      result.append(arbiterBusLocks);
      result.append(String.format(index, idx));
      result.append((isVHDL) ? " <= " : " = ");
      result.append((master == null) ? zero : 
        master.getSignals().get(busGeneratorWishboneSignals.lockEntry).getName());
      result.append(";\n");
    }
    for (var idx = 0 ; idx < nrOfMasters; idx++) {
      final var master = masters.get(idx);
      result.append((isVHDL) ? "  " : "  assign ");
      result.append(arbiterBusCycs);
      result.append(String.format(index, idx));
      result.append((isVHDL) ? " <= " : " = ");
      result.append((master == null) ? zero : 
        master.getSignals().get(busGeneratorWishboneSignals.cycEntry).getName());
      result.append(";\n");
    }
    result.append("\n");
    return result.toString();
  }

  public String getWhenElse(String dest, String cond, String valTrue, String valFalse, boolean isVHDL) {
    final var result = new StringBuilder();
    result.append((isVHDL) ? "  " : "  assign ");
    result.append(dest);
    result.append((isVHDL) ? " <= " : " = ");
    if (isVHDL) {
      result.append(String.format("%s when %s else %s", valTrue, cond, valFalse));
    } else {
      result.append(String.format("(%s) ? %s : %s", cond, valTrue,valFalse));
    }
    result.append(";\n");
    return result.toString();
  }

  public String getMaskedDefinitions(boolean isVHDL, TreeMap<Long, busHdlComponent> slaves) {
    final var result = new StringBuilder();
    if (slaves != null) {
      result.append(getRemark(" Here the masked slave signals are defined", 2, isVHDL));
      for (var slaveEntry : slaves.keySet()) {
        final var slave = slaves.get(slaveEntry);
        final var ackName = slave.getSignals().get(busGeneratorWishboneSignals.ackEntry).getName();
        final var ackCond = (isVHDL) ? ackName+" = '1'" : ackName+" == 1'b1";
        for (var slaveSig : slave.getSignals()) {
          final var maskedSlaveSig = slaveSig.getMaskedSignalName();
          if (maskedSlaveSig != null) {
            result.append(getWhenElse(maskedSlaveSig, ackCond, slaveSig.getName(), slaveSig.getZeroString(isVHDL), isVHDL));
          }
        }
      }
      result.append("\n");
    }
    result.append(getRemark(" Here the masked master signals are defined", 2, isVHDL));
    for (var masterEntry : masters.keySet()) {
      final var master = masters.get(masterEntry);
      for (var masterSig : master.getSignals()) {
        final var maskedMasterSig = masterSig.getMaskedSignalName();
        if (maskedMasterSig != null) {
          final var ackName = (isVHDL) ? String.format("%s(%d)", arbiterBusEnables, masterEntry) :
              String.format("%s[%d]", arbiterBusEnables, masterEntry);
          final var ackCond = (isVHDL) ? ackName+" = '1'" : ackName+" == 1'b1";
          result.append(getWhenElse(maskedMasterSig, ackCond, masterSig.getName(), masterSig.getZeroString(isVHDL), isVHDL));
        }
      }
    }
    result.append("\n");
    return result.toString();
  }

  public String getDataConnetions(boolean isVHDL) {
    final var result = new StringBuilder();
    result.append(getRemark(" Here the slave -> master databus is defined", 2, isVHDL));
    for (var masterEntry : masters.keySet()) {
      final var master = masters.get(masterEntry);
      final var masterDatI = master.getSignals().get(busGeneratorWishboneSignals.datInEntry).getName();
      result.append("  "+getAssignment(masterDatI, masterDataBusIn, isVHDL)+"\n");
    }
    var firstEntry = true;
    result.append((isVHDL) ? "  " : "  assign ");
    result.append(masterDataBusIn);
    result.append((isVHDL) ? " <=\n      " : " =\n      ");
    for (var slaveEntry : slaves.keySet()) {
      final var slaveDatO = slaves.get(slaveEntry).getSignals().get(busGeneratorWishboneSignals.datOutEntry).getMaskedSignalName();
      if (firstEntry) {
        result.append(slaveDatO);
        firstEntry = false;
      } else {
        result.append((isVHDL) ? " or\n      " : " |\n      ");
        result.append(slaveDatO);
      }
    }
    result.append(";\n\n");
    result.append(getRemark(" Here the master -> slave databus is defined", 2, isVHDL));
    for (var slaveEntry : slaves.keySet()) {
      final var slaveDatI = slaves.get(slaveEntry).getSignals().get(busGeneratorWishboneSignals.datInEntry).getName();
      result.append("  "+getAssignment(slaveDatI, slaveDataBusIn, isVHDL)+"\n");
    }
    firstEntry = true;
    result.append((isVHDL) ? "  " : "  assign ");
    result.append(slaveDataBusIn);
    result.append((isVHDL) ? " <=\n      " : " =\n      ");
    for (var masterEntry : masters.keySet()) {
      final var masterDatO = masters.get(masterEntry).getSignals().get(busGeneratorWishboneSignals.datOutEntry).getMaskedSignalName();
      if (firstEntry) {
        result.append(masterDatO);
        firstEntry = false;
      } else {
        result.append((isVHDL) ? " or\n      " : " |\n      ");
        result.append(masterDatO);
      }
    }
    result.append(";\n\n");
    return result.toString();
  }

  public String getMasterConnections(boolean isVHDL) {
    final var result = new StringBuilder();
    final var masterInputs = busGeneratorWishboneSignals.getMasterInputMap();
    result.append(getRemark(" Here all master inputs are mapped", 2, isVHDL));
    for (var masterEntry : masters.keySet()) {
      final var masterSignals = masters.get(masterEntry).getSignals();
      for (var inp : masterInputs.keySet()) {
        if (inp == busGeneratorWishboneSignals.datInEntry) {
          // the databus is haldled seperately
          continue;
        }
        final var andOpp = (isVHDL) ? " and " : " & ";
        final var enaVarIndex = (isVHDL) ? String.format("(%d)", masterEntry) :
            String.format("[%d]", masterEntry);
        result.append("  "+getAssignment(masterSignals.get(inp).getName(), 
            masterInputs.get(inp)+andOpp+arbiterBusEnables+enaVarIndex, isVHDL)+"\n");
      }
    }
    for (var inp : masterInputs.keySet()) {
      if (inp == busGeneratorWishboneSignals.datInEntry) {
        continue;
      }
      final var inpName = masterInputs.get(inp);
      result.append((isVHDL) ? "  " : "  assign ");
      result.append(inpName);
      result.append((isVHDL) ? " <=\n      " : " =\n      ");
      var firstEnty = inp != busGeneratorWishboneSignals.errorEntry;
      if (!firstEnty) {
        result.append(arbiterError);
      }
      for (var slaveEntry : slaves.keySet()) {
        final var slaveSignals = slaves.get(slaveEntry).getSignals();
        if (firstEnty) {
          result.append(slaveSignals.get(inp).getName());
          firstEnty = false;
        } else {
          result.append((isVHDL) ? " or\n      " : " |\n      ");
          result.append(slaveSignals.get(inp).getName());
        }
      }
      result.append(";\n");
    }
    result.append("\n");
    return result.toString();
  }

  public String getSlaveSignals(boolean isVHDL) {
    final var result = new StringBuilder();
    final var slaveInputs = busGeneratorWishboneSignals.getSlaveInputMap();
    result.append(getRemark(" Here all slave inputs are mapped", 2, isVHDL));
    for (var slaveEntry : slaves.keySet()) {
      final var slaveSignals = slaves.get(slaveEntry).getSignals();
      for (var inp : slaveInputs.keySet()) {
        if (inp == busGeneratorWishboneSignals.datInEntry) {
          continue;
        }
        result.append("  "+getAssignment(slaveSignals.get(inp).getName(), slaveInputs.get(inp), isVHDL)+"\n");
      }
    }
    for (var inp : slaveInputs.keySet()) {
      if (inp == busGeneratorWishboneSignals.datInEntry) {
        continue;
      }
      final var inpName = slaveInputs.get(inp);
      result.append((isVHDL) ? "  " : "  assign ");
      result.append(inpName);
      result.append((isVHDL) ? " <=\n      " : " =\n      ");
      var firstEnty = true;
      for (var masterEntry : masters.keySet()) {
        final var masterMaskedName = masters.get(masterEntry).getSignals().get(inp).getMaskedSignalName();
        final var masterName = (masterMaskedName != null) ? masterMaskedName :
            masters.get(masterEntry).getSignals().get(inp).getName();
        if (firstEnty) {
          result.append(masterName);
          firstEnty = false;
        } else {
          result.append((isVHDL) ? " or\n      " : " |\n      ");
          result.append(masterName);
        }
      }
      result.append(";\n");
    }
    result.append("\n");
    return result.toString();
  }

  public String getArbiter(boolean isVHDL, boolean withTimeout) {
    final var result = new StringBuilder();
    result.append(getRemark(" Here the arbiter is defined", 2, isVHDL));
    result.append("  "+getAssignment(arbiterBusEnables, arbiterInternalSignals[1], isVHDL)+"\n");
    final var andOpp = (isVHDL) ? "and" : "&";
    if (withTimeout) {
      var str = String.format("%s %s %s", arbiterInternalSignals[3], andOpp, arbiterInternalSignals[10]);
      result.append("  "+getAssignment(arbiterError, str, isVHDL)+"\n");
    }
    final var zeroIdx = (isVHDL) ? "(0)" : "[0]";
    final var notOpp = (isVHDL) ? "not " : "~";
    final var zeroVal = (isVHDL) ? "'0'" : "1'b0";
    final var oneVal = (isVHDL) ? "'1'" : "1'b1";
    final var zeroVect = new StringBuilder();
    for (var nr = 0; nr < nrOfMasters; nr++) {
      zeroVect.append("0");
    }
    final var zero = zeroVect.toString();
    result.append("  "+getAssignment(arbiterInternalSignals[4]+zeroIdx, notOpp+arbiterBusCycs+zeroIdx, isVHDL)+"\n");
    result.append("  "+getAssignment(arbiterInternalSignals[5]+zeroIdx, zeroVal, isVHDL)+"\n");
    result.append("  "+getAssignment(arbiterInternalSignals[6]+zeroIdx, arbiterBusCycs+zeroIdx, isVHDL)+"\n");
    result.append("  "+getAssignment(arbiterInternalSignals[7]+zeroIdx, zeroVal, isVHDL)+"\n");
    String cond;
    if (isVHDL) {
      cond = String.format("((%s and %s) = \"%s\") and ((%s and %s) = \"%s\")", 
          arbiterBusCycs, arbiterInternalSignals[1], zero, arbiterBusLocks, arbiterInternalSignals[1], zero);
    } else {
      cond = String.format("((%s & %s) == %d'd0) && ((%s & %s) == %d'd0)", 
          arbiterBusCycs, arbiterInternalSignals[1], nrOfMasters, arbiterBusLocks, arbiterInternalSignals[1], nrOfMasters);
    }
    result.append(getWhenElse(arbiterInternalSignals[11], cond, arbiterInternalSignals[3], zeroVal, isVHDL));
    if (withTimeout) {
      if (isVHDL) {
        cond = String.format("%s = x\"0000\"", arbiterInternalSignals[2]);
      } else {
        cond = String.format("%s == 16'd0", arbiterInternalSignals[2]);
      }
      result.append(getWhenElse(arbiterInternalSignals[10], cond, oneVal, zeroVal, isVHDL));
    }
    if (isVHDL) {
      cond = String.format("%s = 1 or %s = \"%s\"", arbiterGeneric, arbiterInternalSignals[7], zero);
    } else {
      cond = String.format("%s == 1 || %s == %d'd0", arbiterGeneric, arbiterInternalSignals[7], nrOfMasters);
    }
    result.append(getWhenElse(arbiterInternalSignals[8], cond, arbiterInternalSignals[6], arbiterInternalSignals[7], isVHDL));
    if (isVHDL) {
      cond = String.format("%s /= \"%s\" and %s = '0'", arbiterBusCycs, zero, arbiterInternalSignals[3]);
    } else {
      cond = String.format("%s != %d'd0 && %s == 1'b0", arbiterBusCycs, nrOfMasters, arbiterInternalSignals[3]);
    }
    result.append(getWhenElse(arbiterInternalSignals[9], cond, oneVal, zeroVal, isVHDL));
    result.append("\n");
    if (nrOfMasters > 1) {
      // here we make the generate block
      if (isVHDL) {
        result.append(String.format("  genMasks : for i in 1 to %d generate\n", nrOfMasters - 1));
        result.append(String.format("    %s(i) <= %s(i-1) and not(%s(i));\n",
            arbiterInternalSignals[4], arbiterInternalSignals[4], arbiterBusCycs));
        result.append(String.format("    %s(i) <= %s(i) and %s(i-1);\n", 
            arbiterInternalSignals[6], arbiterBusCycs, arbiterInternalSignals[4]));
        result.append(String.format("    %s(i) <= %s(i) or (%s(i-1) and not(%s(i)));\n", 
            arbiterInternalSignals[5], arbiterInternalSignals[0], arbiterInternalSignals[5], arbiterBusCycs));
        result.append(String.format("    %s(i) <= %s(i-1) and %s(i);\n", 
            arbiterInternalSignals[7], arbiterInternalSignals[5], arbiterBusCycs));
        result.append("  end generate genMasks;\n");
      } else {
        result.append("""
          genvar i;
          generate
        """);
        result.append(String.format("    for (i = 1; i < %d; i = i + 1)\n    begin : arbiterGen\n", nrOfMasters));
        result.append(String.format("      assign %s[i] = %s[i-1] & ~%s[i];\n", 
            arbiterInternalSignals[4], arbiterInternalSignals[4], arbiterBusCycs));
        result.append(String.format("      assign %s[i] = %s[i] & %s[i-1];\n", 
            arbiterInternalSignals[6], arbiterBusCycs, arbiterInternalSignals[4]));
        result.append(String.format("      assign %s[i] = %s[i] | (%s[i-1] & ~%s[i]);\n", 
            arbiterInternalSignals[5], arbiterInternalSignals[0], arbiterInternalSignals[5], arbiterBusCycs));
        result.append(String.format("      assign %s[i] = %s[i-1] & %s[i];\n", 
            arbiterInternalSignals[7], arbiterInternalSignals[5], arbiterBusCycs));
        result.append("""
            end
          endgenerate
        """);
      }
      result.append("\n");
      final var AckSignal = busGeneratorWishboneSignals.getMasterInputMap().get(busGeneratorWishboneSignals.ackEntry);
      if (isVHDL) {
        result.append(String.format("""
          arb_1 : process( CLK_O ) is
          begin
            if (rising_edge(CLK_O)) then
              if (RST_O = '1' or %s = '1') then
                %s <= '0';
                %s <= (others => '0');
              elsif (%s = '1') then
                %s <= '1';
                %s <= %s;
              end if;
            end if;
          end process arb_1;

        """, arbiterInternalSignals[11], 
            arbiterInternalSignals[3], arbiterInternalSignals[1], arbiterInternalSignals[9], 
            arbiterInternalSignals[3], arbiterInternalSignals[1], arbiterInternalSignals[8]));
        result.append(String.format("""
          arb_2 : process( CLK_O ) is
          begin
            if (rising_edge(CLK_O)) then
              if (%s = '1') then
                %s <= %s;
              elsif (%s = '0') then
                %s <= (others => '0');
              end if;
            end if;
          end process arb_2;

        """, arbiterInternalSignals[9], arbiterInternalSignals[0], 
            arbiterInternalSignals[8], arbiterInternalSignals[3], arbiterInternalSignals[0]));
        if (withTimeout) {
          result.append(String.format("""
            arb_3 : process( CLK_O ) is
            begin
              if (rising_edge(CLK_O)) then
                if (%s = '0' or %s = '1') then
                  %s <= (others => '1');
                elsif (%s = '0') then
                  %s <= std_logic_vector(unsigned(%s) - to_unsigned(1,16));
                end if;
              end if;
            end process arb_3;
          """, arbiterInternalSignals[3], AckSignal, arbiterInternalSignals[2], arbiterInternalSignals[10],
              arbiterInternalSignals[2], arbiterInternalSignals[2]));
        }
      } else {
        result.append("""
          always @(posedge CLK_O)
          begin
        """);
        result.append(String.format("    %s <= (RST_O == 1'b1 || %s == 1'b1) ? 1'b0 : (%s == 1'b1) ? 1'b1 : %s;\n", 
          arbiterInternalSignals[3], arbiterInternalSignals[11], arbiterInternalSignals[9], arbiterInternalSignals[3]));
        result.append(String.format("    %s <= (RST_O == 1'b1 || %s == 1'b1) ? %d'd0 : (%s == 1'b1) ? %s : %s;\n", 
          arbiterInternalSignals[1], arbiterInternalSignals[11], nrOfMasters, arbiterInternalSignals[9], arbiterInternalSignals[8], arbiterInternalSignals[1]));
        result.append(String.format("    %s <= (%s == 1'b1) ? %s : (%s == 1'b0) ? %d'd0 : %s;\n", 
          arbiterInternalSignals[0], arbiterInternalSignals[9], arbiterInternalSignals[8], arbiterInternalSignals[3], nrOfMasters, arbiterInternalSignals[0]));
        if (withTimeout) {
          result.append(String.format("    %s <= (%s == 1'b0 || %s == 1'b1) ? {16{1'b1}} : (%s == 1'b0) ? %s - 16'd1 : %s;\n", 
            arbiterInternalSignals[2], arbiterInternalSignals[3], AckSignal, arbiterInternalSignals[10], arbiterInternalSignals[2], arbiterInternalSignals[2]));
        }
        result.append("  end\n");
      }
      result.append("\n");
    }
    return result.toString();
  }

  private String getMapSignals(boolean isVHDL) {
    final var result = new StringBuilder();
    if (isVHDL) {
      result.append(String.format("""
        constant %s : integer := %d;
        constant %s : integer := %d;
        constant %s : integer := %d;

      """, 
      busGeneratorWishboneSignals.AddressBitsGeneric, W_ADDR,
      busGeneratorWishboneSignals.DataBitsGeneric, W_DATA,
      arbiterGeneric, 1));
    } else {
      result.append(String.format("""
      localparam %s = %d;
      localparam %s = %d;
      localParam %s = %d;

      """, 
      busGeneratorWishboneSignals.AddressBitsGeneric, W_ADDR,
      busGeneratorWishboneSignals.DataBitsGeneric, W_DATA,
      arbiterGeneric, 1));
    }
    result.append(getRemark("""
    Here all signals are defined that are used to connect the
    master and slaves to the shared bus component.
    You can copy-paste them in your toplevel file.
    """, 0, isVHDL));
    result.append("\n");
    for (var masterEntry : masters.keySet()) {
      final var masterSignals = masters.get(masterEntry).getSignals();
      for (var sig : masterSignals) {
        result.append(sig.getMapSignalDefinition(isVHDL));
      }
    }
    for (var slaveEntry : slaves.keySet()) {
      final var slaveSignals = slaves.get(slaveEntry).getSignals();
      for (var sig : slaveSignals) {
        result.append(sig.getMapSignalDefinition(isVHDL));
      }
    }
    result.append("  "+busGeneratorPortType.getSignalDefinition("s_SYSCON_CLK_O", 1, isVHDL)+"\n");
    result.append("  "+busGeneratorPortType.getSignalDefinition("s_SYSCON_RST_O", 1, isVHDL)+"\n");
    result.append("\n");
    return result.toString();
  }

  private String getVHDLComponentMap(busHdlComponent comp) {
    final var result = new StringBuilder();
    final var label = comp.getComponent().getName();
    final var signals = comp.getSignals();
    final var compName = comp.getComponent().isSlaveComponent() ? "busSlave_"+label : "busMaster_"+label;
    result.append(String.format("  %s : entity work.%s(yourImplementation)\n", compName, label));
    result.append("  generic map (\n");
    if (comp.getComponent().isSlaveComponent()) {
      result.append(String.format("    %s => std_logic_vector(to_unsigned(16#%s#, %s)),\n",
          busGeneratorWishboneSignals.BaseAddressGeneric, 
          Long.toHexString(comp.getComponent().getBaseAddress()),
          busGeneratorWishboneSignals.AddressBitsGeneric));
    }
    result.append(String.format("""
        %s => %s,
        %s => %s)
      port map (
    """, 
        busGeneratorWishboneSignals.AddressBitsGeneric, busGeneratorWishboneSignals.AddressBitsGeneric,
        busGeneratorWishboneSignals.DataBitsGeneric, busGeneratorWishboneSignals.DataBitsGeneric));
    var firstEntry = true;
    for (var sig: signals) {
      if (firstEntry) {
        result.append(String.format("    %s => %s", 
          sig.getPortName(), sig.getMapSignalName()));
        firstEntry = false;
      } else {
        result.append(String.format(",\n    %s => %s",
          sig.getPortName(), sig.getMapSignalName()));
      }
    }
    result.append(");\n\n");
    return result.toString();
  }

  private String getVerilogComponentMap(busHdlComponent comp) {
    final var result = new StringBuilder();
    final var label = comp.getComponent().getName();
    final var signals = comp.getSignals();
    final var compName = comp.getComponent().isSlaveComponent() ? "busSlave_"+label : "busMaster_"+label;
    result.append(String.format("  %s #(\n", label));
    if (comp.getComponent().isSlaveComponent()) {
      result.append(String.format("    .%s(%s),\n",
          busGeneratorWishboneSignals.BaseAddressGeneric,
          String.format("'h%s", Long.toHexString(comp.getComponent().getBaseAddress()))));
    }
    result.append(String.format("""
        .%s(%s),
        .%s(%s)
      ) %s (
    """, 
        busGeneratorWishboneSignals.AddressBitsGeneric, busGeneratorWishboneSignals.AddressBitsGeneric,
        busGeneratorWishboneSignals.DataBitsGeneric, busGeneratorWishboneSignals.DataBitsGeneric,
        compName));
    var firstEntry = true;
    for (var sig: signals) {
      if (firstEntry) {
        result.append(String.format("    .%s(%s)", 
          sig.getPortName(), sig.getMapSignalName()));
        firstEntry = false;
      } else {
        result.append(String.format(",\n    .%s(%s)",
          sig.getPortName(), sig.getMapSignalName()));
      }
    }
    result.append(");\n\n");
    return result.toString();
  }

  private String getComponentMap(busHdlComponent comp, boolean isVHDL) {
    if (isVHDL) {
      return getVHDLComponentMap(comp);
    } else {
      return getVerilogComponentMap(comp);
    }
  }

  private String getComponentMaps(boolean isVHDL) {
    final var result = new StringBuilder();
    result.append(getRemark("""
    Here all your master and slave connections are mapped
    Probably you have to change it slightly to adapt to your
    masters/slaves
    """, 0, isVHDL));
    result.append("\n");
    for (var masterEntry : masters.keySet()) {
      final var master = masters.get(masterEntry);
      result.append(getComponentMap(master, isVHDL));
    }
    for (var slaveEntry : slaves.keySet()) {
      final var slave = slaves.get(slaveEntry);
      result.append(getComponentMap(slave, isVHDL));
    }
    return result.toString();
  }

  private String getBusMap(boolean isVHDL) {
    final var result = new StringBuilder();
    result.append(getRemark("""
    Finally here the wishboneBus is mapped
    """, 0, isVHDL));
    if (isVHDL) {
      result.append(String.format("""
        wishboneBus : entity work.%s(autogenerated)
        generic map (
            %s => %s,
            %s => %s,
            %s => %s
        ) port map (
      """, 
        busTopLevelName,
        busGeneratorWishboneSignals.AddressBitsGeneric, busGeneratorWishboneSignals.AddressBitsGeneric,
        busGeneratorWishboneSignals.DataBitsGeneric, busGeneratorWishboneSignals.DataBitsGeneric,
        arbiterGeneric, arbiterGeneric));
    } else {
      result.append(String.format("""
        %s #(
          .%s(%s),
          .%s(%s),
          .%s(%s)
        ) wishboneBus (
      """, 
        busTopLevelName,
        busGeneratorWishboneSignals.AddressBitsGeneric, busGeneratorWishboneSignals.AddressBitsGeneric,
        busGeneratorWishboneSignals.DataBitsGeneric, busGeneratorWishboneSignals.DataBitsGeneric,
        arbiterGeneric, arbiterGeneric));
    }
    final var formatStr = (isVHDL) ? "    %s => %s" : "    .%s(%s)";
    for (var masterEntry : masters.keySet()) {
      final var masterSignals = masters.get(masterEntry).getSignals();
      for (var sig : masterSignals) {
        result.append(String.format(formatStr+",\n", sig.getName(), sig.getMapSignalName()));
      }
    }
    for (var slaveEntry : slaves.keySet()) {
      final var slaveSignals = slaves.get(slaveEntry).getSignals();
      for (var sig : slaveSignals) {
        result.append(String.format(formatStr+",\n", sig.getName(), sig.getMapSignalName()));
      }
    }
    result.append(String.format(formatStr+",\n", "CLK_O", "s_SYSCON_CLK_O"));
    result.append(String.format(formatStr+");\n\n", "RST_O", "s_SYSCON_RST_O"));
    return result.toString();
  }

  private boolean generateTemplate() {
    var filenameVHDL = baseDirectory+vhdlDir+busTopTemplateName+vhdlExtention;
    var fileNameVerilog = baseDirectory+verilogDir+busTopTemplateName+verilogExtention;
    try {
      final var vhdlFile = new FileWriter(filenameVHDL);
      final var verilogFile = new FileWriter(fileNameVerilog);
      vhdlFile.write(getMapSignals(true));
      verilogFile.write(getMapSignals(false));
      vhdlFile.write(getComponentMaps(true));
      verilogFile.write(getComponentMaps(false));
      vhdlFile.write(getBusMap(true));
      verilogFile.write(getBusMap(false));
      vhdlFile.close();
      verilogFile.close();
    } catch (IOException e) {
      return false;
    }
    return true;
  }

  public boolean gegerateBus() {
    var filenameVHDL = baseDirectory+vhdlDir+busTopLevelName+vhdlExtention;
    var fileNameVerilog = baseDirectory+verilogDir+busTopLevelName+verilogExtention;
    try {
      final var vhdlFile = new FileWriter(filenameVHDL);
      final var verilogFile = new FileWriter(fileNameVerilog);
      vhdlFile.write(getPreamble(true, busTopLevelName, false));
      verilogFile.write(getPreamble(false, busTopLevelName, false));
      vhdlFile.write(getPorts(true));
      verilogFile.write(getPorts(false));
      vhdlFile.write(getSignals(true, slaves, true));
      verilogFile.write(getSignals(false, slaves, true));
      vhdlFile.write("begin\n\n");
      vhdlFile.write(getSyscon(true));
      verilogFile.write(getSyscon(false));
      vhdlFile.write(getArbiterCons(true));
      verilogFile.write(getArbiterCons(false));
      vhdlFile.write(getMaskedDefinitions(true, slaves));
      verilogFile.write(getMaskedDefinitions(false, slaves));
      vhdlFile.write(getDataConnetions(true));
      verilogFile.write(getDataConnetions(false));
      vhdlFile.write(getMasterConnections(true));
      verilogFile.write(getMasterConnections(false));
      vhdlFile.write(getSlaveSignals(true));
      verilogFile.write(getSlaveSignals(false));
      vhdlFile.write(getArbiter(true, true));
      verilogFile.write(getArbiter(false, true));
      vhdlFile.write("end architecture autogenerated;\n");
      verilogFile.write("endmodule");
      vhdlFile.close();
      verilogFile.close();
    } catch (IOException e) {
      return false;
    }
    return true;
  }

  boolean generateHdl() {
    return gegerateBus() && generateTemplate();
  }

  public boolean createHdlFiles() {
    if (!canGenerate()) {
      return false;
    }
    if (!generateHdl()) {
      return false;
    }
    return true;
  }
}
