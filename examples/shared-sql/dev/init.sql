IF SUSER_ID(N'sandbox_test') IS NULL
BEGIN
    CREATE LOGIN [sandbox_test] WITH PASSWORD = N'$(TestPassword)';
    ALTER SERVER ROLE [dbcreator] ADD MEMBER [sandbox_test];
END;
