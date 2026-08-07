"""Beat tracker: onset envelope -> tempo estimate -> Ellis-style DP beat tracking.

Emits actual beat timestamps, so a chart never drifts against the audio no
matter how imprecise the tempo estimate is.
"""
import wave, array, math, json

w = wave.open("analysis.wav","rb"); sr,n = w.getframerate(), w.getnframes()
s = array.array('h'); s.frombytes(w.readframes(n)); w.close()
dur = n/sr

HOP = 128
fps = sr/HOP
nf = len(s)//HOP
env = [math.sqrt(sum(v*v for v in s[i*HOP:(i+1)*HOP])/HOP) for i in range(nf)]

# Onset strength: half-wave rectified difference, smoothed a touch.
on = [max(0.0, env[i]-env[i-1]) for i in range(1,len(env))]
mu = sum(on)/len(on)
on = [max(0.0, o-mu) for o in on]
sm = [ (on[max(0,i-1)]+on[i]+on[min(len(on)-1,i+1)])/3 for i in range(len(on)) ]

# --- tempo via autocorrelation with FRACTIONAL lag (interpolated) ---
def autocorr(lag):
    li = int(lag); frac = lag-li
    if li < 2 or li+1 >= len(sm): return 0.0
    tot = 0.0
    for i in range(li+1, len(sm)):
        prev = sm[i-li]*(1-frac) + sm[i-li-1]*frac
        tot += sm[i]*prev
    return tot/(len(sm)-li)

best = (0,0)
b = 60.0
while b <= 180.0:
    sc = autocorr(fps*60.0/b)
    if sc > best[0]: best = (sc,b)
    b += 0.05
tempo = best[1]
print(f"duration {dur:.1f}s  envelope {fps:.1f}fps")
print(f"tempo estimate: {tempo:.2f} BPM (period {60/tempo:.4f}s)")

# --- Ellis DP beat tracking ---
period = fps*60.0/tempo
TIGHT = 100.0
N = len(sm)
mx = max(sm) or 1.0
o = [v/mx for v in sm]

C = [0.0]*N          # cumulative score
P = [-1]*N           # backpointer
lo = int(-2*period); hi = int(-period/2)
for t in range(N):
    bestsc, bestp = -1e18, -1
    for d in range(lo, hi+1):
        tp = t+d
        if tp < 0: continue
        pen = -TIGHT * (math.log(-d/period))**2
        sc = C[tp] + pen
        if sc > bestsc: bestsc, bestp = sc, tp
    if bestp < 0:
        C[t], P[t] = o[t], -1
    else:
        C[t], P[t] = o[t] + bestsc, bestp

# Backtrack from a strong late peak
tail = int(N*0.9)
start = max(range(tail, N), key=lambda i: C[i])
beats = []
t = start
while t >= 0:
    beats.append(t)
    t = P[t]
beats.reverse()
times = [round(bt/fps, 4) for bt in beats]

# quality report
ivals = [times[i+1]-times[i] for i in range(len(times)-1)]
avg = sum(ivals)/len(ivals)
var = math.sqrt(sum((v-avg)**2 for v in ivals)/len(ivals))
print(f"tracked {len(times)} beats, first {times[0]:.3f}s last {times[-1]:.3f}s")
print(f"mean interval {avg:.4f}s ({60/avg:.2f} BPM), sd {var*1000:.1f}ms")
print(f"coverage: {times[-1]-times[0]:.1f}s of {dur:.1f}s")

json.dump({"songId":"demo_song","bpm":round(60/avg,2),"beats":times},
          open("demo_song_beats.json","w"))
print("wrote demo_song_beats.json")
