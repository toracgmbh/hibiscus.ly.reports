package de.open4me.hibiscus.reports.mcp;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

public final class TransactionDeleteConfirmationTests
{
    private TransactionDeleteConfirmationTests()
    {
    }

    public static void run()
    {
        confirmationTextShowsTransaction();
        confirmationTextMentionsUnknownIds();
        confirmationTextListsEveryTransaction();
    }

    private static void confirmationTextShowsTransaction()
    {
        TransactionDeleter.Candidate candidate = new TransactionDeleter.Candidate("4711", "7", "Beispielkonto",
            LocalDate.of(2025, 1, 14), -42.0, "Beispiel GmbH", "Rechnung 4711\nzweite Zeile",
            List.of("kategorie: Versicherung"));
        String text = TransactionDeleteConfirmation.text(List.of(candidate), 0);
        for (String expected : List.of("Ein MCP-Client möchte 1 Umsatz löschen:", "14.01.2025", "-42,00 EUR",
            "Beispiel GmbH", "Rechnung 4711", "Beispielkonto", "[kategorie: Versicherung]",
            "bei der Bank ändert sich nichts", "[kategorie: Versicherung]  #4711"))
            check(text.contains(expected), "text contains '" + expected + "' but was:\n" + text);
        check(!text.contains("zweite Zeile"), "only first purpose line shown");
    }

    private static void confirmationTextMentionsUnknownIds()
    {
        List<TransactionDeleter.Candidate> candidates = List.of(candidate(1));
        check(TransactionDeleteConfirmation.text(candidates, 2).contains("2 unbekannte ID(s)"),
            "unknown ids mentioned");
        check(!TransactionDeleteConfirmation.text(candidates, 0).contains("unbekannte"),
            "no unknown line without unknown ids");
    }

    private static void confirmationTextListsEveryTransaction()
    {
        List<TransactionDeleter.Candidate> candidates = new ArrayList<>();
        for (int i = 1; i <= 60; i++)
            candidates.add(candidate(i));
        String text = TransactionDeleteConfirmation.text(candidates, 0);
        check(text.contains("60 Umsätze"), "plural header");
        check(text.contains("-1.234,50 EUR"), "thousands separator and decimal comma");
        for (int i = 1; i <= 60; i++)
            check(text.contains("Rechnung " + i + " "), "purpose " + i + " listed");
    }

    private static TransactionDeleter.Candidate candidate(int number)
    {
        return new TransactionDeleter.Candidate(Integer.toString(number), "7", "Beispielkonto",
            LocalDate.of(2025, 1, 14), -1234.5, "Beispiel GmbH", "Rechnung " + number, List.of());
    }

    private static void check(boolean condition, String message)
    {
        if (!condition)
            throw new AssertionError(message);
    }
}
