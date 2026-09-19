// Minimal CUPTI injection profiler: GPU-side start/end for every kernel, including kernels
// replayed from CUDA graphs. Loaded by the CUDA driver via CUDA_INJECTION64_PATH; no app changes.
//
// Output (CUPTI_TRACE_OUT, default cupti_trace.csv): one row per kernel in completion order:
//   seq,start_us,dur_us,gap_us,gridX,blockX,graphId,name
// gap_us is the GPU idle time between the previous kernel's end and this kernel's start on the
// same device (negative = overlapped). A summary by kernel name goes to stderr at exit.

#define NOMINMAX
#include <windows.h>

#include <cupti.h>

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

namespace {

typedef CUptiResult (CUPTIAPI *pfn_register)(CUpti_BuffersCallbackRequestFunc, CUpti_BuffersCallbackCompleteFunc);
typedef CUptiResult (CUPTIAPI *pfn_enable)(CUpti_ActivityKind);
typedef CUptiResult (CUPTIAPI *pfn_next)(uint8_t *, size_t, CUpti_Activity **);
typedef CUptiResult (CUPTIAPI *pfn_flush)(uint32_t);
typedef CUptiResult (CUPTIAPI *pfn_result_string)(CUptiResult, const char **);

pfn_register      p_register      = nullptr;
pfn_enable        p_enable        = nullptr;
pfn_next          p_next          = nullptr;
pfn_flush         p_flush         = nullptr;
pfn_result_string p_result_string = nullptr;

struct Rec {
    uint64_t start;
    uint64_t end;
    int32_t  gridX;
    int32_t  blockX;
    uint32_t graphId;
    int      name_id;
};

std::mutex                           g_mu;
std::vector<Rec>                     g_recs;
std::unordered_map<std::string, int> g_intern;
std::vector<std::string>             g_names;
bool                                 g_done = false;

int intern(const char * s) {
    std::string key = s ? s : "?";
    auto        it  = g_intern.find(key);
    if (it != g_intern.end()) {
        return it->second;
    }
    const int id = (int) g_names.size();
    g_names.push_back(key);
    g_intern.emplace(key, id);
    return id;
}

// Demangle-lite: strip template noise so aggregation keys stay readable.
std::string short_name(const std::string & n) {
    std::string s = n;
    const char * prefixes[] = { "void ", "_Z" };
    for (const char * p : prefixes) {
        if (s.rfind(p, 0) == 0) {
            s = s.substr(strlen(p));
        }
    }
    const size_t lt = s.find('<');
    if (lt != std::string::npos) {
        // keep the first template arg list, it distinguishes kernel variants
        const size_t gt = s.find('>', lt);
        if (gt != std::string::npos && gt - lt < 120) {
            return s.substr(0, gt + 1);
        }
        return s.substr(0, lt) + "<...>";
    }
    const size_t paren = s.find('(');
    return paren == std::string::npos ? s : s.substr(0, paren);
}

void CUPTIAPI buffer_requested(uint8_t ** buffer, size_t * size, size_t * max_num_records) {
    *size            = 1 * 1024 * 1024;
    *buffer          = (uint8_t *) _aligned_malloc(*size, 8);
    *max_num_records = 0;
}

void CUPTIAPI buffer_completed(CUcontext, uint32_t, uint8_t * buffer, size_t, size_t valid_size) {
    CUpti_Activity * record = nullptr;
    std::lock_guard<std::mutex> lock(g_mu);
    for (;;) {
        const CUptiResult st = p_next(buffer, valid_size, &record);
        if (st != CUPTI_SUCCESS) {
            break;
        }
        if (record->kind == CUPTI_ACTIVITY_KIND_CONCURRENT_KERNEL || record->kind == CUPTI_ACTIVITY_KIND_KERNEL) {
            const CUpti_ActivityKernel13 * k = (const CUpti_ActivityKernel13 *) record;
            g_recs.push_back({ k->start, k->end, k->gridX, k->blockX, k->graphId, intern(k->name) });
        }
    }
    _aligned_free(buffer);
}

void dump() {
    std::lock_guard<std::mutex> lock(g_mu);
    if (g_done) {
        return;
    }
    g_done = true;
    if (g_recs.empty()) {
        fprintf(stderr, "[cupti-trace] no kernel records\n");
        return;
    }
    std::sort(g_recs.begin(), g_recs.end(), [](const Rec & a, const Rec & b) { return a.start < b.start; });

    const char * out_env = getenv("CUPTI_TRACE_OUT");
    const std::string out = out_env ? out_env : "cupti_trace.csv";
    FILE * f = fopen(out.c_str(), "w");
    if (f) {
        fprintf(f, "seq,start_us,dur_us,gap_us,gridX,blockX,graphId,name\n");
        const uint64_t t0       = g_recs.front().start;
        uint64_t       prev_end = g_recs.front().start;
        for (size_t i = 0; i < g_recs.size(); ++i) {
            const Rec & r = g_recs[i];
            fprintf(f, "%zu,%.3f,%.3f,%.3f,%d,%d,%u,%s\n", i, (r.start - t0) / 1000.0, (r.end - r.start) / 1000.0,
                    ((double) r.start - (double) prev_end) / 1000.0, r.gridX, r.blockX, r.graphId,
                    g_names[r.name_id].c_str());
            prev_end = std::max(prev_end, r.end);
        }
        fclose(f);
    }

    // Summary by short kernel name.
    struct Agg { size_t n = 0; double us = 0; };
    std::map<std::string, Agg> agg;
    double total_us = 0;
    double busy_us  = 0;
    uint64_t prev_end = g_recs.front().start;
    for (const Rec & r : g_recs) {
        Agg & a = agg[short_name(g_names[r.name_id])];
        a.n += 1;
        a.us += (r.end - r.start) / 1000.0;
        total_us += (r.end - r.start) / 1000.0;
        if (r.start > prev_end) {
            busy_us += 0;
        }
        prev_end = std::max(prev_end, r.end);
    }
    const double span_us = (g_recs.back().end - g_recs.front().start) / 1000.0;
    fprintf(stderr, "[cupti-trace] %zu kernels, sum of kernel time %.3f ms, wall span %.3f ms, GPU idle %.3f ms -> %s\n",
            g_recs.size(), total_us / 1000.0, span_us / 1000.0, (span_us - total_us) / 1000.0, out.c_str());
    std::vector<std::pair<double, std::string>> rows;
    for (const auto & kv : agg) {
        rows.push_back({ kv.second.us, kv.first });
    }
    std::sort(rows.begin(), rows.end(), [](const auto & a, const auto & b) { return a.first > b.first; });
    for (const auto & r : rows) {
        const Agg & a = agg[r.second];
        fprintf(stderr, "[cupti-trace] %10.3f ms %7zu x %8.2f us  %s\n", a.us / 1000.0, a.n, a.us / a.n, r.second.c_str());
    }
    (void) busy_us;
}

// Flushing CUPTI inside atexit deadlocks against driver teardown on Windows, so a worker thread
// flushes periodically while the app runs and exit only writes what has already been delivered.
DWORD WINAPI flusher(LPVOID) {
    for (;;) {
        Sleep(250);
        if (p_flush) {
            p_flush(0);
        }
    }
    return 0;
}

void at_exit() {
    dump();
}

} // namespace

extern "C" __declspec(dllexport) int InitializeInjection(void) {
    static bool once = false;
    if (once) {
        return 1;
    }
    once = true;

    const char * dll = getenv("CUPTI_TRACE_DLL");
    HMODULE      h   = LoadLibraryA(dll ? dll : "cupti64_2026.3.1.dll");
    if (!h) {
        fprintf(stderr, "[cupti-trace] cannot load CUPTI dll (set CUPTI_TRACE_DLL or PATH)\n");
        return 0;
    }
    p_register      = (pfn_register) GetProcAddress(h, "cuptiActivityRegisterCallbacks");
    p_enable        = (pfn_enable) GetProcAddress(h, "cuptiActivityEnable");
    p_next          = (pfn_next) GetProcAddress(h, "cuptiActivityGetNextRecord");
    p_flush         = (pfn_flush) GetProcAddress(h, "cuptiActivityFlushAll");
    p_result_string = (pfn_result_string) GetProcAddress(h, "cuptiGetResultString");
    if (!p_register || !p_enable || !p_next || !p_flush) {
        fprintf(stderr, "[cupti-trace] missing CUPTI entry points\n");
        return 0;
    }
    CUptiResult st = p_register(buffer_requested, buffer_completed);
    if (st != CUPTI_SUCCESS) {
        const char * s = "?";
        if (p_result_string) {
            p_result_string(st, &s);
        }
        fprintf(stderr, "[cupti-trace] register failed: %s\n", s);
        return 0;
    }
    st = p_enable(CUPTI_ACTIVITY_KIND_CONCURRENT_KERNEL);
    if (st != CUPTI_SUCCESS) {
        const char * s = "?";
        if (p_result_string) {
            p_result_string(st, &s);
        }
        fprintf(stderr, "[cupti-trace] enable failed: %s\n", s);
        return 0;
    }
    atexit(at_exit);
    CreateThread(nullptr, 0, flusher, nullptr, 0, nullptr);
    fprintf(stderr, "[cupti-trace] active\n");
    return 1;
}
