"""Minimal ASF/AMC reader: joint positions per frame (pure Python)."""
import math, re

def rot(axis, deg):
    a = math.radians(deg); c, s = math.cos(a), math.sin(a)
    if axis == "x": return [[1,0,0],[0,c,-s],[0,s,c]]
    if axis == "y": return [[c,0,s],[0,1,0],[-s,0,c]]
    return [[c,-s,0],[s,c,0],[0,0,1]]

def mul(a, b): return [[sum(a[i][k]*b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
def tr(a): return [[a[j][i] for j in range(3)] for i in range(3)]
def app(m, v): return [sum(m[i][k]*v[k] for k in range(3)) for i in range(3)]
I = [[1,0,0],[0,1,0],[0,0,1]]

def euler(ax, ay, az):   # ASF "XYZ": rotate about x, then y, then z
    return mul(rot("z", az), mul(rot("y", ay), rot("x", ax)))

def read_asf(path):
    t = open(path).read()
    bones = {}
    for blk in re.findall(r"begin(.*?)end", t.split(":bonedata")[1].split(":hierarchy")[0], re.S):
        name = re.search(r"name (\S+)", blk).group(1)
        d = [float(x) for x in re.search(r"direction (\S+) (\S+) (\S+)", blk).groups()]
        L = float(re.search(r"length (\S+)", blk).group(1))
        ax = [float(x) for x in re.search(r"axis (\S+) (\S+) (\S+)", blk).groups()]
        dof = re.search(r"dof ([^\n]+)", blk)
        bones[name] = dict(dir=d, len=L, C=euler(*ax), dof=dof.group(1).split() if dof else [])
    parent = {}
    hier = t.split(":hierarchy")[1]
    for line in hier.split("begin")[1].split("end")[0].strip().splitlines():
        p, *kids = line.split()
        for k in kids: parent[k] = p
    return bones, parent

def read_amc(path):
    frames, cur = [], None
    for line in open(path):
        line = line.strip()
        if not line or line[0] in "#:": continue
        if line.isdigit():
            cur = {}; frames.append(cur); continue
        name, *vals = line.split(); cur[name] = [float(v) for v in vals]
    return frames

def pose(bones, parent, frame):
    """Joint end positions {bone: (x,y,z)} plus 'root'."""
    r = frame["root"]
    Rroot = euler(*r[3:6])
    pos = {"root": r[0:3]}; glob = {"root": Rroot}
    order = []
    def visit(n):
        for k in [c for c, p in parent.items() if p == n]:
            order.append(k); visit(k)
    visit("root")
    for b in order:
        bd = bones[b]; vals = frame.get(b, [])
        M = I
        ang = {"rx": 0, "ry": 0, "rz": 0}
        for d, v in zip(bd["dof"], vals): ang[d] = v
        M = euler(ang["rx"], ang["ry"], ang["rz"])
        L = mul(bd["C"], mul(M, tr(bd["C"])))
        G = mul(glob[parent[b]], L)
        glob[b] = G
        off = app(G, [c * bd["len"] for c in bd["dir"]])
        p0 = pos[parent[b]]
        pos[b] = [p0[i] + off[i] for i in range(3)]
    return pos
