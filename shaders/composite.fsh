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

mat4 perspectiveProjection(float fov, float aspect, float near, float far) {
	float inverseTanFovHalf = 1.0 / tan(fov/ 2);
	
	return mat4(
		inverseTanFovHalf / aspect, 0, 0, 0,
		0, inverseTanFovHalf, 0, 0,
		0, 0, -(far + near) / (far - near), -1,
		0, 0, -2 * far * near / (far - near), 0
	);
}

void main() {
    vec4 inputColorData = texture(colortex0, texCoord);
    vec3 inColor = pow(inputColorData.rgb, vec3(2.2));
    vec3 lightColor = texture(colortex4, texCoord).rgb;
    float transparency = inputColorData.a;

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

    vec3 outputColor;
    #ifdef DISTANT_HORIZONS
    if (dhDepth < 1.0) {
        outputColor = mix(inColor, pow(fogColor, vec3(2.2)), fogBlendValue);
    } else {
        outputColor = inColor;
    }
    #else
    if (depth < 1.0) {
        outputColor = mix(inColor, pow(fogColor, vec3(2.2)), fogBlendValue);
    } else {
        outputColor = inColor;
    }
    #endif

    outColor0 = pow(vec4(outputColor, transparency), vec4(1 / 2.2));
}