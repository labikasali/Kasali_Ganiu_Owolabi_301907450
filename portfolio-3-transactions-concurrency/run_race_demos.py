#!/usr/bin/env python3
"""run_race_demos.py - six concurrency demos with TWO real PostgreSQL sessions (A and B).
Everything printed here is real output from your own database. Run: python3 run_race_demos.py
"""
import threading, time, sys
import psycopg2
from psycopg2 import errors

DSN = "host=/var/run/postgresql dbname=driveeasy user=driveeasy"

def conn(iso=None):
    c = psycopg2.connect(DSN)
    c.autocommit = False
    if iso:
        c.set_isolation_level(iso)
    return c

def q(cur, sql, args=None):
    cur.execute(sql, args)
    return cur.fetchall() if cur.description else None

def say(msg):
    print(msg, flush=True)

def reset_loose():
    c = conn(); cur = c.cursor()
    cur.execute("""CREATE TABLE IF NOT EXISTS rental_loose (
        rental_id bigserial PRIMARY KEY, car_id bigint NOT NULL, customer_id bigint NOT NULL,
        pickup_time timestamptz NOT NULL, return_time timestamptz NOT NULL,
        CHECK (return_time > pickup_time))""")
    cur.execute("TRUNCATE rental_loose RESTART IDENTITY")
    c.commit(); c.close()

FREE = """SELECT NOT EXISTS (SELECT 1 FROM rental_loose WHERE car_id=3
          AND tstzrange(pickup_time,return_time,'[)') && tstzrange(now()+'7 days', now()+'9 days','[)'))"""
INS = "INSERT INTO rental_loose(car_id,customer_id,pickup_time,return_time) VALUES (3,%s,now()+'7 days',now()+'9 days')"

def count_loose():
    c = conn(); cur = c.cursor(); n = q(cur, "SELECT count(*) FROM rental_loose")[0][0]; c.close(); return n

# ---------------------------------------------------------------- PART 1
def part1():
    say("\n=== PART 1: BUG - check-then-insert with no protection (READ COMMITTED) ===")
    reset_loose()
    A, B = conn(), conn(); a, b = A.cursor(), B.cursor()
    say(f"A: is car 3 free? -> {q(a, FREE)[0][0]}")
    say(f"B: is car 3 free? -> {q(b, FREE)[0][0]}")
    q(b, INS, (2,)); B.commit(); say("B: inserted booking for customer 2 and COMMITTED")
    q(a, INS, (1,)); A.commit(); say("A: inserted booking for customer 1 and COMMITTED")
    n = count_loose()
    say(f"RESULT: {n} bookings for the same car and window -> {'DOUBLE BOOKING (bug reproduced)' if n == 2 else 'no bug'}")
    A.close(); B.close()

# ---------------------------------------------------------------- PART 2
def part2():
    say("\n=== PART 2: FIX 1 - EXCLUDE constraint on the real rental table ===")
    c0 = conn(); cur0 = c0.cursor()
    car = q(cur0, """SELECT car_id FROM car c WHERE status<>'maintenance' AND NOT EXISTS
        (SELECT 1 FROM rental r WHERE r.car_id=c.car_id AND r.rental_range && tstzrange(now()+'40 days', now()+'42 days','[)'))
        AND NOT EXISTS (SELECT 1 FROM maintenance m WHERE m.car_id=c.car_id AND tstzrange(m.start_time,m.end_time,'[)') && tstzrange(now()+'40 days', now()+'42 days','[)')) ORDER BY car_id LIMIT 1""")[0][0]
    custs = [r[0] for r in q(cur0, "SELECT customer_id FROM driver_licence WHERE expiry_date > current_date+100 ORDER BY customer_id LIMIT 2")]
    c0.close()
    sql = """INSERT INTO rental(car_id,customer_id,pickup_branch_id,return_branch_id,pickup_time,return_time,start_mileage,end_mileage,status)
             VALUES (%s,%s,1,1,now()+'40 days',now()+'42 days',0,0,'booked') RETURNING rental_id"""
    A, B = conn(), conn(); a, b = A.cursor(), B.cursor()
    rid = q(a, sql, (car, custs[0]))[0][0]
    say(f"A: inserted rental {rid} for car {car} (not committed yet)")
    out = {}
    def run_b():
        try:
            q(b, sql, (car, custs[1])); B.commit(); out['b'] = "B: insert succeeded (double booking!)"
        except errors.ExclusionViolation as e:
            B.rollback(); out['b'] = f"B: REJECTED with SQLSTATE {e.pgcode} (exclusion_violation) - {str(e).splitlines()[0]}"
    t = threading.Thread(target=run_b); t.start(); time.sleep(1.5)
    say(f"B: is waiting for A (thread alive = {t.is_alive()})")
    A.commit(); say("A: COMMIT"); t.join(); say(out['b'])
    c = conn(); cu = c.cursor(); cu.execute("DELETE FROM rental WHERE rental_id=%s", (rid,)); c.commit(); c.close()
    A.close(); B.close()

# ---------------------------------------------------------------- PART 3
def part3():
    say("\n=== PART 3: FIX 2 - SELECT ... FOR UPDATE on the car row (serialises the check) ===")
    reset_loose()
    A, B = conn(), conn(); a, b = A.cursor(), B.cursor()
    q(a, "SELECT car_id FROM car WHERE car_id=3 FOR UPDATE"); say("A: locked car 3 (FOR UPDATE)")
    say(f"A: is car 3 free? -> {q(a, FREE)[0][0]}")
    q(a, INS, (1,)); say("A: inserted booking (not committed yet)")
    out = {}
    def run_b():
        q(b, "SELECT car_id FROM car WHERE car_id=3 FOR UPDATE")
        free = q(b, FREE)[0][0]; out['free'] = free
        if free: q(b, INS, (2,))
        B.commit()
    t = threading.Thread(target=run_b); t.start(); time.sleep(1.5)
    say(f"B: BLOCKED waiting for the car lock (thread alive = {t.is_alive()})")
    A.commit(); say("A: COMMIT (lock released)"); t.join()
    say(f"B: after waiting, is car 3 free? -> {out['free']}  -> B refuses to book")
    n = count_loose(); say(f"RESULT: {n} booking(s) in the table -> {'correct, no double booking' if n == 1 else 'BUG'}")
    A.close(); B.close()

# ---------------------------------------------------------------- PART 4
def part4():
    say("\n=== PART 4: FIX 3 - SERIALIZABLE isolation (second committer is aborted) ===")
    reset_loose()
    S = psycopg2.extensions.ISOLATION_LEVEL_SERIALIZABLE
    A, B = conn(S), conn(S); a, b = A.cursor(), B.cursor()
    say(f"A: is car 3 free? -> {q(a, FREE)[0][0]}")
    say(f"B: is car 3 free? -> {q(b, FREE)[0][0]}")
    q(a, INS, (1,)); q(b, INS, (2,))
    A.commit(); say("A: COMMIT ok")
    try:
        B.commit(); say("B: COMMIT ok (unexpected)")
    except psycopg2.Error as e:
        B.rollback(); say(f"B: COMMIT FAILED SQLSTATE {e.pgcode} - {str(e).splitlines()[0]}")
    say(f"RESULT: {count_loose()} booking(s) stored; the application retries B and sees the car is taken")
    A.close(); B.close()

# ---------------------------------------------------------------- PART 5
def part5():
    say("\n=== PART 5: READ COMMITTED vs REPEATABLE READ (non-repeatable read) ===")
    for name, iso in (("READ COMMITTED", psycopg2.extensions.ISOLATION_LEVEL_READ_COMMITTED),
                      ("REPEATABLE READ", psycopg2.extensions.ISOLATION_LEVEL_REPEATABLE_READ)):
        reset_loose()
        A, B = conn(iso), conn(); a, b = A.cursor(), B.cursor()
        first = q(a, "SELECT count(*) FROM rental_loose")[0][0]
        q(b, INS, (9,)); B.commit()
        second = q(a, "SELECT count(*) FROM rental_loose")[0][0]
        A.commit(); A.close(); B.close()
        say(f"{name}: A reads {first} row(s); B inserts + commits; A reads again -> {second} row(s)  "
            f"{'(non-repeatable/phantom read)' if first != second else '(same snapshot)'}")

# ---------------------------------------------------------------- PART 6
def part6():
    say("\n=== PART 6: DEADLOCK - A locks car 1 then 2, B locks car 2 then 1 ===")
    A, B = conn(), conn(); a, b = A.cursor(), B.cursor()
    q(a, "SELECT 1 FROM car WHERE car_id=1 FOR UPDATE"); say("A: locked car 1")
    q(b, "SELECT 1 FROM car WHERE car_id=2 FOR UPDATE"); say("B: locked car 2")
    res = {}
    def go(name, C, cur, cid):
        try:
            q(cur, "SELECT 1 FROM car WHERE car_id=%s FOR UPDATE", (cid,)); res[name] = "got the second lock"
        except psycopg2.Error as e:
            C.rollback(); res[name] = f"DEADLOCK DETECTED SQLSTATE {e.pgcode} - {str(e).splitlines()[0]}"
    ta = threading.Thread(target=go, args=("A", A, a, 2)); tb = threading.Thread(target=go, args=("B", B, b, 1))
    ta.start(); time.sleep(0.5); tb.start()
    first = None
    for _ in range(100):
        if len(res) >= 1: break
        time.sleep(0.1)
    for n in ("A", "B"):
        if n in res and "DEADLOCK" in res[n]:
            say(f"{n}: {res[n]}  -> {n} is the victim and is rolled back")
    # release the survivor
    for n, C in (("A", A), ("B", B)):
        if n in res and "DEADLOCK" not in res[n]:
            C.commit()
    for t in (ta, tb): t.join(timeout=10)
    for n in ("A", "B"):
        if n in res and "DEADLOCK" not in res[n]:
            say(f"{n}: {res[n]} after the victim released its lock -> COMMIT")
    for C in (A, B):
        try: C.rollback(); C.close()
        except Exception: pass
    say("FIX: always lock rows in a fixed order (lowest car_id first) so a cycle cannot form.")

if __name__ == "__main__":
    for p in (part1, part2, part3, part4, part5, part6):
        p()
    say("\nAll 6 demos finished.")
