#version 460

const bool colortex0MipmapEnabled = true;

//uniforms
uniform sampler2D colortex0; //inColor
uniform sampler2D colortex1; //specular
uniform sampler2D colortex2; //normals
uniform sampler2D colortex3; //albedo
uniform sampler2D colortex4; //skyLight
uniform sampler2D depthtex0;
#ifdef DISTANT_HORIZONS
uniform sampler2D dhDepthTex0;
#endif

uniform float near;
uniform float far;
#ifdef DISTANT_HORIZONS
uniform float dhNearPlane;
uniform float dhFarPlane;
#endif
uniform float aspectRatio;

uniform vec3 fogColor;
uniform vec3 skyColor;

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferModelView;
uniform mat4 gbufferProjection;

in vec2 texCoord;

layout(location = 0) out vec4 outColor0;

struct Ray {
    vec3 origin;
    vec3 direction;
};

float fogify(float x, float w) {
	return w / (x * x + w);
}

vec3 calcSkyColor(vec3 pos) {
	float upDot = dot(pos, gbufferModelView[1].xyz); // not much, what's up with you?
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
    vec3 screenFrag = mix(vec3(texCoord, depth),vec3(texCoord, dhDepth), float(isFragDH));
    vec3 ndcFrag = screenFrag * 2.0 - 1.0;
    vec4 clipFrag = mix(gbufferProjectionInverse * vec4(ndcFrag, 1.0),customGbufferProjectionInverse * vec4(ndcFrag, 1.0), float(isFragDH));
    #else
    vec3 screenFrag = vec3(texCoord,depth);
    vec3 ndcFrag = screenFrag * 2.0 - 1.0;
    vec4 clipFrag = gbufferProjectionInverse * vec4(ndcFrag, 1.0);
    #endif
    vec3 viewFrag = clipFrag.xyz / clipFrag.w;

    float distanceFromCamera = distance(viewFrag, vec3(0));

    float maxFogDistance = 2000;
    float minFogDistance = 1500;

    float fogBlendValue = clamp((distanceFromCamera - minFogDistance) / (maxFogDistance - minFogDistance), 0, 1);

    // material
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

    vec3 reflectionColor = vec3(0.);
    // add reflections
    if((roughness < .2 && screenFrag.z != 1.0)) {
        vec3 viewDir = normalize(viewFrag);
        vec3 reflectionDir = reflect(viewDir, viewNormal);

        Ray ray;
        ray.origin = viewFrag;
        ray.direction = reflectionDir;

        reflectionColor = skyLight * pow(calcSkyColor(ray.direction), vec3(2.2)) * brdf(ray.direction, -viewDir, roughness, viewNormal, albedo, metallic, reflectance, false, true);

        vec3 curPos = ray.origin;
        // ray march
        for (int i = 0; i < 1000; i++) {
            float stepSize = mix(.02, 5.0, smoothstep(100.0, 1000.0, float(i)));
            curPos += ray.direction * stepSize;
            
            #ifdef DISTANT_HORIZONS
            bool isDH = distance(curPos, vec3(0)) > far;
            vec4 curClipPos = mix(gbufferProjection * vec4(curPos, 1.0), customGbufferProjection * vec4(curPos, 1.0), float(isDH));
            #else
            vec4 curClipPos = gbufferProjection * vec4(curPos, 1.0);
            #endif

            vec3 curNDCPos = curClipPos.xyz / curClipPos.w;
            vec3 curScreenPos = curNDCPos * 0.5 + 0.5;

            if (curScreenPos.x > 1.0 || curScreenPos.x < 0.0 || curScreenPos.y > 1.0 || curScreenPos.y < 0.0) {
                break;
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

            if (rayDepthLinear > mixDepthLinear && abs(rayDepthLinear - mixDepthLinear) < stepSize * 4) {
                reflectionColor = pow(texture(colortex0,curClipPos.xy).rgb, vec3(2.2)) * brdf(ray.direction, -viewDir, roughness, viewNormal, albedo, metallic, reflectance, false, true);
                break;
            }
        }
    }

    vec3 outputColor = inColor + mix(reflectionColor, vec3(0), pow(roughness,.1));
    #ifdef DISTANT_HORIZONS
    if (dhDepth < 1.0) {
        outputColor = mix(outputColor, pow(fogColor, vec3(2.2)), fogBlendValue);
    }
    #else
    if (depth < 1.0) {
        outputColor = mix(outputColor, pow(fogColor, vec3(2.2)), fogBlendValue);
    }
    #endif

    outColor0 = pow(vec4(outputColor, transparency), vec4(1 / 2.2));
}