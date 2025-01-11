//functions
#include "/programs/distort.glsl"
#include "/programs/brdf.glsl"
mat3 tbnNormalTangent(vec3 normal, vec3 tangent) {
    // For DirectX normal mapping you want to switch the order of these 
    vec3 bitangent = normalize(cross(tangent, normal));
    return mat3(tangent, bitangent, normal);
}

vec4 getNoise(vec2 coord){
  ivec2 screenCoord = ivec2(coord * vec2(viewWidth, viewHeight)); // exact pixel coordinate onscreen
  ivec2 noiseCoord = screenCoord % 64; // wrap to range of noiseTextureResolution
  return texelFetch(noisetex, noiseCoord, 0);
}

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

vec3 getSoftShadow(vec4 shadowClipFrag) {
    const float range = SHADOW_SOFTNESS / 2; // how far away from the original position we take our samples from
    const float increment = range / SHADOW_QUALITY; // distance between each sample
    float noise = getNoise(texCoord).r;

  float theta = noise * radians(360.0); // random angle using noise value
  float cosTheta = cos(theta);
  float sinTheta = sin(theta);

  mat2 rotation = mat2(cosTheta, -sinTheta, sinTheta, cosTheta); // matrix to rotate the offset around the original position by the angle

    vec3 shadowAccum = vec3(0.0); // sum of all shadow samples
    int samples = 0;

    for(float x = -range; x <= range; x += increment) {
        for (float y = -range; y <= range; y+= increment) {
            vec2 offset = rotation * vec2(x, y) / shadowMapResolution; // we divide by the resolution so our offset is in terms of pixels
            vec4 offsetShadowClipPos = shadowClipFrag + vec4(offset, 0.0, 0.0); // add offset
            offsetShadowClipPos.z -= 0.001; // apply bias
            offsetShadowClipPos.xyz = distortShadowClipPos(offsetShadowClipPos.xyz); // apply distortion
            vec3 shadowNDCPos = offsetShadowClipPos.xyz / offsetShadowClipPos.w; // convert to NDC space
            vec3 shadowScreenPos = shadowNDCPos * 0.5 + 0.5; // convert to screen space
            shadowAccum += getShadow(shadowScreenPos); // take shadow sample
            samples++;
        }
    }

    return shadowAccum / float(samples); // divide sum by count, getting average shadow
}

vec3 updateWorldNormal(vec3 worldNormal, vec3 worldGeoNormal) {
    // Bump mapping from paper: Bump Mapping Unparametrized Surfaces on the GPU
    float bump = 0.7;
    return worldGeoNormal * (1. - bump) + worldNormal * bump;
}

vec3 getSunLightColor(int time) {
    vec3 white = vec3(1.0);
    vec3 sunriseColor = vec3(1.0, 0.5, 0.0);
    vec3 noonColor = vec3(1.0);
    vec3 sunsetColor = vec3(1.0, 0.5, 0.0);
    vec3 nightColor = vec3(0.9, 0.9, 0.9);

    if (time < 500) {
        return mix(nightColor, sunriseColor, float(time) / 500.0);
    } else if (time < 3000) {
        return mix(sunriseColor, white, float(time - 500) / 2500.0);
    } else if (time < 10000) {
        return mix(white, sunsetColor, float(time - 3000) / 7000.0);
    } else if (time < 12000) {
        return mix(sunsetColor, nightColor, float(time - 10000) / 2000.0);
    } else {
        return nightColor;
    }
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
    vec3 adjustedFeetPlayerFrag = feetPlayerFrag + worldGeoNormal * .03;    // tiny offset to prevent shadow acne
    vec3 shadowViewFrag = (shadowModelView * vec4(adjustedFeetPlayerFrag, 1.0)).xyz;
    vec4 shadowClipFrag = shadowProjection * vec4(shadowViewFrag, 1.0);

    //directions
    vec3 shadowLightDir =  normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
    vec3 reflectionDir = reflect(-shadowLightDir, worldNormal);
    vec3 viewDir = normalize(cameraPosition - fragWorldSpace);

    //shadow - 0 if in shadow, 1 if it is not
    vec3 shadow = getSoftShadow(shadowClipFrag);

    float distanceFromPlayer = distance(feetPlayerFrag, vec3(0));
    float shadowFade = clamp(smoothstep(100, 150, distanceFromPlayer), 0.0, 1.0);
    shadow = mix(shadow, vec3(1.0), shadowFade);

    // sun light
    vec3 sunLightColor = getSunLightColor(worldTime);
    vec3 sunLight = sunLightColor * clamp(dot(shadowLightDir, worldGeoNormal), 0.0, 1.0) * skyLight;
    
    //ambient lighting
    vec3 ambientLightDir = worldGeoNormal;
    vec3 blockLight = pow(texture(lightmap, vec2(lightMapCoords.x, 1.0 / 32.0)).rgb, vec3(2.2));
    vec3 ambientLight = (blockLight + .2 * skyLight) * brdf(ambientLightDir, viewDir, roughness, worldNormal, albedo, metallic, reflectance, true, false);

    //brdf
    vec3 outputColor;
    if (renderStage == MC_RENDER_STAGE_PARTICLES) {
        outputColor = ambientLight + skyLight * albedo;
    } else {
        outputColor = ambientLight * 0.5 + 1.5 * sunLight * shadow * brdf(shadowLightDir, viewDir, roughness, worldNormal, albedo, metallic, reflectance, false, false);
    }

    return outputColor;
}