ShaderView subclass: #JugglerStage
	instanceVariableNames: 'juggler'
	classVariableNames: ''
	package: 'Tools'!

JugglerStage comment: 'I show a ShannonJuggler in 3D: a scene raymarched on the GPU (shaderSource, MSL) on a little stage, a curtain behind, a gilded proscenium at the walls and the ceiling: the W. C. Fields figure (top hat, nose, glowing cigar) behind its box, the arms posed to reach the cups, the balls blurred along their way since the previous frame, the drum whose head gives under a bounce. My uniforms are the model''s state in its stage''s points, read at each drawing; the camera drifts on the act''s clock (frame), so a halted act shows a still picture. A click restarts the act.'!

!JugglerStage methodsFor: 'accessing'!
juggler: aShannonJuggler
	juggler := aShannonJuggler
! !

!JugglerStage methodsFor: 'shader'!
uniforms
	"The rows of the shader's Scene: the stage, the drum, the ball colour, the cups, the ball radius, five balls (in a hand: no velocity)."
	| balls left right |
	balls := juggler balls.
	left := (juggler hands detect: [:each | each isLeft]) position.
	right := (juggler hands detect: [:each | each isLeft not]) position.
	^(Array
		with: (Array with: juggler stageExtent with: juggler frame with: (balls size min: 5))
		with: (Array with: juggler drum origin with: juggler drum corner)
		with: juggler ballColor
		with: (Array with: left with: right)
		with: JugglerBall radius),
	((1 to: 5) collect: [:i |
		i > balls size
			ifTrue: [0]
			ifFalse: [Array
				with: (balls at: i) position
				with: ((juggler flying includes: (balls at: i)) ifTrue: [(balls at: i) velocity] ifFalse: [0 @ 0])]])
!
renderScale
	"Three quarters of the device pixels, for the frame budget."
	^0.75
!
shaderSource
	^'struct Scene {
	float4 stage;		// stage width, height (points), frame, ball count
	float4 drum;		// left, top (the drumhead), right, bottom
	float4 ballColor;
	float4 hands;		// cups: left x, y, right x, y
	float4 ballRadius;
	float4 balls[5];	// centre x, y, velocity x, y (points per frame; 0 in a hand)
};

// The model placed in the scene: 100 stage points a unit, y up, the floor at 0, the balls in the plane z = 0, the figure behind at figureZ.
struct Pose {
	float3 shoulder[2], elbow[2], wrist[2], cup[2], forearm[2];
	float4 ball[5];
	float3 velocity[5];	// per frame
	float dent[5];
	int balls;
	float3 drum;		// centre x, head y, radius
	float2 stage;		// the walls'' x, the ceiling''s y
	float time;
};

constant float figureZ = -1.3;
// what the rays march through: everything below the shoulders, the head and hat above them
constant float3 lowMin = float3(-2.7, 0.0, -1.9), lowMax = float3(2.7, 2.55, 0.95);
constant float3 highMin = float3(-0.62, 2.5, -1.7), highMax = float3(0.62, 3.72, -0.7);
constant float curtainZ = -3.0;

float3 world(float2 p, constant Scene &s) { return float3((p.x - s.stage.x * 0.5) * 0.01, (s.drum.w - p.y) * 0.01, 0.0); }
float3 lin(float3 srgb) { return pow(srgb, float3(2.2)); }

float smin(float a, float b, float k) { float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0); return mix(b, a, h) - k * h * (1.0 - h); }
float sdCapsule(float3 p, float3 a, float3 b, float r) { float3 pa = p - a, ba = b - a; float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0); return length(pa - ba * h) - r; }
float sdRoundBox(float3 p, float3 b, float r) { float3 q = abs(p) - b + r; return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - r; }
float sdCylinder(float3 p, float r, float y0, float y1) { float2 d = float2(length(p.xz) - r, abs(p.y - (y0 + y1) * 0.5) - (y1 - y0) * 0.5); return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)); }
float sdTorus(float3 p, float R, float r) { return length(float2(length(p.xz) - R, p.y)) - r; }
float sdEllipsoid(float3 p, float3 r) { float k0 = length(p / r); float k1 = length(p / (r * r)); return k0 * (k0 - 1.0) / k1; }
float sdRoundCone(float3 p, float3 a, float3 b, float r1, float r2) {
	float3 ba = b - a; float l2 = dot(ba, ba); float rr = r1 - r2; float a2 = l2 - rr * rr; float il2 = 1.0 / l2;
	float3 pa = p - a; float y = dot(pa, ba); float z = y - l2; float3 xv = pa * l2 - ba * y; float x2 = dot(xv, xv);
	float y2 = y * y * l2; float z2 = z * z * l2; float k = sign(rr) * rr * rr * x2;
	if (sign(z) * a2 * z2 > k) return sqrt(x2 + z2) * il2 - r2;
	if (sign(y) * a2 * y2 < k) return sqrt(x2 + y2) * il2 - r1;
	return (sqrt(x2 * a2 * il2) + y * rr) * il2 - r1;
}
float2 opU(float2 a, float2 b) { return a.x < b.x ? a : b; }

float hash(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }
float noise(float2 p) {
	float2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + float2(1, 0)), f.x), mix(hash(i + float2(0, 1)), hash(i + float2(1, 1)), f.x), f.y);
}

#define M_JACKET 1.0
#define M_ACCENT 2.0
#define M_SKIN 3.0
#define M_NOSE 4.0
#define M_EYE 5.0
#define M_HAT 6.0
#define M_BAND 7.0
#define M_CIGAR 8.0
#define M_BRASS 9.0
#define M_SHELL 10.0
#define M_CHROME 11.0
#define M_HEAD 12.0
#define M_WOOD 13.0
#define M_GLOVE 14.0
#define M_SHIRT 15.0
#define M_LIP 16.0
#define M_SATIN 17.0

constant float3 headC = float3(0.0, 2.86, figureZ);
constant float3 cigarA = float3(0.06, 2.7, 0.2 + figureZ);
constant float3 cigarB = float3(0.34, 2.6, 0.47 + figureZ);

// the top hat''s frame: tilted a little to the side
float3 hatSpace(float3 q) {
	float3 h = q - float3(0.0, 3.06, 0.0);
	const float c = 0.9939, s = -0.1098;
	return float3(c * h.x - s * h.y, s * h.x + c * h.y, h.z);
}

float2 mapHead(float3 p) {
	float3 q = p - float3(0.0, 0.0, figureZ);
	float3 e = float3(abs(q.x), q.y, q.z);
	float d = length(q - float3(0.0, 2.88, 0.0)) - 0.265;
	d = smin(d, sdEllipsoid(q - float3(0.0, 2.74, 0.05), float3(0.25, 0.17, 0.22)), 0.1);
	d = smin(d, sdCapsule(q, float3(0.0, 2.4, -0.03), float3(0.0, 2.7, 0.0), 0.12), 0.06);
	d = smin(d, sdEllipsoid(e - float3(0.262, 2.87, -0.01), float3(0.045, 0.085, 0.06)), 0.03);
	float2 r = float2(d, M_SKIN);
	// W. C. Fields'' nose
	float nose = smin(length(q - float3(0.0, 2.825, 0.29)) - 0.078, sdCapsule(q, float3(0.0, 2.94, 0.24), float3(0.0, 2.84, 0.29), 0.034), 0.04);
	nose = smin(nose, length(e - float3(0.048, 2.81, 0.26)) - 0.045, 0.03);
	r = opU(r, float2(nose, M_NOSE));
	// the eyes under heavy lids, the brows, the mouth
	float3 eye = e - float3(0.098, 2.935, 0.214);
	r = opU(r, float2(length(eye) - 0.036, M_EYE));
	float lids = min(max(length(eye) - 0.042, 0.004 - eye.y - 0.006 * eye.x / 0.04), max(length(eye) - 0.04, eye.y + 0.014));
	r = opU(r, float2(lids, M_SKIN));
	r = opU(r, float2(sdCapsule(e, float3(0.05, 2.995, 0.248), float3(0.16, 2.985, 0.212), 0.017), M_BAND));
	r = opU(r, float2(sdCapsule(q, float3(-0.095, 2.708, 0.236), float3(0.045, 2.698, 0.255), 0.01), M_LIP));
	r = opU(r, float2(sdCapsule(q, cigarA - float3(0.0, 0.0, figureZ), cigarB - float3(0.0, 0.0, figureZ), 0.03), M_CIGAR));
	float3 h = hatSpace(q);
	float crownR = 0.215 + 0.035 * clamp(h.y / 0.5, 0.0, 1.0) - 0.014 * sin(3.1416 * clamp(h.y / 0.5, 0.0, 1.0)) - 0.012;
	float2 cd = float2(length(h.xz * float2(1.0, 1.08)) - crownR, abs(h.y - 0.26) - 0.238);
	float crown = min(max(cd.x, cd.y), 0.0) + length(max(cd, 0.0)) - 0.012;
	float3 b = h;
	b.y -= 0.08 * (b.x * b.x) / (0.36 * 0.36) - 0.015 * (b.z * b.z) / (0.33 * 0.33);
	float2 bd = float2((length(b.xz / float2(0.37, 0.33)) - 1.0) * 0.33, abs(b.y) - 0.008);
	float brim = min(max(bd.x, bd.y), 0.0) + length(max(bd, 0.0)) - 0.007;
	r = opU(r, float2(smin(crown, brim, 0.03), (h.y > 0.035 && h.y < 0.14 && cd.x > -0.02) ? M_BAND : M_HAT));
	return r;
}

float torsoRadius(float y) { return mix(0.5, 0.34, clamp((y - 1.05) / 1.15, 0.0, 1.0)); }

float2 mapBody(float3 p) {
	float3 q = p - float3(0.0, 0.0, figureZ);
	float bound = sdRoundBox(q - float3(0.0, 1.7, 0.0), float3(0.72, 0.95, 0.5), 0.1);
	if (bound > 0.3) return float2(bound, M_JACKET);
	float3 t = float3(q.x, q.y, q.z * 1.35);
	float d = sdRoundCone(t, float3(0.0, 1.05, 0.0), float3(0.0, 2.2, 0.0), 0.5, 0.34) / 1.35;
	d = smin(d, sdCapsule(t, float3(-0.36, 2.36, 0.0), float3(0.36, 2.36, 0.0), 0.14) / 1.35, 0.13);
	float2 r = float2(d, M_JACKET);
	// satin lapels along the V, a pocket square
	float edge = abs(q.x) - (q.y - 1.72) * 0.24;
	float lapel = max(max(d - 0.012, abs(edge - 0.06) - 0.06), max(max(1.74 - q.y, q.y - 2.36), -q.z));
	r = opU(r, float2(lapel, M_SATIN));
	r = opU(r, float2(sdEllipsoid(q - float3(-0.25, 2.075, 0.19), float3(0.07, 0.028, 0.022)), M_ACCENT));
	// the shirt collar, the bow tie, the buttons
	float collar = sdTorus(q - float3(0.0, 2.45, -0.015), 0.115, 0.035);
	r = opU(r, float2(collar, M_SHIRT));
	float3 x = float3(abs(q.x), q.y, q.z);
	float bow = sdEllipsoid(x - float3(0.075, 2.39, 0.215), float3(0.078, 0.05, 0.032));
	bow = min(bow, length(q - float3(0.0, 2.39, 0.235)) - 0.032);
	r = opU(r, float2(bow, M_ACCENT));
	float y = clamp(floor((2.15 - q.y) / 0.28 + 0.5), 0.0, 2.0);
	y = 2.15 - 0.28 * y;
	r = opU(r, float2(length(q - float3(0.0, y, torsoRadius(y) / 1.35 - 0.004)) - 0.032, M_ACCENT));
	return r;
}

float2 mapArm(float3 p, thread const Pose &P, int i) {
	float d = sdCapsule(p, P.shoulder[i], P.elbow[i], 0.09);
	d = smin(d, sdCapsule(p, P.elbow[i], P.wrist[i], 0.072), 0.05);
	float2 r = float2(d, M_JACKET);
	float near = length(p - P.cup[i]) - 0.32;
	if (near > 0.05) return opU(r, float2(near, M_BRASS));
	float3 fa = P.forearm[i];
	r = opU(r, float2(sdCapsule(p, P.wrist[i] - fa * 0.08, P.wrist[i] - fa * 0.035, 0.083), M_SHIRT));
	r = opU(r, float2(sdEllipsoid(p - P.wrist[i] - float3(0.0, 0.035, 0.02), float3(0.085, 0.07, 0.085)), M_GLOVE));
	// the cup on the hand, open at the top
	float3 c = p - P.cup[i];
	float cup = sdCylinder(c, 0.118, -0.045, 0.045);
	cup = max(cup, -sdCylinder(c, 0.1, -0.025, 0.2));
	cup = min(cup, sdTorus(c - float3(0.0, 0.045, 0.0), 0.109, 0.011));
	cup = min(cup, sdCapsule(p, P.wrist[i] + float3(0.0, 0.05, 0.03), P.cup[i] - float3(0.0, 0.04, 0.0), 0.026));
	return opU(r, float2(cup, M_BRASS));
}

float dentAt(float2 xz, thread const Pose &P) {
	float d = 0.0;
	for (int i = 0; i < P.balls; i++) {
		float2 o = xz - P.ball[i].xz;
		d += P.dent[i] * exp(-dot(o, o) * 16.0);
	}
	return d;
}

float2 mapDrum(float3 p, thread const Pose &P) {
	float3 q = p - float3(P.drum.x, 0.0, 0.0);
	float R = P.drum.z, top = P.drum.y;
	float b = sdCylinder(q, R + 0.06, 0.0, top + 0.05);
	if (b > 0.05) return float2(b, M_SHELL);
	float rq = length(q.xz);
	float2 r = float2(max(sdCylinder(q, R - 0.005, 0.16, top - 0.03), -sdCylinder(q, R - 0.035, top - 0.12, top)), M_SHELL);
	float hoops = min(sdTorus(q - float3(0.0, top - 0.008, 0.0), R + 0.004, 0.02), sdTorus(q - float3(0.0, 0.17, 0.0), R + 0.004, 0.02));
	if (rq > R - 0.12) {
		// lugs and tension rods, ten around the shell; three legs
		float a = atan2(q.z, q.x);
		const float sector = 6.2831853 / 10.0;
		float k = (floor(a / sector) + 0.5) * sector;
		float3 l = float3(rq * cos(a - k), q.y, rq * sin(a - k));
		hoops = min(hoops, sdRoundBox(l - float3(R + 0.018, (top + 0.17) * 0.5, 0.0), float3(0.018, 0.06, 0.022), 0.012));
		hoops = min(hoops, sdCapsule(l, float3(R + 0.03, top - 0.03, 0.0), float3(R + 0.03, top - 0.12, 0.0), 0.008));
		const float leg = 6.2831853 / 3.0;
		float lk = (floor((a + 0.5236) / leg) + 0.5) * leg - 0.5236;
		float3 g = float3(rq * cos(a - lk), q.y, rq * sin(a - lk));
		hoops = min(hoops, sdCapsule(g, float3(R + 0.03, 0.3, 0.0), float3(R + 0.17, 0.0, 0.0), 0.014));
	}
	r = opU(r, float2(hoops, M_CHROME));
	float skin = q.y - top;
	if (skin > -0.08 && skin < 0.06) skin += dentAt(q.xz + float2(P.drum.x, 0.0), P);
	float head = max(rq - (R - 0.01), max(skin, top - 0.08 - q.y));
	return opU(r, float2(head, M_HEAD));
}

float2 mapBox(float3 p) {
	float3 q = p - float3(0.0, 0.58, -1.36);
	float d = sdRoundBox(q, float3(1.32, 0.58, 0.5), 0.02);
	if (d > 0.1) return float2(d, M_WOOD);
	float panel = sdRoundBox(q - float3(0.0, -0.02, 0.5), float3(1.12, 0.4, 0.012), 0.01);
	d = max(d, -panel);
	float2 r = float2(d, M_WOOD);
	float3 t = float3(q.x, abs(q.y) - 0.565, q.z);
	float trim = max(sdRoundBox(t, float3(1.345, 0.022, 0.52), 0.012), -sdRoundBox(t, float3(1.29, 0.05, 0.465), 0.0));
	return opU(r, float2(trim, M_BRASS));
}

float2 map(float3 p, thread const Pose &P) {
	float2 r = mapBox(p);
	r = opU(r, mapDrum(p, P));
	float head = length(p - float3(0.0, 3.05, figureZ)) - 0.72;
	r = opU(r, head > 0.3 ? float2(head, M_SKIN) : mapHead(p));
	r = opU(r, mapBody(p));
	r = opU(r, mapArm(p, P, 0));
	r = opU(r, mapArm(p, P, 1));
	return r;
}

// A coarse stand-in for shadows and the floor''s occlusion: a dozen primitives.
float proxy(float3 p, thread const Pose &P) {
	float d = sdRoundBox(p - float3(0.0, 0.58, -1.375), float3(1.32, 0.58, 0.485), 0.02);
	d = min(d, sdCylinder(p - float3(P.drum.x, 0.0, 0.0), P.drum.z - 0.01, 0.16, P.drum.y - 0.01));
	for (int i = 0; i < P.balls; i++) d = min(d, length(p - P.ball[i].xyz) - P.ball[i].w);
	for (int i = 0; i < 2; i++) {
		d = min(d, sdCapsule(p, P.shoulder[i], P.elbow[i], 0.088));
		d = min(d, sdCapsule(p, P.elbow[i], P.wrist[i], 0.07));
		d = min(d, sdCylinder(p - P.cup[i], 0.118, -0.045, 0.045));
	}
	float3 q = p - float3(0.0, 0.0, figureZ);
	float fig = sdRoundBox(q - float3(0.0, 2.35, 0.0), float3(0.6, 1.3, 0.45), 0.1);
	if (fig > d) return d;
	float3 t = float3(q.x, q.y, q.z * 1.35);
	d = min(d, sdRoundCone(t, float3(0.0, 1.05, 0.0), float3(0.0, 2.2, 0.0), 0.5, 0.34) / 1.35);
	d = min(d, sdCapsule(t, float3(-0.36, 2.36, 0.0), float3(0.36, 2.36, 0.0), 0.14) / 1.35);
	d = min(d, length(q - float3(0.0, 2.84, 0.02)) - 0.25);
	float3 h = hatSpace(q);
	d = min(d, sdCylinder(h, 0.17, 0.0, 0.48));
	d = min(d, sdCylinder(h, 0.32, -0.006, 0.006));
	return min(d, sdCapsule(p, cigarA, cigarB, 0.028));
}

float3 normalAt(float3 p, thread const Pose &P) {
	const float2 k = float2(1, -1);
	const float h = 0.0006;
	return normalize(k.xyy * map(p + k.xyy * h, P).x + k.yyx * map(p + k.yyx * h, P).x
		+ k.yxy * map(p + k.yxy * h, P).x + k.xxx * map(p + k.xxx * h, P).x);
}

float2 boxHit(float3 ro, float3 inv, float3 bmin, float3 bmax) {
	float3 t0 = (bmin - ro) * inv, t1 = (bmax - ro) * inv;
	float3 lo = min(t0, t1), hi = max(t0, t1);
	return float2(max(max(lo.x, lo.y), lo.z), min(min(hi.x, hi.y), hi.z));
}

// the span of the ray inside the bounds (empty: x > y)
float2 boxHit(float3 ro, float3 rd) {
	float3 inv = 1.0 / rd;
	float2 a = boxHit(ro, inv, lowMin, lowMax), b = boxHit(ro, inv, highMin, highMax);
	if (a.x > a.y) return b;
	if (b.x > b.y) return a;
	return float2(min(a.x, b.x), max(a.y, b.y));
}

// the nearest hit: t, material (0: none)
float2 march(float3 ro, float3 rd, float tMax, thread const Pose &P, int steps) {
	float2 b = boxHit(ro, rd);
	float t = max(b.x, 0.0);
	float end = min(b.y, tMax);
	for (int i = 0; i < steps && t < end; i++) {
		float2 h = map(ro + rd * t, P);
		if (h.x < 0.0005 * t) return float2(t, h.y);
		t += h.x;
	}
	return float2(tMax, 0.0);
}

float ballHit(float3 ro, float3 rd, float4 s) {
	float3 o = ro - s.xyz;
	float b = dot(o, rd), c = dot(o, o) - s.w * s.w, h = b * b - c;
	if (h < 0.0) return -1.0;
	return -b - sqrt(h);
}

float softShadow(float3 ro, float3 rd, thread const Pose &P) {
	float2 b = boxHit(ro, rd);
	float end = min(b.y, 8.0);
	float res = 1.0, t = max(b.x, 0.012);
	for (int i = 0; i < 24 && t < end; i++) {
		float h = proxy(ro + rd * t, P);
		res = min(res, 7.0 * h / t);
		if (res < 0.003) return 0.0;
		t += clamp(h, 0.02, 0.35);
	}
	return smoothstep(0.0, 1.0, res);
}

float occlusion(float3 p, float3 n, thread const Pose &P) {
	float o = 0.0, w = 1.0;
	for (int i = 1; i <= 4; i++) {
		float h = 0.018 * float(i * i);
		o += (h - map(p + n * h, P).x) * w;
		w *= 0.65;
	}
	return clamp(1.0 - 3.0 * o, 0.0, 1.0);
}

float floorOcclusion(float3 p, thread const Pose &P) {
	float o = 0.0, w = 1.0;
	for (int i = 1; i <= 4; i++) {
		float h = 0.04 * float(i * i);
		o += (h - proxy(p + float3(0.0, h, 0.0), P)) * w;
		w *= 0.6;
	}
	return clamp(1.0 - 1.6 * o, 0.0, 1.0);
}

constant float3 keyPos = float3(-2.3, 7.6, 7.6);
constant float3 keyColor = float3(1.0, 0.86, 0.68) * 2.6;
constant float3 fillDir = float3(0.66, 0.3, 0.69);
constant float3 fillColor = float3(0.42, 0.52, 0.75) * 0.3;
constant float3 rimDir = float3(0.45, 0.5, -0.74);
constant float3 rimColor = float3(0.85, 0.92, 1.0) * 1.5;
constant float3 footDir = float3(0.0, -0.41, 0.91);
constant float3 footColor = float3(1.0, 0.72, 0.42) * 0.4;

float spot(float3 p) {
	float3 axis = normalize(float3(0.0, 1.9, -1.3) - keyPos);
	float c = dot(normalize(p - keyPos), axis);
	return 0.06 + 0.94 * smoothstep(0.925, 0.983, c);
}

struct Surface { float3 albedo; float rough; float spec; float3 emit; float metal; };

float flickerAt(float time) { return 0.75 + 0.25 * sin(time * 7.0) * sin(time * 2.3 + 1.0); }

Surface materialAt(float m, float3 p, float3 n, thread const Pose &P) {
	Surface o = { float3(0.6), 0.5, 0.04, float3(0.0), 0.0 };
	float3 q = p - float3(0.0, 0.0, figureZ);
	if (m == M_JACKET) {
		// the shirt front, a V between the lapels
		float edge = abs(q.x) - (q.y - 1.72) * 0.24;
		float front = step(0.0, q.z) * step(1.72, q.y);
		o.albedo = lin(mix(float3(0.88, 0.85, 0.79), float3(0.97, 0.97, 0.98), smoothstep(0.004, -0.004, edge) * front));
		o.albedo *= 1.0 - 0.35 * smoothstep(0.012, 0.0, abs(edge)) * front;
		o.rough = 0.65;
	} else if (m == M_SHIRT) { o.albedo = lin(float3(0.97, 0.97, 0.98)); o.rough = 0.5; }
	else if (m == M_GLOVE) { o.albedo = lin(float3(0.95, 0.95, 0.93)); o.rough = 0.55; }
	else if (m == M_ACCENT) { o.albedo = lin(float3(0.106, 0.227, 0.549)); o.rough = 0.3; o.spec = 0.06; }
	else if (m == M_SKIN) {
		float2 c = float2(abs(q.x) - 0.15, q.y - 2.79);
		o.albedo = lin(mix(float3(0.96, 0.9, 0.85), float3(0.95, 0.66, 0.64), 0.6 * exp(-dot(c, c) * 160.0) * step(0.0, q.z)));
		o.rough = 0.45;
	} else if (m == M_LIP) { o.albedo = lin(float3(0.55, 0.25, 0.24)); o.rough = 0.4; }
	else if (m == M_SATIN) { o.albedo = lin(float3(0.92, 0.9, 0.86)); o.rough = 0.28; o.spec = 0.05; }
	else if (m == M_NOSE) { o.albedo = lin(float3(0.93, 0.62, 0.6)); o.rough = 0.32; }
	else if (m == M_EYE) {
		float3 d = normalize(float3(abs(q.x) - 0.098, q.y - 2.935, q.z - 0.214));
		o.albedo = d.z > 0.88 ? float3(0.004) : (d.z > 0.8 ? lin(float3(0.25, 0.17, 0.1)) : lin(float3(0.9, 0.88, 0.84)));
		o.rough = 0.1; o.spec = 0.08;
	}
	else if (m == M_HAT) { o.albedo = lin(float3(0.6, 0.6, 0.62)) * (0.9 + 0.1 * noise(p.xy * 90.0)); o.rough = 0.85; o.spec = 0.02; }
	else if (m == M_BAND) { o.albedo = float3(0.006); o.rough = 0.25; o.spec = 0.05; }
	else if (m == M_CIGAR) {
		float h = dot(p - cigarA, cigarB - cigarA) / dot(cigarB - cigarA, cigarB - cigarA);
		o.albedo = lin(mix(float3(0.42, 0.25, 0.13), float3(0.62, 0.6, 0.57), smoothstep(0.87, 0.9, h))) * (0.8 + 0.2 * noise(float2(h * 60.0, 0.0)));
		o.rough = 0.7;
		o.emit = float3(1.0, 0.3, 0.04) * 8.0 * flickerAt(P.time) * smoothstep(0.955, 0.99, h + 0.02 * noise(n.xy * 20.0));
	} else if (m == M_BRASS) { o.albedo = float3(0.95, 0.7, 0.32); o.rough = 0.25; o.metal = 1.0; }
	else if (m == M_CHROME) { o.albedo = float3(0.9, 0.91, 0.93); o.rough = 0.1; o.metal = 1.0; }
	else if (m == M_SHELL) {
		float a = atan2(p.z, p.x - P.drum.x);
		o.albedo = lin(float3(0.55, 0.06, 0.08)) * (0.85 + 0.15 * noise(float2(a * 30.0, p.y * 4.0)));
		o.rough = 0.1; o.spec = 0.06;
	} else if (m == M_HEAD) {
		// a coated head: a darker ring near the hoop, a dot in the middle
		float r = length(p.xz - float2(P.drum.x, 0.0)) / P.drum.z;
		o.albedo = lin(float3(0.86, 0.84, 0.79)) * (0.92 + 0.08 * noise(p.xz * 60.0));
		o.albedo *= 1.0 - 0.12 * smoothstep(0.86, 0.9, r) - 0.2 * smoothstep(0.13, 0.12, r);
		o.rough = 0.6;
	} else if (m == M_WOOD) {
		float v = p.y + p.z + 0.05 * sin(p.x * 2.0);
		float g = noise(float2(p.x * 1.2, v * 11.0 + noise(float2(p.x, v) * 2.0) * 2.0));
		g = 0.75 * g + 0.25 * noise(float2(p.x * 3.0, v * 24.0));
		o.albedo = lin(mix(float3(0.13, 0.045, 0.025), float3(0.27, 0.1, 0.05), g)) * (n.y > 0.5 ? 0.6 : 1.0);
		o.rough = 0.35; o.spec = 0.04;
	}
	return o;
}

float3 floorAlbedo(float3 p) {
	float plank = floor(p.x / 0.24);
	float along = p.z + hash(float2(plank, 3.0)) * 7.0;
	float seam = floor(along / 2.4);
	float h = hash(float2(plank, seam));
	float g = noise(float2(p.x * 16.0 + noise(float2(p.x, along) * 3.0), along * 1.1)) * 0.7 + noise(float2(p.x * 36.0, along * 2.6)) * 0.3;
	float3 c = lin(mix(float3(0.27, 0.15, 0.08), float3(0.34, 0.19, 0.1), h)) * (0.85 + 0.25 * g);
	float lines = min(smoothstep(0.0, 0.01, abs(fract(p.x / 0.24) - 0.5) * 0.24 - 0.112), smoothstep(0.0, 0.015, abs(fract(along / 2.4) - 0.5) * 2.4 - 1.185));
	return c * (0.6 + 0.4 * lines);
}

// the curtain: velvet in folds
// the curtain: velvet in soft folds, darker in the cores, lighter where the folds turn away (the sheen)
float3 curtainColor(float3 p, float3 rd, float shadow) {
	float x = p.x;
	float w = x * 5.2 + 1.1 * sin(x * 1.4) + p.y * 0.2 * sin(x * 1.9);
	float f = sin(w);
	float df = cos(w) * (5.2 + 1.54 * cos(x * 1.4));
	float3 n = normalize(float3(-0.15 * df, 0.0, 1.0));
	float3 l = normalize(keyPos - p);
	float facing = max(dot(n, -rd), 0.0);
	float diff = 0.3 + 0.7 * max(dot(n, l), 0.0);
	float core = 0.45 + 0.55 * facing * facing;
	float sheen = pow(1.0 - facing, 2.2);
	float valley = 0.18 + 0.82 * smoothstep(-1.0, 1.0, f);
	float3 base = lin(float3(0.46, 0.035, 0.06));
	float pool = spot(p) * shadow;
	float3 c = base * keyColor * pool * diff * valley * core * 0.85 + base * 0.02 * valley;
	c += lin(float3(0.95, 0.36, 0.38)) * sheen * (0.25 + 0.75 * valley) * (0.05 + 0.9 * pool);
	float hem = smoothstep(0.13, 0.12, p.y);
	c = mix(c, lin(float3(0.75, 0.55, 0.2)) * (0.3 + 0.7 * valley) * keyColor * pool * 0.35 * (0.85 + 0.15 * sin(x * 140.0)), hem);
	return c * smoothstep(5.5, 1.2, p.y);
}

float3 lightSurface(float3 p, float3 n, float3 rd, Surface m, float shadow, float ao) {
	float3 l = normalize(keyPos - p);
	float3 h = normalize(l - rd);
	float nl = max(dot(n, l), 0.0);
	float nv = max(dot(n, -rd), 0.0);
	float r2 = m.rough * m.rough;
	float shininess = 2.0 / max(r2 * r2, 0.0005);
	float3 f0 = mix(float3(m.spec), m.albedo, m.metal);
	float3 fres = f0 + (1.0 - f0) * pow(1.0 - nv, 5.0);
	float specK = pow(max(dot(n, h), 0.0), shininess) * (shininess + 8.0) / 25.0;
	float3 diffuse = m.albedo * (1.0 - m.metal);
	float3 c = (diffuse + fres * specK) * keyColor * (nl * shadow * spot(p));
	c += diffuse * fillColor * max(dot(n, fillDir), 0.0) * ao;
	c += fres * pow(max(dot(n, normalize(fillDir - rd)), 0.0), shininess * 0.5) * fillColor * ao;
	c += (diffuse + fres * pow(max(dot(n, normalize(footDir - rd)), 0.0), shininess)) * footColor * max(dot(n, footDir), 0.0) * ao;
	float rim = max(dot(n, rimDir), 0.0) * pow(1.0 - nv, 2.5);
	c += (diffuse + f0) * rimColor * rim * ao;
	c += (diffuse * mix(float3(0.05, 0.025, 0.025), float3(0.09, 0.085, 0.095), 0.5 + 0.5 * n.y) + f0 * 0.04) * ao;
	return c + m.emit;
}

// The proscenium: gilded pillars at the walls, a beam at the ceiling (the stage''s edges for a ball''s rim). Answers t (1e5: missed) and the normal.
float proscenium(float3 ro, float3 rd, thread const Pose &P, thread float3 &n) {
	float3 inv = 1.0 / rd;
	float w = P.stage.x, c = P.stage.y, t = 1e5;
	float3 lo[3] = { float3(-w - 0.4, 0.0, -0.3), float3(w, 0.0, -0.3), float3(-w - 0.4, c, -0.3) };
	float3 hi[3] = { float3(-w, c, 0.3), float3(w + 0.4, c, 0.3), float3(w + 0.4, c + 0.36, 0.3) };
	for (int i = 0; i < 3; i++) {
		float3 t0 = (lo[i] - ro) * inv, t1 = (hi[i] - ro) * inv;
		float3 a = min(t0, t1), b = max(t0, t1);
		float tn = max(max(a.x, a.y), a.z), tf = min(min(b.x, b.y), b.z);
		if (tn < tf && tn > 0.0 && tn < t) {
			t = tn;
			n = tn == a.x ? float3(-sign(rd.x), 0, 0) : (tn == a.y ? float3(0, -sign(rd.y), 0) : float3(0, 0, -sign(rd.z)));
		}
	}
	return t;
}

float3 gilded(float3 p, float3 n, float3 rd) {
	// flutes up the pillars, mouldings along the beam
	float3 m = n;
	if (abs(n.z) > 0.5) m += p.y > 4.25 ? float3(0.0, 0.15 * sin(p.y * 52.0), 0.0) : float3(0.15 * sin(p.x * 47.0), 0.0, 0.0);
	Surface g = { float3(1.0, 0.76, 0.36), 0.38, 0.04, float3(0.0), 1.0 };
	if (abs(n.z) < 0.5) { g.albedo = lin(float3(0.62, 0.42, 0.2)); g.rough = 0.6; g.metal = 0.4; }
	return lightSurface(p, normalize(m), rd, g, 1.0, 1.0) + g.albedo * lin(float3(0.3, 0.06, 0.06)) * 0.25;
}

// A look along a reflected ray: the scene without shadows, the curtain, the floor; blurred: shorter, no normals.
float3 reflected(float3 ro, float3 rd, thread const Pose &P, constant Scene &s, int avoidBall, bool sharp) {
	float tFloor = rd.y < 0.0 ? -ro.y / rd.y : 1e5;
	float tCurtain = rd.z < 0.0 ? (curtainZ - ro.z) / rd.z : 1e5;
	float tMax = min(min(tFloor, tCurtain), 30.0);
	float2 h = march(ro, rd, tMax, P, sharp ? 40 : 24);
	float tb = 1e5;
	int bi = -1;
	for (int i = 0; i < P.balls; i++) {
		if (i == avoidBall) continue;
		float t = ballHit(ro, rd, P.ball[i]);
		if (t > 0.0 && t < tb) { tb = t; bi = i; }
	}
	if (bi >= 0 && tb < h.x) {
		float3 p = ro + rd * tb;
		Surface m = { lin(s.ballColor.rgb), 0.15, 0.05, float3(0.0), 0.0 };
		return lightSurface(p, normalize(p - P.ball[bi].xyz), rd, m, 1.0, 1.0);
	}
	if (h.y > 0.0) {
		float3 p = ro + rd * h.x;
		if (!!sharp) {
			Surface m = materialAt(h.y, p, -rd, P);
			return (m.albedo * (0.4 * keyColor * spot(p) + 0.08) + m.emit) * (m.metal > 0.5 ? 0.12 : 1.0);
		}
		float3 n = normalAt(p, P);
		return lightSurface(p, n, rd, materialAt(h.y, p, n, P), 1.0, 0.8);
	}
	if (tFloor < tCurtain) {
		float3 p = ro + rd * tFloor;
		return floorAlbedo(p) * keyColor * 0.3 * spot(p);
	}
	if (tCurtain < 1e4) return curtainColor(ro + rd * tCurtain, rd, 1.0);
	// the house, dark, a glimmer of the footlights low down
	return mix(float3(0.06, 0.035, 0.02), float3(0.012, 0.012, 0.016), smoothstep(-0.2, 0.4, rd.y));
}

// where ball i was at s (0: the previous frame, 1: now), bouncing off the drumhead on the way
float3 ballAt(int i, float s, thread const Pose &P) {
	float3 c = P.ball[i].xyz - P.velocity[i] * (1.0 - s);
	float head = P.drum.y + P.ball[i].w - P.dent[i];
	if (P.velocity[i].x !!= 0.0 && c.y < head && abs(c.x - P.drum.x) < P.drum.z) c.y = 2.0 * head - c.y;
	return c;
}

float3 aces(float3 x) { return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0); }

Pose pose(constant Scene &s) {
	Pose P;
	P.time = s.stage.z / 60.0;
	float left = s.drum.x, right = s.drum.z;
	P.drum = float3((left + right) * 0.5 - s.stage.x * 0.5, s.drum.w - s.drum.y, (right - left) * 0.5) * 0.01;
	P.balls = int(min(s.stage.w, 5.0));
	P.stage = float2(s.stage.x * 0.005, s.drum.w * 0.01);
	float r = s.ballRadius.x * 0.01;
	for (int i = 0; i < P.balls; i++) {
		float4 b = s.balls[i];
		float3 c = world(b.xy, s);
		float3 v = float3(b.z, -b.w, 0.0) * 0.01;
		// the drumhead gives where a ball comes down on it: fully in a frame with a bounce
		float onHead = step(abs(c.x - P.drum.x), P.drum.z - 0.05);
		float gap = min(c.y, c.y - v.y) - r - P.drum.y;
		P.dent[i] = onHead * 0.028 * pow(clamp(1.0 - gap / 0.07, 0.0, 1.0), 2.0);
		P.ball[i] = float4(c, r);
		P.velocity[i] = v;
	}
	// each arm reaches its cup: two bones, the elbow down and out
	for (int i = 0; i < 2; i++) {
		float side = i == 0 ? -1.0 : 1.0;
		float3 cup = world(i == 0 ? s.hands.xy : s.hands.zw, s);
		float3 sh = float3(side * 0.47, 2.36, figureZ);
		float3 w = cup + float3(-side * 0.02, -0.11, -0.1);
		const float L1 = 1.08, L2 = 1.02;
		float3 v = w - sh;
		float d = clamp(length(v), 0.1, L1 + L2 - 0.001);
		float3 dir = normalize(v);
		w = sh + dir * d;
		float a = (L1 * L1 - L2 * L2 + d * d) / (2.0 * d);
		float3 pole = normalize(float3(side * 0.9, -1.0, -0.35));
		float3 perp = normalize(pole - dir * dot(pole, dir));
		P.shoulder[i] = sh;
		P.elbow[i] = sh + dir * a + perp * sqrt(max(L1 * L1 - a * a, 0.0));
		P.wrist[i] = w;
		P.forearm[i] = normalize(w - P.elbow[i]);
		P.cup[i] = cup;
	}
	return P;
}

fragment float4 fmain(ShaderIn in [[stage_in]], constant Scene &s [[buffer(0)]]) {
	Pose P = pose(s);
	float aspect = in.size.x / in.size.y;
	// the camera drifts slowly, on the act''s clock
	float yaw = 0.11 * sin(P.time * 0.13) + 0.02;
	float pitch = 0.09 + 0.02 * sin(P.time * 0.09 + 1.0);
	float3 target = float3(0.0, 2.2, -0.5);
	float3 ro = target + 8.4 * float3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch));
	float3 fw = normalize(target - ro);
	float3 rt = normalize(cross(fw, float3(0, 1, 0)));
	float3 up = cross(rt, fw);
	float tanV = max(0.33, 0.37 / aspect);
	float2 ndc = float2(in.uv.x * 2.0 - 1.0, 1.0 - in.uv.y * 2.0);
	float3 rd = normalize(fw + rt * ndc.x * tanV * aspect + up * ndc.y * tanV);

	float tFloor = rd.y < 0.0 ? -ro.y / rd.y : 1e5;
	float tCurtain = rd.z < 0.0 ? (curtainZ - ro.z) / rd.z : 1e5;
	float tMax = min(min(tFloor, tCurtain), 40.0);
	float3 pn;
	float tp = proscenium(ro, rd, P, pn);
	float2 h = march(ro, rd, min(tMax, tp), P, 96);
	if (h.y == 0.0 && tp < tMax) h = float2(tp, -1.0);
	// the balls, blurred along their way since the previous frame
	const int samples = 6;
	float tb = 1e5, cover = 0.0;
	int bi = -1;
	float3 bc = 0.0;
	for (int i = 0; i < P.balls; i++) {
		for (int k = 0; k < samples; k++) {
			float3 c = ballAt(i, (float(k) + 0.5) / float(samples), P);
			float t = ballHit(ro, rd, float4(c, P.ball[i].w));
			if (t > 0.0 && t < h.x) {
				cover += 1.0 / float(samples);
				if (t < tb) { tb = t; bi = i; bc = c; }
			}
		}
	}
	float3 col = 0.0, ball = 0.0;
	if (bi >= 0) {
		// a ball: lacquered, mirroring the stage
		float3 p = ro + rd * tb;
		float3 n = normalize(p - bc);
		Surface m = { lin(s.ballColor.rgb), 0.08, 0.05, float3(0.0), 0.0 };
		float ao = 0.5 + 0.5 * occlusion(p, n, P);
		ball = lightSurface(p, n, rd, m, softShadow(p + n * 0.004, normalize(keyPos - p), P), ao);
		float fres = 0.04 + 0.96 * pow(1.0 - max(dot(n, -rd), 0.0), 5.0);
		ball += reflected(p + n * 0.003, reflect(rd, n), P, s, bi, true) * mix(0.1, 1.0, fres) * ao;
		cover = min(cover, 1.0);
	}
	if (cover >= 1.0) {
	} else if (h.y < 0.0) {
		col = gilded(ro + rd * h.x, pn, rd);
	} else if (h.y > 0.0) {
		float3 p = ro + rd * h.x;
		float3 n = normalAt(p, P);
		Surface m = materialAt(h.y, p, n, P);
		col = lightSurface(p, n, rd, m, softShadow(p + n * 0.003, normalize(keyPos - p), P), occlusion(p, n, P));
		if (m.metal > 0.5 || h.y == M_SHELL) {
			float3 f0 = mix(float3(m.spec), m.albedo, m.metal);
			float3 fres = f0 + (1.0 - f0) * pow(1.0 - max(dot(n, -rd), 0.0), 5.0);
			col += reflected(p + n * 0.02, reflect(rd, n), P, s, -1, false) * fres * (1.0 - m.rough);
		}
	} else if (tFloor < tCurtain) {
		// the stage floor, lacquered boards
		float3 p = ro + rd * tFloor;
		float ao = floorOcclusion(p, P);
		Surface m = { floorAlbedo(p), 0.35, 0.04, float3(0.0), 0.0 };
		col = lightSurface(p, float3(0, 1, 0), rd, m, softShadow(p + float3(0, 0.002, 0), normalize(keyPos - p), P), ao);
		float fres = 0.04 + 0.96 * pow(1.0 - max(-rd.y, 0.0), 5.0);
		col += reflected(p + float3(0, 0.002, 0), reflect(rd, float3(0, 1, 0)), P, s, -1, false) * mix(0.05, 0.45, fres) * ao;
	} else {
		float3 p = ro + rd * tCurtain;
		col = curtainColor(p, rd, spot(p) < 0.1 ? 1.0 : softShadow(p + float3(0, 0, 0.01), normalize(keyPos - p), P));
	}
	col = mix(col, ball, cover);
	// the glow around the cigar''s tip
	float tt = max(dot(cigarB - ro, rd), 0.0);
	float glow = length(ro + rd * tt - cigarB);
	col += float3(1.0, 0.35, 0.08) * 0.08 * flickerAt(P.time) * exp(-glow * 35.0);

	float2 v = in.uv - 0.5;
	col *= 1.0 - 0.8 * dot(v, v);
	col = pow(aces(col * 1.05), float3(1.0 / 2.2));
	// triangular dither of one 8-bit step
	uint2 q = uint2(in.pos.xy);
	uint k = q.x * 1973u + q.y * 9277u + 26699u;
	k = (k ^ (k >> 15)) * 2246822519u;
	k ^= k >> 13;
	col += (float(k & 0xFFFFu) / 65535.0 + float(k >> 16) / 65535.0 - 1.0) / 255.0;
	return float4(col, 1.0);
}
'
! !

!JugglerStage methodsFor: 'events'!
mouseDown: anEvent
	anEvent button = 1 ifFalse: [^false].
	juggler restart.
	^true
!
mouseUp: anEvent
	^true
! !

!JugglerStage methodsFor: 'remote control'!
remoteRole
	^#canvas
!
remoteLabel
	^'Claude''s Robot'
! !
