import de.open4me.hibiscus.reports.mcp.McpJsonRpcHandlerTests;
import de.open4me.hibiscus.reports.mcp.McpRequestLogTests;

/** Startet die MCP-Tests ohne CoreTests (die benötigen Dateien, die im Repo fehlen). */
public class McpRunner
{
  public static void main(String[] args)
  {
    McpJsonRpcHandlerTests.run();
    McpRequestLogTests.run();
    System.out.println("MCP tests OK");
  }
}
