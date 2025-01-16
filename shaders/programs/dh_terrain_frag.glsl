#version 460 compatibility

//uniforms
uniform sampler2D lightmap;
uniform sampler2D depthtex0;    // 深度纹理，0表示最近，1表示最远
uniform sampler2D dhDepthTex0;  // Distant Horizons的深度纹理
uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;
uniform sampler2D shadowcolor0;
uniform sampler2D specular;
uniform sampler2D normals;

uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowModelView;

uniform float viewHeight;   // 窗口高度
uniform float viewWidth;    // 窗口宽度
uniform float near; // 近平面
uniform float far;  // 远平面
uniform float dhNearPlane;  // Distant Horizons近平面
uniform float dhFarPlane;
uniform vec3 fogColor;
uniform vec3 shadowLightPosition;   // 光照方向
uniform vec3 cameraPosition;
uniform int renderStage;    // 渲染阶段

//vertexToFragment
in vec4 blockColor;
in vec2 lightMapCoords;
in vec3 viewSpacePosition;
in vec3 geoNormal;
in vec2 texCoord;
flat in int dh_MaterialId;

/* DRAWBUFFERS:0124 */
layout(location = 0) out vec4 outColor0; //colortex0 - outcolor
layout(location = 1) out vec4 outColor1; //colortex1 - specular
layout(location = 2) out vec4 outColor2; //colortex2 - normal
layout(location = 3) out vec4 outColor4; //colortex3 - skyLight

//functions
float linearizeDepth(float depth, float near, float far) {
    return (near * far) / (depth * (near - far) + far);
}

#include "/programs/functions.glsl"

void main() {

    //input color
    vec4 outputColorData = blockColor;
    vec3 albedo = pow(outputColorData.rgb, vec3(2.2));
    float transparency = outputColorData.a;

    if (transparency < .1) {
        discard;
    }

    vec3 feetPlayerFrag = (gbufferModelViewInverse * vec4(viewSpacePosition, 1.0)).xyz;
    vec3 worldFrag = feetPlayerFrag + cameraPosition;

    vec3 viewTangent = mat3(gbufferModelViewInverse) * normalize(cross(geoNormal, vec3(0, 1, 1)));
    vec3 worldGeoNormal = mat3(gbufferModelViewInverse) * geoNormal;

    vec3 skyLight = pow(texture(lightmap, vec2(1.0 / 32.0, lightMapCoords.y)).rgb, vec3(2.2));

    vec3 outputColor = lightingCalculations(albedo, viewTangent, worldGeoNormal, worldGeoNormal, skyLight, feetPlayerFrag, worldFrag);
    
    //depth testing
    vec2 texCoord = gl_FragCoord.xy / vec2(viewWidth, viewHeight);  // 像素坐标归一化到[0,1]
    float depth = texture(depthtex0, texCoord).r;
    float dhDepth = gl_FragCoord.z;
    float depthLinear = linearizeDepth(depth, near, far * 4);
    float dhDepthLinear = linearizeDepth(dhDepth, dhNearPlane, dhFarPlane);
    if (depthLinear < dhDepthLinear && depth != 1) {    // 若物体在Distant Horizons物体前面且不是天空
        discard;
    }

    //dh blend
    float distanceFromCamera = distance(viewSpacePosition, vec3(0));
    float dhBlend = pow(smoothstep(far - .5 * far, far, distanceFromCamera), .6);
    transparency = mix(0.0, transparency, dhBlend);

    float perceptualSmoothness = 0.0;
    float reflectance = 0.0;
    if (dh_MaterialId == DH_BLOCK_WATER) {
        perceptualSmoothness = .99;
        reflectance = 0.036;
    }

    //output color
    outColor0 = vec4(pow(outputColor,vec3(1 / 2.2)), transparency);
    outColor1 = vec4(perceptualSmoothness, reflectance, 1.0, 1.0);
    outColor2 = vec4(worldGeoNormal * .5 + .5, 1.0); //colortex2 - normal
    outColor4 = vec4(skyLight, 1.0); //colortex4 - skyLight
}