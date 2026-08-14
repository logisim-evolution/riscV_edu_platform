import java.util.ArrayList;
import java.util.TreeMap;

public class busGeneratorWishboneSignals {
  public static String DataBitsGeneric = "DataBits";
  public static String AddressBitsGeneric = "AddrBits";
  public static String BaseAddressGeneric = "BaseAddress";
  public static String EndAddressGeneric = "EndAddress";
  public static int clockEntry = 0;
  public static int resetEntry = 1;
  public static int ackEntry = 4;
  public static int lockEntry = 8;
  public static int cycEntry = 6;
  public static int datInEntry = 2;
  public static int datOutEntry = 3;
  public static int addrEntry = 5;
  public static int errorEntry = 7;
  private static String[] busNames = {"CLK","RST","DAT","DAT","ACK","ADDR","CYC","ERR","LOCK","SEL","STB","WE","CTI","BTE"};

  public static ArrayList<busGeneratorPortType> getMasterSignals(String prefix) {
    final var result = new ArrayList<busGeneratorPortType>();
    result.add(busGeneratorPortType.getInputPin(busNames[0], 1));
    result.add(busGeneratorPortType.getInputPin(busNames[1], 1));
    result.add(busGeneratorPortType.getGenericInputPin(busNames[2], DataBitsGeneric));
    result.add(busGeneratorPortType.getMaskedGenericOutputPin(busNames[3], DataBitsGeneric));
    result.add(busGeneratorPortType.getInputPin(busNames[4], 1));
    result.add(busGeneratorPortType.getMaskedGenericOutputPin(busNames[5], AddressBitsGeneric));
    result.add(busGeneratorPortType.getMaskedOutputPin(busNames[6], 1));
    result.add(busGeneratorPortType.getInputPin(busNames[7], 1));
    result.add(busGeneratorPortType.getMaskedOutputPin(busNames[8], 1));
    result.add(busGeneratorPortType.getMaskedGenericOutputPin(busNames[9], "("+DataBitsGeneric+" / 8)"));
    result.add(busGeneratorPortType.getMaskedOutputPin(busNames[10], 1));
    result.add(busGeneratorPortType.getMaskedOutputPin(busNames[11], 1));
    result.add(busGeneratorPortType.getMaskedOutputPin(busNames[12], 3));
    result.add(busGeneratorPortType.getMaskedOutputPin(busNames[13], 2));
    if (prefix != null && !prefix.isBlank()) {
      for (var port : result) {
        port.setPrefix(prefix);
      }
    }
    result.get(clockEntry).setSysCon();
    result.get(resetEntry).setSysCon();
    return result;
  }

  public static TreeMap<Integer, String> getMasterInputMap() {
    final var result = new TreeMap<Integer, String>();
    result.put(2, String.format("s_sharedBusMaster_%s", busNames[2]));
    result.put(4, String.format("s_sharedBusMaster_%s", busNames[4]));
    result.put(7, String.format("s_sharedBusMaster_%s", busNames[7]));
    return result;
  }

  public static TreeMap<Integer, String> getSlaveInputMap() {
    final var result = new TreeMap<Integer, String>();
    result.put(2, String.format("s_sharedBusSlave_%s", busNames[2]));
    result.put(5, String.format("s_sharedBusSlave_%s", busNames[5]));
    result.put(6, String.format("s_sharedBusSlave_%s", busNames[6]));
    for (var idx = 8; idx < 14; idx++) {
      result.put(idx, String.format("s_sharedBusSlave_%s", busNames[idx]));
    }
    return result;
  }

  public static ArrayList<busGeneratorPortType> getSlaveSignals(String prefix) {
    final var result = new ArrayList<busGeneratorPortType>();
    result.add(busGeneratorPortType.getInputPin(busNames[0], 1));
    result.add(busGeneratorPortType.getInputPin(busNames[1], 1));
    result.add(busGeneratorPortType.getGenericInputPin(busNames[2], DataBitsGeneric));
    result.add(busGeneratorPortType.getMaskedGenericOutputPin(busNames[3], DataBitsGeneric));
    result.add(busGeneratorPortType.getOutputPin(busNames[4], 1));
    result.add(busGeneratorPortType.getGenericInputPin(busNames[5], AddressBitsGeneric));
    result.add(busGeneratorPortType.getInputPin(busNames[6], 1));
    result.add(busGeneratorPortType.getOutputPin(busNames[7], 1));
    result.add(busGeneratorPortType.getInputPin(busNames[8], 1));
    result.add(busGeneratorPortType.getGenericInputPin(busNames[9], "("+DataBitsGeneric+" / 8)"));
    result.add(busGeneratorPortType.getInputPin(busNames[10], 1));
    result.add(busGeneratorPortType.getInputPin(busNames[11], 1));
    result.add(busGeneratorPortType.getInputPin(busNames[12], 3));
    result.add(busGeneratorPortType.getInputPin(busNames[13], 2));
    if (prefix != null && !prefix.isBlank()) {
      for (var port : result) {
        port.setPrefix(prefix);
      }
    }
    result.get(clockEntry).setSysCon();
    result.get(resetEntry).setSysCon();
    return result;
  }

}
