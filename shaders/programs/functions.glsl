//functions
#include "/programs/distort.glsl"
#include "/programs/brdf.glsl"
mat3 tbnNormalTangent(vec3 normal, vec3 tangent) {
    // For DirectX normal mapping you want to switch the order of these 
    vec3 bitangent = normalize(cross(tangent, normal));
    return mat3(tangent, bitangent, normal);
}

vec3 updateWorldNormal(vec3 worldNormal, vec3 worldGeoNormal) {
    // Bump mapping from paper: Bump Mapping Unparametrized Surfaces on the GPU
    float bump = 0.4;
    return worldGeoNormal * (1. - bump) + worldNormal * bump;
}

// vec4 getNoise(vec2 coord) {
//     ivec2 screenCoord = ivec2(coord * vec2(viewWidth, viewHeight)); // exact pixel coordinate onscreen
//     ivec2 noiseCoord = screenCoord % 64; // wrap to range of noiseTextureResolution
//     return texelFetch(noisetex, noiseCoord, 0);
// }

vec3 getShadow(vec3 shadowScreenFrag) {
    float isInShadow = step(shadowScreenFrag.z, texture(shadowtex0, shadowScreenFrag.xy).r);
    float isInNonColoredShadow = step(shadowScreenFrag.z, texture(shadowtex1, shadowScreenFrag.xy).r);
    vec3 shadowColor = pow(texture(shadowcolor0, shadowScreenFrag.xy).rgb, vec3(2.2));

    vec3 shadow = vec3(1.0);

    if(isInShadow == 0.0) {
        if(isInNonColoredShadow == 0.0) {
            shadow = vec3(0.0);
        } else { //if fragment is in colored shadow
            shadow = shadowColor;
        }
    }
    return shadow;
}

// vec3 getSoftShadow(vec4 shadowClipFrag) {
//     const float range = SHADOW_SOFTNESS / 2; // how far away from the original position we take our samples from
//     const float increment = range / SHADOW_QUALITY; // distance between each sample
//     float noise = getNoise(texCoord).r;

//     float theta = noise * radians(360.0); // random angle using noise value
//     float cosTheta = cos(theta);
//     float sinTheta = sin(theta);

//     mat2 rotation = mat2(cosTheta, -sinTheta, sinTheta, cosTheta); // matrix to rotate the offset around the original position by the angle

//     vec3 shadowAccum = vec3(0.0); // sum of all shadow samples
//     int samples = 0;

//     for(float x = -range; x <= range; x += increment) {
//         for (float y = -range; y <= range; y+= increment) {
//             vec2 offset = rotation * vec2(x, y) / shadowMapResolution; // we divide by the resolution so our offset is in terms of pixels
//             vec4 offsetShadowClipPos = shadowClipFrag + vec4(offset, 0.0, 0.0); // add offset
//             offsetShadowClipPos.z -= 0.001; // apply bias
//             vec3 shadowNdcPos = offsetShadowClipPos.xyz / offsetShadowClipPos.w; // convert to NDC space
//             shadowNdcPos.xy = distort(shadowNdcPos.xy);
//             vec3 shadowScreenPos = shadowNdcPos * 0.5 + 0.5; // convert to screen space
//             shadowAccum += getShadow(shadowScreenPos); // take shadow sample
//             samples++;
//         }
//     }

//     return samples > 0 ? shadowAccum / float(samples) : vec3(1.0); // divide sum by count, getting average shadow
// }

vec3 lightingCalculations(vec3 albedo, vec3 viewTangent, vec3 worldNormal, vec3 worldGeoNormal, vec3 skyLight, vec3 feetPlayerFrag, vec3 fragWorldSpace) {
    //material data
    vec4 specularData = texture(specular, texCoord);
    float perceptualSmoothness = specularData.r;    // 感知光滑度
    float metallic = 0.0;
    vec3 reflectance = vec3(0);
    if (specularData.g * 255 > 229) {   // 若为金属
        metallic = 1.0;
        reflectance = albedo;   // 金属的反射颜色为它本身
    } else {
        reflectance = vec3(specularData.g);
    }
    float roughness = pow(1.0 - perceptualSmoothness, 2.0); // 线性化
    float smoothness = 1 - roughness;

    //space conversion
    vec3 adjustedFeetPlayerFrag = feetPlayerFrag + .03 * worldNormal;    // tiny offset to prevent shadow acne
    vec3 shadowViewFrag = (shadowModelView * vec4(adjustedFeetPlayerFrag, 1.0)).xyz;
    vec4 homogeneousFrag = shadowProjection * vec4(shadowViewFrag, 1.0);
    vec3 fragShadowNdcSpace = homogeneousFrag.xyz / homogeneousFrag.w;
    vec3 shadowScreenFrag = vec3(distort(fragShadowNdcSpace.xy),fragShadowNdcSpace.z) * 0.5 + 0.5;

    //directions
    vec3 shadowLightDir =  normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
    vec3 reflectionDir = reflect(-shadowLightDir, worldNormal);
    vec3 viewDir = normalize(cameraPosition - fragWorldSpace);

    //shadow
    vec3 shadow = getShadow(shadowScreenFrag);

    float distanceFromPlayer = distance(feetPlayerFrag, vec3(0));
    float shadowFade = clamp(smoothstep(100, 150, distanceFromPlayer), 0.0, 1.0);   // 根据距离淡化阴影
    shadow = mix(shadow, vec3(1.0), shadowFade);
    
    // sun light
    vec3 sunLightColor = vec3(1.051, 0.985, 0.940);
    vec3 sunLight = sunLightColor * clamp(dot(shadowLightDir, worldNormal), 0.0, 1.0) * skyLight;

    //ambient lighting
    vec3 ambientLightDir = worldNormal;
    vec3 blockLight = pow(texture(lightmap, vec2(lightMapCoords.x, 1.0 / 32.0)).rgb, vec3(2.2));
    vec3 ambientLight = (blockLight + .2 * skyLight) * brdf(ambientLightDir, viewDir, roughness, worldNormal, albedo, metallic, reflectance, true, false);

    //brdf
    vec3 outputColor;
    if (renderStage == MC_RENDER_STAGE_PARTICLES) { // 粒子渲染
        outputColor = ambientLight + skyLight * albedo;
    } else {
        outputColor = ambientLight * 0.5 + 1.5 * sunLight * shadow * brdf(shadowLightDir, viewDir, roughness, worldNormal, albedo, metallic, reflectance, false, false);
    }

    return outputColor;
}