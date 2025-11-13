//
//  ShaderTypes.h
//  MyMTLTestApp
//
//  Created by Andy Zhang on 2025/11/12.
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
typedef metal::int32_t EnumBackingType;
#else
#import <Foundation/Foundation.h>
typedef NSInteger EnumBackingType;
#endif

#include <simd/simd.h>

struct PlaneVertex {
    simd_float3 position;
    simd_float3 normal;
    simd_float2 texCoord;
};

#endif /* ShaderTypes_h */
