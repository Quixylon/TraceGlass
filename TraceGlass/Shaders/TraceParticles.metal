#include <metal_stdlib>
using namespace metal;

struct TransitionUniforms {
    float4 c0, c1, c2, c3;
    float4 viewport;
    float4 parameters;
};
struct ParticleVertex {
    float4 position [[position]];
    float2 uv;
    float opacity;
};
float hash21(float2 p) { return fract(sin(dot(p, float2(127.1,311.7))) * 43758.5453); }
float2 quadPoint(float2 uv, float2 a, float2 b, float2 c, float2 d) {
    // Projective interpolation keeps straight lines straight on the destination paper.
    float2 delta = a-b+c-d;
    float2 e=b-c, f=d-c;
    float det=e.x*f.y-e.y*f.x;
    if (abs(det)<0.0001) return mix(mix(a,b,uv.x),mix(d,c,uv.x),uv.y);
    float g=(delta.x*f.y-delta.y*f.x)/det;
    float h=(e.x*delta.y-e.y*delta.x)/det;
    return ((b-a+g*b)*uv.x+(d-a+h*d)*uv.y+a)/(g*uv.x+h*uv.y+1);
}
vertex ParticleVertex traceParticleVertex(uint vertexID [[vertex_id]], uint instanceID [[instance_id]],
                                          constant TransitionUniforms &u [[buffer(0)]]) {
    const float2 vertices[6]={float2(0,0),float2(1,0),float2(0,1),float2(1,0),float2(1,1),float2(0,1)};
    uint columns=uint(u.parameters.y),rows=uint(u.parameters.z);
    float2 cell=float2(instanceID%columns,instanceID/columns);
    float p=clamp(u.parameters.x,0.0,1.0);
    float burst=sin(p*M_PI_F);
    float2 local=(vertices[vertexID]-0.5)*(1.0-0.45*burst);
    float2 uv=(cell+0.5+local)/float2(columns,rows);
    float2 from=quadPoint(uv,u.c0.xy,u.c1.xy,u.c2.xy,u.c3.xy);
    float2 to=quadPoint(uv,u.c0.zw,u.c1.zw,u.c2.zw,u.c3.zw);
    float random=hash21(cell),angle=random*2*M_PI_F;
    float2 scatter=float2(cos(angle),sin(angle))*(18+random*74)*burst;
    float depth=1+burst*(0.08+random*0.15);
    float2 position=mix(from,to,smoothstep(0.05,0.95,p));
    position=(position-u.viewport.xy*0.5)*depth+u.viewport.xy*0.5+scatter;
    ParticleVertex out;
    out.position=float4(position.x/u.viewport.x*2-1,1-position.y/u.viewport.y*2,0,1);
    out.uv=uv;
    out.opacity=u.parameters.w*(1-0.10*burst);
    return out;
}
fragment float4 traceParticleFragment(ParticleVertex in [[stage_in]],texture2d<float> reference [[texture(0)]]) {
    constexpr sampler sampleFilter(coord::normalized,address::clamp_to_edge,filter::linear);
    float4 color=reference.sample(sampleFilter,in.uv);
    color.a*=in.opacity;
    return color;
}
