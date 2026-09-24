#r "System.Data.Common.dll"
#r "Microsoft.Data.Sqlite.dll"
using Microsoft.Data.Sqlite;

class MyTemplate
{
    private readonly string CONNECTION_STRING = "Data Source=:memory:";
    async Task<FormattableString> Main()
    {
        using (SqliteConnection sqliteConnection = new SqliteConnection(CONNECTION_STRING))
        {
            sqliteConnection.Open();
            return $"My template worked";
        }
        return $"My template failed";
    }
}
