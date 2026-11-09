package de.open4me.hibiscus.reports.mcp;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

public interface TransactionDeleter
{
    /** Empty if the ID is malformed or no such transaction exists. Throws only on real lookup failures. */
    Optional<Candidate> find(String id) throws Exception;

    /** Blocks until the user answers. true only on explicit confirmation. */
    boolean confirm(List<Candidate> candidates, int unknownCount) throws Exception;

    void delete(String id) throws Exception;

    record Candidate(String id, String accountId, String accountName, LocalDate date, double amount,
                     String counterpartyName, String purpose, List<String> links)
    {
    }
}
