// =============================================================================
// Portfolio 4 — seed_gps_logs.js
// Generate GPS trip logs (time-series) — for ~5,000 rentals, one point every
// 60 seconds for a 30-minute trip = 30 points per rental = ~150k documents.
//
// Run AFTER setup_validation.js + seed_inspections.js:
//   mongosh --quiet --file seed_gps_logs.js
// =============================================================================

const db = db.getSiblingDB('driveeasy');

const Lagos = { lat: 6.5244, lng: 3.3792 };   // Ikeja approx
const Abuja = { lat: 9.0765, lng: 7.3986 };

const RENTALS = 5000;        // generate GPS for 5,000 rentals
const POINTS_PER_TRIP = 30;  // one point per minute → 30-min trips

let batch = [];
let start = Date.now();

for (let r = 1; r <= RENTALS; r++) {
  const carId = 1 + (r % 200);
  const startCity = Math.random() < 0.8 ? Lagos : Abuja;
  // jitter around the city centre
  let lat = startCity.lat + (Math.random()-0.5) * 0.1;
  let lng = startCity.lng + (Math.random()-0.5) * 0.1;
  const tripStart = Date.now() - Math.floor(Math.random()*30)*86400e3;   // within last 30 days
  let odometer = 1000 + Math.floor(Math.random()*180000);

  for (let p = 0; p < POINTS_PER_TRIP; p++) {
    const ts = new Date(tripStart + p*60_000);
    // random walk
    lat += (Math.random()-0.5) * 0.001;
    lng += (Math.random()-0.5) * 0.001;
    const speed = p === 0 || p === POINTS_PER_TRIP-1 ? 0 : 20 + Math.random()*60;
    odometer += speed / 60;   // km
    const event = p === 0 ? 'ignition_on'
                : p === POINTS_PER_TRIP-1 ? 'ignition_off'
                : speed < 5 ? 'idle' : 'moving';

    batch.push({
      ts:          ts,
      rental_id:   r,
      car_id:      carId,
      lat:         lat,
      lng:         lng,
      speed_kph:   speed,
      odometer_km: odometer,
      event:       event
    });
  }
  if (batch.length >= 5000) {
    db.gps_trip_logs.insertMany(batch, { ordered: false });
    batch = [];
    if (r % 1000 === 0) {
      print(`Generated GPS for ${r}/${RENTALS} rentals — elapsed ${((Date.now()-start)/1000).toFixed(1)}s`);
    }
  }
}
if (batch.length) db.gps_trip_logs.insertMany(batch, { ordered: false });

print(`Done. gps_trip_logs count: ${db.gps_trip_logs.countDocuments()}`);
