# Databricks notebook source
# MAGIC %md
# MAGIC # Week 6 — Databricks Free Edition Lab
# MAGIC
# MAGIC This is the **Databricks** version of `week6_databricks_notebook.ipynb`.
# MAGIC Same concepts (DataFrames, medallion, Delta history + time travel), but:
# MAGIC
# MAGIC - **No SparkSession setup** — Databricks provides `spark` already.
# MAGIC - Data is stored as **managed Delta tables** in Unity Catalog
# MAGIC   (`workspace.default`) instead of a local `/home/jovyan/work/delta` path.
# MAGIC
# MAGIC Import this file via **Workspace → Import**, attach serverless compute, and run.

# COMMAND ----------

import pyspark.sql.functions as F

# On Databricks `spark` already exists — no configure_spark_with_delta_pip needed.
print(f"Spark {spark.version} — running on Databricks")

CATALOG = "workspace"
SCHEMA  = "default"
spark.sql(f"USE CATALOG {CATALOG}")
spark.sql(f"USE SCHEMA {SCHEMA}")

# COMMAND ----------

# MAGIC %md ## 1) Create a DataFrame and run core operations

# COMMAND ----------

data = [
    (1, "C01", "Laptop",   120.50),
    (2, "C02", "Mouse",     25.00),
    (3, "C01", "Keyboard",  70.00),
    (4, "C03", "Monitor",  220.00),
]

df = spark.createDataFrame(data, ["order_id", "customer_id", "product", "amount"])
df.show()

# COMMAND ----------

print("--- Orders with amount > 50 ---")
df.filter(F.col("amount") > 50).show()

print("--- Spend by customer (descending) ---")
(df.groupBy("customer_id")
   .agg(F.sum("amount").alias("total_spend"))
   .orderBy(F.col("total_spend").desc())
   .show())

# COMMAND ----------

# MAGIC %md ## 2) Bronze -> Silver -> Gold (Medallion pattern)
# MAGIC
# MAGIC Managed tables, so no file paths — Databricks tracks the storage location.

# COMMAND ----------

# Bronze: raw records as-is
df.write.format("delta").mode("overwrite").saveAsTable("bronze_orders")
print("Bronze written")

# Silver: cast amount to DECIMAL, deduplicate
silver_df = (
    spark.read.table("bronze_orders")
    .withColumn("amount", F.col("amount").cast("decimal(12,2)"))
    .dropDuplicates(["order_id"])
)
silver_df.write.format("delta").mode("overwrite").saveAsTable("silver_orders")
print("Silver written")

# Gold: aggregated revenue per customer
gold_df = (
    spark.read.table("silver_orders")
    .groupBy("customer_id")
    .agg(F.sum("amount").alias("total_revenue"))
)
gold_df.write.format("delta").mode("overwrite").saveAsTable("gold_customer_revenue")
print("Gold written")

print("\n--- Gold: revenue per customer ---")
spark.read.table("gold_customer_revenue").orderBy("customer_id").show()

# COMMAND ----------

# MAGIC %md ## 3) Delta history and time travel

# COMMAND ----------

# silver_orders version 0 = the cast (DECIMAL) + deduplicated write above.
# Update one row to create version 1.
spark.sql("UPDATE silver_orders SET amount = 121.50 WHERE order_id = 1")

# COMMAND ----------

# MAGIC %sql
# MAGIC DESCRIBE HISTORY silver_orders

# COMMAND ----------

# MAGIC %md
# MAGIC Version 0 (original write) vs the current version after the UPDATE.

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT * FROM silver_orders VERSION AS OF 0 ORDER BY order_id;

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT * FROM silver_orders ORDER BY order_id;

# COMMAND ----------

# MAGIC %md ## 4) Quick checks
# MAGIC
# MAGIC - `df` returns 4 rows; the filter returns 3 (amount > 50).
# MAGIC - Bronze, Silver, Gold managed Delta tables created in `workspace.default`.
# MAGIC - `DESCRIBE HISTORY silver_orders` shows version `0` (WRITE) then `1` (UPDATE).
# MAGIC - `VERSION AS OF 0` shows `amount = 120.50` for order_id 1; current shows `121.50`.
# MAGIC
# MAGIC **Same results as the local Docker run** — the DataFrame and Delta APIs are identical.
