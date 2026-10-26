using System;
using System.Data;
using System.Globalization;
using Dapper;
using Microsoft.Data.Sqlite;

namespace MyProject.POCOs
{
    public class IDbConnectionFactory
    {
        static IDbConnectionFactory()
        {
            SqlMapper.RemoveTypeMap(typeof(decimal));
            SqlMapper.RemoveTypeMap(typeof(decimal?));
            SqlMapper.AddTypeHandler(new SqliteDecimalHandler());
            SqlMapper.RemoveTypeMap(typeof(Guid));
            SqlMapper.RemoveTypeMap(typeof(Guid?));
            SqlMapper.AddTypeHandler(new SqliteGuidHandler());
        }

        public static IDbConnection CreateConnection()
        {
            return new SqliteConnection("Data Source=:memory:");
        }

        private sealed class SqliteDecimalHandler : SqlMapper.TypeHandler<decimal>
        {
            public override decimal Parse(object value) => Convert.ToDecimal(value, CultureInfo.InvariantCulture);

            public override void SetValue(IDbDataParameter parameter, decimal value) => parameter.Value = value;
        }

        private sealed class SqliteGuidHandler : SqlMapper.TypeHandler<Guid>
        {
            public override Guid Parse(object value) => value is byte[] bytes ? new Guid(bytes) : Guid.Parse(Convert.ToString(value, CultureInfo.InvariantCulture));

            public override void SetValue(IDbDataParameter parameter, Guid value) => parameter.Value = value.ToString("N");
        }
    }
}
