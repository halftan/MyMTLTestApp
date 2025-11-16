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
VertexOut vertex_main(uint vertexID [[vertex_id]],
                      constant float4x4 &modelProjectionMatrix [[buffer(0)]])
{
    float2 vertices[] = {
        { 0.0f, 0.0f },
        { 0.0f, 1.0f },
        { 1.0f, 0.0f },
        { 1.0f, 1.0f },
    };
    float2 modelPosition = vertices[vertexID];
    float2 texCoords = vertices[vertexID];

    float4 clipPosition = modelProjectionMatrix * float4(modelPosition, 0.0f, 1.0f);

    return {
        clipPosition,
//        float4(modelPosition, 0.0f, 1.0f),
        texCoords,
    };
}

[[vertex]]
VertexOut vertex_fullscreen(uint vid [[vertex_id]]) {
    float2 positions[4] = { {-1,-1}, {1,-1}, {-1,1}, {1,1} };
    float2 uvs[4] = { {0,1}, {1,1}, {0,0}, {1,0} };

    VertexOut out;
    out.position = float4(positions[vid], 0, 1);
    out.texCoords = uvs[vid];
    return out;
}


float2 texture_mapping(float2 texCoords, uint viewID) {
   return float2(texCoords.x * 0.5 + viewID * 0.5, texCoords.y);
    // return texCoords.xy;
}

// Linear Rec.709 to Linear Display P3 conversion matrix
// Derived via CIE XYZ: Rec.709 → XYZ → P3
// Values from ICC/Apple/SMPTE standards
constant half3x3 REC709_TO_P3_MATRIX = half3x3(
                                                 half3(1.2249401h, -0.2249401h, 0.0h),
                                                 half3(-0.0420569h, 1.0420569h, 0.0h),
                                                 half3(-0.0196376h, 0.0196376h, 1.0h));

half3 tonemap_rec709_to_p3(half3 linear_rec709_rgb, half intensity) {
    // Apply optional intensity scaling (e.g., for exposure adjustment)
    half3 scaled = linear_rec709_rgb * intensity;

    // Convert linear Rec.709 RGB → linear Display P3 RGB
    half3 linear_p3 = REC709_TO_P3_MATRIX * scaled;

    // Optional: clamp to [0, 1] if you're targeting SDR P3 display
    // For HDR, you might omit clamping or use tone mapping instead
    return clamp(linear_p3, 0.0h, 1.0h);
}

float3 tonemap_maxrgb(float3 x, float maxInput, float maxOutput) {
    if (maxInput <= maxOutput) {
        return x;
    }
    float a = maxOutput / (maxInput * maxInput);
    float b = 1.0f / maxOutput;
    float colorMax = max(x.r, max(x.g, x.b));
    return x * (1.0f + a * colorMax) / (1.0f + b * colorMax);
}

[[fragment]]
half4 fragment_linear_sbs(VertexOut in [[stage_in]],
                          texture2d<half> frameTexture [[texture(0)]],
                          constant int &viewID [[buffer(0)]])
{
    constexpr sampler bilinearSampler(address::clamp_to_edge, filter::linear, mip_filter::none);
    half4 color = frameTexture.sample(bilinearSampler, float2(in.texCoords.x * 0.5 + viewID * 0.5, in.texCoords.y));
//    color.rgb = tonemap_rec709_to_p3(color.rgb, 1.0h);
    return color;
}

[[fragment]]
half4 fragment_linear(VertexOut in [[stage_in]],
                      texture2d<half> frameTexture [[texture(0)]])
{
    constexpr sampler bilinearSampler(address::clamp_to_edge, filter::linear, mip_filter::none);
    half4 color = frameTexture.sample(bilinearSampler, in.texCoords);
    return color;
}

float3 eotf_pq(float3 x) {
    float c1 =  107 / 128.0f;
    float c2 = 2413 / 128.0f;
    float c3 = 2392 / 128.0f;
    float m1 = 1305 / 8192.0f;
    float m2 = 2523 / 32.0f;
    float3 p = pow(x, 1.0f / m2);
    float3 L = 10000.0f * pow(max(p - c1, 0.0f) / (c2 - c3 * p), 1.0f / m1);
    return L;
}

float3 tonemap_pq(float3 x, float hdrHeadroom) {
    const float referenceWhite = 203.0f;
    const float peakWhite = 10000.0f;
    return tonemap_maxrgb(eotf_pq(x) / referenceWhite, peakWhite / referenceWhite, hdrHeadroom);
}

[[fragment]]
float4 fragment_tonemap_pq(VertexOut in [[stage_in]],
                           uint ampId [[amplification_id]],
                           constant float &edrHeadroom [[buffer(0)]],
                           texture2d<float> frameTexture [[texture(0)]])
{
    constexpr sampler bilinearSampler(address::clamp_to_edge, filter::linear, mip_filter::none);
    float4 color = frameTexture.sample(bilinearSampler, texture_mapping(in.texCoords, ampId));
    color.rgb = tonemap_pq(color.rgb, edrHeadroom);
    return color;
}

float3 ootf_hlg(float3 Y, float Lw) {
    float gamma = 1.2f + 0.42f * log(Lw / 1000.0f) / log(10.0f);
    return pow(Y, gamma - 1.0f) * Y;
}

float inv_oetf_hlg(float v) {
    float a = 0.17883277f;
    float b = 1.0f - 4 * a;
    float c = 0.5f - a * log(4.0f * a);
    if (v <= 0.5f) {
        return pow(v, 2.0f) / 3.0f;
    } else {
        return (exp((v - c) / a) + b) / 12.0f;
    }
}

float3 inv_oetf_hlg(float3 v) {
    return float3(inv_oetf_hlg(v.r),
                  inv_oetf_hlg(v.g),
                  inv_oetf_hlg(v.b));
}

float3 tonemap_hlg(float3 x, float edrHeadroom) {
    const float referenceWhite = 100.0f;
    const float peakWhite = 1000.0f;

    float3 v = ootf_hlg(inv_oetf_hlg(x), peakWhite);
    v *= peakWhite / referenceWhite;
    v = tonemap_maxrgb(v, peakWhite / referenceWhite, edrHeadroom);
    return v;
};

[[fragment]]
float4 fragment_tonemap_hlg(VertexOut in [[stage_in]],
                           constant uint &viewID [[buffer(0)]],
                           texture2d<float> frameTexture [[texture(0)]])
{
    constexpr sampler bilinearSampler(address::clamp_to_edge, filter::linear, mip_filter::none);
    float4 color = frameTexture.sample(bilinearSampler, texture_mapping(in.texCoords, viewID));
    color.rgb = tonemap_hlg(color.rgb, 1.0);
    return color;
}

    // ========== Fragment Shader: YUV → Linear Display P3 ==========

    // BT.709 full-range YUV to gamma-encoded RGB matrix
    // Assumes Y ∈ [0,1], Cb/Cr ∈ [-0.5, 0.5]
constant half3x3 YUV_TO_RGB_BT709 = half3x3(
                                            half3(1.0h,  1.0h, 1.0h),
                                            half3(0.0h, -0.187324h, 1.855600h),
                                            half3(1.574800h, -0.468124h, 0.0h)
                                            );

    // Linear Rec.709 to Linear Display P3 color matrix
constant half3x3 REC709_TO_P3 = half3x3(
                                        half3( 1.2249401h, -0.0420569h, -0.0196376h ),
                                        half3(-0.2249401h,  1.0420569h,  0.0196376h ),
                                        half3( 0.0h,        0.0h,        1.0h )
                                        );


    // Inverse EOTF: Rec.709 gamma decoding (to linear)
half rec709_inverse_oetf(half c) {
    if (c <= 0.081h) {
        return c / 4.5h;
    } else {
        return pow((c + 0.099h) / 1.099h, 1.0h / 0.45h);
    }
}

    // Main conversion function
half3 convert_yuv_bt709_limited_to_linear_p3(half y_r16, half2 cbcr_rg16) {
        // Step 1: Convert R16Unorm [0,1] back to 10-bit integer scale
    half y_10bit = y_r16 * 1023.0h;
    half2 cbcr_10bit = cbcr_rg16 * 1023.0h;
    
        // Step 2: Expand limited range to full range [0, 1023]
        // Y:   [64, 940]  → map to [0, 1023]
        // CbCr: [64, 960] → map to [0, 1023]
    half y_full = (y_10bit - 64.0h) / (940.0h - 64.0h);
    half2 cbcr_full = (cbcr_10bit - 64.0h) / (960.0h - 64.0h);
    
        // Step 3: Center chroma to [-0.5, 0.5]
    half2 cbcr_centered = cbcr_full - 0.5h;
    
        // Safety clamp
    y_full = clamp(y_full, 0.0h, 1.0h);
    cbcr_centered = clamp(cbcr_centered, -0.5h, 0.5h);
    
        // Step 4: YUV → gamma-encoded Rec.709 RGB
    half3 rgb_gamma = YUV_TO_RGB_BT709 * half3(y_full, cbcr_centered.r, cbcr_centered.g);
    
        // Step 5: Gamma decode to linear Rec.709
    half3 linear_rec709 = half3(
                                rec709_inverse_oetf(rgb_gamma.r),
                                rec709_inverse_oetf(rgb_gamma.g),
                                rec709_inverse_oetf(rgb_gamma.b)
                                );
    
        // Step 6: Convert to linear Display P3
    half3 linear_p3 = REC709_TO_P3 * linear_rec709;
    
    return clamp(linear_p3, 0.0h, 1.0h);
}

    // Fragment shader entry point
[[fragment]]
half4 fragment_biplanar_sbs(VertexOut in [[stage_in]],
                            constant uint &viewID [[buffer(0)]],
                            texture2d<half, access::sample> lumaTexture  [[texture(0)]],
                            texture2d<half, access::sample> chromaTexture [[texture(1)]]) {
    constexpr sampler bilinearSampler(address::clamp_to_edge, filter::linear, mip_filter::none);
        // Sample Y and CbCr
    half y = lumaTexture.sample(bilinearSampler, texture_mapping(in.texCoords, viewID)).r;
    half2 cbcr = chromaTexture.sample(bilinearSampler, texture_mapping(in.texCoords, viewID)).rg;
    
        // Convert to linear Display P3
    half3 p3_rgb = convert_yuv_bt709_limited_to_linear_p3(y, cbcr);
    
        // Return with alpha = 1
    return half4(p3_rgb, 1.0h);
}
