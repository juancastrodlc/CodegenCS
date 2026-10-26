using System;
using System.Globalization;
using Dapper;
using MyProject.POCOs;

namespace SampleSourceGenerator.Demo
{
    partial class Program
    {
        static void Main(string[] args)
        {
            using (var cn = IDbConnectionFactory.CreateConnection())
            {
                cn.Open();
                cn.Execute("""
                    CREATE TABLE Product (
                        ProductID INTEGER PRIMARY KEY AUTOINCREMENT,
                        Name TEXT NOT NULL,
                        ProductNumber TEXT NOT NULL,
                        ListPrice NUMERIC NOT NULL
                    )
                    """);

                var newProducts = new[]
                {
                    new Product() { Name = "Tesla Model S", ProductNumber = "TS-0001", ListPrice = 79990 },
                    new Product() { Name = "Mountain Bike", ProductNumber = "MB-0002", ListPrice = 1250.50m },
                };
                cn.Execute("INSERT INTO Product (Name, ProductNumber, ListPrice) VALUES (@Name, @ProductNumber, @ListPrice)", newProducts);

                var products = cn.Query<Product>("SELECT ProductID, Name, ProductNumber, ListPrice FROM Product ORDER BY ProductID");
                foreach (var p in products)
                    Console.WriteLine(string.Format(CultureInfo.InvariantCulture, "I'll buy a {0} (#{1}, {2}) for {3:0.00}", p.Name, p.ProductId, p.ProductNumber, p.ListPrice));
            }
        }
    }
}
