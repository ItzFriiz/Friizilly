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

vec3 lightingCalculations(vec3 albedo, vec3 viewTangent, vec3 worldNormal, vec3 worldGeoNormal, vec3 skyLight, vec3 feetPlayerFrag, vec3 fragWorldSpace) {
    //material data
    vec4 specularData = texture(specular, texCoord);
    float perceptualSmoothness = specularData.r;
    float metallic = 0.0;
    vec3 reflectance = vec3(0);
    if (specularData.g * 255 > 229) {
        metallic = 1.0;
        reflectance = albedo;
    } else {
        reflectance = vec3(specularData.g);
    }
    float roughness = pow(1.0 - perceptualSmoothness, 2.0);
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

    //shadow - 0 if in shadow, 1 if it is not
    float isInShadow = step(shadowScreenFrag.z, texture(shadowtex0, shadowScreenFrag.xy).r);
    float isInNonColoredShadow = step(shadowScreenFrag.z - .001, texture(shadowtex1, shadowScreenFrag.xy).r);
    vec3 shadowColor = pow(texture(shadowcolor0, shadowScreenFrag.xy).rgb, vec3(2.2));

    vec3 shadowMultiplier = vec3(1.0);

    if(isInShadow == 0.0) {
        if(isInNonColoredShadow == 0.0) {
            shadowMultiplier = vec3(0.0);
        } else { //if fragment is in colored shadow
            shadowMultiplier = shadowColor;
        }
    }

    float distanceFromPlayer = distance(feetPlayerFrag, vec3(0));
    float shadowFade = clamp(smoothstep(100, 150, distanceFromPlayer), 0.0, 1.0);
    shadowMultiplier = mix(shadowMultiplier, vec3(1.0), shadowFade);
    
    //ambient lighting
    vec3 ambientLightDir = worldNormal;
    vec3 blockLight = pow(texture(lightmap, vec2(lightMapCoords.x, 1.0 / 32.0)).rgb, vec3(2.2));
    vec3 ambientLight = (blockLight + .2 * skyLight) * brdf(ambientLightDir, viewDir, roughness, worldNormal, albedo, metallic, reflectance, true, false);

    //brdf
    vec3 outputColor;
    if (renderStage == MC_RENDER_STAGE_PARTICLES) {
        outputColor = ambientLight + skyLight * albedo;
    } else {
        outputColor = ambientLight + skyLight * shadowMultiplier * brdf(shadowLightDir, viewDir, roughness, worldNormal, albedo, metallic, reflectance, false, false);
    }

    return outputColor;
}