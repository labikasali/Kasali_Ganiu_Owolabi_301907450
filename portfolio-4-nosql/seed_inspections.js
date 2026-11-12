// =============================================================================
// Portfolio 4 — seed_inspections.js
// Generate 40,000+ vehicle_inspection documents (pickup + return checklists).
// Pickup and return checklists differ by car category:
//   Economy      → minimal checklist (tyres, lights, spare, registration, insurance)
//   SUV          → + AC, child seat
//   Luxury       → + AC, sunroof
//   Mini-bus/Van → + AC, child seat, cargo space
//
// Run AFTER setup_validation.js:
//   mongosh --quiet --file seed_inspections.js
// =============================================================================

const db = db.getSiblingDB('driveeasy');

const CATEGORIES = ['Economy', 'SUV', 'Luxury', 'Mini-bus', 'Van'];
const BRANCHES  = ['IKE', 'LKK', 'VTC', 'MMA', 'ABJ'];
const INSPECTORS = [
  'Adebayo Okoro','Fatima Bello','Chinedu Eze','Yetunde Adeyemi','Ibrahim Suleiman',
  'Aisha Mohammed','Tunde Bakare','Ngozi Nwosu','Emeka Okafor','Bola Adewale',
  'Kunle Adebowale','Halima Yusuf','Seyi Ogunleye','Amina Idris','Bayo Musa'
];
const DAMAGE_AREAS = ['front_bumper','rear_bumper','left_door','right_door',
                     'bonnet','boot','roof','windscreen','tyre','interior'];

// Categories per car_id — must match the SQL seeding (cat_id = ((i-1)%5)+1, i=1..200)
function categoryForCar(carId) {
  return CATEGORIES[(carId - 1) % 5];
}

// Build a checklist appropriate to the category and inspection type
function buildChecklist(category, type) {
  const c = {
    tyres_ok:        Math.random() > 0.02,
    lights_ok:       Math.random() > 0.02,
    spare_tyre_ok:   Math.random() > 0.05
  };
  if (category === 'SUV')        { c.ac_ok = Math.random() > 0.03; c.child_seat = Math.random() > 0.4; }
  if (category === 'Luxury')     { c.ac_ok = Math.random() > 0.02; c.sunroof_ok = Math.random() > 0.05; }
  if (category === 'Mini-bus')  { c.ac_ok = Math.random() > 0.04; c.child_seat = Math.random() > 0.3; c.cargo_space_ok = Math.random() > 0.05; }
  if (category === 'Van')       { c.ac_ok = Math.random() > 0.04; c.child_seat = Math.random() > 0.5; c.cargo_space_ok = Math.random() > 0.05; }
  if (category === 'Economy')   { /* no extras */ }
  if (type === 'pickup')        { c.registration_ok = true; c.insurance_ok = true; }
  if (type === 'return')        { c.cleaned = Math.random() > 0.2; c.refuelled = Math.random() > 0.15; }
  return c;
}

// Generate damage marks (~12% of inspections have at least one mark; ~3% multiple)
function buildDamageMarks() {
  const n = Math.random() < 0.88 ? 0
          : Math.random() < 0.7  ? 1
          : Math.random() < 0.8  ? 2
          : 3;
  const marks = [];
  for (let i = 0; i < n; i++) {
    const sev = Math.random() < 0.7 ? 'minor' : Math.random() < 0.9 ? 'moderate' : 'major';
    marks.push({
      area:     DAMAGE_AREAS[Math.floor(Math.random()*DAMAGE_AREAS.length)],
      severity: sev,
      notes:    sev === 'major' ? 'Customer signed damage acknowledgement form.'
                                : 'Photographed and logged in inspection app.',
      photo_url: `https://cdn.driveeasy.ng/insp/${Math.floor(Math.random()*1e9)}.jpg`
    });
  }
  return marks;
}

const TOTAL = 42000;     // > 40k requirement (21,000 rentals × 2 inspections)
const BATCH = 2000;
let batch = [];
let start = Date.now();

for (let i = 1; i <= TOTAL; i++) {
  const carId     = 1 + (i % 200);                       // cars 1..200
  const category  = categoryForCar(carId);
  const rentalId = i;                                     // synthetic rental id
  const inspType = i % 2 === 1 ? 'pickup' : 'return';
  const inspectorIdx = i % INSPECTORS.length;
  const inspectorId  = inspectorIdx + 1;
  const inspectorName= INSPECTORS[inspectorIdx];
  // pickup was ~1-7 days ago; return ~1-10 days after pickup
  const pickupAt  = new Date(Date.now() - (1 + Math.floor(Math.random()*7))*86400e3
                                 - Math.floor(Math.random()*86400e3));
  const performedAt = inspType === 'pickup' ? pickupAt
                    : new Date(pickupAt.getTime() + (1 + Math.floor(Math.random()*9))*86400e3);

  const odometer = 1000 + Math.floor(Math.random() * 180000);
  const doc = {
    inspection_id:   i,
    rental_id:       rentalId,
    car_id:          carId,
    car_category:    category,
    inspection_type: inspType,
    inspector_id:    inspectorId,
    inspector_name:  inspectorName,
    performed_at:    performedAt,
    branch_code:     BRANCHES[carId % 5],
    odometer_km:     odometer,
    fuel_level_pct:  inspType === 'pickup' ? 100 : Math.floor(Math.random()*100),
    damage_marks:    buildDamageMarks(),
    checklist:       buildChecklist(category, inspType),
    inspector_notes: inspType === 'pickup'
                       ? 'Vehicle released to customer after checklist confirmation.'
                       : (Math.random() < 0.05
                            ? 'Customer reported minor concern on return — logged.'
                            : 'No issues reported on return.')
  };
  batch.push(doc);

  if (batch.length === BATCH) {
    db.vehicle_inspections.insertMany(batch, { ordered: false });
    batch = [];
    if ((i / BATCH) % 5 === 0) {
      print(`Inserted ${i} / ${TOTAL} inspections — elapsed ${((Date.now()-start)/1000).toFixed(1)}s`);
    }
  }
}
if (batch.length) db.vehicle_inspections.insertMany(batch, { ordered: false });

print(`Done. vehicle_inspections count: ${db.vehicle_inspections.countDocuments()}`);
print(`Pickups: ${db.vehicle_inspections.countDocuments({inspection_type:'pickup'})}`);
print(`Returns: ${db.vehicle_inspections.countDocuments({inspection_type:'return'})}`);
print(`With damage: ${db.vehicle_inspections.countDocuments({'damage_marks.0':{$exists:true}})}`);
