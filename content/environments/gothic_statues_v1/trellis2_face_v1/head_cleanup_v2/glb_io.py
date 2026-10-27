"""Minimal GLB data access; keep approved vertex and image buffers unchanged."""
import json
import struct
import numpy as np

DTYPES={5121:'u1',5123:'<u2',5125:'<u4',5126:'<f4'}
WIDTH={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}

def read_glb(path):
    raw=path.read_bytes();assert struct.unpack_from('<I',raw)[0]==0x46546c67
    length,kind=struct.unpack_from('<II',raw,12);assert kind==0x4e4f534a
    document=json.loads(raw[20:20+length]);offset=20+length
    size,kind=struct.unpack_from('<II',raw,offset);assert kind==0x004e4942
    return document,bytearray(raw[offset+8:offset+8+size])

def array(document,binary,index):
    acc=document['accessors'][index];view=document['bufferViews'][acc['bufferView']]
    assert 'sparse' not in acc
    dtype=np.dtype(DTYPES[acc['componentType']]);width=WIDTH[acc['type']]
    stride=view.get('byteStride',dtype.itemsize*width)
    offset=view.get('byteOffset',0)+acc.get('byteOffset',0)
    return np.ndarray((acc['count'],width),dtype=dtype,buffer=binary,
        offset=offset,strides=(stride,dtype.itemsize)).copy()

def append_indices(document,binary,indices):
    binary.extend(b'\x00'*((-len(binary))%4));offset=len(binary)
    values=np.asarray(indices,dtype='<u4').ravel();data=values.tobytes();binary.extend(data)
    view=len(document['bufferViews']);document['bufferViews'].append({
        'buffer':0,'byteOffset':offset,'byteLength':len(data),'target':34963})
    index=len(document['accessors']);document['accessors'].append({
        'bufferView':view,'componentType':5125,'count':len(values),'type':'SCALAR',
        'min':[int(values.min())],'max':[int(values.max())]})
    return index

def write_glb(path,document,binary):
    binary.extend(b'\x00'*((-len(binary))%4));document['buffers']=[{'byteLength':len(binary)}]
    text=json.dumps(document,separators=(',',':')).encode();text+=b' '*((-len(text))%4)
    total=12+8+len(text)+8+len(binary)
    path.write_bytes(struct.pack('<III',0x46546c67,2,total)+
        struct.pack('<II',len(text),0x4e4f534a)+text+
        struct.pack('<II',len(binary),0x004e4942)+binary)
