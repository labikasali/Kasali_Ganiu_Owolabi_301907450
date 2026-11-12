// =============================================================================
// Portfolio 4 — indexes.js
// Demonstrates COLLSCAN → IXSCAN.
//   1. Show the plan BEFORE the index (COLLSCAN).
//   2. Create the index.
//   3. Show the plan AFTER the index (IXSCAN).
//
// Run AFTER seeding:
//   mongosh --quiet --file indexes.js
// =============================================================================

db = db.getSiblingDB('driveeasy');

print('==================================================================');
print('Query: find all inspections on car_id=42 of type "return".');
print('Run twice — before and after the index.');
print('==================================================================');

// pick a real target so the query always returns documents
const sample = db.vehicle_inspections.findOne({ inspection_type: 'return' });
const query = { car_id: sample.car_id, inspection_type: 'return' };
print('Target: ' + JSON.stringify(query));

// re-runnable: drop the demo indexes first (ignore "index not found")
['idx_car_type'].forEach(n => { try { db.vehicle_inspections.dropIndex(n); } catch (e) {} });
['idx_rental_ts', 'idx_car_ts_desc'].forEach(n => { try { db.gps_trip_logs.dropIndex(n); } catch (e) {} });

// find the deepest scan stage (COLLSCAN or IXSCAN) in the plan tree
function scanStage(st) {
  while (st.inputStage) st = st.inputStage;
  return st;
}
function summarise(ex) {
  const sc = scanStage(ex.executionStats.executionStages);
  return {
    stage: sc.stage, indexName: sc.indexName || null,
    totalDocsExamined: ex.executionStats.totalDocsExamined,
    totalKeysExamined: ex.executionStats.totalKeysExamined,
    nReturned: ex.executionStats.nReturned,
    executionTimeMs: ex.executionStats.executionTimeMillis
  };
}

print('');
print('--- BEFORE index (COLLSCAN expected) ---');
const before = summarise(db.vehicle_inspections.find(query).explain('executionStats'));
printjson(before);

print('');
print('--- CREATE index { car_id: 1, inspection_type: 1 } ---');
db.vehicle_inspections.createIndex({ car_id: 1, inspection_type: 1 }, { name: 'idx_car_type' });

print('');
print('--- AFTER index (IXSCAN expected) ---');
const after = summarise(db.vehicle_inspections.find(query).explain('executionStats'));
printjson(after);

db.gps_trip_logs.createIndex({ rental_id: 1, ts: 1 }, { name: 'idx_rental_ts' });
db.gps_trip_logs.createIndex({ car_id: 1, ts: -1 }, { name: 'idx_car_ts_desc' });

print('');
print('==================================================================');
print('SUMMARY (real values from this run)');
print('  Stage              | Docs examined | Keys examined | Time ms | Returned');
print('  ' + before.stage + ' (before)  | ' + before.totalDocsExamined + ' | ' + before.totalKeysExamined + ' | ' + before.executionTimeMs + ' | ' + before.nReturned);
print('  ' + after.stage + ' (after, ' + after.indexName + ') | ' + after.totalDocsExamined + ' | ' + after.totalKeysExamined + ' | ' + after.executionTimeMs + ' | ' + after.nReturned);
print('==================================================================');
