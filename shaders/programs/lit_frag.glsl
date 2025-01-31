#version 460 

//uniforms
uniform sampler2D gtexture; // gbuffer texture
uniform sampler2D lightmap; // 根据游戏中的光照强度分配的亮度贴图，x分量对应天空亮度，y分量对应方块亮度
uniform sampler2D normals;  // 材质包提供的法线贴图
uniform sampler2D specular; // r = perceptualSmoothness; g = Values from 0 to 229 represent F0, also known as reflectance. This attribute is stored linearly. Please note that a value of 229 represents exactly 229 divided by 255, or approximately 90%, instead of 100%. Values from 230 to 255 represent various different metals; b = On dielectrics: Values from 0 to 64 represent porosity Values from 65 to 255 represent subsurface scattering. Both porosity and subsurface scattering are stored linearly.
uniform sampler2D shadowtex0;   // colored shadow
uniform sampler2D shadowtex1;   // non colored shadow
uniform sampler2D shadowcolor0; // shadow color
uniform sampler2D noisetex;

uniform mat4 gbufferModelViewInverse;
uniform mat4 modelViewMatrixInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;

uniform float far;
uniform float dhNearPlane;
uniform vec3 shadowLightPosition; 
uniform vec3 cameraPosition;

uniform float viewHeight;
uniform float viewWidth;
uniform int renderStage;
uniform int worldTime;

in vec2 texCoord;
in vec3 foliageColor;
in vec2 lightMapCoords;
in vec3 viewSpacePosition;
in vec4 viewTangent;
in float blockId;

/*
const int colortex2Format = RGBA32F;
*/

/* DRAWBUFFERS:01234 */
layout(location = 0) out vec4 outColor0; //colortex0 - outcolor
layout(location = 1) out vec4 outColor1; //colortex1 - specular
layout(location = 2) out vec4 outColor2; //colortex2 - normal
layout(location = 3) out vec4 outColor3; //colortex3 - albedo
layout(location = 4) out vec4 outColor4; //colortex4 - skyLight

#include "/programs/functions.glsl"

void main() {

    //input color
    vec4 outputColorData = texture(gtexture, texCoord);
    vec3 albedo = pow(outputColorData.rgb,vec3(2.2)) * pow(foliageColor, vec3(2.2));    // 结合材质颜色和顶点颜色
    float transparency = outputColorData.a;

    if (transparency < .1) {
        discard;
    }

    //normal calculations
    vec3 feetPlayerFrag = (gbufferModelViewInverse * vec4(viewSpacePosition, 1.0)).xyz; // 将view space坐标转换到world space坐标
    vec3 worldFrag = feetPlayerFrag + cameraPosition;   // 注意加上偏移量：相对于眼睛；不直接使用worldFrag = mat3(gbufferModelViewInverse * viewSpacePosition)，是因为这样得到的坐标包含了视角摇晃的影响

    vec3 dfdx = dFdx(viewSpacePosition);
    vec3 dfdy = dFdy(viewSpacePosition);

    vec3 viewGeoNormal = normalize(cross(dfdx, dfdy));  // 对表面偏导数求叉乘即可得到表面法线
    vec3 worldGeoNormal = mat3(gbufferModelViewInverse) * viewGeoNormal;    // 转换到世界坐标
    vec3 viewInitialTangent = viewTangent.xyz;
    vec3 viewSpaceTangent = normalize(viewInitialTangent - dot(viewInitialTangent, viewGeoNormal) * viewGeoNormal); // Remove the component of the tangent vector that is in the direction of the normal so that the result is orthogonal to the normal, in this way, we can compute TBN.

    vec4 normalData = texture(normals, texCoord) * 2.0 - 1.0;   // Normal map data is stored in the range [0, 1], so we need to convert it to the range [-1, 1].
    vec3 normalSpaceNormal = vec3(normalData.xy, sqrt(1.0 - dot(normalData.xy, normalData.xy)));    // Reconstruct the normal from the normal map; the third component (.z) of the normal vector can be reconstructed using sqrt(1.0 - dot(normal.xy, normal.xy)).

    mat3 TBN = tbnNormalTangent(viewGeoNormal, viewSpaceTangent);   // TBN matrix
    vec3 viewNormal = TBN * normalSpaceNormal;  // 将法线贴图从normal space转换到view space
    vec3 worldNormal = mat3(gbufferModelViewInverse) * viewNormal;  // 将法线贴图转换到world space
    worldNormal = updateWorldNormal(worldNormal, worldGeoNormal);   // bump mapping

    vec3 specularData = texture(specular, texCoord).rgb;

    float reflectance = specularData.g;
    if (int(blockId + 0.5) == 1000) {   // water
        worldNormal = worldGeoNormal;
        reflectance = 0.036;
        specularData.r = .9;
    }
    specularData.g = reflectance;

    //sky light
    vec3 skyLight = pow(texture(lightmap, vec2(1.0 / 32.0, lightMapCoords.y)).rgb, vec3(2.2));

    //lighting
    vec3 outputColor = lightingCalculations(albedo, viewTangent.rgb, worldNormal, worldGeoNormal, skyLight, feetPlayerFrag, worldFrag);

    //dh blend
    float distanceFromCamera = distance(viewSpacePosition, vec3(0));
    float dhBlend = smoothstep(far- .5 * far, far, distanceFromCamera); // 0 if far away, 1 if close
    if (int(blockId + 0.5) == 1000) {   // water
        transparency = mix(0.0, transparency, pow((1 - dhBlend), .6));  // 根据距离相机的距离调整水面透明度，越远越不透明
    }

    //output color
    outColor0 = vec4(pow(outputColor, vec3(1 / 2.2)), transparency);
    outColor1 = vec4(specularData, 1.0);
    outColor2 = vec4(worldNormal * .5 + .5, 1.0);   // 变换到[0,1]范围进行存储
    outColor3 = vec4(albedo, 1.0);
    outColor4 = vec4(skyLight, 1.0);
}
