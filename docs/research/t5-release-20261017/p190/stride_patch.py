p = 'src/llama-kv-cache.cpp'
s = open(p, encoding='utf-8').read()


def rep(a, b, n=1):
    global s
    assert s.count(a) == n, (a[:70], s.count(a))
    s = s.replace(a, b)


rep('''// a ubatch that ends before the dense tail (n_prompt - T, set by the server) masks cells with S <= pos < p - W; tail and decode stay dense
''', '''// a ubatch that ends before the dense tail (n_prompt - T, set by the server) masks cells with S <= pos < p - W; tail and decode stay dense
// stride=N (P190, 0 = off): every N-th 256-position block of the far part stays visible (a sparse sample of the far context)
''')
rep('''    int32_t tail   = 1024;
    std::vector<int> dense; // layers that keep the dense mask''', '''    int32_t tail   = 1024;
    int32_t stride = 0;
    std::vector<int> dense; // layers that keep the dense mask''')
rep('''                if (k == "tail")   { c.tail   = v; }''', '''                if (k == "tail")   { c.tail   = v; }
                if (k == "stride") { c.stride = std::max(0, v); }''')
rep('''        LLAMA_LOG_WARN("%s: prefill window on (experimental): window %d, sink %d, tail %d, dense layers %zu\\n", __func__,
            c.window, c.sink, c.tail, c.dense.size());''', '''        LLAMA_LOG_WARN("%s: prefill window on (experimental): window %d, sink %d, tail %d, stride %d, dense layers %zu\\n", __func__,
            c.window, c.sink, c.tail, c.stride, c.dense.size());''')
rep('''    int32_t sink = 0;
    int32_t pmax = -1;''', '''    int32_t sink = 0;
    int32_t stride = 0;
    int32_t pmax = -1;''')
rep('''    st.sink = c.sink;
    return st;''', '''    st.sink = c.sink;
    st.stride = c.stride;
    return st;''')
rep('''                if (pw.on && p0 >= pw.sink && p0 + pw.w < p1) {
                    goto skip;''', '''                if (pw.on && p0 >= pw.sink && p0 + pw.w < p1 && !(pw.stride > 0 && (p0 >> 8) % pw.stride == 0)) {
                    goto skip;''')
rep('''                    if (keep && pw.on && p0 >= pw.sink && p0 + pw.w < p1) {''',
    '''                    if (keep && pw.on && p0 >= pw.sink && p0 + pw.w < p1 && !(pw.stride > 0 && (p0 >> 8) % pw.stride == 0)) {''')
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
