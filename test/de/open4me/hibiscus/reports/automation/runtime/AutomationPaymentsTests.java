package de.open4me.hibiscus.reports.automation.runtime;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

import de.open4me.hibiscus.reports.mcp.SepaTransferDraftWriter;
import de.open4me.hibiscus.reports.model.ReportAccount;

public final class AutomationPaymentsTests
{
    private AutomationPaymentsTests()
    {
    }

    public static void run()
    {
        includesCustomDialogTextInSummary();
        keepsSummaryCompactWithoutCustomDialogText();
        summaryShowsMergedPurpose();
        summaryNormalizesWhitespaceInPurpose();
        summaryRejectsTooLongPurpose();
        summaryRejectsCharacterHibiscusDoesNotAllow();
        draftPassesTheMergedPurposeToTheWriter();
    }

    private static void includesCustomDialogTextInSummary()
    {
        String summary = AutomationPayments.summary(Map.of(
            "konto", account(),
            "empfaengerName", "Max Mustermann",
            "iban", "DE02120300000000202051",
            "bic", "BYLADEM1001",
            "betrag", "50.00",
            "verwendungszweck", "Beispiel",
            "dialogText", "Bitte Rechnung 4711 pruefen."));

        check(summary.contains("Bitte Rechnung 4711 pruefen."), "custom dialog text is shown");
        check(summary.indexOf("Bitte Rechnung 4711 pruefen.") < summary.indexOf("Konto: Giro"),
            "custom dialog text is shown before payment details");
    }

    private static void keepsSummaryCompactWithoutCustomDialogText()
    {
        String summary = AutomationPayments.summary(Map.of(
            "konto", account(),
            "empfaengerName", "Max Mustermann",
            "iban", "DE02120300000000202051",
            "betrag", "50.00",
            "verwendungszweck", "Beispiel"));

        check(summary.startsWith("Überweisung\n\nKonto: Giro"), "summary has no empty custom text section");
    }

    private static void summaryShowsMergedPurpose()
    {
        String summary = AutomationPayments.summary(Map.of(
            "konto", account(),
            "empfaengerName", "Max Mustermann",
            "iban", "DE02120300000000202051",
            "betrag", "50.00",
            "verwendungszweck", "Rechnung",
            "verwendungszweck2", "4711",
            "weitereVerwendungszwecke", List.of("vom 01.01.2026")));

        check(summary.endsWith("\nZweck: Rechnung 4711 vom 01.01.2026"),
            "summary shows the merged purpose that is stored");
    }

    private static void summaryNormalizesWhitespaceInPurpose()
    {
        String summary = AutomationPayments.summary(Map.of(
            "konto", account(),
            "empfaengerName", "Max Mustermann",
            "iban", "DE02120300000000202051",
            "betrag", "50.00",
            "verwendungszweck", "Rechnung\n4711",
            "verwendungszweck2", "\tvom\n01.01.2026 "));

        check(summary.endsWith("\nZweck: Rechnung 4711 vom 01.01.2026"),
            "summary shows the normalized purpose");
    }

    private static void summaryRejectsTooLongPurpose()
    {
        try
        {
            AutomationPayments.summary(Map.of(
                "konto", account(),
                "empfaengerName", "Max Mustermann",
                "iban", "DE02120300000000202051",
                "betrag", "50.00",
                "verwendungszweck", "x".repeat(100),
                "verwendungszweck2", "y".repeat(100)));
        }
        catch (IllegalArgumentException e)
        {
            check("Der Verwendungszweck ist 201 Zeichen lang; Hibiscus erlaubt maximal 140.".equals(e.getMessage()),
                "clear message for a too long purpose: " + e.getMessage());
            return;
        }
        throw new AssertionError("too long purpose is rejected before confirmation");
    }

    private static void summaryRejectsCharacterHibiscusDoesNotAllow()
    {
        try
        {
            AutomationPayments.summary(payment("Rechnung 4711", "100 €", null));
        }
        catch (IllegalArgumentException e)
        {
            check(e.getMessage().contains("U+20AC"), "character named before confirmation: " + e.getMessage());
            return;
        }
        throw new AssertionError("character outside the SEPA set is rejected before confirmation");
    }

    private static void draftPassesTheMergedPurposeToTheWriter()
    {
        SepaTransferDraftWriter.Request request = AutomationPayments.draft(
            payment("Rechnung\n4711", "vom 01.01.2026", List.of("Auftrag 1"))).request();
        check("Rechnung 4711 vom 01.01.2026 Auftrag 1".equals(request.purpose()),
            "writer gets the merged purpose: " + request.purpose());
        check(request.purpose2() == null, "no second purpose line for the writer");
        check(request.additionalPurposes().isEmpty(), "no additional purposes for the writer");
    }

    private static Map<String, Object> payment(Object purpose, Object purpose2, Object additional)
    {
        Map<String, Object> map = new HashMap<>();
        map.put("konto", account());
        map.put("empfaengerName", "Max Mustermann");
        map.put("iban", "DE02120300000000202051");
        map.put("betrag", "50.00");
        map.put("verwendungszweck", purpose);
        map.put("verwendungszweck2", purpose2);
        map.put("weitereVerwendungszwecke", additional);
        return map;
    }

    private static ReportAccount account()
    {
        return new ReportAccount("1", 0, 0, null, "Giro", "12030000",
            "DE02120300000000202051", "Privat", true, false, null);
    }

    private static void check(boolean value, String message)
    {
        if (!value)
            throw new AssertionError(message);
    }
}
