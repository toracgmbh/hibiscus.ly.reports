import de.open4me.hibiscus.reports.automation.runtime.AutomationPaymentsTests;
import de.open4me.hibiscus.reports.mcp.McpJsonRpcHandlerTests;
import de.open4me.hibiscus.reports.mcp.McpRequestLogTests;
import de.open4me.hibiscus.reports.mcp.SepaPurposeTests;

/** Startet die Tests, die ohne Hibiscus-Laufzeit und ohne Dateien außerhalb des Repos laufen (statt CoreTests). */
public class McpRunner
{
  public static void main(String[] args)
  {
    McpJsonRpcHandlerTests.run();
    McpRequestLogTests.run();
    SepaPurposeTests.run();
    AutomationPaymentsTests.run();
    System.out.println("MCP tests OK");
  }
}
