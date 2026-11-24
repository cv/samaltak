!GlslCudaWriter class methodsFor: 'header'!
header
	"GLSL's types and built-in functions in CUDA C++, namespace gl: what the CUDA I write uses."
	^'// GLSL''s types and built-in functions in CUDA C++ (Graphics-Shaders: GlslCudaWriter''s header).
namespace gl {
#define GL_D __device__ __forceinline__
typedef unsigned int uint;
template<class T, int N> struct vec_;
template<class T> struct alignas(2 * sizeof(T)) vec_<T, 2> { T x, y;
	GL_D T& operator[](int i) { return i == 0 ? x : y; }
	GL_D T operator[](int i) const { return i == 0 ? x : y; } };
template<class T> struct vec_<T, 3> { T x, y, z;
	GL_D T& operator[](int i) { return i == 0 ? x : i == 1 ? y : z; }
	GL_D T operator[](int i) const { return i == 0 ? x : i == 1 ? y : z; } };
template<class T> struct alignas(4 * sizeof(T)) vec_<T, 4> { T x, y, z, w;
	GL_D T& operator[](int i) { return i == 0 ? x : i == 1 ? y : i == 2 ? z : w; }
	GL_D T operator[](int i) const { return i == 0 ? x : i == 1 ? y : i == 2 ? z : w; } };
typedef vec_<float, 2> vec2; typedef vec_<float, 3> vec3; typedef vec_<float, 4> vec4;
typedef vec_<int, 2> ivec2; typedef vec_<int, 3> ivec3; typedef vec_<int, 4> ivec4;
typedef vec_<uint, 2> uvec2; typedef vec_<uint, 3> uvec3; typedef vec_<uint, 4> uvec4;
typedef vec_<bool, 2> bvec2; typedef vec_<bool, 3> bvec3; typedef vec_<bool, 4> bvec4;
template<int C, int R> struct mat_ { vec_<float, R> c[C];
	GL_D vec_<float, R>& operator[](int i) { return c[i]; }
	GL_D const vec_<float, R>& operator[](int i) const { return c[i]; } };
typedef mat_<2, 2> mat2; typedef mat_<3, 3> mat3; typedef mat_<4, 4> mat4;
typedef mat_<2, 3> mat2x3; typedef mat_<2, 4> mat2x4; typedef mat_<3, 2> mat3x2; typedef mat_<3, 4> mat3x4; typedef mat_<4, 2> mat4x2; typedef mat_<4, 3> mat4x3;
template<class T, int N> struct arr { T a[N];
	GL_D T& operator[](int i) { return a[i]; }
	GL_D const T& operator[](int i) const { return a[i]; } };

// components, constructors, swizzles
template<class T> struct traits { typedef T E; enum { n = 1 }; };
template<class T, int N> struct traits<vec_<T, N> > { typedef T E; enum { n = N }; };
template<int I, class T, int N> GL_D T get(const vec_<T, N>& v) {
	if constexpr (I == 0) return v.x; else if constexpr (I == 1) return v.y; else if constexpr (I == 2) return v.z; else return v.w; }
template<int I, class T, int N> GL_D void set(vec_<T, N>& v, T x) {
	if constexpr (I == 0) v.x = x; else if constexpr (I == 1) v.y = x; else if constexpr (I == 2) v.z = x; else v.w = x; }
template<class E, class S> GL_D void put(E* c, int& i, int n, S s) { if (i < n) c[i++] = (E)s; }
template<class E, class T, int N> GL_D void put(E* c, int& i, int n, const vec_<T, N>& v) { for (int k = 0; k < N; k++) if (i < n) c[i++] = (E)v[k]; }
template<class E, int C, int R> GL_D void put(E* c, int& i, int n, const mat_<C, R>& m) { for (int k = 0; k < C; k++) put(c, i, n, m.c[k]); }
template<class V, class... A> GL_D V mk(A... a) {
	typedef typename traits<V>::E E; E c[traits<V>::n]; int i = 0; (put(c, i, (int)traits<V>::n, a), ...);
	V r; for (int k = 0; k < traits<V>::n; k++) r[k] = c[k]; return r; }
template<class V, class S> GL_D V splat(S s) { V r; for (int k = 0; k < traits<V>::n; k++) r[k] = (typename traits<V>::E)s; return r; }
template<class M> struct mtraits;
template<int C, int R> struct mtraits<mat_<C, R> > { enum { c = C, r = R }; };
template<class M, class... A> GL_D M mkm(A... a) {
	enum { C = mtraits<M>::c, R = mtraits<M>::r }; float f[C * R]; int i = 0; (put(f, i, C * R, a), ...);
	M m; for (int k = 0; k < C; k++) for (int j = 0; j < R; j++) m.c[k][j] = f[k * R + j]; return m; }
template<class M> GL_D M diag(float s) {
	enum { C = mtraits<M>::c, R = mtraits<M>::r }; M m; for (int k = 0; k < C; k++) for (int j = 0; j < R; j++) m.c[k][j] = k == j ? s : 0.0f; return m; }
template<class M, int C2, int R2> GL_D M mconv(const mat_<C2, R2>& a) {
	enum { C = mtraits<M>::c, R = mtraits<M>::r }; M m;
	for (int k = 0; k < C; k++) for (int j = 0; j < R; j++) m.c[k][j] = k < C2 && j < R2 ? a.c[k][j] : (k == j ? 1.0f : 0.0f); return m; }
template<int... I, class T, int N> GL_D vec_<T, sizeof...(I)> sw(const vec_<T, N>& v) { return vec_<T, sizeof...(I)>{get<I>(v)...}; }
template<class T, int N, int... I> struct swref { vec_<T, N>& v;
	typedef vec_<T, sizeof...(I)> V;
	GL_D operator V() const { return V{get<I>(v)...}; }
	GL_D swref& operator=(V x) { int k = 0; (set<I>(v, x[k++]), ...); return *this; }
	GL_D swref& operator+=(V x) { return *this = V(*this) + x; } GL_D swref& operator-=(V x) { return *this = V(*this) - x; }
	GL_D swref& operator*=(V x) { return *this = V(*this) * x; } GL_D swref& operator/=(V x) { return *this = V(*this) / x; }
	GL_D swref& operator+=(T x) { return *this = V(*this) + x; } GL_D swref& operator-=(T x) { return *this = V(*this) - x; }
	GL_D swref& operator*=(T x) { return *this = V(*this) * x; } GL_D swref& operator/=(T x) { return *this = V(*this) / x; }
	template<int C> GL_D swref& operator*=(const mat_<C, C>& m) { return *this = V(*this) * m; } };
template<int... I, class T, int N> GL_D swref<T, N, I...> swz(vec_<T, N>& v) { return swref<T, N, I...>{v}; }

// operators
#define GL_OP(op) \
template<class T, int N> GL_D vec_<T, N> operator op(vec_<T, N> a, vec_<T, N> b) { vec_<T, N> r; for (int i = 0; i < N; i++) r[i] = a[i] op b[i]; return r; } \
template<class T, int N> GL_D vec_<T, N> operator op(vec_<T, N> a, T b) { vec_<T, N> r; for (int i = 0; i < N; i++) r[i] = a[i] op b; return r; } \
template<class T, int N> GL_D vec_<T, N> operator op(T a, vec_<T, N> b) { vec_<T, N> r; for (int i = 0; i < N; i++) r[i] = a op b[i]; return r; } \
template<class T, int N> GL_D vec_<T, N>& operator op##=(vec_<T, N>& a, vec_<T, N> b) { for (int i = 0; i < N; i++) a[i] = a[i] op b[i]; return a; } \
template<class T, int N> GL_D vec_<T, N>& operator op##=(vec_<T, N>& a, T b) { for (int i = 0; i < N; i++) a[i] = a[i] op b; return a; }
GL_OP(+) GL_OP(-) GL_OP(*) GL_OP(/) GL_OP(%) GL_OP(&) GL_OP(|) GL_OP(^) GL_OP(<<) GL_OP(>>)
#undef GL_OP
template<class T, int N> GL_D vec_<T, N> operator-(vec_<T, N> a) { vec_<T, N> r; for (int i = 0; i < N; i++) r[i] = -a[i]; return r; }
template<class T, int N> GL_D vec_<T, N> operator+(vec_<T, N> a) { return a; }
template<class T, int N> GL_D vec_<T, N> operator~(vec_<T, N> a) { vec_<T, N> r; for (int i = 0; i < N; i++) r[i] = ~a[i]; return r; }
template<class T, int N> GL_D vec_<T, N>& operator++(vec_<T, N>& a) { for (int i = 0; i < N; i++) ++a[i]; return a; }
template<class T, int N> GL_D vec_<T, N>& operator--(vec_<T, N>& a) { for (int i = 0; i < N; i++) --a[i]; return a; }
template<class T, int N> GL_D vec_<T, N> operator++(vec_<T, N>& a, int) { vec_<T, N> r = a; ++a; return r; }
template<class T, int N> GL_D vec_<T, N> operator--(vec_<T, N>& a, int) { vec_<T, N> r = a; --a; return r; }
template<class T, int N> GL_D bool operator==(vec_<T, N> a, vec_<T, N> b) { bool r = true; for (int i = 0; i < N; i++) r = r && a[i] == b[i]; return r; }
template<class T, int N> GL_D bool operator!!=(vec_<T, N> a, vec_<T, N> b) { return !!(a == b); }
#define GL_MOP(op) \
template<int C, int R> GL_D mat_<C, R> operator op(const mat_<C, R>& a, const mat_<C, R>& b) { mat_<C, R> r; for (int i = 0; i < C; i++) r.c[i] = a.c[i] op b.c[i]; return r; } \
template<int C, int R> GL_D mat_<C, R> operator op(const mat_<C, R>& a, float b) { mat_<C, R> r; for (int i = 0; i < C; i++) r.c[i] = a.c[i] op b; return r; } \
template<int C, int R> GL_D mat_<C, R> operator op(float a, const mat_<C, R>& b) { mat_<C, R> r; for (int i = 0; i < C; i++) r.c[i] = a op b.c[i]; return r; }
GL_MOP(+) GL_MOP(-) GL_MOP(/)
#undef GL_MOP
template<int C, int R> GL_D mat_<C, R> operator*(const mat_<C, R>& a, float b) { mat_<C, R> r; for (int i = 0; i < C; i++) r.c[i] = a.c[i] * b; return r; }
template<int C, int R> GL_D mat_<C, R> operator*(float a, const mat_<C, R>& b) { mat_<C, R> r; for (int i = 0; i < C; i++) r.c[i] = a * b.c[i]; return r; }
template<int C, int R> GL_D vec_<float, R> operator*(const mat_<C, R>& m, vec_<float, C> v) { vec_<float, R> r = m.c[0] * v[0]; for (int i = 1; i < C; i++) r = r + m.c[i] * v[i]; return r; }
template<int C, int R> GL_D vec_<float, C> operator*(vec_<float, R> v, const mat_<C, R>& m) { vec_<float, C> r; for (int i = 0; i < C; i++) { float s = 0.0f; for (int j = 0; j < R; j++) s += v[j] * m.c[i][j]; r[i] = s; } return r; }
template<int K, int R, int C> GL_D mat_<C, R> operator*(const mat_<K, R>& a, const mat_<C, K>& b) { mat_<C, R> r; for (int i = 0; i < C; i++) r.c[i] = a * b.c[i]; return r; }
template<int C, int R> GL_D mat_<C, R> operator-(const mat_<C, R>& a) { mat_<C, R> r; for (int i = 0; i < C; i++) r.c[i] = -a.c[i]; return r; }
template<int C, int R> GL_D mat_<C, R>& operator+=(mat_<C, R>& a, const mat_<C, R>& b) { return a = a + b; }
template<int C, int R> GL_D mat_<C, R>& operator-=(mat_<C, R>& a, const mat_<C, R>& b) { return a = a - b; }
template<int C> GL_D mat_<C, C>& operator*=(mat_<C, C>& a, const mat_<C, C>& b) { return a = a * b; }
template<int C, int R> GL_D mat_<C, R>& operator*=(mat_<C, R>& a, float b) { return a = a * b; }
template<int C, int R> GL_D mat_<C, R>& operator/=(mat_<C, R>& a, float b) { return a = a / b; }
template<int C, int R> GL_D mat_<C, R>& operator+=(mat_<C, R>& a, float b) { return a = a + b; }
template<int C, int R> GL_D mat_<C, R>& operator-=(mat_<C, R>& a, float b) { return a = a - b; }
template<int C> GL_D vec_<float, C>& operator*=(vec_<float, C>& v, const mat_<C, C>& m) { return v = v * m; }
template<int C, int R> GL_D bool operator==(const mat_<C, R>& a, const mat_<C, R>& b) { bool r = true; for (int i = 0; i < C; i++) r = r && a.c[i] == b.c[i]; return r; }
template<int C, int R> GL_D bool operator!!=(const mat_<C, R>& a, const mat_<C, R>& b) { return !!(a == b); }

// built-in functions: component-wise ones on scalars, then on vectors
#define GL_V1(name) template<class T, int N> GL_D auto name(vec_<T, N> a) { vec_<decltype(name(a.x)), N> r; for (int i = 0; i < N; i++) r[i] = name(a[i]); return r; }
#define GL_V2(name) template<class T, int N> GL_D vec_<T, N> name(vec_<T, N> a, vec_<T, N> b) { vec_<T, N> r; for (int i = 0; i < N; i++) r[i] = name(a[i], b[i]); return r; } \
	template<class T, int N> GL_D vec_<T, N> name(vec_<T, N> a, T b) { vec_<T, N> r; for (int i = 0; i < N; i++) r[i] = name(a[i], b); return r; }
#define GL_F1(name, e) GL_D float name(float x) { return e; } GL_V1(name)
GL_F1(radians, x * 0.01745329251994329577f) GL_F1(degrees, x * 57.29577951308232088f)
GL_F1(sin, ::sinf(x)) GL_F1(cos, ::cosf(x)) GL_F1(tan, ::tanf(x)) GL_F1(asin, ::asinf(x)) GL_F1(acos, ::acosf(x)) GL_F1(atan, ::atanf(x))
GL_F1(sinh, ::sinhf(x)) GL_F1(cosh, ::coshf(x)) GL_F1(tanh, ::tanhf(x)) GL_F1(asinh, ::asinhf(x)) GL_F1(acosh, ::acoshf(x)) GL_F1(atanh, ::atanhf(x))
GL_F1(exp, ::expf(x)) GL_F1(log, ::logf(x)) GL_F1(exp2, ::exp2f(x)) GL_F1(log2, ::log2f(x)) GL_F1(sqrt, ::sqrtf(x)) GL_F1(inversesqrt, ::rsqrtf(x))
GL_F1(floor, ::floorf(x)) GL_F1(ceil, ::ceilf(x)) GL_F1(trunc, ::truncf(x)) GL_F1(round, ::roundf(x)) GL_F1(roundEven, ::rintf(x)) GL_F1(fract, x - ::floorf(x))
GL_D float abs(float x) { return ::fabsf(x); } GL_D int abs(int x) { return x < 0 ? -x : x; } GL_V1(abs)
GL_D float sign(float x) { return x > 0.0f ? 1.0f : x < 0.0f ? -1.0f : 0.0f; } GL_D int sign(int x) { return x > 0 ? 1 : x < 0 ? -1 : 0; } GL_V1(sign)
GL_D bool isnan(float x) { return ::isnan(x); } GL_D bool isinf(float x) { return ::isinf(x); } GL_V1(isnan) GL_V1(isinf)
GL_D int floatBitsToInt(float x) { return __float_as_int(x); } GL_D uint floatBitsToUint(float x) { return __float_as_uint(x); }
GL_D float intBitsToFloat(int x) { return __int_as_float(x); } GL_D float uintBitsToFloat(uint x) { return __uint_as_float(x); }
GL_V1(floatBitsToInt) GL_V1(floatBitsToUint) GL_V1(intBitsToFloat) GL_V1(uintBitsToFloat)
GL_D float atan(float y, float x) { return ::atan2f(y, x); } GL_D float pow(float x, float y) { return ::powf(x, y); }
GL_D float mod(float x, float y) { return x - y * ::floorf(x / y); }
GL_D float min(float a, float b) { return ::fminf(a, b); } GL_D int min(int a, int b) { return a < b ? a : b; } GL_D uint min(uint a, uint b) { return a < b ? a : b; }
GL_D float max(float a, float b) { return ::fmaxf(a, b); } GL_D int max(int a, int b) { return a > b ? a : b; } GL_D uint max(uint a, uint b) { return a > b ? a : b; }
GL_D float step(float e, float x) { return x < e ? 0.0f : 1.0f; }
GL_V2(atan) GL_V2(pow) GL_V2(mod) GL_V2(min) GL_V2(max)
template<int N> GL_D vec_<float, N> step(vec_<float, N> e, vec_<float, N> x) { vec_<float, N> r; for (int i = 0; i < N; i++) r[i] = step(e[i], x[i]); return r; }
template<int N> GL_D vec_<float, N> step(float e, vec_<float, N> x) { vec_<float, N> r; for (int i = 0; i < N; i++) r[i] = step(e, x[i]); return r; }
template<class T> GL_D T clamp(T x, T a, T b) { return min(max(x, a), b); }
template<class T, int N> GL_D vec_<T, N> clamp(vec_<T, N> x, T a, T b) { return min(max(x, a), b); }
GL_D float mix(float x, float y, float a) { return x * (1.0f - a) + y * a; }
template<int N> GL_D vec_<float, N> mix(vec_<float, N> x, vec_<float, N> y, vec_<float, N> a) { return x * (1.0f - a) + y * a; }
template<int N> GL_D vec_<float, N> mix(vec_<float, N> x, vec_<float, N> y, float a) { return x * (1.0f - a) + y * a; }
template<class T> GL_D T mix(T x, T y, bool a) { return a ? y : x; }
template<class T, int N> GL_D vec_<T, N> mix(vec_<T, N> x, vec_<T, N> y, vec_<bool, N> a) { vec_<T, N> r; for (int i = 0; i < N; i++) r[i] = a[i] ? y[i] : x[i]; return r; }
GL_D float smoothstep(float e0, float e1, float x) { float t = clamp((x - e0) / (e1 - e0), 0.0f, 1.0f); return t * t * (3.0f - 2.0f * t); }
template<int N> GL_D vec_<float, N> smoothstep(vec_<float, N> e0, vec_<float, N> e1, vec_<float, N> x) { vec_<float, N> r; for (int i = 0; i < N; i++) r[i] = smoothstep(e0[i], e1[i], x[i]); return r; }
template<int N> GL_D vec_<float, N> smoothstep(float e0, float e1, vec_<float, N> x) { vec_<float, N> r; for (int i = 0; i < N; i++) r[i] = smoothstep(e0, e1, x[i]); return r; }
GL_D float fma(float a, float b, float c) { return ::fmaf(a, b, c); }
template<int N> GL_D vec_<float, N> fma(vec_<float, N> a, vec_<float, N> b, vec_<float, N> c) { vec_<float, N> r; for (int i = 0; i < N; i++) r[i] = ::fmaf(a[i], b[i], c[i]); return r; }
GL_D float modf(float x, float& i) { i = ::truncf(x); return x - i; }
template<int N> GL_D vec_<float, N> modf(vec_<float, N> x, vec_<float, N>& i) { i = trunc(x); return x - i; }

// geometry
GL_D float dot(float a, float b) { return a * b; }
template<int N> GL_D float dot(vec_<float, N> a, vec_<float, N> b) { float s = a[0] * b[0]; for (int i = 1; i < N; i++) s += a[i] * b[i]; return s; }
template<class V> GL_D float length(V v) { return ::sqrtf(dot(v, v)); }
template<class V> GL_D float distance(V a, V b) { return length(a - b); }
GL_D float normalize(float x) { return sign(x); }
template<int N> GL_D vec_<float, N> normalize(vec_<float, N> v) { return v * ::rsqrtf(dot(v, v)); }
GL_D vec3 cross(vec3 a, vec3 b) { return vec3{a.y * b.z - b.y * a.z, a.z * b.x - b.z * a.x, a.x * b.y - b.x * a.y}; }
template<class V> GL_D V faceforward(V n, V i, V nref) { return dot(nref, i) < 0.0f ? n : -n; }
template<class V> GL_D V reflect(V i, V n) { return i - 2.0f * dot(n, i) * n; }
template<class V> GL_D V refract(V i, V n, float eta) {
	float d = dot(n, i), k = 1.0f - eta * eta * (1.0f - d * d);
	return k < 0.0f ? i * 0.0f : eta * i - (eta * d + ::sqrtf(k)) * n; }

// matrices
template<int C, int R> GL_D mat_<C, R> matrixCompMult(const mat_<C, R>& a, const mat_<C, R>& b) { mat_<C, R> r; for (int i = 0; i < C; i++) r.c[i] = a.c[i] * b.c[i]; return r; }
template<int C, int R> GL_D mat_<R, C> transpose(const mat_<C, R>& m) { mat_<R, C> r; for (int i = 0; i < C; i++) for (int j = 0; j < R; j++) r.c[j][i] = m.c[i][j]; return r; }
template<int C, int R> GL_D mat_<C, R> outerProduct(vec_<float, R> c, vec_<float, C> r) { mat_<C, R> m; for (int i = 0; i < C; i++) m.c[i] = c * r[i]; return m; }
GL_D float determinant(const mat2& m) { return m.c[0].x * m.c[1].y - m.c[1].x * m.c[0].y; }
GL_D float determinant(const mat3& m) { return dot(m.c[0], cross(m.c[1], m.c[2])); }
GL_D float determinant(const mat4& m) {
	float r = 0.0f;
	for (int i = 0; i < 4; i++) { mat3 s; for (int k = 0, c = 0; k < 4; k++) if (k !!= i) { s.c[c++] = vec3{m.c[k].y, m.c[k].z, m.c[k].w}; } r += (i & 1 ? -1.0f : 1.0f) * m.c[i].x * determinant(s); }
	return r; }
GL_D mat2 inverse(const mat2& m) { float d = 1.0f / determinant(m); return mat2{{vec2{m.c[1].y * d, -m.c[0].y * d}, vec2{-m.c[1].x * d, m.c[0].x * d}}}; }
GL_D mat3 inverse(const mat3& m) { vec3 a = cross(m.c[1], m.c[2]), b = cross(m.c[2], m.c[0]), c = cross(m.c[0], m.c[1]); float d = 1.0f / dot(m.c[0], a); return transpose(mat3{{a * d, b * d, c * d}}); }
GL_D mat4 inverse(const mat4& m) {
	float a[16], inv[16];
	for (int i = 0; i < 4; i++) for (int j = 0; j < 4; j++) a[i * 4 + j] = m.c[i][j];
	for (int i = 0; i < 16; i++) { int r = i / 4, c = i % 4; float s[9]; int n = 0;
		for (int x = 0; x < 4; x++) if (x !!= c) for (int y = 0; y < 4; y++) if (y !!= r) s[n++] = a[x * 4 + y];
		float d = s[0] * (s[4] * s[8] - s[5] * s[7]) - s[3] * (s[1] * s[8] - s[2] * s[7]) + s[6] * (s[1] * s[5] - s[2] * s[4]);
		inv[r * 4 + c] = ((r + c) & 1 ? -d : d); }
	float det = 0.0f; for (int k = 0; k < 4; k++) det += a[k] * inv[k * 4];
	mat4 o; for (int i = 0; i < 4; i++) for (int j = 0; j < 4; j++) o.c[i][j] = inv[i * 4 + j] / det; return o; }

// relational
#define GL_REL(name, op) template<class T, int N> GL_D vec_<bool, N> name(vec_<T, N> a, vec_<T, N> b) { vec_<bool, N> r; for (int i = 0; i < N; i++) r[i] = a[i] op b[i]; return r; }
GL_REL(lessThan, <) GL_REL(lessThanEqual, <=) GL_REL(greaterThan, >) GL_REL(greaterThanEqual, >=) GL_REL(equal, ==) GL_REL(notEqual, !!=)
#undef GL_REL
template<int N> GL_D bool any(vec_<bool, N> a) { bool r = false; for (int i = 0; i < N; i++) r = r || a[i]; return r; }
template<int N> GL_D bool all(vec_<bool, N> a) { bool r = true; for (int i = 0; i < N; i++) r = r && a[i]; return r; }
template<int N> GL_D vec_<bool, N> not_(vec_<bool, N> a) { vec_<bool, N> r; for (int i = 0; i < N; i++) r[i] = !!a[i]; return r; }

// derivatives: a warp is 8 x 4 pixels, so x + 1 is lane ^ 1, y + 1 lane ^ 8
GL_D float dFdx(float v) { float o = __shfl_xor_sync(__activemask(), v, 1); return (threadIdx.x & 1) ? v - o : o - v; }
GL_D float dFdy(float v) { float o = __shfl_xor_sync(__activemask(), v, 8); return (threadIdx.x & 8) ? v - o : o - v; }
GL_D float fwidth(float v) { return ::fabsf(dFdx(v)) + ::fabsf(dFdy(v)); }
GL_V1(dFdx) GL_V1(dFdy) GL_V1(fwidth)
GL_D float dFdxFine(float v) { return dFdx(v); } GL_D float dFdyFine(float v) { return dFdy(v); } GL_D float dFdxCoarse(float v) { return dFdx(v); } GL_D float dFdyCoarse(float v) { return dFdy(v); }
GL_V1(dFdxFine) GL_V1(dFdyFine) GL_V1(dFdxCoarse) GL_V1(dFdyCoarse)

// uniforms (std140: bools are 32 bits, a matrix''s columns 16 bytes apart)
template<class T> GL_D T uload(const char* b, int o) { return *(const T*)(b + o); }
template<> GL_D bool uload<bool>(const char* b, int o) { return *(const uint*)(b + o) !!= 0u; }
template<class M> GL_D M uloadm(const char* b, int o) { enum { C = mtraits<M>::c, R = mtraits<M>::r }; M m; for (int i = 0; i < C; i++) for (int j = 0; j < R; j++) m.c[i][j] = *(const float*)(b + o + i * 16 + j * 4); return m; }
template<class V> GL_D V uloadb(const char* b, int o) { V v; for (int i = 0; i < traits<V>::n; i++) v[i] = *(const uint*)(b + o + i * 4) !!= 0u; return v; }

// the pixel''s output: premultiplied RGBA as RGBA8, rounded
GL_D uint rgba8(vec4 c) {
	return (uint)__float2int_rn(__saturatef(c.x) * 255.0f) | (uint)__float2int_rn(__saturatef(c.y) * 255.0f) << 8
		| (uint)__float2int_rn(__saturatef(c.z) * 255.0f) << 16 | (uint)__float2int_rn(__saturatef(c.w) * 255.0f) << 24; }
#undef GL_V1
#undef GL_V2
#undef GL_F1
}
'
! !
