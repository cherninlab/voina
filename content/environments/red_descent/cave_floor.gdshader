shader_type spatial;
// UV follows each actual flag; UV2 carries the shared earth/water field.
uniform int floor_kind = 0; // 0 flagstone, 1 earth, 2 shallow water
uniform sampler2D stone_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 world_tangent;

float ground_noise(vec2 point) {
 vec2 cell=floor(point);
 vec2 f=fract(point);
 f=f*f*(3.0-2.0*f);
 vec4 h=fract(sin(vec4(dot(cell,vec2(127.1,311.7)))+vec4(0,127.1,311.7,438.8))*43758.5453);
 return mix(mix(h.x,h.y,f.x),mix(h.z,h.w,f.x),f.y);
}

void vertex() {
 world_pos=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;
 world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
 world_tangent=normalize((MODEL_MATRIX*vec4(TANGENT,0)).xyz);
}
void fragment() {
 float earth=UV2.x;
 float pool=1.0-UV2.y; // glTF flips Blender UV V.
 if (floor_kind==0 && earth>.78) { discard; }
 if (floor_kind==2 && pool<.5+(ground_noise(world_pos.xz*2.2)-.5)*.14) { discard; }
 vec3 n=normalize(world_normal);
 vec3 t=floor_kind==0 ? normalize(world_tangent-n*dot(world_tangent,n)) : normalize(vec3(1,0,0)-n*n.x);
 vec3 b=normalize(cross(n,t));
 vec2 soil_uv=world_pos.xz*.64;
 vec3 soil=texture(soil_albedo,soil_uv).rgb*vec3(.50,.43,.35);
 vec3 stone=texture(stone_albedo,UV*.8).rgb*vec3(.86,.9,.88)*COLOR.rgb;
 float burial=smoothstep(.40,.78,earth);
 vec3 color=floor_kind==0 ? mix(stone,soil,burial) : soil;
 float damp=smoothstep(.1,.75,earth)*.35+pool*.65;
 color*=mix(1.0,.56,damp);
 vec3 detail;
 if (floor_kind==0) {
  detail=mix(texture(stone_normal,UV*.8).xyz,texture(soil_normal,soil_uv).xyz,burial)*2.0-1.0;
  detail.xy*=.23;
 } else {
  detail=texture(soil_normal,soil_uv).xyz*2.0-1.0;
  detail.xy*=.18;
 }
 detail.z=sqrt(max(.01,1.0-dot(detail.xy,detail.xy)));
 vec3 bent=normalize(t*detail.x-b*detail.y+n*detail.z);
 if (floor_kind==2) {
  color=vec3(.035,.031,.025);
  bent=normalize(n+vec3(sin(world_pos.z*7.3)*.007,0,cos(world_pos.x*6.1)*.007));
 }
 NORMAL=normalize((VIEW_MATRIX*vec4(bent,0)).xyz);
 ALBEDO=color;
 ROUGHNESS=floor_kind==2 ? mix(.16,.32,1.0-smoothstep(.5,.7,pool)) : mix(.96,.69,damp);
 SPECULAR=floor_kind==2 ? .5 : .28;
}
