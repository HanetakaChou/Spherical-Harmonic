//
// Copyright (C) YuqiaoZhang(HanetakaChou)
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Lesser General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

#ifndef _ENVIRONMENT_LIGHTING_HLSLI_
#define _ENVIRONMENT_LIGHTING_HLSLI_ 1

#include "ao.hlsli"
#include "../thirdparty/Brioche-Shader-Language/shaders/brx_shader_language.bsli"
#include "../thirdparty/Brioche-Shader-Language/shaders/brx_brdf.bsli"
#include "../thirdparty/Hemispherical-Directional-Reflectance/shaders/brx_hemispherical_directional_reflectance.bsli"
#include "../thirdparty/Spherical-Harmonic/shaders/brx_spherical_harmonic_diffuse_radiance.bsli"
#include "../thirdparty/Spherical-Harmonic/shaders/brx_spherical_harmonic_specular_radiance.bsli"

brx_int2 brx_hdr_application_bridge_get_specular_fresnel_factor_lut_dimension()
{
    return brx_texture_2d_get_dimension(t_lut_specular_hdr_fresnel_factors, 0);
}

brx_float2 brx_hdr_application_bridge_get_specular_fresnel_factor_lut(in brx_float2 in_lut_uv)
{
    return brx_sample_level_2d(t_lut_specular_hdr_fresnel_factors, s_clamp_linear_sampler, in_lut_uv, 0.0).xy;
}

brx_int3 brx_sh_application_bridge_get_specular_transfer_function_sh_coefficient_lut_dimension()
{
    return brx_texture_2d_array_get_dimension(t_lut_specular_transfer_function_sh_coefficients, 0);
}

brx_float brx_sh_application_bridge_get_specular_transfer_function_sh_coefficient_lut(in brx_float2 in_lut_uv, brx_int in_sh_coefficient_index)
{
    return brx_sample_level_2d_array(t_lut_specular_transfer_function_sh_coefficients, s_clamp_linear_sampler, brx_float3(in_lut_uv, brx_float(in_sh_coefficient_index)), 0.0).x;
}

float3 EvaluateEnvironmentLighting(float3 diffuse_color, float3 specular_color, float roughness, float3 N, float3 V, float raw_ambient_occlusion)
{
    brx_float3 environment_map_sh_coefficients[BRX_SH_COEFFICIENT_COUNT];
    for (brx_int environment_map_sh_coefficient_index = 0; environment_map_sh_coefficient_index < BRX_SH_COEFFICIENT_COUNT; ++environment_map_sh_coefficient_index)
    {
        environment_map_sh_coefficients[environment_map_sh_coefficient_index] = brx_uint_as_float(brx_byte_address_buffer_load3(t_environment_map_sh_coefficients, (4 * 3) * environment_map_sh_coefficient_index));
    }

    brx_float3 diffuse_albedo = diffuse_color;

    brx_float3 specular_albedo = brx_hdr_specular_albedo(specular_color, roughness, N, V);

    brx_float3 diffuse_radiance = brx_sh_diffuse_radiance(diffuse_albedo, N, environment_map_sh_coefficients);

    brx_float3 specular_radiance = brx_sh_specular_radiance(specular_albedo, roughness, N, V, environment_map_sh_coefficients);

    brx_float3 ambient_occlusion = AO_InterReflections(AO_BentNormal(raw_ambient_occlusion, N), diffuse_color);

    // UE: [GBufferAO](https://github.com/EpicGames/UnrealEngine/blob/4.27/Engine/Shaders/Private/BasePassPixelShader.usf#L1072)
    brx_float specular_color_luminance = brx_dot(specular_color, brx_float3(0.3, 0.59, 0.11));
    brx_float raw_directional_occlusion = AO_InterReflections(DO_BentNormal(raw_ambient_occlusion, N), brx_float3(specular_color_luminance, specular_color_luminance, specular_color_luminance)).g;

    const brx_float NdotV = brx_max(brx_float(BRX_TROWBRIDGE_REITZ_NDOTV_MINIMUM), brx_dot(N, V));
    brx_float directional_occlusion = DO_FromAO(raw_directional_occlusion, roughness, NdotV);

    // U3D: [ApplyAmbientOcclusionFactor](https://github.com/Unity-Technologies/Graphics/blob/v10.8.0/com.unity.render-pipelines.high-definition/Runtime/Material/Lit/Lit.hlsl#L2020)

    return (diffuse_radiance * ambient_occlusion + specular_radiance * directional_occlusion);
}

#endif