public class busGeneratorPortType {
  private String name;
  private String prefix = "";
  private Boolean isAnInput;
  private Boolean genericNrOfBits;
  private String genericName;
  private int fixedNrOfBits;
  private boolean needsToBeMasked = false;

  private busGeneratorPortType(String name, boolean isInput, String genericBits, boolean mask) {
    this.name = (isInput) ? name+"_I" : name+"_O";
    this.isAnInput = isInput;
    this.genericNrOfBits = true;
    this.genericName = genericBits;
    this.fixedNrOfBits = 0;
    this.needsToBeMasked = mask;
  }

  private busGeneratorPortType(String name, boolean isInput, int nrOfBits, boolean mask) {
    this.name = (isInput) ? name+"_I" : name+"_O";
    this.isAnInput = isInput;
    this.genericNrOfBits = false;
    this.genericName = "";
    this.fixedNrOfBits = nrOfBits;
    this.needsToBeMasked = mask;
  }

  public static busGeneratorPortType getGenericInputPin(String name, String genName) {
    return new busGeneratorPortType(name, true, genName, false);
  }

  public static busGeneratorPortType getInputPin(String name, int nrOfBits) {
    return new busGeneratorPortType(name, true, nrOfBits, false);
  }

  public static busGeneratorPortType getGenericOutputPin(String name, String genName) {
    return new busGeneratorPortType(name, false, genName, false );
  }

  public static busGeneratorPortType getMaskedGenericOutputPin(String name, String genName) {
    return new busGeneratorPortType(name, false, genName, true );
  }

  public static busGeneratorPortType getOutputPin(String name, int nrOfBits) {
    return new busGeneratorPortType(name, false, nrOfBits, false);
  }

  public static busGeneratorPortType getMaskedOutputPin(String name, int nrOfBits) {
    return new busGeneratorPortType(name, false, nrOfBits, true);
  }

  public boolean isGeneric() {
    return genericNrOfBits;
  }

  public String getGeneric() {
    return genericName;
  }

  public int getNrOfBits() {
    return fixedNrOfBits;
  }

  public void setPrefix(String prefix) {
    this.prefix = prefix.trim().replaceAll("\\s+ ", "_");
  }

  public String getPortName() {
    return name;
  }

  public String getName() {
    return prefix+"_"+name;
  }

  public String getZeroString(boolean isVHDL) {
    final var result = new StringBuffer();
    if (isVHDL) {
      if (genericNrOfBits || fixedNrOfBits > 1) {
        result.append("(others => '0')");
      } else {
        result.append("'0'");
      }
    } else {
      if (genericNrOfBits) {
        result.append(String.format("{%s{1'b0}}", genericName));
      } else if (fixedNrOfBits > 1) {
        result.append(String.format("{%d{1'b0}}", fixedNrOfBits));
      } else {
        result.append("1'b0");
      }
    }
    return result.toString();
  } 

  public boolean needsToBeMasked() {
    return needsToBeMasked;
  }

  public void setMasked() {
    needsToBeMasked = true;
  }

  public String getMaskedSignalName() {
    if (!needsToBeMasked) {
      return null;
    }
    return "s_masked_"+getName();
  }

  private String getVhdlType() {
    final var result = new StringBuilder();
    if (genericNrOfBits || fixedNrOfBits > 1) {
      result.append("std_logic_vector(");
      if (genericNrOfBits) {
        result.append("("+genericName+" - 1)");
      } else {
        result.append(Integer.toString(fixedNrOfBits - 1));
      }
      result.append(" downto 0)");
    } else {
      result.append("std_logic");
    }
    return result.toString();
  }

  private String getVerilogType() {
    final var result = new StringBuilder();
    result.append("wire ");
    if (genericNrOfBits || fixedNrOfBits > 1) {
      result.append("[");
      if (genericNrOfBits) {
        result.append(genericName+" - 1");
      } else {
        result.append(Integer.toString(fixedNrOfBits - 1));
      }
      result.append(":0] ");
    }
    return result.toString();
  }

  public String getVhdlMaskedSignalDefinition() {
    if (!needsToBeMasked) {
      return null;
    }
    return "signal "+getMaskedSignalName()+" : "+getVhdlType()+";";
  }

  public String getVerilogMaskedSignalDefinition() {
    if (!needsToBeMasked) {
      return null;
    }
    return getVerilogType()+getMaskedSignalName()+";";
  }

  public String getMapSignalName() {
    return "s_"+getName();
  }

  public String getMapSignalDefinition(boolean isVHDL) {
    if (isVHDL) {
      return "  signal "+getMapSignalName()+" : "+getVhdlType()+";\n";
    } else {
      return "  "+getVerilogType()+getMapSignalName()+";\n";
    }
  }

  private static String getSignalRest(String name, int nrOfBits, boolean isVHDL) {
    final var result = new StringBuilder();
    if (!isVHDL && nrOfBits > 1) {
      result.append(String.format("[%d:0] ", nrOfBits - 1));
    }
    result.append(name);
    if (isVHDL) {
      result.append(" : ");
      if (nrOfBits > 1) {
        result.append(String.format("std_logic_vector(%d downto 0)", nrOfBits - 1));
      } else {
        result.append("std_logic");
      }
    }
    result.append(";");
    return result.toString();
  }

  public static String getSignalDefinition(String name, int nrOfBits, boolean isVHDL) {
    final var result = new StringBuilder();
    result.append((isVHDL) ? "signal " : "wire ");
    result.append(getSignalRest(name, nrOfBits, isVHDL));
    return result.toString();
  }

  public static String getSignalDefinition(String name, int nrOfBits, boolean isVHDL, boolean isReg) {
    final var result = new StringBuilder();
    result.append((isVHDL) ? "signal " : (isReg) ? "reg " : "wire ");
    result.append(getSignalRest(name, nrOfBits, isVHDL));
    return result.toString();
  }

  public static String getSignalDefinition(String name, String generic, boolean isVHDL) {
    final var result = new StringBuilder();
    result.append((isVHDL) ? "signal " : "wire ");
    if (!isVHDL) {
      result.append(String.format("[%s - 1:0] ", generic));
    }
    result.append(name);
    if (isVHDL) {
      result.append(" : ");
      result.append(String.format("std_logic_vector(%s - 1 downto 0)", generic));
    }
    result.append(";");
    return result.toString();
  }

  public String getVHDLPort(boolean opositeSide) {
    final var result = new StringBuilder();
    result.append(getName());
    result.append(" : ");
    if (isAnInput ^ opositeSide) {
      result.append("in  ");
    } else {
      result.append("out ");
    }
    result.append(getVhdlType());
    return result.toString();
  }

  public String getVerilogPort(boolean opositeSide) {
    final var result = new StringBuilder();
    if (isAnInput ^ opositeSide) {
      result.append("input  ");
    } else {
      result.append("output ");
    }
    result.append(getVerilogType());
    result.append(getName());
    return result.toString();
  }
}
