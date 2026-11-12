// =============================================================================
// Portfolio 4 — aggregations.js
// Three aggregation pipelines:
//   A. Damage per car category  (which category suffers most damage?)
//   B. Distance per rental       (max odometer_km - min odometer_km from GPS)
//   C. Cars with repeat damage   (≥3 separate inspections with damage marks)
//
// Run AFTER seeding:
//   mongosh --quiet --file aggregations.js
// =============================================================================

const db = db.getSiblingDB('driveeasy');

print('==================================================================');
print('A. Damage per car category (count of inspections with ≥1 damage mark)');
print('==================================================================');
const damageByCat = db.vehicle_inspections.aggregate([
  { $match: { 'damage_marks.0': { $exists: true } } },
  { $group: {
      _id: '$car_category',
      inspections_with_damage: { $sum: 1 },
      distinct_cars:           { $addToSet: '$car_id' },
      major_count:              { $sum: {
        $size: { $filter: { input: '$damage_marks', as: 'm', cond: { $eq: ['$$m.severity','major'] } } }
      } }
  }},
  { $project: {
      _id: 0,
      category: '$_id',
      inspections_with_damage: 1,
      distinct_cars: { $size: '$distinct_cars' },
      major_count: 1
  }},
  { $sort: { inspections_with_damage: -1 } }
]).toArray();
printjson(damageByCat);

print('');
print('==================================================================');
print('B. Distance per rental — derived from GPS trip logs');
print('    (max odometer - min odometer for each rental_id)');
print('==================================================================');
const distancePerRental = db.gps_trip_logs.aggregate([
  { $group: {
      _id: '$rental_id',
      car_id:        { $first: '$car_id' },
      start_odo:     { $min: '$odometer_km' },
      end_odo:       { $max: '$odometer_km' },
      points:        { $sum: 1 },
      max_speed:     { $max: '$speed_kph' }
  }},
  { $project: {
      _id: 0,
      rental_id: '$_id',
      car_id: 1,
      points: 1,
      distance_km: { $round: [{ $subtract: ['$end_odo','$start_odo'] }, 2] },
      max_speed_kph: { $round: ['$max_speed', 1] }
  }},
  { $sort: { distance_km: -1 } },
  { $limit: 15 }
]).toArray();
printjson(distancePerRental);

print('');
print('==================================================================');
print('C. Cars with REPEAT damage — ≥3 separate inspections with damage marks');
print('==================================================================');
const repeatDamage = db.vehicle_inspections.aggregate([
  { $match: { 'damage_marks.0': { $exists: true } } },
  { $group: {
      _id: '$car_id',
      category:           { $first: '$car_category' },
      damage_inspections: { $sum: 1 },
      inspector_ids:      { $addToSet: '$inspector_id' },
      first_at:           { $min: '$performed_at' },
      last_at:            { $max: '$performed_at' }
  }},
  { $match: { damage_inspections: { $gte: 3 } } },
  { $project: {
      _id: 0,
      car_id: '$_id',
      category: 1,
      damage_inspections: 1,
      distinct_inspectors: { $size: '$inspector_ids' },
      first_damage_at: '$first_at',
      last_damage_at:  '$last_at'
  }},
  { $sort: { damage_inspections: -1 } },
  { $limit: 15 }
]).toArray();
printjson(repeatDamage);

print('');
print('==================================================================');
print('BONUS — Damage severity distribution (across all damage_marks)');
print('==================================================================');
const sevDist = db.vehicle_inspections.aggregate([
  { $unwind: '$damage_marks' },
  { $group: { _id: '$damage_marks.severity', count: { $sum: 1 } } },
  { $sort: { count: -1 } }
]).toArray();
printjson(sevDist);

print('');
print('Done. Copy the four JSON arrays above into your screenshots/evidence.');
