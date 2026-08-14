import java.io.FileWriter;
import java.io.IOException;
import java.util.TreeMap;

public class busGeneratorCrossbarBusGenerator extends busGeneratorSharedBusGenerator {

  private static String slaveArbiterName = "wishBoneSlaveArbiter";
  TreeMap<Long, busHdlComponent> arbiterSlaves = new TreeMap<Long, busHdlComponent>();

  busGeneratorCrossbarBusGenerator(busGeneratorFrame parent) {
    super(parent);
    busTopLevelName = "wishBoneCrossbarBusTop";
    busTopTemplateName = "wishBoneCrossbarBusTemplate";
    initArbiterSlave();
  }

  busGeneratorCrossbarBusGenerator(busGeneratorFrame parent, String directory) {
    super(parent, directory);
    busTopLevelName = "wishBoneCrossbarBusTop";
    busTopTemplateName = "wishBoneCrossbarBusTemplate";
    initArbiterSlave();
  }

  private void initArbiterSlave() {
    final var arbSlave = new busGeneratorObject(0, 2, true);
    arbSlave.setName("slave_port");
    final var arbComp = new busHdlComponent(arbSlave);
    arbiterSlaves.put(0L, arbComp);
  }

  @Override
  public String getSyscon(boolean isVHDL) {
    final var result = new StringBuilder();
    result.append(getRemark(" Here we connect all clocks and resets to the syscon", 2, isVHDL));
    for (var slaveEntry : arbiterSlaves.keySet()) {
      final var slave = arbiterSlaves.get(slaveEntry);
      result.append("  "+getAssignment(slave.getSignals().get(busGeneratorWishboneSignals.clockEntry).getName(), "CLK_O", isVHDL)+"\n");
      result.append("  "+getAssignment(slave.getSignals().get(busGeneratorWishboneSignals.resetEntry).getName(), "RST_O", isVHDL)+"\n");
    }
    result.append("\n");
    return result.toString();
  }

  @Override
  public String getArbiterCons(boolean isVHDL) {
    final var result = new StringBuilder();
    result.append(getRemark(" Here the arbiter signals are mapped", 2, isVHDL));
    final var index = (isVHDL) ? "(%d)" : "[%d]";
    final var zero = (isVHDL) ? "'0'" : "1'b0";
    for (var idx = 0 ; idx < nrOfMasters; idx++) {
      final var master = masters.get(idx);
      if (master == null) {
        result.append((isVHDL) ? "  " : "  assign ");
        result.append(arbiterBusLocks);
        result.append(String.format(index, idx));
        result.append((isVHDL) ? " <= " : " = ");
        result.append(zero+";\n");
      } else {
        final var masterSigName = master.getSignals().get(busGeneratorWishboneSignals.lockEntry).getName();
        final var masterAddrName = master.getSignals().get(busGeneratorWishboneSignals.addrEntry).getName();
        final var target = arbiterBusLocks+String.format(index, idx);
        final var condition = (isVHDL) ?
          String.format("(unsigned(%s) >= unsigned(%s) and unsigned(%s) <= unsigned(%s))", 
            masterAddrName, busGeneratorWishboneSignals.BaseAddressGeneric,
            masterAddrName, busGeneratorWishboneSignals.EndAddressGeneric) :
          String.format("%s >= %s && %s <= %s", 
            masterAddrName, busGeneratorWishboneSignals.BaseAddressGeneric,
            masterAddrName, busGeneratorWishboneSignals.EndAddressGeneric);
        result.append(getWhenElse(target, condition, masterSigName, zero, isVHDL));
      }
    }
    for (var idx = 0 ; idx < nrOfMasters; idx++) {
      final var master = masters.get(idx);
      if (master == null) {
        result.append((isVHDL) ? "  " : "  assign ");
        result.append(arbiterBusCycs);
        result.append(String.format(index, idx));
        result.append((isVHDL) ? " <= " : " = ");
        result.append(zero+";\n");
      } else {
        final var masterSigName = master.getSignals().get(busGeneratorWishboneSignals.cycEntry).getName();
        final var masterAddrName = master.getSignals().get(busGeneratorWishboneSignals.addrEntry).getName();
        final var target = arbiterBusCycs+String.format(index, idx);
        final var condition = (isVHDL) ?
          String.format("(unsigned(%s) >= unsigned(%s) and unsigned(%s) <= unsigned(%s))", 
            masterAddrName, busGeneratorWishboneSignals.BaseAddressGeneric,
            masterAddrName, busGeneratorWishboneSignals.EndAddressGeneric) :
          String.format("%s >= %s && %s <= %s", 
            masterAddrName, busGeneratorWishboneSignals.BaseAddressGeneric,
            masterAddrName, busGeneratorWishboneSignals.EndAddressGeneric);
        result.append(getWhenElse(target, condition, masterSigName, zero, isVHDL));
      }
    }
    result.append("\n");
    return result.toString();
  }

  @Override
  public String getDataConnetions(boolean isVHDL) {
    final var result = new StringBuilder();
    result.append(getRemark(" Here the slave -> master databus is defined", 2, isVHDL));
    final var slaveDatO = arbiterSlaves.get(0L).getSignals().get(busGeneratorWishboneSignals.datOutEntry).getName();
    final var index = (isVHDL) ? "(%d)" : "[%d]";
    final var one = (isVHDL) ? " = '1'" : " == 1'b1";
    final var zero = (isVHDL) ? "(others => '0')" : String.format("{%s{1'b0}}", busGeneratorWishboneSignals.DataBitsGeneric);
    for (var masterEntry : masters.keySet()) {
      final var master = masters.get(masterEntry);
      final var masterDatI = master.getSignals().get(busGeneratorWishboneSignals.datInEntry).getName();
      final var condition = arbiterBusEnables+String.format(index, masterEntry)+one;
      result.append(getWhenElse(masterDatI, condition, slaveDatO, zero, isVHDL));
    }
    result.append("\n");
    result.append(getRemark(" Here the master -> slave databus is defined", 2, isVHDL));
    var firstEntry = true;
    final var slaveDatI = arbiterSlaves.get(0L).getSignals().get(busGeneratorWishboneSignals.datInEntry).getName();
    result.append((isVHDL) ? "  " : "  assign ");
    result.append(slaveDatI);
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

  @Override
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
        final var slaveSig = arbiterSlaves.get(0L).getSignals().get(inp).getName();
        final var enaVarIndex = (isVHDL) ? String.format("(%d)", masterEntry) :
            String.format("[%d]", masterEntry);
        result.append("  "+getAssignment(masterSignals.get(inp).getName(), 
            slaveSig+andOpp+arbiterBusEnables+enaVarIndex, isVHDL)+"\n");
      }
    }
    result.append("\n");
    return result.toString();
  }

  @Override
  public String getSlaveSignals(boolean isVHDL) {
    final var result = new StringBuilder();
    final var slaveInputs = busGeneratorWishboneSignals.getSlaveInputMap();
    result.append(getRemark(" Here all slave inputs are mapped", 2, isVHDL));
    for (var inp : slaveInputs.keySet()) {
      if (inp == busGeneratorWishboneSignals.datInEntry) {
        continue;
      }
      final var inpName = arbiterSlaves.get(0L).getSignals().get(inp).getName();
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

  private String getArbConSignals(boolean isVHDL) {
    final var result = new StringBuilder();
    for (var masterEntry : masters.keySet()) {
      final var masterSignals = masters.get(masterEntry).getSignals();
      for (var sig : masterSignals) {
        final var idx = masterSignals.indexOf(sig);
        if (idx == busGeneratorWishboneSignals.ackEntry) {
          result.append((isVHDL) ? String.format("  signal s_%s : std_logic;\n", sig.getName()) :
            String.format("  wire s_%s;\n", sig.getName()));
        }
        if (idx == busGeneratorWishboneSignals.clockEntry ||
            idx == busGeneratorWishboneSignals.resetEntry ||
            sig.isOutput()) {
          continue;
        }
        for (var slaveEntry : slaves.keySet()) {
          final var slaveName = slaves.get(slaveEntry).getComponent().getName();
          result.append(sig.getMapSignalDefinition(isVHDL, slaveName));
        }
      }
      final var errSig = String.format("s_%s_arbiterTimeOut", masters.get(masterEntry).getComponent().getName());
      final var errCounter = String.format("s_%s_arbiterTimeOutCounter", masters.get(masterEntry).getComponent().getName());
      result.append(String.format((isVHDL) ? "  signal %s : std_logic;\n" : "  wire %s;\n", errSig));
      result.append(String.format((isVHDL) ? "  signal %s : unsigned(15 downto 0);\n" : 
          "  reg [15:0] %s;\n", errCounter));
    }
    result.append("\n");
    return result.toString();
  }

  private String getMasterClockReset(boolean isVHDL) {
    final var result = new StringBuilder();
    result.append(getRemark(" Here all master clock connections are defined", 2, isVHDL));
    for (var masterEntry : masters.keySet()) {
      final var masterSignals = masters.get(masterEntry).getSignals();
      result.append("  "+getAssignment(masterSignals.get(busGeneratorWishboneSignals.clockEntry).getName(), "CLK_O", isVHDL)+"\n");
      result.append("  "+getAssignment(masterSignals.get(busGeneratorWishboneSignals.resetEntry).getName(), "RST_O", isVHDL)+"\n");
    }
    result.append("\n");
    return result.toString();
  }

  private String getArbiterMap(boolean isVHDL) {
    final var result = new StringBuilder();
    var idx = 0;
    final var mapStr = (isVHDL) ? "    %s => %s" : "    .%s(%s)";
    for (var slaveEntry : slaves.keySet()) {
      final var slave = slaves.get(slaveEntry).getComponent();
      final var slaveSignals = slaves.get(slaveEntry).getSignals();
      final var compName = String.format("arbiter%d", idx++);
      if (isVHDL) {
        result.append(String.format("""
          %s : entity work.%s(autogenerated)
          generic map (
        """, compName, slaveArbiterName));
      } else {
        result.append(String.format("""
          %s #(
        """, slaveArbiterName));
      }
      result.append(String.format(mapStr+",\n", busGeneratorWishboneSignals.AddressBitsGeneric, busGeneratorWishboneSignals.AddressBitsGeneric));
      result.append(String.format(mapStr+",\n", busGeneratorWishboneSignals.DataBitsGeneric, busGeneratorWishboneSignals.DataBitsGeneric));
      final var hexFormat = (isVHDL) ? "std_logic_vector(to_unsigned(16#%s#, "+busGeneratorWishboneSignals.AddressBitsGeneric+"))" : "'h%s";
      result.append(String.format(mapStr+",\n", busGeneratorWishboneSignals.BaseAddressGeneric,
        String.format(hexFormat, Long.toHexString(slave.getBaseAddress()))));
      result.append(String.format(mapStr+",\n", busGeneratorWishboneSignals.EndAddressGeneric,
        String.format(hexFormat, Long.toHexString(slave.getEndAddress()))));
      result.append(String.format(mapStr, arbiterGeneric, arbiterGeneric));
      if (isVHDL) {
        result.append(")\n  port map (\n");
      } else {
        result.append(String.format("\n  ) %s (\n", compName));
      }
      for (var masterEntry : masters.keySet()) {
        final var masterSignals = masters.get(masterEntry).getSignals();
        for (final var sig : masterSignals) {
          if (masterSignals.indexOf(sig) == busGeneratorWishboneSignals.clockEntry ||
              masterSignals.indexOf(sig) == busGeneratorWishboneSignals.resetEntry) {
            continue;
          }
          final var mapName = (sig.isOutput()) ? sig.getName() : sig.getMapSignalName(slave.getName());
          result.append(String.format(mapStr+",\n", sig.getName(), mapName));
        }
      }
      final var arbSigs = arbiterSlaves.get(0L).getSignals();
      for (var i = 0; i < arbSigs.size(); i++) {
        result.append(String.format(mapStr+",\n", arbSigs.get(i).getName(), slaveSignals.get(i).getName()));
      }
      result.append(String.format(mapStr+",\n", "CLK_O", "CLK_O"));
      result.append(String.format(mapStr+");\n\n", "RST_O", "RST_O"));
    }
    return result.toString();
  }

  private String getMasterOrs(boolean isVHDL) {
    final var result = new StringBuilder();
    result.append(getRemark(" Here the master output signals are defined", 2, isVHDL));
    for (final var masterEntry : masters.keySet()) {
      final var masterSignals = masters.get(masterEntry).getSignals();
      for (var i = 2; i < masterSignals.size(); i++) {
        final var sig = masterSignals.get(i);
        if (sig.isOutput()) {
          continue;
        }
        final var name = sig.getName();
        if (isVHDL) {
          if (i == busGeneratorWishboneSignals.ackEntry) {
            result.append(String.format("  %s <= s_%s;\n", name, name));
            result.append(String.format("  s_%s <=\n    ", name));
          } else {
            result.append(String.format("  %s <=\n    ", name));
          }
        } else {
          if (i == busGeneratorWishboneSignals.ackEntry) {
            result.append(String.format("  assign %s = s_%s;\n", name, name));
            result.append(String.format("  assign s_%s =\n    ", name));
          } else {
            result.append(String.format("  assign %s =\n    ", name));
          }
        }
        var first = true;
        for (var slaveEntry : slaves.keySet()) {
          final var slave = slaves.get(slaveEntry).getComponent().getName();
          if (first) {
            result.append(sig.getMapSignalName(slave));
            first = false;
          } else {
            result.append((isVHDL) ? " or\n    " : " |\n    ");
            result.append(sig.getMapSignalName(slave));
          }
        }
        if (i == busGeneratorWishboneSignals.errorEntry) {
          result.append((isVHDL) ? " or\n    " : " |\n    ");
          result.append(String.format("s_%s_arbiterTimeOut", masters.get(masterEntry).getComponent().getName()));
        }
        result.append(";\n\n");
      }
    }
    return result.toString();
  }

  private String getTimeOutCounters(boolean isVHDL) {
    final var result = new StringBuilder();
    var idx = 0;
    for (final var masterEntry : masters.keySet()) {
      final var masterName = masters.get(masterEntry).getComponent().getName();
      final var masterSignals = masters.get(masterEntry).getSignals();
      final var errSig = String.format("s_%s_arbiterTimeOut", masterName);
      final var errCounter = String.format("s_%s_arbiterTimeOutCounter", masterName);
      if (isVHDL) {
        result.append(String.format("""
          %s <= '1' when %s = to_unsigned(0, 16) else '0';

          proc_%d : process( CLK_O ) is
            begin
              if (rising_edge(CLK_O)) then
                if (RST_O = '1' or 
                    %s = '0' or 
                    %s = '1') then
                  %s <= (others => '1');
                elsif (%s = '0') then
                  %s <= %s - to_unsigned(1, 16);
                end if;
              end if;
            end process proc_%d;
        
        """, errSig, errCounter, 
          idx,
          masterSignals.get(busGeneratorWishboneSignals.cycEntry).getName(),
          "s_"+masterSignals.get(busGeneratorWishboneSignals.ackEntry).getName(),
          errCounter, errSig, errCounter, errCounter, idx++));
      } else {
        result.append(String.format("""
          assign %s = (%s == 16'd0) ? 1'd1 : 1'd0;
          always @(posedge CLK_O)
            begin
              %s <= (RST_O == 1'b1 || %s == 1'b0 || %s == 1'b1) ? {16{1'b1}} :
                    (%s == 1'b0) ? %s - 16'd1 : %s;
            end
        
        """, 
          errSig, errCounter,
          errCounter, masterSignals.get(busGeneratorWishboneSignals.cycEntry).getName(),
          "s_"+masterSignals.get(busGeneratorWishboneSignals.ackEntry).getName(),
        errSig, errCounter, errCounter));
      }
    }
    return result.toString();
  }

  @Override
  public boolean gegerateBus() {
    var filenameVHDL = baseDirectory+vhdlDir+slaveArbiterName+vhdlExtention;
    var fileNameVerilog = baseDirectory+verilogDir+slaveArbiterName+verilogExtention;
    try {
      final var vhdlFile = new FileWriter(filenameVHDL);
      final var verilogFile = new FileWriter(fileNameVerilog);
      vhdlFile.write(getPreamble(true, slaveArbiterName, true));
      verilogFile.write(getPreamble(false, slaveArbiterName, true));
      vhdlFile.write(getMasterPorts(true,true));
      verilogFile.write(getMasterPorts(false, true));
      vhdlFile.write(getSlavePorts(true, arbiterSlaves));
      verilogFile.write(getSlavePorts(false, arbiterSlaves));
      vhdlFile.write(getSysconPort(true, slaveArbiterName));
      verilogFile.write(getSysconPort(false, slaveArbiterName));
      vhdlFile.write(getSignals(true, null, false));
      verilogFile.write(getSignals(false, null, false));
      vhdlFile.write("begin\n\n");
      vhdlFile.write(getSyscon(true));
      verilogFile.write(getSyscon(false));
      vhdlFile.write(getArbiterCons(true));
      verilogFile.write(getArbiterCons(false));
      vhdlFile.write(getMaskedDefinitions(true, null));
      verilogFile.write(getMaskedDefinitions(false, null));
      vhdlFile.write(getDataConnetions(true));
      verilogFile.write(getDataConnetions(false));
      vhdlFile.write(getMasterConnections(true));
      verilogFile.write(getMasterConnections(false));
      vhdlFile.write(getSlaveSignals(true));
      verilogFile.write(getSlaveSignals(false));
      vhdlFile.write(getArbiter(true, false));
      verilogFile.write(getArbiter(false, false));
      vhdlFile.write("end architecture autogenerated;\n");
      verilogFile.write("endmodule");
      vhdlFile.close();
      verilogFile.close();
    } catch (IOException e) {
      return false;
    }
    filenameVHDL = baseDirectory+vhdlDir+busTopLevelName+vhdlExtention;
    fileNameVerilog = baseDirectory+verilogDir+busTopLevelName+verilogExtention;
    try {
      final var vhdlFile = new FileWriter(filenameVHDL);
      final var verilogFile = new FileWriter(fileNameVerilog);
      vhdlFile.write(getPreamble(true, busTopLevelName, false));
      verilogFile.write(getPreamble(false, busTopLevelName, false));
      vhdlFile.write(getMasterPorts(true,false));
      verilogFile.write(getMasterPorts(false, false));
      vhdlFile.write(getSlavePorts(true, slaves));
      verilogFile.write(getSlavePorts(false, slaves));
      vhdlFile.write(getSysconPort(true, busTopLevelName));
      verilogFile.write(getSysconPort(false, busTopLevelName));
      vhdlFile.write(getArbConSignals(true));
      verilogFile.write(getArbConSignals(false));
      vhdlFile.write("begin\n\n");
      vhdlFile.write(getMasterClockReset(true));
      verilogFile.write(getMasterClockReset(false));
      vhdlFile.write(getArbiterMap(true));
      verilogFile.write(getArbiterMap(false));
      vhdlFile.write(getMasterOrs(true));
      verilogFile.write(getMasterOrs(false));
      vhdlFile.write(getTimeOutCounters(true));
      verilogFile.write(getTimeOutCounters(false));
      vhdlFile.write("end architecture autogenerated;\n");
      verilogFile.write("endmodule");
      vhdlFile.close();
      verilogFile.close();
    } catch (IOException e) {
      return false;
    }
    return true;
  }

}
