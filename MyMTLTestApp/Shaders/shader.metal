//
//  shader.metal
//  MyMTLTestApp
//
//  Created by Andy Zhang on 2025/11/8.
//

#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoords;
};

[[vertex]]
VertexOut vertexShader(uint vertexID [[vertex_id]])
{
    return {
        float4(1.0, 1.0, 1.0, 1),
        float2(1.0, 1.0)
    };
}

[[fragment]]
float4 fragmentShader(VertexOut vertexIn [[stage_in]])
{
    return float4(1.0, 0, 0, 1);
}
