shader_type sky;
uniform sampler2D panorama : source_color, filter_linear_mipmap, repeat_enable;
uniform float lightning = 0.0;
void sky() {
 vec2 uv=SKY_COORDS;
 uv.x=fract(uv.x+TIME*0.00012);
 // Explicit LOD avoids a bright mip stripe where the spherical UV wraps.
 vec3 base=textureLod(panorama,uv,0.0).rgb;
 vec3 opposite=textureLod(panorama,vec2(1.0-uv.x,uv.y),0.0).rgb;
 float seam=smoothstep(0.0,0.025,min(uv.x,1.0-uv.x));
 vec3 c=mix((base+opposite)*0.5,base,seam);
 // Soft pole blending avoids the generated LDR panorama's pinched zenith.
 c=mix(vec3(0.035,0.045,0.055),c,smoothstep(0.0,0.07,uv.y));
 vec3 d=normalize(EYEDIR);
 float patch=pow(max(dot(d,normalize(vec3(-0.5,0.35,-0.8))),0.0),18.0);
 c+=vec3(0.32,0.035,0.025)*lightning*patch;
 COLOR=c;
}
