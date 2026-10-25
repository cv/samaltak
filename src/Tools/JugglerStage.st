ShaderView subclass: #JugglerStage
	instanceVariableNames: 'juggler'
	classVariableNames: ''
	package: 'Tools'!

JugglerStage comment: 'I show a ShannonJuggler in 3D: a scene raymarched on the GPU (shaderSource, MSL) on a little stage, a curtain behind, a gilded proscenium at the walls and the ceiling: the W. C. Fields figure (top hat, nose, glowing cigar) behind its box, the arms posed to reach the cups, the balls blurred along their way since the previous frame, the drum whose head gives under a bounce; lit like a photograph of the real machine (painted papier-mâché, wool, felt, turned brass, old wood, haze in the spotlight, film grain). My uniforms are the model''s state in its stage''s points, read at each drawing; the camera drifts on the act''s clock (frame), so a halted act shows a still picture. A click restarts the act.'!

!JugglerStage methodsFor: 'accessing'!
juggler: aShannonJuggler
	juggler := aShannonJuggler
! !

!JugglerStage methodsFor: 'shader'!
uniforms
	"The rows of the shader's Scene: the stage, the drum, the ball colour, the bowls, the sizes, the bowls' tilts, five balls."
	| balls left right |
	balls := juggler balls.
	left := juggler hands detect: [:each | each isLeft].
	right := juggler hands detect: [:each | each isLeft not].
	^(Array
		with: (Array with: juggler stageExtent with: juggler frame with: (balls size min: 5))
		with: (Array with: juggler drum origin with: juggler drum corner)
		with: juggler ballColor
		with: (Array with: left position with: right position)
		with: (Array with: JugglerBall radius with: JugglerHand bowlRadius with: JugglerHand rimAngle)
		with: (Array with: left tilt with: right tilt)),
	((1 to: 5) collect: [:i |
		i > balls size
			ifTrue: [0]
			ifFalse: [Array with: (balls at: i) position with: (balls at: i) velocity]])
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
	float4 hands;		// the bowls'' centres: left x, y, right x, y
	float4 sizes;		// ball radius, bowl radius, rim angle
	float4 handPose;	// tilt left, right (radians, + turns the opening to +x)
	float4 balls[5];	// centre x, y, velocity x, y (points per frame)
};

// The model placed in the scene: 100 stage points a unit, y up, the floor at 0, the balls in the plane z = 0, the figure behind at figureZ.
struct Pose {
	float3 shoulder[2], elbow[2], wrist[2], cup[2], forearm[2];
	float2 tilt[2];		// the bowl''s tilt as cos, sin
	float bowl;
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
#define M_BUTTON 18.0

constant float3 headC = float3(0.0, 2.86, figureZ);
constant float3 cigarA = float3(0.03, 2.704, 0.17 + figureZ);
constant float3 cigarB = float3(0.3, 2.585, 0.46 + figureZ);

// the top hat''s frame: tilted a little to the side
float3 hatSpace(float3 q) {
	float3 h = q - float3(0.0, 3.06, 0.0);
	const float c = 0.9939, s = -0.1098;
	return float3(c * h.x - s * h.y, s * h.x + c * h.y, h.z);
}

// the head''s frame: turned a little towards the cigar, cocked a little
float3 headSpace(float3 p) {
	float3 q = p - float3(0.0, 2.8, figureZ);
	const float cy = 0.9975, sy = 0.07, cr = 0.9992, sr = 0.04;
	q.xz = float2(cy * q.x + sy * q.z, -sy * q.x + cy * q.z);
	q.xy = float2(cr * q.x - sr * q.y, sr * q.x + cr * q.y);
	return q + float3(0.0, 2.8, 0.0);
}

float smax(float a, float b, float k) { return -smin(-a, -b, k); }

constant float3 eyeC = float3(0.088, 2.93, 0.2);

// a caricature head, sculpted: cranium, brow ridge, cheekbones, jowls, chin, the nose, lips round the cigar, ears, eyes in their sockets under heavy lids
float2 mapHead(float3 p) {
	float3 w = p - float3(0.0, 0.0, figureZ);
	float3 q = headSpace(p);
	float3 e = float3(abs(q.x), q.y, q.z);
	float2 r = float2(sdCapsule(w, cigarA - float3(0.0, 0.0, figureZ), cigarB - float3(0.0, 0.0, figureZ), 0.03), M_CIGAR);
	float3 h = hatSpace(q);
	float hatBound = sdCylinder(h, 0.42, -0.06, 0.56);
	if (hatBound > 0.06) r = opU(r, float2(hatBound, M_HAT));
	else {
		float crownR = 0.215 + 0.035 * clamp(h.y / 0.5, 0.0, 1.0) - 0.014 * sin(3.1416 * clamp(h.y / 0.5, 0.0, 1.0)) - 0.012;
		float2 cd = float2(length(h.xz * float2(1.0, 1.08)) - crownR, abs(h.y - 0.26) - 0.238);
		float crown = min(max(cd.x, cd.y), 0.0) + length(max(cd, 0.0)) - 0.012;
		float3 b = h;
		b.y -= 0.08 * (b.x * b.x) / (0.36 * 0.36) - 0.015 * (b.z * b.z) / (0.33 * 0.33);
		float2 bd = float2((length(b.xz / float2(0.37, 0.33)) - 1.0) * 0.33, abs(b.y) - 0.008);
		float brim = min(max(bd.x, bd.y), 0.0) + length(max(bd, 0.0)) - 0.007;
		r = opU(r, float2(smin(crown, brim, 0.03), (h.y > 0.035 && h.y < 0.14 && cd.x > -0.02) ? M_BAND : M_HAT));
		r = opU(r, float2(sdEllipsoid(h - float3(-0.21, 0.085, 0.07), float3(0.022, 0.035, 0.03)), M_BAND));
	}
	float faceBound = length(q - float3(0.0, 2.82, 0.03)) - 0.4;
	if (faceBound > 0.06) return opU(r, float2(faceBound, M_SKIN));
	float d = sdEllipsoid(q - float3(0.0, 2.93, -0.02), float3(0.235, 0.255, 0.245));
	d = smin(d, sdEllipsoid(q - float3(0.0, 2.8, 0.06), float3(0.22, 0.2, 0.19)), 0.08);
	d = smin(d, sdEllipsoid(q - float3(0.0, 2.995, 0.19), float3(0.165, 0.038, 0.06)), 0.04);
	d = smin(d, sdEllipsoid(e - float3(0.115, 2.865, 0.165), float3(0.075, 0.05, 0.065)), 0.05);
	d = smin(d, sdEllipsoid(e - float3(0.13, 2.7, 0.1), float3(0.1, 0.105, 0.1)), 0.07);
	d = smin(d, sdEllipsoid(q - float3(0.0, 2.635, 0.13), float3(0.085, 0.06, 0.07)), 0.05);
	d = smin(d, sdEllipsoid(e - float3(0.232, 2.88, -0.03), float3(0.03, 0.075, 0.055)), 0.025);
	d = smin(d, sdCapsule(q, float3(0.0, 2.35, -0.03), float3(0.0, 2.68, -0.04), 0.115), 0.06);
	d = smax(d, -(length(e - eyeC - float3(0.0, 0.0, 0.03)) - 0.045), 0.02);
	r = opU(r, float2(d, M_SKIN));
	// W. C. Fields'' nose: a bulb, the wings of the nostrils, the bridge
	float nose = length(q - float3(0.008, 2.83, 0.285)) - 0.078;
	nose = smin(nose, length(e - float3(0.042, 2.805, 0.262)) - 0.048, 0.03);
	nose = smin(nose, sdCapsule(q, float3(0.0, 2.97, 0.225), float3(0.004, 2.86, 0.29), 0.032), 0.04);
	r = opU(r, float2(nose, M_NOSE));
	// lips, the cigar in the corner of the mouth
	float lips = sdEllipsoid(q - float3(-0.01, 2.715, 0.21), float3(0.075, 0.022, 0.035));
	lips = smin(lips, sdEllipsoid(q - float3(-0.01, 2.687, 0.2), float3(0.062, 0.02, 0.032)), 0.012);
	// pursed round the cigar in the corner of the mouth
	lips = smin(lips, sdEllipsoid(w - float3(0.058, 2.699, 0.212), float3(0.034, 0.032, 0.024)), 0.015);
	r = opU(r, float2(lips, M_LIP));
	r = opU(r, float2(length(e - eyeC) - 0.04, M_EYE));
	float3 eye = e - eyeC;
	float lids = min(max(length(eye) - 0.046, 0.019 - eye.y - 0.006 * eye.x / 0.04), max(length(eye) - 0.044, eye.y + 0.027));
	return opU(r, float2(lids, M_SKIN));
}

float torsoRadius(float y) { return mix(0.5, 0.34, clamp((y - 1.05) / 1.15, 0.0, 1.0)); }

float torso(float3 q) {
	float3 t = float3(q.x, q.y, q.z * 1.35);
	float d = sdRoundCone(t, float3(0.0, 1.05, 0.0), float3(0.0, 2.2, 0.0), 0.5, 0.34) / 1.35;
	d = smin(d, sdCapsule(t, float3(-0.39, 2.34, 0.0), float3(0.39, 2.34, 0.0), 0.15) / 1.35, 0.12);
	return smin(d, sdEllipsoid(q - float3(0.01, 1.5, 0.08), float3(0.43, 0.42, 0.31)), 0.12);
}

float2 mapBody(float3 p) {
	float3 q = p - float3(0.0, 0.0, figureZ);
	float bound = sdRoundBox(q - float3(0.0, 1.7, 0.0), float3(0.72, 0.95, 0.5), 0.1);
	if (bound > 0.3) return float2(bound, M_JACKET);
	float d = torso(q);
	float2 r = float2(d, M_JACKET);
	// lapels rolled over the V, flapped pockets, a pocket square
	float edge = abs(q.x) - (q.y - 1.72) * 0.24;
	float lapel = smax(smax(d - 0.018 + 0.012 * smoothstep(0.0, 0.12, edge), abs(edge - 0.065) - 0.065, 0.012), max(max(1.74 - q.y, q.y - 2.37), -q.z), 0.01);
	r = opU(r, float2(lapel, M_SATIN));
	float3 x = float3(abs(q.x), q.y, q.z);
	r = opU(r, float2(sdEllipsoid(q - float3(-0.25, 2.075, 0.19), float3(0.07, 0.028, 0.022)), M_ACCENT));
	// the wing collar, the bow tie, the buttons
	float collar = sdTorus(q - float3(0.0, 2.45, -0.015), 0.125, 0.033);
	collar = min(collar, sdEllipsoid(x - float3(0.045, 2.43, 0.115), float3(0.035, 0.03, 0.012)));
	r = opU(r, float2(collar, M_SHIRT));
	float bow = sdEllipsoid(x - float3(0.075, 2.39, 0.215), float3(0.078, 0.05, 0.032));
	bow = min(bow, length(q - float3(0.0, 2.39, 0.235)) - 0.032);
	r = opU(r, float2(bow, M_ACCENT));
	float y = clamp(floor((2.15 - q.y) / 0.28 + 0.5), 0.0, 2.0);
	y = 2.15 - 0.28 * y;
	float belly = 0.08 + 0.31 * sqrt(max(1.0 - (y - 1.5) * (y - 1.5) / (0.42 * 0.42), 0.0));
	r = opU(r, float2(sdEllipsoid(q - float3(0.003 * y, y, max(torsoRadius(y) / 1.35, belly) + 0.014), float3(0.032, 0.032, 0.012)), M_BUTTON));
	return r;
}

// a sleeve from a to b: the cloth hangs below the arm
float sdSleeve(float3 p, float3 a, float3 b, float ra, float rb) {
	float3 pa = p - a, ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	float3 v = pa - ba * h;
	float l = length(v);
	float sag = max(-v.y / max(l, 1e-4), 0.0);
	return l - mix(ra, rb, h) * (1.0 + 0.22 * sag * sag);
}

float2 mapArm(float3 p, thread const Pose &P, int i) {
	float bound = min(sdCapsule(p, P.shoulder[i], P.elbow[i], 0.19), sdCapsule(p, P.elbow[i], P.cup[i], 0.2));
	if (bound > 0.08) return float2(bound, M_JACKET);
	float3 fa = P.forearm[i];
	float3 cuff = P.wrist[i] - fa * 0.075;
	float d = sdSleeve(p, P.shoulder[i], P.elbow[i], 0.12, 0.092);
	d = smin(d, length(p - P.shoulder[i] - float3(0.0, 0.025, 0.0)) - 0.135, 0.06);
	d = smin(d, sdSleeve(p, P.elbow[i], cuff, 0.094, 0.082), 0.05);
	// the cloth bunches at the bend
	float3 eb = p - P.elbow[i];
	float bunch = exp(-dot(eb, eb) * 60.0);
	d -= bunch * 0.012 * (0.5 + 0.5 * sin(dot(eb, normalize(P.wrist[i] - P.shoulder[i])) * 90.0));
	float2 r = float2(d, M_JACKET);
	float near = length(p - P.cup[i]) - 0.32;
	if (near > 0.05) return opU(r, float2(near, M_BRASS));
	r = opU(r, float2(sdCapsule(p, cuff - fa * 0.01, P.wrist[i] - fa * 0.02, 0.07), M_SHIRT));
	// in the bowl''s frame: its axis up, the opening at y = 0
	float3 c = p - P.cup[i];
	float2 cs = P.tilt[i];
	c.xy = float2(cs.x * c.x - cs.y * c.y, cs.y * c.x + cs.x * c.y);
	float R = P.bowl;
	float glove = sdRoundCone(p, P.wrist[i] - fa * 0.03, P.wrist[i] + fa * 0.01, 0.068, 0.062);
	glove = smin(glove, sdEllipsoid(c - float3(0.0, -R - 0.05, -0.03), float3(0.075, 0.05, 0.075)), 0.025);
	float side = i == 0 ? 1.0 : -1.0;
	for (int k = 0; k < 4; k++) {
		float x = (float(k) - 1.5) * 0.034;
		glove = smin(glove, sdCapsule(c, float3(x, -R - 0.05, 0.03), float3(x * 1.15, -R * 0.55 - 0.004 * float(k & 1), R * 0.86 + 0.012), 0.0165), 0.012);
	}
	glove = smin(glove, sdCapsule(c, float3(side * 0.06, -R - 0.04, -0.01), float3(side * (R * 0.9 + 0.015), -R * 0.45, 0.02), 0.018), 0.015);
	r = opU(r, float2(glove, M_GLOVE));
	// the bowl: a brass hemisphere, a rolled rim
	float bowl = max(abs(length(c) - R - 0.007) - 0.007, c.y);
	bowl = min(bowl, sdTorus(c, R + 0.007, 0.01));
	return opU(r, float2(bowl, M_BRASS));
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
	float panel = sdRoundBox(q - float3(0.0, -0.02, 0.5), float3(1.12, 0.4, 0.02), 0.012);
	d = max(d, -panel);
	float2 r = float2(d, M_WOOD);
	float3 t = float3(q.x, abs(q.y) - 0.578, q.z);
	float trim = max(sdRoundBox(t, float3(1.345, 0.028, 0.52), 0.012), -sdRoundBox(t, float3(1.29, 0.05, 0.465), 0.0));
	return opU(r, float2(trim, M_BRASS));
}

float2 map(float3 p, thread const Pose &P) {
	float2 r = mapBox(p);
	r = opU(r, mapDrum(p, P));
	float head = length(p - float3(0.0, 3.05, figureZ)) - 0.72;
	r = opU(r, head > 0.1 ? float2(head, M_SKIN) : mapHead(p));
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
		float3 c = p - P.cup[i];
		float2 cs = P.tilt[i];
		c.xy = float2(cs.x * c.x - cs.y * c.y, cs.y * c.x + cs.x * c.y);
		d = min(d, max(length(c) - P.bowl - 0.012, c.y + 0.03));
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

// the same, noting where a ray that misses passes closest (t, distance / t) for antialiased silhouettes
float2 marchEdge(float3 ro, float3 rd, float tMax, thread const Pose &P, int steps, thread float2 &edge) {
	float2 b = boxHit(ro, rd);
	float t = max(b.x, 0.0);
	float end = min(b.y, tMax);
	edge = float2(0.0, 1e5);
	for (int i = 0; i < steps && t < end; i++) {
		float2 h = map(ro + rd * t, P);
		if (h.x < 0.0005 * t) {
			// settle onto the surface, for clean normals on thin features
			t += h.x;
			t += map(ro + rd * t, P).x;
			return float2(t, h.y);
		}
		if (h.x / t < edge.y) edge = float2(t, h.x / t);
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

constant float3 keyPos = float3(-4.6, 7.2, 6.2);
constant float3 keyColor = float3(1.0, 0.84, 0.67) * 2.2;
constant float3 fillDir = float3(0.66, 0.3, 0.69);
constant float3 fillColor = float3(0.5, 0.55, 0.65) * 0.2;
constant float3 rimDir = float3(0.45, 0.5, -0.74);
constant float3 rimColor = float3(0.95, 0.93, 0.9) * 1.0;
constant float3 footDir = float3(0.0, -0.41, 0.91);
constant float3 footColor = float3(1.0, 0.74, 0.5) * 0.22;

float spot(float3 p) {
	float3 axis = normalize(float3(0.2, 1.9, -1.3) - keyPos);
	float c = dot(normalize(p - keyPos), axis);
	return 0.035 + 0.965 * smoothstep(0.935, 0.985, c);
}

// sheen: cloth and felt fuzz; aniso: brushed round a vertical axis (turned brass, hoops); wrap: light through paint and skin
struct Surface { float3 albedo; float rough; float spec; float3 emit; float metal; float sheen; float aniso; float wrap; float3 normal; };

float flickerAt(float time) { return 0.75 + 0.25 * sin(time * 7.0) * sin(time * 2.3 + 1.0); }

// a lumpy, creased normal for cloth
float3 creased(float3 n, float3 p, float amount) {
	float2 k = float2(noise(p.xy * 6.0 + p.z * 3.0), noise(p.zy * 6.0 + p.x * 3.0 + 7.0)) - 0.5;
	float fold = sin(p.y * 14.0 + 5.0 * noise(p.xz * 2.0)) * 0.6 * noise(p.xy * 3.0 + 1.0);
	return normalize(n + amount * float3(k.x, k.y * 0.6 + fold, k.y - k.x));
}

Surface materialAt(float m, float3 p, float3 n, thread const Pose &P) {
	Surface o = { float3(0.5), 0.5, 0.04, float3(0.0), 0.0, 0.0, 0.0, 0.0, n };
	float3 q = p - float3(0.0, 0.0, figureZ);
	float speck = noise(p.xy * 140.0 + p.z * 60.0);
	if (m == M_JACKET) {
		// ivory wool; the shirt front in the V between the lapels
		float edge = abs(q.x) - (q.y - 1.72) * 0.24;
		float front = step(0.0, q.z) * step(1.72, q.y);
		float shirt = smoothstep(0.004, -0.004, edge) * front;
		o.albedo = lin(mix(float3(0.72, 0.69, 0.62), float3(0.8, 0.79, 0.76), shirt)) * (0.94 + 0.06 * speck);
		o.rough = 0.85; o.spec = 0.03; o.sheen = 0.4;
		o.normal = creased(n, p, shirt > 0.5 ? 0.12 : 0.3);
		// flapped pockets
		float2 pk = float2(abs(q.x) - 0.27, q.y - 1.6);
		float pocket = step(0.0, q.z) * smoothstep(0.012, 0.0, abs(max(abs(pk.x) - 0.1, abs(pk.y) - 0.03)));
		o.albedo *= 1.0 - 0.35 * pocket - 0.2 * step(0.0, q.z) * smoothstep(0.0, -0.02, pk.y + 0.03) * smoothstep(-0.05, -0.03, pk.y) * step(abs(pk.x), 0.1);
		// the weave of the wool
		o.normal = normalize(o.normal + 0.06 * (float3(noise(p.xy * 70.0), noise(p.yz * 70.0 + 3.0), noise(p.zx * 70.0 + 5.0)) - 0.5));
		// seams round the shoulders, folds hanging from the armpits
		for (int i = 0; i < 2; i++) {
			float3 a = p - P.shoulder[i];
			o.albedo *= 1.0 - 0.35 * smoothstep(0.012, 0.0, abs(length(a) - 0.15)) * step(a.y, 0.12);
			float3 pit = p - P.shoulder[i] - float3(-sign(P.shoulder[i].x) * 0.12, -0.16, 0.0);
			float hang = exp(-dot(pit, pit) * 22.0);
			o.normal = normalize(o.normal + hang * 0.55 * float3(sin(atan2(pit.y, pit.x) * 9.0), 0.0, 0.0));
		}
		// the sleeves ruck up at the elbows
		for (int i = 0; i < 2; i++) {
			float3 e = p - P.elbow[i];
			float near = exp(-dot(e, e) * 40.0);
			float3 along = normalize(P.wrist[i] - P.shoulder[i]);
			o.normal = normalize(o.normal + near * 0.5 * along * sin(dot(e, along) * 70.0 + noise(e.xy * 20.0) * 2.0));
		}
	} else if (m == M_SATIN) {
		o.albedo = lin(float3(0.76, 0.74, 0.68)); o.rough = 0.4; o.spec = 0.05; o.sheen = 0.25;
		o.normal = creased(n, p, 0.12);
	} else if (m == M_SHIRT) { o.albedo = lin(float3(0.82, 0.81, 0.78)); o.rough = 0.7; o.sheen = 0.2; o.normal = creased(n, p, 0.15); }
	else if (m == M_GLOVE) { o.albedo = lin(float3(0.8, 0.79, 0.76)) * (0.94 + 0.06 * speck); o.rough = 0.9; o.sheen = 0.45; o.normal = creased(n, p * 2.0, 0.2); }
	else if (m == M_ACCENT) { o.albedo = lin(float3(0.12, 0.2, 0.42)); o.rough = 0.45; o.spec = 0.05; o.sheen = 0.3; }
	else if (m == M_SKIN || m == M_NOSE || m == M_LIP) {
		// painted papier-mâché: matte, mottled, the paint worn here and there
		float3 h = headSpace(p);
		float2 c = float2(abs(h.x) - 0.15, h.y - 2.79);
		float3 paint = m == M_NOSE ? float3(0.8, 0.52, 0.48) : (m == M_LIP ? float3(0.5, 0.26, 0.24) : float3(0.84, 0.77, 0.69));
		paint = mix(paint, float3(0.8, 0.5, 0.46), m == M_SKIN ? 0.65 * exp(-dot(c, c) * 110.0) * step(0.0, h.z) : 0.0);
		paint *= m == M_SKIN ? 1.0 - 0.12 * smoothstep(2.78, 2.62, h.y) : 1.0;
		float mottle = noise(h.xy * 18.0) * 0.6 + noise(h.zy * 45.0) * 0.4;
		o.albedo = lin(paint) * (0.9 + 0.12 * mottle) * (1.0 - 0.12 * smoothstep(0.84, 0.92, speck));
		// painted lashes along the lids
		float3 eye = float3(abs(h.x), h.y, h.z) - eyeC;
		float lash = smoothstep(0.054, 0.047, length(eye)) * smoothstep(0.006, 0.014, eye.y) * smoothstep(0.034, 0.02, eye.y);
		// painted brows, the left one raised
		float bx = abs(h.x);
		float brow = smoothstep(0.014, 0.007, abs(h.y - (2.997 + (h.x < 0.0 ? 0.012 : 0.0) - 1.2 * (bx - 0.09) * (bx - 0.09)))) * smoothstep(0.17, 0.15, bx) * smoothstep(0.025, 0.04, bx) * step(0.1, h.z);
		o.albedo = mix(o.albedo, float3(0.025, 0.018, 0.014), max(lash * 0.85, brow * 0.9) * (m == M_SKIN ? 1.0 : 0.0));
		o.rough = 0.55; o.spec = 0.035; o.wrap = 0.35;
	} else if (m == M_EYE) {
		float3 hp = headSpace(p);
		float3 d = normalize(hp - float3(sign(hp.x) * eyeC.x, eyeC.y, eyeC.z));
		o.albedo = d.z > 0.9 ? float3(0.004) : (d.z > 0.72 ? lin(float3(0.22, 0.15, 0.09)) : lin(float3(0.8, 0.78, 0.72)));
		o.rough = 0.15; o.spec = 0.06;
	}
	else if (m == M_HAT) {
		// grey felt: fuzz, a little uneven
		o.albedo = lin(float3(0.47, 0.46, 0.45)) * (0.85 + 0.15 * noise(p.xy * 60.0 + p.z * 30.0)) * (0.95 + 0.05 * speck);
		o.rough = 0.95; o.spec = 0.02; o.sheen = 0.7;
		o.normal = normalize(n + 0.08 * (float3(noise(p.xy * 90.0), noise(p.yz * 90.0), noise(p.zx * 90.0)) - 0.5));
	}
	else if (m == M_BUTTON) {
		// four thread holes, a shine
		float3 b = p - float3(0.0, 0.0, figureZ);
		float2 c = float2(b.x - 0.003 * b.y, fract((2.15 - b.y) / 0.28 + 0.5) * 0.28 - 0.14);
		float holes = smoothstep(0.006, 0.004, length(abs(c) - 0.009));
		o.albedo = mix(lin(float3(0.12, 0.2, 0.42)), float3(0.01), holes);
		o.rough = 0.25; o.spec = 0.07;
	}
	else if (m == M_BAND) { o.albedo = float3(0.008); o.rough = 0.3; o.spec = 0.05; o.sheen = 0.3; }
	else if (m == M_CIGAR) {
		float h = dot(p - cigarA, cigarB - cigarA) / dot(cigarB - cigarA, cigarB - cigarA);
		o.albedo = lin(mix(float3(0.36, 0.22, 0.12), float3(0.55, 0.53, 0.5), smoothstep(0.87, 0.9, h))) * (0.75 + 0.25 * noise(float2(h * 60.0, atan2(n.z, n.x) * 3.0)));
		o.rough = 0.8;
		o.emit = float3(1.0, 0.3, 0.04) * 8.0 * flickerAt(P.time) * smoothstep(0.955, 0.99, h + 0.02 * noise(n.xy * 20.0));
	} else if (m == M_BRASS) {
		// turned brass, a patina in patches
		float patina = smoothstep(0.45, 0.8, noise(p.xy * 4.0 + p.z * 3.0) * 0.8 + noise(p.zy * 12.0) * 0.2);
		o.albedo = mix(float3(0.85, 0.64, 0.36), float3(0.3, 0.28, 0.2), patina * 0.7);
		o.rough = mix(0.3, 0.6, patina); o.metal = 1.0 - 0.5 * patina; o.aniso = 1.0;
	} else if (m == M_CHROME) { o.albedo = float3(0.8, 0.8, 0.8); o.rough = 0.2; o.metal = 1.0; o.aniso = 1.0; }
	else if (m == M_SHELL) {
		// old lacquer, rubbed thin in places
		float a = atan2(p.z, p.x - P.drum.x);
		float wear = smoothstep(0.55, 0.85, noise(float2(a * 9.0, p.y * 6.0)));
		o.albedo = lin(mix(float3(0.44, 0.09, 0.09), float3(0.36, 0.16, 0.12), wear)) * (0.9 + 0.1 * noise(float2(a * 40.0, p.y * 30.0)));
		o.rough = mix(0.18, 0.45, wear); o.spec = 0.05;
	} else if (m == M_HEAD) {
		// calfskin: mottled, a little translucent, darker in the middle where the balls land
		float r = length(p.xz - float2(P.drum.x, 0.0)) / P.drum.z;
		float mottle = noise(p.xz * 7.0) * 0.6 + noise(p.xz * 23.0) * 0.4;
		o.albedo = lin(float3(0.8, 0.75, 0.64)) * (0.82 + 0.22 * mottle);
		o.albedo *= 1.0 - 0.1 * smoothstep(0.86, 0.92, r) - 0.12 * exp(-r * r * 30.0);
		o.rough = 0.75; o.wrap = 0.4;
	} else if (m == M_WOOD) {
		// old mahogany: the grain, worn paler and duller on the edges, scratches
		float3 b = abs(p - float3(0.0, 0.58, -1.36)) - float3(1.32, 0.58, 0.5);
		float edge = -max(max(min(b.x, b.y), min(b.y, b.z)), min(b.x, b.z));
		float wear = smoothstep(0.03, 0.0, edge) * (0.5 + 0.5 * noise(p.xy * 30.0 + p.z * 20.0));
		float v = p.y + p.z + 0.05 * sin(p.x * 2.0);
		float g = noise(float2(p.x * 1.2, v * 11.0 + noise(float2(p.x, v) * 2.0) * 2.0));
		g = 0.7 * g + 0.3 * noise(float2(p.x * 3.0, v * 24.0)) * (0.7 + 0.3 * noise(p.xz * 4.0));
		float scratch = smoothstep(0.97, 1.0, noise(float2(p.x * 3.0 - v * 2.0, (v + p.x * 0.3) * 160.0)));
		o.albedo = lin(mix(float3(0.17, 0.07, 0.04), float3(0.3, 0.13, 0.07), g)) * (n.y > 0.5 ? 0.7 : 1.0);
		o.albedo = mix(o.albedo, lin(float3(0.36, 0.22, 0.14)), wear * 0.7 + scratch * 0.4);
		o.rough = mix(0.3, 0.7, max(wear, scratch)); o.spec = 0.04;
	}
	return o;
}

// blur: out of focus, the boards'' texture fades
float3 floorAlbedo(float3 p, float blur) {
	float plank = floor(p.x / 0.24);
	float along = p.z + hash(float2(plank, 3.0)) * 7.0;
	float seam = floor(along / 2.4);
	float h = hash(float2(plank, seam));
	float g = noise(float2(p.x * 16.0 + noise(float2(p.x, along) * 3.0), along * 1.1)) * 0.7 + noise(float2(p.x * 36.0, along * 2.6)) * 0.3;
	float3 c = lin(mix(float3(0.27, 0.15, 0.08), float3(0.34, 0.19, 0.1), mix(h, 0.5, blur * 0.6))) * (0.85 + 0.25 * mix(g, 0.5, blur));
	float lines = min(smoothstep(0.0, 0.01, abs(fract(p.x / 0.24) - 0.5) * 0.24 - 0.112), smoothstep(0.0, 0.015, abs(fract(along / 2.4) - 0.5) * 2.4 - 1.185));
	return c * (0.6 + 0.4 * mix(lines, 0.85, blur));
}

// the curtain: velvet hanging in folds, rounded crests with a line of sheen, deep narrow valleys; the pile darkens what faces you
float3 curtainColor(float3 p, float3 rd, float shadow) {
	float x = p.x;
	float w = x * 2.9 + 0.7 * sin(x * 1.3) + p.y * 0.12 * sin(x * 1.7);
	float sw = sin(w), cw = cos(w);
	float crest = sqrt(abs(sw));
	float df = 0.5 * sign(sw) * cw / max(crest, 0.05) * (2.9 + 0.91 * cos(x * 1.3));
	float3 n = normalize(float3(-0.22 * df, 0.0, 1.0));
	float3 l = normalize(keyPos - p);
	float facing = max(dot(n, -rd), 0.0);
	float diff = 0.2 + 0.8 * max(dot(n, l), 0.0);
	float valley = smoothstep(0.0, 0.75, crest);
	float pile = 0.55 + 0.45 * pow(1.0 - facing, 1.5);
	float line = pow(max(dot(normalize(l - rd), n), 0.0), 18.0) * smoothstep(0.75, 1.0, crest);
	float3 base = lin(float3(0.38, 0.04, 0.055));
	float pool = spot(p) * shadow;
	float3 c = base * keyColor * pool * diff * valley * pile * 0.8 + base * 0.012 * valley;
	c += lin(float3(0.9, 0.42, 0.42)) * (line * 0.35 + pow(1.0 - facing, 3.0) * 0.15 * valley) * pool * keyColor * 0.4;
	float hem = smoothstep(0.13, 0.12, p.y);
	c = mix(c, lin(float3(0.7, 0.52, 0.22)) * (0.3 + 0.7 * valley) * keyColor * pool * 0.3 * (0.85 + 0.15 * sin(x * 140.0)), hem);
	return c * smoothstep(5.5, 1.2, p.y);
}

// the light bounced off the floor, the curtain and the rest of the stage
float3 bounce(float3 n) {
	return float3(0.08, 0.048, 0.028) * max(-n.y, 0.0) + float3(0.045, 0.011, 0.013) * max(-n.z, 0.0) + float3(0.02, 0.019, 0.019) * (0.6 + 0.4 * n.y);
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
	if (m.aniso > 0.0) {
		// stretched along the axis, narrow round it
		float3 t = normalize(cross(float3(0.0, 1.0, 0.0), n) + 1e-4);
		float3 b = cross(n, t);
		float ht = dot(h, t) / (0.06 + r2 * 0.3), hb = dot(h, b) / (0.3 + r2), hn = max(dot(h, n), 0.05);
		specK = mix(specK, exp(-(ht * ht + hb * hb) / (hn * hn)) * 2.0, m.aniso * smoothstep(0.95, 0.7, abs(n.y)));
	}
	float3 diffuse = m.albedo * (1.0 - m.metal);
	float wrapped = max((dot(n, l) + m.wrap) / (1.0 + m.wrap), 0.0);
	float key = shadow * spot(p);
	float3 c = (diffuse * wrapped + fres * specK * nl) * keyColor * key;
	c += diffuse * m.wrap * 0.12 * float3(1.0, 0.45, 0.3) * keyColor * key * smoothstep(0.2, -0.2, dot(n, l));
	c += diffuse * fillColor * max(dot(n, fillDir), 0.0) * ao;
	c += fres * pow(max(dot(n, normalize(fillDir - rd)), 0.0), shininess * 0.5) * fillColor * ao;
	c += (diffuse + fres * pow(max(dot(n, normalize(footDir - rd)), 0.0), shininess)) * footColor * max(dot(n, footDir), 0.0) * ao;
	float rim = max(dot(n, rimDir), 0.0) * pow(1.0 - nv, 2.5);
	c += (diffuse + f0) * rimColor * rim * ao;
	// fuzz: cloth and felt catch the light where they turn away
	c += m.sheen * sqrt(m.albedo) * pow(1.0 - nv, 3.0) * (keyColor * key * wrapped * 0.5 + bounce(n) * 2.0) ;
	c += (diffuse * bounce(n) * 2.2 + f0 * 0.04) * ao;
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
		return (sharp ? floorAlbedo(p, 1.0) : lin(float3(0.3, 0.17, 0.09))) * keyColor * 0.3 * spot(p);
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
	float r = s.sizes.x * 0.01;
	P.bowl = s.sizes.y * 0.01;
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
	// each arm reaches under its bowl, the hand turned with it: two bones, the elbow down and out
	for (int i = 0; i < 2; i++) {
		float side = i == 0 ? -1.0 : 1.0;
		float3 cup = world(i == 0 ? s.hands.xy : s.hands.zw, s);
		float t = i == 0 ? s.handPose.x : s.handPose.y;
		P.tilt[i] = float2(cos(t), sin(t));
		float3 sh = float3(side * 0.5, 2.33, figureZ);
		float3 w = cup + float3(-sin(t), -cos(t), 0.0) * (P.bowl + 0.075) + float3(0.0, 0.0, -0.05);
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
	float2 edge;
	float2 h = marchEdge(ro, rd, min(tMax, tp), P, 96, edge);
	float pixel = 2.0 * tanV / in.size.y;
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
		col = lightSurface(p, m.normal, rd, m, softShadow(p + n * 0.003, normalize(keyPos - p), P), occlusion(p, n, P));
		if (m.metal > 0.5 || h.y == M_SHELL) {
			float3 f0 = mix(float3(m.spec), m.albedo, m.metal);
			float3 fres = f0 + (1.0 - f0) * pow(1.0 - max(dot(n, -rd), 0.0), 5.0);
			col += reflected(p + n * 0.02, reflect(rd, n), P, s, -1, false) * fres * (1.0 - m.rough) * (1.0 - m.rough);
		}
	} else if (tFloor < tCurtain) {
		// the stage floor, lacquered boards
		float3 p = ro + rd * tFloor;
		float ao = floorOcclusion(p, P);
		Surface m = { floorAlbedo(p, clamp(abs(tFloor - 8.4) * 0.12, 0.0, 1.0)), 0.35, 0.04, float3(0.0), 0.0 };
		col = lightSurface(p, float3(0, 1, 0), rd, m, softShadow(p + float3(0, 0.002, 0), normalize(keyPos - p), P), ao);
		float fres = 0.04 + 0.96 * pow(1.0 - max(-rd.y, 0.0), 5.0);
		col += reflected(p + float3(0, 0.002, 0), reflect(rd, float3(0, 1, 0)), P, s, -1, false) * mix(0.05, 0.45, fres) * ao;
	} else {
		float3 p = ro + rd * tCurtain;
		col = curtainColor(p, rd, spot(p) < 0.1 ? 1.0 : softShadow(p + float3(0, 0, 0.01), normalize(keyPos - p), P));
	}
	if (h.y <= 0.0 && cover < 1.0 && edge.y < 1.5 * pixel) {
		// a silhouette passing through this pixel: blend it in by how close the ray came
		float3 p = ro + rd * edge.x;
		float3 n = normalAt(p, P);
		Surface m = materialAt(map(p, P).y, p, n, P);
		float3 c = lightSurface(p, m.normal, rd, m, softShadow(p + n * 0.003, normalize(keyPos - p), P), 0.8);
		col = mix(col, c, clamp((1.5 * pixel - edge.y) / (2.0 * pixel), 0.0, 0.5));
	}
	col = mix(col, ball, cover);
	// haze in the spotlight, thicker up in the beam; jittered samples along the view ray
	uint2 q = uint2(in.pos.xy);
	uint k = q.x * 1973u + q.y * 9277u + uint(s.stage.z) * 26699u + 1u;
	k = (k ^ (k >> 15)) * 2246822519u;
	k ^= k >> 13;
	float j1 = float(k & 0xFFFFu) / 65535.0, j2 = float(k >> 16) / 65535.0;
	float tHit = min(cover > 0.0 ? tb : h.x, min(tFloor, tCurtain));
	float haze = 0.0;
	for (int i = 0; i < 6; i++) {
		float3 hp = ro + rd * (tHit * (float(i) + j1) / 6.0);
		haze += spot(hp) * (0.6 + 0.4 * smoothstep(0.0, 4.5, hp.y));
	}
	col += keyColor * float3(1.0, 0.93, 0.85) * 0.0018 * haze * tHit / 6.0;
	// the glow around the cigar''s tip
	float tt = max(dot(cigarB - ro, rd), 0.0);
	float glow = length(ro + rd * tt - cigarB);
	col += float3(1.0, 0.35, 0.08) * 0.08 * flickerAt(P.time) * exp(-glow * 35.0);

	// the lens: falloff to the corners; film: a fine grain, strongest in the mid-tones; then a dither of one 8-bit step
	float2 v = (in.uv - 0.5) * float2(aspect, 1.0);
	float falloff = 1.0 / (1.0 + 0.55 * dot(v, v));
	col *= falloff * falloff;
	col = pow(aces(col * 0.95), float3(1.0 / 2.2));
	float grain = (j1 + j2 - 1.0);
	col += grain * (0.018 * col * (1.0 - col) * 4.0 * 0.5 + 1.0 / 255.0);
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
