#version 460

const bool colortex0MipmapEnabled = true;
const int noiseTextureResolution = 32;     // 噪声图分辨率

//uniforms
uniform sampler2D colortex0; //inColor
uniform sampler2D colortex1; //specular
uniform sampler2D colortex2; //normals
uniform sampler2D colortex3; //albedo
uniform sampler2D colortex4; //skyLight
uniform sampler2D noisetex;
uniform sampler2D depthtex0;
#ifdef DISTANT_HORIZONS
uniform sampler2D dhDepthTex0;
#endif

uniform int worldTime;  // 世界游戏刻

uniform float near;
uniform float far;
#ifdef DISTANT_HORIZONS
uniform float dhNearPlane;
uniform float dhFarPlane;
#endif
uniform float aspectRatio;

uniform vec3 fogColor;
uniform vec3 skyColor;

uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 cameraPosition;

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferModelView;
uniform mat4 gbufferProjection;

in vec2 texCoord;
flat in int isNight;

/* DRAWBUFFERS:01 */
layout(location = 0) out vec4 outColor0;
layout(location = 1) out vec4 outColor1;

struct Ray {
    vec3 origin;
    vec3 direction;
};

float fogify(float x, float w) {    // 迷雾混合因子
	return w / (x * x + w);
}

vec3 calcSkyColor(vec3 pos) {   // 考虑迷雾影响，计算天空颜色
	float upDot = dot(pos, gbufferModelView[1].xyz);
	return mix(skyColor, fogColor, fogify(max(upDot, 0.0), 0.25));
}

//functions
float linearizeDepth(float depth, float near, float far) {
    return (near * far) / (depth * (near - far) + far);
}

float unlinearizeDepth(float linearDepth, float near, float far) {
    return (near * far - linearDepth * far) / (linearDepth * (near - far));
}

mat4 perspectiveProjection(float fov, float aspect, float near, float far) {
	float inverseTanFovHalf = 1.0 / tan(fov/ 2);
	
	return mat4(
		inverseTanFovHalf / aspect, 0, 0, 0,
		0, inverseTanFovHalf, 0, 0,
		0, 0, -(far + near) / (far - near), -1,
		0, 0, -2 * far * near / (far - near), 0
	);
}

#include "/programs/brdf.glsl"
#include "/programs/clouds.glsl"

void main() {
    vec4 inputColorData = texture(colortex0, texCoord);
    vec3 inColor = pow(inputColorData.rgb, vec3(2.2));
    float transparency = inputColorData.a;

    vec3 specularData = texture(colortex1, texCoord).rgb;
    vec3 worldNormal = texture(colortex2, texCoord).rgb * 2.0 - 1.0;
    vec3 viewNormal = mat3(gbufferModelView) * worldNormal;
    vec3 albedo = texture(colortex3, texCoord).rgb;
    vec3 skyLight = texture(colortex4, texCoord).rgb;

    float depth = texture(depthtex0, texCoord).r;
    #ifdef DISTANT_HORIZONS
    float dhDepth = texture(dhDepthTex0, texCoord).r;
    #endif

    float fov = 2.0 * atan(1.0 / gbufferProjection[1][1]);

    #ifdef DISTANT_HORIZONS
    mat4 customGbufferProjection = perspectiveProjection(fov, aspectRatio, dhNearPlane, dhFarPlane);
    mat4 customGbufferProjectionInverse = inverse(customGbufferProjection);
    bool isFragDH = depth == 1.0;
    vec3 screenFrag = mix(vec3(texCoord, depth), vec3(texCoord, dhDepth), float(isFragDH));
    vec3 ndcFrag = screenFrag * 2.0 - 1.0;
    vec4 clipFrag = mix(gbufferProjectionInverse * vec4(ndcFrag, 1.0),customGbufferProjectionInverse * vec4(ndcFrag, 1.0), float(isFragDH));
    #else
    vec3 screenFrag = vec3(texCoord, depth);
    vec3 ndcFrag = screenFrag * 2.0 - 1.0;
    vec4 clipFrag = gbufferProjectionInverse * vec4(ndcFrag, 1.0);
    #endif
    vec3 viewFrag = clipFrag.xyz / clipFrag.w;

    float distanceFromCamera = distance(viewFrag, vec3(0.));

    float maxFogDistance = 2000;
    float minFogDistance = 1300;

    float fogBlendValue = clamp((distanceFromCamera - minFogDistance) / (maxFogDistance - minFogDistance), 0, 1);

    // material
    float perceptualSmoothness = specularData.r;
    float metallic = 0.0;
    vec3 reflectance = vec3(0.);
    if (specularData.g * 255 > 229) {
        metallic = 1.0;
        reflectance = albedo;
    } else {
        reflectance = vec3(specularData.g);
    }
    float roughness = pow(1.0 - perceptualSmoothness, 2.0);
    float smoothness = 1 - roughness;

    vec3 reflectionColor = vec3(0.);
    // add reflections
    if ((roughness < .2 && screenFrag.z != 1.0)) {
        vec3 viewDir = normalize(viewFrag);
        vec3 reflectionDir = reflect(viewDir, viewNormal);

        Ray ray;
        ray.origin = viewFrag + viewNormal * mix(0.01, 1.5, smoothstep(0, far, distanceFromCamera));    // 光线起点，略微偏离表面，避免从表面内部开始计算导致自相交问题
        ray.direction = reflectionDir;

        reflectionColor = skyLight * pow(calcSkyColor(ray.direction), vec3(2.2)) * brdf(ray.direction, -viewDir, roughness, viewNormal, albedo, metallic, reflectance, false, true);    // 没有其他物体遮挡的情况下使用天空光照

        vec3 curPos = ray.origin;
        // ray march
        for (int i = 0; i < 1000; i++) {
            float stepSize = mix(.02, 5.0, smoothstep(100.0, 1000.0, float(i))); // adaptive step size, smaller steps for closer objects
            curPos += ray.direction * stepSize;
            
            #ifdef DISTANT_HORIZONS
            bool isDH = distance(curPos, vec3(0)) > far;
            vec4 curClipPos = mix(gbufferProjection * vec4(curPos, 1.0), customGbufferProjection * vec4(curPos, 1.0), float(isDH));
            #else
            vec4 curClipPos = gbufferProjection * vec4(curPos, 1.0);    // 将当前光线位置投影到屏幕空间，从而与深度进行比较
            #endif

            vec3 curNDCPos = curClipPos.xyz / curClipPos.w;
            vec3 curScreenPos = curNDCPos * 0.5 + 0.5;

            if (curScreenPos.x > 1.0 || curScreenPos.x < 0.0 || curScreenPos.y > 1.0 || curScreenPos.y < 0.0) {
                break;  // 光线射到屏幕之外，终止行进
            }

            float curDepth = texture(depthtex0, curScreenPos.xy).r;
            float curDepthLinear = linearizeDepth(curDepth, near, far * 4);

            #ifdef DISTANT_HORIZONS
            float curDHDepth = texture(dhDepthTex0, curScreenPos.xy).r;
            float curDHDepthLinear = linearizeDepth(curDHDepth, dhNearPlane, dhFarPlane);

            float mixDepthLinear = mix(curDepthLinear, curDHDepthLinear, float(isDH));
            float rayDepthLinear = mix(linearizeDepth(curScreenPos.z, near, far * 4), linearizeDepth(curScreenPos.z, dhNearPlane, dhFarPlane), float(isDH));
            #else
            float mixDepthLinear = curDepthLinear;
            float rayDepthLinear = linearizeDepth(curScreenPos.z, near, far * 4);
            #endif

            if (rayDepthLinear > mixDepthLinear && abs(rayDepthLinear - mixDepthLinear) < stepSize * 4) {   // 判断当前光线深度是否命中表面
                reflectionColor = pow(texture(colortex0,curScreenPos.xy).rgb, vec3(2.2)) * brdf(ray.direction, -viewDir, roughness, viewNormal, albedo, metallic, reflectance, false, true);    // 如果命中，采样屏幕上的颜色纹理
                break;
            }
        }
    }

    // 体积云
    vec4 cloud = vec4(1);
    if(texCoord.s < 0.5 && texCoord.t < 0.5) {
        // 用 1/4 屏幕坐标重投影到完整屏幕
        vec2 tc14 = texCoord.st * 2;
        float depth2 = texture2D(depthtex0, tc14).x;
        vec4 ndcPos2 = vec4(tc14 * 2 - 1, depth2 * 2 - 1, 1);
        vec4 clipPos2 = gbufferProjectionInverse * ndcPos2;
        vec4 viewPos2 = vec4(clipPos2.xyz / clipPos2.w, 1.0);
        vec4 worldPos2 = gbufferModelViewInverse * viewPos2;

        vec3 sunPos = (gbufferModelViewInverse * vec4(sunPosition, 0)).xyz + cameraPosition;
        vec3 moonPos = (gbufferModelViewInverse * vec4(moonPosition, 0)).xyz + cameraPosition;
        vec3 sun = bool(isNight) ? moonPos : sunPos;    // 光源位置 -- 世界坐标
        vec3 worldPos = worldPos2.xyz + cameraPosition;
        vec3 ndcPos = ndcPos2.xyz;
        vec3 sunColor = vec3(1.051, 0.985, 0.940);
        cloud = volumeCloud(worldPos, cameraPosition, sun, noisetex, sunColor);
    }

    vec3 outputColor = inColor + mix(reflectionColor, vec3(0), pow(roughness, .1));
    #ifdef DISTANT_HORIZONS
    if (dhDepth < 1.0) {
        outputColor = mix(outputColor, pow(fogColor, vec3(2.2)), fogBlendValue);    // 迷雾混合
    }
    #else
    if (depth < 1.0) {
        outputColor = mix(outputColor, pow(fogColor, vec3(2.2)), fogBlendValue);
    }
    #endif

    outColor0 = pow(vec4(outputColor, transparency), vec4(1 / 2.2));
    outColor1 = cloud;
}