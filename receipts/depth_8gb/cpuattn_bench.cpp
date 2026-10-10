// P97: decode attention over the host tail on the CPU, Bonsai 2 27B layout, AVX2.
// One layer: R cells; each cell holds K and V rows of 4 KV heads x 256 dims in q4_0 (18-byte blocks of 32), 1152 B.
// Queries: nb tokens x 24 heads (GQA 6: q head j reads KV head j/6). Output per thread: (max, sum, unnormalized V) per
// query head, merged at the end (the same partial form the GPU merge would take).
// Build: cl /O2 /arch:AVX2 /EHsc /std:c++17 cpuattn_bench.cpp
#include <immintrin.h>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <vector>
#include <thread>
#include <chrono>
#include <algorithm>
#include <random>

static const int D = 256, NKV = 4, GQA = 6, NQ = NKV * GQA, QB = 32, NBLK = D / QB;   // 8 blocks per head row
struct block_q4_0 { uint16_t d; uint8_t qs[16]; };                                      // 18 bytes
static_assert(sizeof(block_q4_0) == 18, "q4_0 block");
static const int ROW_BLOCKS = NKV * NBLK;                                               // 32 blocks per K (or V) row
static const size_t CELL = 2 * ROW_BLOCKS * sizeof(block_q4_0);                         // 1152 B

static inline float h2f(uint16_t h) { return _mm_cvtss_f32(_mm_cvtph_ps(_mm_cvtsi32_si128(h))); }
static inline uint16_t f2h(float f) { return (uint16_t) _mm_extract_epi16(_mm_cvtps_ph(_mm_set_ss(f), 0), 0); }

struct q8_block { float d; int32_t sum; int8_t qs[32]; };

// sum_i nib_i * q_i over 32 values, nib in 0..15 (q4_0 low nibbles = elements 0..15, high = 16..31)
static inline int dot_q4_q8(const block_q4_0 * k, const q8_block * q) {
    const __m128i raw = _mm_loadu_si128((const __m128i *) k->qs);
    const __m128i lo  = _mm_and_si128(raw, _mm_set1_epi8(0x0F));
    const __m128i hi  = _mm_and_si128(_mm_srli_epi16(raw, 4), _mm_set1_epi8(0x0F));
    const __m256i nib = _mm256_set_m128i(hi, lo);                                       // elements 0..15 | 16..31
    const __m256i qv  = _mm256_loadu_si256((const __m256i *) q->qs);
    const __m256i p16 = _mm256_maddubs_epi16(nib, qv);
    const __m256i p32 = _mm256_madd_epi16(p16, _mm256_set1_epi16(1));
    __m128i s = _mm_add_epi32(_mm256_castsi256_si128(p32), _mm256_extracti128_si256(p32, 1));
    s = _mm_hadd_epi32(s, s); s = _mm_hadd_epi32(s, s);
    return _mm_cvtsi128_si32(s) - 8 * q->sum;
}

// acc[0..31] += w * dequant(block)
static inline void axpy_q4(float * acc, const block_q4_0 * v, float w) {
    const float d = h2f(v->d) * w;
    const __m128i raw = _mm_loadu_si128((const __m128i *) v->qs);
    const __m128i lo  = _mm_and_si128(raw, _mm_set1_epi8(0x0F));
    const __m128i hi  = _mm_and_si128(_mm_srli_epi16(raw, 4), _mm_set1_epi8(0x0F));
    const __m256 vd = _mm256_set1_ps(d), v8 = _mm256_set1_ps(-8.0f * d);
    for (int part = 0; part < 2; ++part) {
        const __m128i n = part == 0 ? lo : hi;
        __m256 f0 = _mm256_cvtepi32_ps(_mm256_cvtepu8_epi32(n));
        __m256 f1 = _mm256_cvtepi32_ps(_mm256_cvtepu8_epi32(_mm_srli_si128(n, 8)));
        float * a = acc + part * 16;
        _mm256_storeu_ps(a,     _mm256_fmadd_ps(f0, vd, _mm256_add_ps(_mm256_loadu_ps(a),     v8)));
        _mm256_storeu_ps(a + 8, _mm256_fmadd_ps(f1, vd, _mm256_add_ps(_mm256_loadu_ps(a + 8), v8)));
    }
}

struct Partial { std::vector<float> m, s, acc; };   // per (token, q head): max, sum, D accumulators

static void run_rows(const uint8_t * cells, size_t r0, size_t r1, int nb, const std::vector<q8_block> & qq,
                     float scale, Partial & out) {
    const int NQT = nb * NQ;
    out.m.assign(NQT, -INFINITY); out.s.assign(NQT, 0.0f); out.acc.assign((size_t) NQT * D, 0.0f);
    const int T = 32;                                   // rows per tile
    std::vector<float> sc((size_t) T * NQT);
    for (size_t t0 = r0; t0 < r1; t0 += T) {
        const int nt = (int) std::min<size_t>(T, r1 - t0);
        // scores: each K block is unpacked once and dotted with the 6 x nb query blocks of its group
        for (int t = 0; t < nt; ++t) {
            const block_q4_0 * K = (const block_q4_0 *) (cells + (t0 + t) * CELL);
            float * srow = &sc[(size_t) t * NQT];
            for (int j = 0; j < NQT; ++j) srow[j] = 0.0f;
            for (int kv = 0; kv < NKV; ++kv) {
                for (int b = 0; b < NBLK; ++b) {
                    const block_q4_0 * kb = K + kv * NBLK + b;
                    const __m128i raw = _mm_loadu_si128((const __m128i *) kb->qs);
                    const __m256i nib = _mm256_set_m128i(_mm_and_si128(_mm_srli_epi16(raw, 4), _mm_set1_epi8(0x0F)),
                                                         _mm_and_si128(raw, _mm_set1_epi8(0x0F)));
                    const float dk = h2f(kb->d);
                    for (int tok = 0; tok < nb; ++tok) {
                        for (int g = 0; g < GQA; ++g) {
                            const int h = kv * GQA + g;
                            const q8_block * q = &qq[((size_t) tok * NQ + h) * NBLK + b];
                            const __m256i p32 = _mm256_madd_epi16(_mm256_maddubs_epi16(nib, _mm256_loadu_si256((const __m256i *) q->qs)), _mm256_set1_epi16(1));
                            __m128i s = _mm_add_epi32(_mm256_castsi256_si128(p32), _mm256_extracti128_si256(p32, 1));
                            s = _mm_hadd_epi32(s, s); s = _mm_hadd_epi32(s, s);
                            srow[tok * NQ + h] += dk * q->d * (float) (_mm_cvtsi128_si32(s) - 8 * q->sum);
                        }
                    }
                }
            }
            for (int j = 0; j < NQT; ++j) srow[j] *= scale;
        }
        // online softmax per query head: tile max, rescale, weights
        for (int j = 0; j < NQT; ++j) {
            float mt = -INFINITY;
            for (int t = 0; t < nt; ++t) mt = std::max(mt, sc[(size_t) t * NQT + j]);
            const float mn = std::max(out.m[j], mt);
            const float r  = std::exp(out.m[j] - mn);
            if (r != 1.0f) { float * a = &out.acc[(size_t) j * D]; for (int i = 0; i < D; ++i) a[i] *= r; }
            out.s[j] *= r; out.m[j] = mn;
            for (int t = 0; t < nt; ++t) { float & p = sc[(size_t) t * NQT + j]; p = std::exp(p - mn); out.s[j] += p; }
        }
        // V accumulation: each V block is dequantized once (32 floats) and added into the 6 x nb accumulators
        for (int t = 0; t < nt; ++t) {
            const block_q4_0 * V = (const block_q4_0 *) (cells + (t0 + t) * CELL) + ROW_BLOCKS;
            const float * srow = &sc[(size_t) t * NQT];
            for (int kv = 0; kv < NKV; ++kv) {
                for (int b = 0; b < NBLK; ++b) {
                    const block_q4_0 * vb = V + kv * NBLK + b;
                    const __m128i raw = _mm_loadu_si128((const __m128i *) vb->qs);
                    const __m128i lo  = _mm_and_si128(raw, _mm_set1_epi8(0x0F));
                    const __m128i hi  = _mm_and_si128(_mm_srli_epi16(raw, 4), _mm_set1_epi8(0x0F));
                    const __m256 d  = _mm256_set1_ps(h2f(vb->d)), m8 = _mm256_set1_ps(8.0f);
                    const __m256 v0 = _mm256_mul_ps(_mm256_sub_ps(_mm256_cvtepi32_ps(_mm256_cvtepu8_epi32(lo)), m8), d);
                    const __m256 v1 = _mm256_mul_ps(_mm256_sub_ps(_mm256_cvtepi32_ps(_mm256_cvtepu8_epi32(_mm_srli_si128(lo, 8))), m8), d);
                    const __m256 v2 = _mm256_mul_ps(_mm256_sub_ps(_mm256_cvtepi32_ps(_mm256_cvtepu8_epi32(hi)), m8), d);
                    const __m256 v3 = _mm256_mul_ps(_mm256_sub_ps(_mm256_cvtepi32_ps(_mm256_cvtepu8_epi32(_mm_srli_si128(hi, 8))), m8), d);
                    for (int tok = 0; tok < nb; ++tok) {
                        for (int g = 0; g < GQA; ++g) {
                            const int j = tok * NQ + kv * GQA + g;
                            const __m256 w = _mm256_set1_ps(srow[j]);
                            float * a = &out.acc[(size_t) j * D + b * QB];
                            _mm256_storeu_ps(a,      _mm256_fmadd_ps(v0, w, _mm256_loadu_ps(a)));
                            _mm256_storeu_ps(a + 8,  _mm256_fmadd_ps(v1, w, _mm256_loadu_ps(a + 8)));
                            _mm256_storeu_ps(a + 16, _mm256_fmadd_ps(v2, w, _mm256_loadu_ps(a + 16)));
                            _mm256_storeu_ps(a + 24, _mm256_fmadd_ps(v3, w, _mm256_loadu_ps(a + 24)));
                        }
                    }
                }
            }
        }
    }
}

int main(int argc, char ** argv) {
    const size_t R  = argc > 1 ? (size_t) atoll(argv[1]) : 196608;
    const int    nb = argc > 2 ? atoi(argv[2]) : 2;
    const int    nt = argc > 3 ? atoi(argv[3]) : (int) std::thread::hardware_concurrency();
    std::vector<uint8_t> cells(R * CELL);
    std::mt19937 rng(1);
    for (size_t c = 0; c < R; ++c) {
        block_q4_0 * b = (block_q4_0 *) (cells.data() + c * CELL);
        for (int i = 0; i < 2 * ROW_BLOCKS; ++i) {
            b[i].d = f2h(0.01f + (rng() % 100) * 0.001f);
            for (int k = 0; k < 16; ++k) b[i].qs[k] = (uint8_t) rng();
        }
    }
    std::vector<q8_block> qq((size_t) nb * NQ * NBLK);
    for (auto & q : qq) { q.d = 0.02f; q.sum = 0; for (int i = 0; i < 32; ++i) { q.qs[i] = (int8_t) ((int) (rng() % 255) - 127); q.sum += q.qs[i]; } }
    const float scale = 1.0f / 16.0f;

    // memory read bandwidth for reference (one pass over the cells)
    auto bw = [&]() {
        std::vector<std::thread> th; std::vector<uint64_t> acc(nt);
        auto t0 = std::chrono::high_resolution_clock::now();
        for (int i = 0; i < nt; ++i) th.emplace_back([&, i] {
            const size_t a = cells.size() * i / nt, b = cells.size() * (i + 1) / nt;
            __m256i s = _mm256_setzero_si256();
            for (size_t o = a; o + 32 <= b; o += 32) s = _mm256_add_epi64(s, _mm256_loadu_si256((const __m256i *) (cells.data() + o)));
            acc[i] = (uint64_t) _mm256_extract_epi64(s, 0); });
        for (auto & t : th) t.join();
        return std::chrono::duration<double, std::milli>(std::chrono::high_resolution_clock::now() - t0).count();
    };
    double best_bw = 1e9; for (int i = 0; i < 5; ++i) best_bw = std::min(best_bw, bw());

    std::vector<double> times;
    std::vector<Partial> parts(nt);
    for (int rep = 0; rep < 7; ++rep) {
        auto t0 = std::chrono::high_resolution_clock::now();
        std::vector<std::thread> th;
        for (int i = 0; i < nt; ++i) th.emplace_back([&, i] { run_rows(cells.data(), R * i / nt, R * (i + 1) / nt, nb, qq, scale, parts[i]); });
        for (auto & t : th) t.join();
        times.push_back(std::chrono::duration<double, std::milli>(std::chrono::high_resolution_clock::now() - t0).count());
    }
    std::sort(times.begin(), times.end());
    double chk = 0; for (auto & p : parts) for (float x : p.s) chk += x;
    printf("R %zu nb %d threads %d: %.2f ms per layer (median of 7, min %.2f); read pass %.2f ms (%.1f GB/s); chk %.3g\n",
           R, nb, nt, times[3], times[0], best_bw, cells.size() / best_bw / 1e6, chk);
    return 0;
}
