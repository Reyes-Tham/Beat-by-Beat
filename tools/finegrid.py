import json, sys
PATH = sys.argv[1] if len(sys.argv) > 1 else "demo_song_beats.json"
d = json.load(open(PATH))
b = d["beats"]
# Detected pulse is every other beat of a ~144 BPM song (a strong backbeat
# pattern). Interpolating midpoints recovers the full beat grid; because every
# level's spacing is even, notes still land on DETECTED beats, and the
# midpoints just leave finer resolution available later.
fine = []
for i in range(len(b)-1):
    fine.append(round(b[i],4))
    fine.append(round((b[i]+b[i+1])/2, 4))
fine.append(round(b[-1],4))
iv = [fine[i+1]-fine[i] for i in range(len(fine)-1)]
bpm = round(60/(sum(iv)/len(iv)), 2)
json.dump({"songId":d["songId"],"bpm":bpm,"beats":fine}, open(PATH,"w"))
print(f"{len(fine)} beats @ {bpm} BPM, {fine[0]}s .. {fine[-1]}s")
print("first 8:", fine[:8])
