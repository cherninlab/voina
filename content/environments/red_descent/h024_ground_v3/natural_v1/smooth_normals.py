from pathlib import Path
import json,struct,math,sys,hashlib
p=Path(sys.argv[1])
before=p.read_bytes();allowed=[]
raw=bytearray(before);jlen=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+jlen]);base=20+jlen+8

def access(i):
 a=doc['accessors'][i];v=doc['bufferViews'][a['bufferView']];t={5126:'f',5125:'I',5123:'H'}[a['componentType']];n={'VEC3':3,'SCALAR':1}[a['type']];fmt='<'+t*n
 offset=base+v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',struct.calcsize(fmt))
 return [struct.unpack_from(fmt,raw,offset+j*stride) for j in range(a['count'])],offset,stride
changed=0
for m in doc['meshes']:
 if not m.get('name','').startswith('tunnel_rock'):continue
 for prim in m['primitives']:
  pos,_,_=access(prim['attributes']['POSITION']);normals,offset,stride=access(prim['attributes']['NORMAL']);allowed.extend((offset+i*stride,offset+i*stride+12) for i in range(len(normals)));idx,_,_=access(prim['indices']);idx=[i[0] for i in idx]
  sums={};keys=[tuple(round(c,5) for c in p) for p in pos]
  for k in range(0,len(idx),3):
   tri=idx[k:k+3];a,b,c=[pos[i] for i in tri];u=[b[j]-a[j] for j in range(3)];v=[c[j]-a[j] for j in range(3)];n=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]]
   for i in tri:
    value=sums.setdefault(keys[i],[0.,0.,0.])
    for j in range(3):value[j]+=n[j]
  for i,key in enumerate(keys):
   n=sums[key];length=math.sqrt(sum(c*c for c in n))
   if length>1e-9:struct.pack_into('<fff',raw,offset+i*stride,*(c/length for c in n));changed+=1
if changed:
 a=bytearray(before);b=bytearray(raw)
 for start,end in allowed:a[start:end]=bytes(end-start);b[start:end]=bytes(end-start)
 assert a==b,'Non-normal byte changed'
 p.write_bytes(raw)
 report={'file':str(p),'before_sha256':hashlib.sha256(before).hexdigest(),'after_sha256':hashlib.sha256(raw).hexdigest(),'normal_vertices':changed,'all_non_normal_bytes_identical':True}
 print(json.dumps(report))
