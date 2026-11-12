// =============================================================================
// Portfolio 4 — setup_validation.js
// Drop & recreate the two collections (vehicle_inspections, gps_trip_logs)
// with JSON Schema validators that enforce the document shape.
//
// Run:   mongosh --quiet --file setup_validation.js
// (or `mongo --quiet setup_validation.js` on older shells)
// =============================================================================

const db = db.getSiblingDB('driveeasy');

// ---- 1. vehicle_inspections -------------------------------------------------
db.vehicle_inspections.drop();

db.createCollection('vehicle_inspections', {
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      required: ['inspection_id', 'rental_id', 'car_id', 'car_category', 'inspection_type',
                 'inspector_id', 'inspector_name', 'performed_at', 'branch_code', 'checklist'],
      properties: {
        inspection_id:    { bsonType: ['long','int','double'], description: 'unique id' },
        rental_id:        { bsonType: ['long','int','double'] },
        car_id:           { bsonType: ['long','int','double'] },
        car_category:     { enum: ['Economy', 'SUV', 'Luxury', 'Mini-bus', 'Van'] },
        inspection_type:  { enum: ['pickup', 'return'] },
        inspector_id:     { bsonType: ['long','int','double'] },
        inspector_name:   { bsonType: 'string' },
        performed_at:     { bsonType: 'date' },
        branch_code:      { enum: ['IKE', 'LKK', 'VTC', 'MMA', 'ABJ'] },
        odometer_km:      { bsonType: ['int','long','double'], minimum: 0 },
        fuel_level_pct:   { bsonType: ['int','long','double'], minimum: 0, maximum: 100 },
        damage_marks: {
          bsonType: 'array',
          items: {
            bsonType: 'object',
            required: ['area', 'severity', 'notes'],
            properties: {
              area:      { enum: ['front_bumper','rear_bumper','left_door','right_door',
                                 'bonnet','boot','roof','windscreen','tyre','interior'] },
              severity:  { enum: ['none','minor','moderate','major'] },
              notes:     { bsonType: 'string' },
              photo_url: { bsonType: 'string' }
            }
          }
        },
        checklist: {
          bsonType: 'object',
          required: ['tyres_ok', 'lights_ok', 'spare_tyre_ok'],
          properties: {
            tyres_ok:        { bsonType: 'bool' },
            lights_ok:       { bsonType: 'bool' },
            spare_tyre_ok:   { bsonType: 'bool' },
            // SUV/Luxury/Mini-bus/Van extras
            ac_ok:           { bsonType: 'bool' },
            sunroof_ok:      { bsonType: 'bool' },   // luxury only
            child_seat:      { bsonType: 'bool' },   // SUV/Mini-bus/Van
            cargo_space_ok:  { bsonType: 'bool' },    // Van/Mini-bus
            // Pickup-only
            registration_ok: { bsonType: 'bool' },
            insurance_ok:    { bsonType: 'bool' },
            // Return-only
            cleaned:         { bsonType: 'bool' },
            refuelled:       { bsonType: 'bool' }
          }
        },
        inspector_notes: { bsonType: 'string' }
      }
    }
  },
  validationLevel: 'strict',
  validationAction: 'error'
});

// ---- 2. gps_trip_logs (time-series) -----------------------------------------
db.gps_trip_logs.drop();

// MongoDB 5+ supports time-series collections natively.
try {
  db.createCollection('gps_trip_logs', {
    timeseries: {
      timeField: 'ts',
      metaField: 'rental_id',
      granularity: 'seconds'
    },
    validator: {
      $jsonSchema: {
        bsonType: 'object',
        required: ['ts', 'rental_id', 'car_id', 'lat', 'lng', 'speed_kph'],
        properties: {
          ts:         { bsonType: 'date' },
          rental_id:  { bsonType: ['long','int','double'] },
          car_id:     { bsonType: ['long','int','double'] },
          lat:        { bsonType: ['double','int','long'], minimum: -90,  maximum: 90 },
          lng:        { bsonType: ['double','int','long'], minimum: -180, maximum: 180 },
          speed_kph:  { bsonType: ['double','int','long'], minimum: 0 },
          odometer_km:{ bsonType: ['double','int','long'], minimum: 0 },
          event:      { enum: ['ignition_on', 'moving', 'idle', 'ignition_off'] }
        }
      }
    }
  });
} catch (e) {
  print('Time-series collection not supported (' + e.message + '); falling back to regular collection.');
  db.createCollection('gps_trip_logs', {
    validator: {
      $jsonSchema: {
        bsonType: 'object',
        required: ['ts', 'rental_id', 'car_id', 'lat', 'lng', 'speed_kph'],
        properties: {
          ts:         { bsonType: 'date' },
          rental_id:  { bsonType: ['long','int','double'] },
          car_id:     { bsonType: ['long','int','double'] },
          lat:        { bsonType: ['double','int','long'] },
          lng:        { bsonType: ['double','int','long'] },
          speed_kph:  { bsonType: ['double','int','long'] },
          odometer_km:{ bsonType: ['double','int','long'] },
          event:      { enum: ['ignition_on', 'moving', 'idle', 'ignition_off'] }
        }
      }
    }
  });
}

print('--- collection info ---');
db.getCollectionNames().forEach(n => print('  collection: ' + n));
print('vehicle_inspections count: ' + db.vehicle_inspections.countDocuments());
print('gps_trip_logs        count: ' + db.gps_trip_logs.countDocuments());

// show validator on each collection
print('--- vehicle_inspections validator ---');
printjson(db.getCollectionInfos({ name: 'vehicle_inspections' })[0]);
print('--- gps_trip_logs validator ---');
printjson(db.getCollectionInfos({ name: 'gps_trip_logs' })[0]);
