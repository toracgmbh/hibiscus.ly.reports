package de.open4me.hibiscus.reports.mcp;

import java.rmi.RemoteException;
import java.time.Duration;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import de.willuhn.datasource.rmi.ObjectNotFoundException;
import de.willuhn.jameica.hbci.Settings;
import de.willuhn.jameica.hbci.messaging.ObjectDeletedMessage;
import de.willuhn.jameica.hbci.rmi.Konto;
import de.willuhn.jameica.hbci.rmi.Umsatz;
import de.willuhn.jameica.hbci.rmi.UmsatzTyp;
import de.willuhn.jameica.system.Application;
import de.willuhn.logging.Logger;

/** Deletes transactions in Hibiscus after an explicit confirmation dialog. Local only; the bank is not told. */
public final class HibiscusTransactionDeleter implements TransactionDeleter
{
    /** Stays below the 60 s request timeout common MCP clients use, so a late click cannot delete unseen. */
    static final Duration CONFIRM_TIMEOUT = Duration.ofSeconds(50);

    public HibiscusTransactionDeleter()
    {
    }

    /** Hibiscus IDs are positive ints; leading zeros or out-of-range values are not IDs (status unknown). */
    static boolean isTransactionId(String id)
    {
        if (id == null || !id.matches("[1-9]\\d{0,9}"))
            return false;
        return Long.parseLong(id) <= Integer.MAX_VALUE;
    }

    @Override
    public Optional<Candidate> find(String id) throws Exception
    {
        if (!isTransactionId(id))
            return Optional.empty();
        Umsatz transaction;
        try
        {
            transaction = Settings.getDBService().createObject(Umsatz.class, id);
        }
        catch (ObjectNotFoundException e)
        {
            return Optional.empty();
        }
        Konto account = transaction.getKonto();
        return Optional.of(new Candidate(id, account.getID(), accountName(account),
            toLocalDate(transaction.getDatum()), transaction.getBetrag(), text(account.getWaehrung()),
            text(transaction.getGegenkontoName()), text(transaction.getZweck()), links(transaction)));
    }

    @Override
    public boolean confirm(List<Candidate> candidates, int unknownCount) throws Exception
    {
        return McpTransactionDeleteDialog.confirm(
            TransactionDeleteConfirmation.text(candidates, unknownCount), CONFIRM_TIMEOUT);
    }

    @Override
    public void delete(String id) throws Exception
    {
        Umsatz transaction = Settings.getDBService().createObject(Umsatz.class, id);
        String transactionId = transaction.getID();
        transaction.delete();
        // Same notification Hibiscus' own delete sends, so open views refresh. The transaction is already
        // gone at this point; a messaging problem must not turn the result into an error.
        try
        {
            Application.getMessagingFactory().sendMessage(new ObjectDeletedMessage(transaction, transactionId));
        }
        catch (Exception e)
        {
            Logger.warn("MCP: Löschmeldung für Umsatz " + transactionId + " konnte nicht gesendet werden: " + e);
        }
    }

    private static List<String> links(Umsatz transaction) throws RemoteException
    {
        List<String> links = new ArrayList<>();
        // getUmsatzTyp() also returns rule-matched categories; only a stored assignment is a real link.
        if (transaction.isAssigned())
        {
            UmsatzTyp category = transaction.getUmsatzTyp();
            if (category != null)
                links.add("kategorie: " + category.getName());
        }
        String comment = transaction.getKommentar();
        if (comment != null && !comment.isBlank())
            links.add("kommentar");
        if (transaction.hasFlag(Umsatz.FLAG_CHECKED))
            links.add("geprueft");
        return links;
    }

    private static String accountName(Konto account) throws RemoteException
    {
        String name = account.getBezeichnung();
        if (name == null || name.isBlank())
            name = account.getLongName();
        if (name == null || name.isBlank())
            name = account.getName();
        return text(name);
    }

    private static LocalDate toLocalDate(java.util.Date date)
    {
        if (date == null)
            return null;
        if (date instanceof java.sql.Date sqlDate)
            return sqlDate.toLocalDate();
        return date.toInstant().atZone(ZoneId.systemDefault()).toLocalDate();
    }

    private static String text(String value)
    {
        return value == null ? "" : value;
    }
}
