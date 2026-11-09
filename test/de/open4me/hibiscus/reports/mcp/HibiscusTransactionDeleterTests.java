package de.open4me.hibiscus.reports.mcp;

import java.util.List;

public final class HibiscusTransactionDeleterTests
{
    private HibiscusTransactionDeleterTests()
    {
    }

    public static void run()
    {
        acceptsOnlyCanonicalTransactionIds();
    }

    private static void acceptsOnlyCanonicalTransactionIds()
    {
        for (String valid : List.of("1", "7", "4711", "2147483647"))
            check(HibiscusTransactionDeleter.isTransactionId(valid), "valid id " + valid);
        for (String invalid : List.of("", "0", "007", "-1", "1.0", "x", " 7", "2147483648",
            "99999999999999999999"))
            check(!HibiscusTransactionDeleter.isTransactionId(invalid), "invalid id '" + invalid + "'");
        check(!HibiscusTransactionDeleter.isTransactionId(null), "null id");
    }

    private static void check(boolean condition, String message)
    {
        if (!condition)
            throw new AssertionError(message);
    }
}
