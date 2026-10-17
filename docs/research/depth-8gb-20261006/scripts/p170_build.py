"""P170 data builder: two ~245k-token documents with 24 facts each, fixed on disk (p170/prose.json, p170/code.json).
prose: the repo's docs/research notes (real prose + tables), 24 invented facts inserted at even paragraph positions; each
  question uses other words than its fact (low word overlap), graded by a keyword.
code: llama.cpp sources (src/*.cpp, ggml-cuda/*.cu / *.cuh); 24 questions on numeric #define macros defined once in the
  document (the agent case: a named identifier), graded by the exact value.
The documents are cut to a character budget here; the driver measures tokens with /tokenize and trims.
"""
import glob, json, os, re

OUT = r"C:/bonsai/8gb/p170"
PROSE_CHARS = 598000
CODE_CHARS = 690000

FACTS = [
    ("Marguerite found that the standby generator behind the east annex had been filled with kerosene by mistake.",
     "Which wrong fuel went into the backup power unit near the eastern wing?", ["kerosene"]),
    ("The ferry captain, a quiet man named Oduya, always kept a jar of pickled ginger on the bridge.",
     "What preserved food did the boat's skipper keep at the helm?", ["ginger"]),
    ("In the last inventory, the greenhouse held exactly 314 orchid pots.",
     "How many flower containers were counted in the glass plant house?", ["314"]),
    ("Professor Lindqvist lost her umbrella on the night train to Narvik.",
     "During an overnight rail journey, which city was the lecturer travelling to when she left her parasol behind?", ["narvik"]),
    ("The bakery on Calloway Street switched its sourdough starter to one fed only with rye.",
     "Which grain now feeds the leaven at the bread shop?", ["rye"]),
    ("Our oldest beehive sits beside a fig tree that was planted in 1957.",
     "In what year was the tree next to the most senior bee colony put in the ground?", ["1957"]),
    ("The museum's night guard reported that the bronze heron statue had been turned to face the river.",
     "Which bird does the metal sculpture that was rotated toward the water depict?", ["heron"]),
    ("Teodor paid for the repaired accordion with three silver spoons.",
     "What items did the man hand over in exchange for fixing his squeezebox?", ["spoon"]),
    ("At the regional chess final, the winning move was a quiet bishop retreat to g7.",
     "To which square did the deciding piece withdraw in the championship game?", ["g7"]),
    ("The lighthouse keeper painted the stairwell a deep shade of saffron.",
     "What colour are the steps inside the coastal beacon tower?", ["saffron"]),
    ("Each winter the village choir rehearses in the abandoned salt warehouse.",
     "The local singers practise in a disused storage building during the cold months. What did that building once store?", ["salt"]),
    ("The surveyor's notebook says the north ridge trail is 11.4 kilometres long.",
     "How long is the hiking path along the upper crest, according to the land measurer's records?", ["11.4"]),
    ("A stray goat named Pepper lived in the school courtyard for two years.",
     "What was the wandering farm animal at the schoolyard called?", ["pepper"]),
    ("The cartographer used walnut ink for every map of the delta.",
     "The mapmaker drew all the river-mouth charts with ink made from which tree?", ["walnut"]),
    ("The jazz trio played their final concert in a converted tram depot.",
     "The three musicians gave their last show in a former depot for which kind of vehicle?", ["tram"]),
    ("Inspector Haldane solved the case after noticing a single blue thread on the windowsill.",
     "What colour was the fibre on the ledge that cracked the detective's investigation?", ["blue"]),
    ("The orchard's best harvest came from a pear variety called Moonglow.",
     "What is the name of the fruit cultivar that gave the top yield in the grove?", ["moonglow"]),
    ("The old clock tower chimes thirteen times at noon because of a gear fault.",
     "Because of a mechanical defect, how many strikes does the town's timepiece make at midday?", ["thirteen", "13"]),
    ("The glassblower's apprentice, Ines, specialized in cobalt vases.",
     "Which metal-based tint was the young furnace worker known for in her vessels?", ["cobalt"]),
    ("The expedition's sled dogs were fed dried capelin on the coastal leg.",
     "Which fish did the polar team give their huskies near the shore?", ["capelin"]),
    ("In the archive basement, the oldest ledger is bound in sealskin.",
     "What animal hide covers the most ancient account book on the record vault's lower floor?", ["seal"]),
    ("The violin maker sourced spruce only from trees felled during a waning moon.",
     "Which wood did the string-instrument craftsman select, cut in a particular lunar phase?", ["spruce"]),
    ("Grandmother Tsai's dumpling recipe uses exactly nine folds per wrapper.",
     "How many pleats does the old woman's recipe put in each dough parcel?", ["nine", "9"]),
    ("The marathon was rerouted past the cathedral because a water main burst on Elm Avenue.",
     "Which street had a broken pipe that forced the long-distance race to change course?", ["elm"]),
]


def prose():
    files = sorted(glob.glob(r"C:/bonsai/bas-rec3/docs/research/**/*.md", recursive=True))
    paras = []
    for f in files:
        for p in re.split(r"\n\s*\n", open(f, encoding="utf-8", errors="replace").read()):
            p = p.strip()
            if p:
                paras.append(p)
    out, n = [], 0
    for p in paras:
        if n > PROSE_CHARS:
            break
        out.append(p)
        n += len(p) + 2
    k = len(FACTS)
    for j in reversed(range(k)):
        out.insert(int(len(out) * (j + 0.5) / k), FACTS[j][0])
    doc = "\n\n".join(out)
    items = [{"q": q, "ans": a, "fact": f, "pos": round(doc.index(f) / len(doc), 3)} for f, q, a in FACTS]
    return {"doc": doc, "items": items, "files": len(files)}


# 24 constants inserted into the real code at even line positions (values a model cannot guess). Even items: the question
# names the identifier (the agent case, high word overlap). Odd items: the question describes it in other words (low overlap).
CONSTS = [
    ("kUploadRetryBudgetMs", "4170", "How many milliseconds may an upload keep trying again before it gives up?"),
    ("kMaxPendingHandshakes", "37", "What is the limit on connection greetings that may wait at the same time?"),
    ("kThumbnailEdgePx", "212", "How many pixels wide is the side of a preview image?"),
    ("kLedgerFlushEveryRows", "1385", "After how many records is the account log written out to disk?"),
    ("kSensorWarmupTicks", "73", "How many timer steps must a detector run before its readings count?"),
    ("kFanCurveKneeCelsius", "61", "At what temperature does the cooling profile bend upward?"),
    ("kSessionIdleKickSec", "2650", "How long, in seconds, may a user stay inactive before being signed out?"),
    ("kTileCacheShards", "19", "Into how many parts is the map-square store split?"),
    ("kDefaultLanguageWeight", "347", "What is the preset score for the spoken-tongue preference?"),
    ("kJitterSpreadUs", "583", "How wide, in microseconds, is the random timing scatter?"),
    ("kMailboxSoftQuotaMb", "7520", "How many megabytes may a message inbox hold before a warning?"),
    ("kPrinterQueueDepth", "29", "How many documents may line up for the paper output device?"),
    ("kHeartbeatMissLimit", "11", "How many skipped liveness signals cause a node to be marked dead?"),
    ("kCompressLevelArchive", "17", "Which squeeze strength is used for long-term stored backups?"),
    ("kGlyphAtlasPages", "43", "How many sheets does the font character texture use?"),
    ("kVoiceFrameSamples", "723", "How many audio points make up one speech packet?"),
    ("kBackoffCeilingSec", "906", "What is the longest wait, in seconds, between repeated attempts?"),
    ("kParcelWeightCapGrams", "3175", "What is the heaviest package allowed, in grams?"),
    ("kShardRebalanceGap", "53", "What size difference between storage pieces starts a redistribution?"),
    ("kThermalTripMilliC", "98250", "At what heat level, in thousandths of a degree, does the safety shutdown fire?"),
    ("kAuditTrailDays", "413", "For how many days are the review records kept?"),
    ("kRouteHopLimit", "23", "How many network relays may a path cross at most?"),
    ("kSpellSuggestMax", "7", "How many alternative word fixes are offered at most?"),
    ("kLockLeaseMs", "8830", "For how many milliseconds does a held mutual-exclusion claim stay valid?"),
]


def code():
    files = sorted(glob.glob(r"C:/bonsai/bonsai-ada-surgery/vendor/prism-q3kv/ggml/src/ggml-cuda/*.cu*")) + \
        sorted(glob.glob(r"C:/bonsai/bonsai-ada-surgery/vendor/prism-q3kv/src/*.cpp"))
    parts, n = [], 0
    for f in files:
        if n > CODE_CHARS:
            break
        t = open(f, encoding="utf-8", errors="replace").read()
        rel = f.replace(chr(92), "/").split("prism-q3kv/")[1]
        parts.append(f"// ===== file: {rel} =====\n{t}")
        n += len(t)
    lines = "\n".join(parts)[:CODE_CHARS].split("\n")
    k = len(CONSTS)
    for j in reversed(range(k)):
        at = int(len(lines) * (j + 0.5) / k)
        while at < len(lines) and lines[at].strip() != "":   # insert at a blank line, so no statement is split
            at += 1
        nm, v, _ = CONSTS[j]
        lines.insert(at, f"static constexpr int {nm} = {v};")
    doc = "\n".join(lines)
    items = []
    for j, (nm, v, desc) in enumerate(CONSTS):
        q = (f"In the code above, what is the value of {nm}? Answer with the number only." if j % 2 == 0 else
             f"In the code above, one constant answers this: {desc} Answer with the number only.")
        line = f"static constexpr int {nm} = {v};"
        items.append({"q": q, "ans": [v], "fact": line, "named": j % 2 == 0, "pos": round(doc.index(line) / len(doc), 3)})
    return {"doc": doc, "items": items, "files": len(parts)}


os.makedirs(OUT, exist_ok=True)
for name, fn in (("prose", prose), ("code", code)):
    d = fn()
    json.dump(d, open(os.path.join(OUT, name + ".json"), "w", encoding="utf-8"))
    print(name, len(d["doc"]), "chars", len(d["items"]), "items", {k: v for k, v in d.items() if k not in ("doc", "items")})
    for it in d["items"]:
        print("  ", it["pos"], it["fact"][:60], it["ans"], it.get("uses", ""))
