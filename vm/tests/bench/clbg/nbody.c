/* CLBG n-body as AWFY's NBody (NBody.st), 250,000 steps of 0.01: the system's energy, which must be
   -0.1690859889909308 (the result is that test, 1 if it holds). */
#define NAME "NBody"
#define EXPECTED 1
#include "harness.h"
#include <math.h>

typedef struct { double x, y, z, vx, vy, vz, mass; } Body;

static const double PI = 3.141592653589793, DAYS_PER_YEAR = 365.24;

static Body body(double x, double y, double z, double vx, double vy, double vz, double mass)
{
    const double solar_mass = 4 * PI * PI;
    Body b = {x, y, z, vx * DAYS_PER_YEAR, vy * DAYS_PER_YEAR, vz * DAYS_PER_YEAR, mass * solar_mass};
    return b;
}

static void advance(Body *bodies, int n, double dt)
{
    for (int i = 0; i < n; i++) {
        Body *ib = &bodies[i];
        for (int j = i + 1; j < n; j++) {
            Body *jb = &bodies[j];
            double dx = ib->x - jb->x, dy = ib->y - jb->y, dz = ib->z - jb->z;
            double d_squared = (dx * dx) + (dy * dy) + (dz * dz);
            double distance = sqrt(d_squared);
            double mag = dt / (d_squared * distance);
            ib->vx = ib->vx - (dx * jb->mass * mag);
            ib->vy = ib->vy - (dy * jb->mass * mag);
            ib->vz = ib->vz - (dz * jb->mass * mag);
            jb->vx = jb->vx + (dx * ib->mass * mag);
            jb->vy = jb->vy + (dy * ib->mass * mag);
            jb->vz = jb->vz + (dz * ib->mass * mag);
        }
    }
    for (int i = 0; i < n; i++) {
        bodies[i].x = bodies[i].x + (dt * bodies[i].vx);
        bodies[i].y = bodies[i].y + (dt * bodies[i].vy);
        bodies[i].z = bodies[i].z + (dt * bodies[i].vz);
    }
}

static double energy(const Body *bodies, int n)
{
    double e = 0.0;
    for (int i = 0; i < n; i++) {
        const Body *ib = &bodies[i];
        e = e + (0.5 * ib->mass * ((ib->vx * ib->vx) + (ib->vy * ib->vy) + (ib->vz * ib->vz)));
        for (int j = i + 1; j < n; j++) {
            const Body *jb = &bodies[j];
            double dx = ib->x - jb->x, dy = ib->y - jb->y, dz = ib->z - jb->z;
            double distance = sqrt((dx * dx) + (dy * dy) + (dz * dz));
            e = e - ((ib->mass * jb->mass) / distance);
        }
    }
    return e;
}

static int64_t setup(void) { return 0; }

static int64_t run(void)
{
    const double solar_mass = 4 * PI * PI;
    Body bodies[5] = {
        body(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0),
        body(4.8414314424647209, -1.16032004402742839, -0.103622044471123109, 0.00166007664274403694, 0.00769901118419740425, -0.0000690460016972063023, 0.000954791938424326609),
        body(8.34336671824457987, 4.12479856412430479, -0.403523417114321381, -0.00276742510726862411, 0.00499852801234917238, 0.0000230417297573763929, 0.000285885980666130812),
        body(12.894369562139131, -15.1111514016986312, -0.223307578892655734, 0.00296460137564761618, 0.0023784717395948095, -0.0000296589568540237556, 0.0000436624404335156298),
        body(15.3796971148509165, -25.9193146099879641, 0.179258772950371181, 0.00268067772490389322, 0.00162824170038242295, -0.000095159225451971587, 0.0000515138902046611451)};
    double px = 0.0, py = 0.0, pz = 0.0;
    for (int i = 0; i < 5; i++) {
        px = px + (bodies[i].vx * bodies[i].mass);
        py = py + (bodies[i].vy * bodies[i].mass);
        pz = pz + (bodies[i].vz * bodies[i].mass);
    }
    bodies[0].vx = 0.0 - (px / solar_mass);
    bodies[0].vy = 0.0 - (py / solar_mass);
    bodies[0].vz = 0.0 - (pz / solar_mass);
    for (int i = 0; i < 250000; i++) advance(bodies, 5, 0.01);
    return energy(bodies, 5) == -0.1690859889909308;
}
