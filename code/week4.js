// =============================================================================
// Week 4: MongoDB NoSQL Examples (mongosh JavaScript)
// Based on MongoDB Official Documentation CRUD Patterns
// =============================================================================
//
// HOW TO RUN THIS SCRIPT:
// -----------------------
// From host machine:
//   docker exec -i mongodb83 mongosh -u mongo -p mongo --authenticationDatabase admin --quiet --eval "$(cat code/week4.js)"
//
// Inside container interactively:
//   docker exec -it mongodb83 mongosh -u mongo -p mongo --authenticationDatabase admin
//
// OFFICIAL MONGODB DOCUMENTATION REFERENCES:
// ------------------------------------------
// - Insert: https://www.mongodb.com/docs/manual/tutorial/insert-documents/
// - Query: https://www.mongodb.com/docs/manual/tutorial/query-documents/
// - Query Embedded Docs: https://www.mongodb.com/docs/manual/tutorial/query-embedded-documents/
// - Query Arrays: https://www.mongodb.com/docs/manual/tutorial/query-arrays/
// - Projection: https://www.mongodb.com/docs/manual/tutorial/project-fields-from-query-results/
// - Update: https://www.mongodb.com/docs/manual/tutorial/update-documents/
// - Delete: https://www.mongodb.com/docs/manual/tutorial/remove-documents/
// - Aggregation: https://www.mongodb.com/docs/manual/aggregation/

// Switch to demo database
use("demo");

// =============================================================================
// SETUP: Reset collection for repeatable classroom demos
// =============================================================================
db.inventory.drop();

// =============================================================================
// CREATE - Insert Documents (Official MongoDB Pattern)
// Reference: https://www.mongodb.com/docs/manual/tutorial/insert-documents/
// =============================================================================
print("\\n== CREATE ==");

// insertOne: Insert a single document
// MongoDB auto-generates _id if not provided
db.inventory.insertOne({
  item: "canvas",
  qty: 100,
  status: "A",
  tags: ["cotton"],
  dim_cm: [28, 35.5],
  size: { h: 28, w: 35.5, uom: "cm" }
});

db.inventory.insertMany([
  { item: "journal", qty: 25, status: "A", tags: ["blank", "red"], dim_cm: [14, 21], size: { h: 14, w: 21, uom: "cm" } },
  { item: "notebook", qty: 50, status: "A", tags: ["red", "blank"], dim_cm: [14, 21], size: { h: 8.5, w: 11, uom: "in" } },
  { item: "paper", qty: 100, status: "D", tags: ["red", "blank", "plain"], dim_cm: [14, 21], size: { h: 8.5, w: 11, uom: "in" } },
  { item: "planner", qty: 75, status: "D", tags: ["blank", "red"], dim_cm: [22.85, 30], size: { h: 22.85, w: 30, uom: "cm" } },
  { item: "postcard", qty: 45, status: "A", tags: ["blue"], dim_cm: [10, 15.25], size: { h: 10, w: 15.25, uom: "cm" } }
]);

// READ
print("\\n== READ ==");
print("All documents:");
printjson(db.inventory.find({}).toArray());

print("status = D:");
printjson(db.inventory.find({ status: "D" }).toArray());

print("status in [A, D]:");
printjson(db.inventory.find({ status: { $in: ["A", "D"] } }).toArray());

print("Projection example:");
printjson(db.inventory.find({ status: "A" }, { item: 1, status: 1, _id: 0 }).toArray());

print("Nested field query (official pattern): size.uom = in");
printjson(db.inventory.find({ "size.uom": "in" }).toArray());

print("Array query (official pattern): tags contains red");
printjson(db.inventory.find({ tags: "red" }).toArray());

print("Array query with $all (official pattern): tags has red and blank");
printjson(db.inventory.find({ tags: { $all: ["red", "blank"] } }).toArray());

print("Array query with $elemMatch (official pattern): dim_cm has value between 22 and 30");
printjson(db.inventory.find({ dim_cm: { $elemMatch: { $gt: 22, $lt: 30 } } }).toArray());

// UPDATE
print("\\n== UPDATE ==");
print("Before updateOne (paper):");
printjson(db.inventory.find({ item: "paper" }).toArray());

db.inventory.updateOne(
  { item: "paper" },
  {
    $set: { "size.uom": "cm", status: "P" },
    $currentDate: { lastModified: true }
  }
);

db.inventory.updateMany(
  { qty: { $lt: 50 } },
  {
    $set: { "size.uom": "in", status: "P" },
    $currentDate: { lastModified: true }
  }
);

print("After updateOne (paper):");
printjson(db.inventory.find({ item: "paper" }).toArray());

print("Before array update ($push on journal.tags):");
printjson(db.inventory.find({ item: "journal" }, { _id: 0, item: 1, tags: 1 }).toArray());

db.inventory.updateOne(
  { item: "journal" },
  { $push: { tags: "featured" } }
);

print("After array update ($push on journal.tags):");
printjson(db.inventory.find({ item: "journal" }, { _id: 0, item: 1, tags: 1 }).toArray());

db.inventory.updateOne(
  { item: "journal" },
  { $inc: { qty: 5 } }
);

print("After updates:");
printjson(db.inventory.find({}).toArray());

// AGGREGATION
print("\\n== AGGREGATION ==");
print("$match + $project:");
printjson(
  db.inventory.aggregate([
    { $match: { qty: { $gt: 50 } } },
    { $project: { _id: 0, item: 1, inventory_status: "$status", unit: "$size.uom" } }
  ]).toArray()
);

print("$group:");
printjson(
  db.inventory.aggregate([
    {
      $group: {
        _id: "$status",
        total_qty: { $sum: "$qty" },
        num_items: { $sum: 1 },
        avg_qty: { $avg: "$qty" }
      }
    },
    { $sort: { total_qty: -1 } }
  ]).toArray()
);

print("$cond in $group:");
printjson(
  db.inventory.aggregate([
    {
      $group: {
        _id: "$status",
        high_qty_docs: {
          $sum: { $cond: [{ $gt: ["$qty", 50] }, 1, 0] }
        },
        total_qty: { $sum: "$qty" }
      }
    },
    { $sort: { _id: 1 } }
  ]).toArray()
);

print("Aggregation result before/after shape (projected output):");
printjson(
  db.inventory.aggregate([
    { $match: { status: { $in: ["A", "P", "D"] } } },
    { $project: { _id: 0, item: 1, status: 1, qty: 1 } },
    { $limit: 3 }
  ]).toArray()
);

// DELETE
print("\\n== DELETE ==");
db.inventory.deleteOne({ status: "D" });
db.inventory.deleteMany({ status: "A" });

print("After deleteOne and deleteMany:");
printjson(db.inventory.find({}).toArray());

print("Delete all documents:");
db.inventory.deleteMany({});
printjson(db.inventory.find({}).toArray());

print("\\nDone.");
